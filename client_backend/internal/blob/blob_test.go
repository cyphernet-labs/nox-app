package blob

import (
	"bytes"
	"errors"
	"io"
	"io/fs"
	"os"
	"strings"
	"testing"
)

func openStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(t.TempDir() + "/files")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func TestUploadRoundtrip(t *testing.T) {
	s := openStore(t)
	payload := bytes.Repeat([]byte("nox"), 1000)

	u, err := s.Create("f_abc")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if n, err := u.CopyFrom(bytes.NewReader(payload)); err != nil || n != int64(len(payload)) {
		t.Fatalf("CopyFrom: n=%d err=%v", n, err)
	}

	// Partial bytes are invisible until Finalize.
	if s.Exists("f_abc") {
		t.Fatal("blob visible before Finalize")
	}
	if err := u.Finalize(); err != nil {
		t.Fatalf("Finalize: %v", err)
	}

	size, err := s.Size("f_abc")
	if err != nil || size != int64(len(payload)) {
		t.Fatalf("Size = %d err=%v", size, err)
	}
	f, err := s.Open("f_abc")
	if err != nil {
		t.Fatalf("Open blob: %v", err)
	}
	defer func() { _ = f.Close() }()
	got, err := io.ReadAll(f)
	if err != nil || !bytes.Equal(got, payload) {
		t.Fatalf("readback mismatch: %d bytes err=%v", len(got), err)
	}
}

func TestAbortDiscardsPart(t *testing.T) {
	s := openStore(t)
	u, err := s.Create("f_gone")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if _, err := u.Write([]byte("half")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	u.Abort()
	if s.Exists("f_gone") {
		t.Fatal("aborted upload became visible")
	}
	if _, err := s.Size("f_gone"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("Size after abort err = %v, want not-exist", err)
	}
}

func TestRemoveIsIdempotentAndSweepsParts(t *testing.T) {
	s := openStore(t)
	u, err := s.Create("f_part")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	_ = u.f.Close()
	// A leftover .part (crash mid-upload) is removed together with the blob.
	if err := s.Remove("f_part"); err != nil {
		t.Fatalf("Remove with part leftover: %v", err)
	}
	if err := s.Remove("f_part"); err != nil {
		t.Fatalf("second Remove: %v", err)
	}
	if err := s.Remove("f_never_existed"); err != nil {
		t.Fatalf("Remove of unknown id: %v", err)
	}
}

func TestTraversalShapedIDsAreRejected(t *testing.T) {
	s := openStore(t)
	for _, id := range []string{"../escape", "a/../../b", "/abs"} {
		if _, err := s.Create(id); err == nil {
			t.Fatalf("Create(%q) unexpectedly succeeded", id)
		}
		if _, err := s.Open(id); err == nil {
			t.Fatalf("Open(%q) unexpectedly succeeded", id)
		}
	}
	if s.Exists(strings.Repeat("../", 10) + "etc/passwd") {
		t.Fatal("traversal id reported existing")
	}
	for _, id := range []string{"../escape", "a/../../b"} {
		if _, err := s.Resume(id, 0); err == nil {
			t.Fatalf("Resume(%q) unexpectedly succeeded", id)
		}
	}
	// "a/../../b" never gets as far as the "..": there is no "a" to walk
	// through, so it simply is not there. A plain escape is refused outright.
	if _, err := s.Received("../escape"); err == nil {
		t.Fatal(`Received("../escape") unexpectedly succeeded`)
	}
}

// partBytes reads id's part straight off the disk, bypassing the store.
func partBytes(t *testing.T, s *Store, id string) []byte {
	t.Helper()
	data, err := s.root.ReadFile(id + partSuffix)
	if err != nil {
		t.Fatalf("read part: %v", err)
	}
	return data
}

// record reads id's synced record as written, or "" when there is none.
func record(t *testing.T, s *Store, id string) string {
	t.Helper()
	data, err := s.root.ReadFile(id + syncedSuffix)
	if errors.Is(err, fs.ErrNotExist) {
		return ""
	}
	if err != nil {
		t.Fatalf("read record: %v", err)
	}
	return string(data)
}

func mustReceived(t *testing.T, s *Store, id string) int64 {
	t.Helper()
	n, err := s.Received(id)
	if err != nil {
		t.Fatalf("Received: %v", err)
	}
	return n
}

func TestANewUploadWritesNoRecordUntilItsFirstCheckpoint(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_new", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write([]byte("first bytes")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if got := record(t, s, "f_new"); got != "" {
		t.Fatalf("record before any checkpoint = %q, want none", got)
	}
	if got := mustReceived(t, s, "f_new"); got != 0 {
		t.Fatalf("Received before any checkpoint = %d, want 0: nothing is durable yet", got)
	}
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	if got := record(t, s, "f_new"); got != "11" {
		t.Fatalf("record after checkpoint = %q, want 11", got)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
}

func TestResumeContinuesFromWhatIsDurableAndDropsTheRest(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_cut", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	durable := bytes.Repeat([]byte("d"), 100)
	if _, err := u.Write(durable); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	// Written after the last checkpoint, and then the process dies: the part
	// holds these bytes, the record does not vouch for them.
	if _, err := u.Write(bytes.Repeat([]byte("?"), 50)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	_ = u.f.Close()

	if got := mustReceived(t, s, "f_cut"); got != 100 {
		t.Fatalf("Received = %d, want the 100 durable bytes, not the 150 written", got)
	}
	u2, err := s.Resume("f_cut", 100)
	if err != nil {
		t.Fatalf("Resume at 100: %v", err)
	}
	if _, err := u2.Write([]byte("tail")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u2.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	want := append(append([]byte{}, durable...), "tail"...)
	if got := partBytes(t, s, "f_cut"); !bytes.Equal(got, want) {
		t.Fatalf("part = %q, want the durable bytes followed by the new ones", got)
	}
	if got := mustReceived(t, s, "f_cut"); got != 104 {
		t.Fatalf("Received after suspend = %d, want 104", got)
	}
}

func TestReceivedIsTheSmallerOfTheRecordAndThePart(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_min", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write(bytes.Repeat([]byte("x"), 80)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	// Something outside the server cut the part below what the record says.
	f, err := s.root.OpenFile("f_min"+partSuffix, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open part: %v", err)
	}
	if err := f.Truncate(30); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	_ = f.Close()
	if got := mustReceived(t, s, "f_min"); got != 30 {
		t.Fatalf("Received = %d, want the part's 30: a record cannot vouch for bytes that are gone", got)
	}
	if got := mustReceived(t, s, "f_never"); got != 0 {
		t.Fatalf("Received of an unknown id = %d, want 0", got)
	}
}

func TestAnUnreadableRecordVouchesForNothing(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_garbled", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write([]byte("bytes")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	if err := s.root.WriteFile("f_garbled"+syncedSuffix, []byte("not a number"), 0o666); err != nil {
		t.Fatalf("garble record: %v", err)
	}
	if got := mustReceived(t, s, "f_garbled"); got != 0 {
		t.Fatalf("Received = %d, want 0", got)
	}
}

func TestResumeRefusesAnOffsetBeyondWhatIsDurable(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_short", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write(bytes.Repeat([]byte("s"), 100)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	if _, err := s.Resume("f_short", 101); !errors.Is(err, ErrShortPart) {
		t.Fatalf("Resume past the durable bytes err = %v, want ErrShortPart", err)
	}
	if _, err := s.Resume("f_short", -1); err == nil {
		t.Fatal("Resume at a negative offset succeeded")
	}
}

func TestResumeLowersTheRecordBeforeCuttingThePart(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_back", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write(bytes.Repeat([]byte("b"), 100)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}

	u2, err := s.Resume("f_back", 40)
	if err != nil {
		t.Fatalf("Resume at 40: %v", err)
	}
	// Before a single new byte: the record already says 40. Left at 100, it
	// would vouch after a crash for bytes 40..100 of the NEXT write, which
	// may never reach the disk.
	if got := record(t, s, "f_back"); got != "40" {
		t.Fatalf("record after Resume at 40 = %q, want 40", got)
	}
	if got := len(partBytes(t, s, "f_back")); got != 40 {
		t.Fatalf("part after Resume at 40 holds %d bytes, want 40", got)
	}
	if err := u2.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
}

func TestRollbackDropsWhatThisRequestWrote(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_roll", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write(bytes.Repeat([]byte("k"), 100)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	u2, err := s.Resume("f_roll", 100)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u2.Write(bytes.Repeat([]byte("z"), 60)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u2.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	if err := u2.Rollback(100); err != nil {
		t.Fatalf("Rollback: %v", err)
	}
	if got := record(t, s, "f_roll"); got != "100" {
		t.Fatalf("record after rollback = %q, want 100", got)
	}
	if got := partBytes(t, s, "f_roll"); !bytes.Equal(got, bytes.Repeat([]byte("k"), 100)) {
		t.Fatalf("part after rollback holds %d bytes, want the 100 from before", len(got))
	}
}

func TestFinalizeLeavesNoRecordBehind(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_done", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write([]byte("whole file")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	if err := u.Finalize(); err != nil {
		t.Fatalf("Finalize: %v", err)
	}
	if !s.Exists("f_done") {
		t.Fatal("finalized bytes are not visible")
	}
	if got := record(t, s, "f_done"); got != "" {
		t.Fatalf("record after Finalize = %q, want none", got)
	}
}

func TestFinalizeTakesAStrayTemporaryRecordToo(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_stray", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write([]byte("whole file")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	// A crash in the middle of an earlier record left its temporary behind.
	if err := s.root.WriteFile("f_stray"+syncedSuffix+tmpSuffix, []byte("7"), 0o666); err != nil {
		t.Fatalf("seed temporary: %v", err)
	}
	if err := u.Finalize(); err != nil {
		t.Fatalf("Finalize: %v", err)
	}
	// Nothing sweeps a file bound to a message, so whatever Finalize leaves
	// beside it stays for good.
	for _, name := range []string{"f_stray" + syncedSuffix, "f_stray" + syncedSuffix + tmpSuffix} {
		if _, err := s.root.Stat(name); !errors.Is(err, fs.ErrNotExist) {
			t.Fatalf("%s survived Finalize (err=%v)", name, err)
		}
	}
}

func TestAFinalizeThatCannotFlushStillClosesThePart(t *testing.T) {
	s := openStore(t)
	// A part the flush fails on: a pipe takes writes and refuses fsync.
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	t.Cleanup(func() { _ = r.Close() })
	u := &Upload{root: s.root, id: "f_pipe", f: w}

	if err := u.Finalize(); err == nil {
		t.Fatal("Finalize succeeded on a part that cannot be flushed")
	}
	if err := w.Close(); !errors.Is(err, os.ErrClosed) {
		t.Fatalf("the part is still open after a failed flush (close = %v): every such failure leaks a descriptor", err)
	}
}

func TestAbortRemovesThePartAndItsRecord(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_abort", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write([]byte("half")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	u.Abort()
	if got := record(t, s, "f_abort"); got != "" {
		t.Fatalf("record after Abort = %q, want none", got)
	}
	if got := mustReceived(t, s, "f_abort"); got != 0 {
		t.Fatalf("Received after Abort = %d, want 0", got)
	}
}

func TestRemoveTakesTheRecordAndItsTemporaryToo(t *testing.T) {
	s := openStore(t)
	u, err := s.Resume("f_sweep", 0)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u.Write([]byte("left behind")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	// A crash in the middle of writing a record leaves its temporary.
	if err := s.root.WriteFile("f_sweep"+syncedSuffix+tmpSuffix, []byte("7"), 0o666); err != nil {
		t.Fatalf("seed temporary: %v", err)
	}
	if err := s.Remove("f_sweep"); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	for _, name := range []string{"f_sweep" + partSuffix, "f_sweep" + syncedSuffix, "f_sweep" + syncedSuffix + tmpSuffix} {
		if _, err := s.root.Stat(name); !errors.Is(err, fs.ErrNotExist) {
			t.Fatalf("%s survived Remove (err=%v)", name, err)
		}
	}
}

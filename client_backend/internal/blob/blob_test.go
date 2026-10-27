package blob

import (
	"bytes"
	"crypto/rand"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// testKey is the data key every test store derives its file keys from.
var testKey = bytes.Repeat([]byte{0x6b}, 32)

// C is one chunk of plaintext.
const C = ChunkSize

func openStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(t.TempDir()+"/files", testKey)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func random(t *testing.T, n int) []byte {
	t.Helper()
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		t.Fatalf("rand: %v", err)
	}
	return b
}

// readAll reads id's finished plaintext back through the store.
func readAll(t *testing.T, s *Store, id string, size int64) []byte {
	t.Helper()
	r, err := s.Open(id, size)
	if err != nil {
		t.Fatalf("Open %s: %v", id, err)
	}
	defer func() { _ = r.Close() }()
	got, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read %s: %v", id, err)
	}
	return got
}

// write puts payload into a new upload of a file of size bytes and finalizes
// it when finish is set.
func write(t *testing.T, s *Store, id string, payload []byte, size int64, finish bool) *Upload {
	t.Helper()
	u, err := s.Create(id, size)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if n, err := u.Write(payload); err != nil || n != len(payload) {
		t.Fatalf("Write: n=%d err=%v", n, err)
	}
	if finish {
		if err := u.Finalize(); err != nil {
			t.Fatalf("Finalize: %v", err)
		}
	}
	return u
}

func TestUploadRoundtrip(t *testing.T) {
	s := openStore(t)
	payload := random(t, 3*C+C/2)

	u, err := s.Create("f_abc", int64(len(payload)))
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
	info, err := s.root.Stat("f_abc")
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if info.Size() != CipherLen(int64(len(payload))) {
		t.Fatalf("on disk %d bytes, want %d: a header and four sealed chunks", info.Size(), CipherLen(int64(len(payload))))
	}
	if got := readAll(t, s, "f_abc", size); !bytes.Equal(got, payload) {
		t.Fatalf("readback mismatch: %d bytes", len(got))
	}
}

// A file whose size is a whole number of chunks ends with a full chunk, and
// that chunk is the last one.
func TestAFileOfWholeChunksEndsOnAFullChunk(t *testing.T) {
	s := openStore(t)
	payload := random(t, 2*C)
	write(t, s, "f_even", payload, int64(len(payload)), true)
	if got := readAll(t, s, "f_even", int64(len(payload))); !bytes.Equal(got, payload) {
		t.Fatal("a file of two whole chunks does not read back")
	}
	one := random(t, 1)
	write(t, s, "f_one", one, 1, true)
	if got := readAll(t, s, "f_one", 1); !bytes.Equal(got, one) {
		t.Fatal("a one-byte file does not read back")
	}
}

func TestAbortDiscardsPart(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_gone", []byte("half"), 10, false)
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
	u, err := s.Create("f_part", 10)
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
		if _, err := s.Create(id, 10); err == nil {
			t.Fatalf("Create(%q) unexpectedly succeeded", id)
		}
		if _, err := s.Open(id, 10); err == nil {
			t.Fatalf("Open(%q) unexpectedly succeeded", id)
		}
		if _, err := s.OpenSealed(id); err == nil {
			t.Fatalf("OpenSealed(%q) unexpectedly succeeded", id)
		}
	}
	if s.Exists(strings.Repeat("../", 10) + "etc/passwd") {
		t.Fatal("traversal id reported existing")
	}
	for _, id := range []string{"../escape", "a/../../b"} {
		if _, err := s.Resume(id, 0, 10); err == nil {
			t.Fatalf("Resume(%q) unexpectedly succeeded", id)
		}
	}
	// "a/../../b" never gets as far as the "..": there is no "a" to walk
	// through, so it simply is not there. A plain escape is refused outright.
	if _, err := s.Received("../escape"); err == nil {
		t.Fatal(`Received("../escape") unexpectedly succeeded`)
	}
}

// partLen is how long id's part is on disk.
func partLen(t *testing.T, s *Store, id string) int64 {
	t.Helper()
	info, err := s.root.Stat(id + partSuffix)
	if err != nil {
		t.Fatalf("stat part: %v", err)
	}
	return info.Size()
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
	u := write(t, s, "f_new", random(t, C+C/2), 3*C, false)
	if got := record(t, s, "f_new"); got != "" {
		t.Fatalf("record before any checkpoint = %q, want none", got)
	}
	if got := mustReceived(t, s, "f_new"); got != 0 {
		t.Fatalf("Received before any checkpoint = %d, want 0: nothing is durable yet", got)
	}
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	// The sealed chunk, and not the half one still in memory.
	if got := record(t, s, "f_new"); got != strconv.Itoa(C) {
		t.Fatalf("record after checkpoint = %q, want %d", got, C)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
}

// FR-009/FR-010: a chunk still arriving never touches the disk - not even
// encrypted - and a request that breaks inside it leaves the next one to start
// at that chunk's first byte.
func TestTheChunkStillArrivingNeverReachesTheDisk(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_tail", random(t, C/2), 3*C, false)
	if got := partLen(t, s, "f_tail"); got != HeaderSize {
		t.Fatalf("the part holds %d bytes with half a chunk received, want the %d of the header alone", got, HeaderSize)
	}
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	if got := mustReceived(t, s, "f_tail"); got != 0 {
		t.Fatalf("Received after a break inside the first chunk = %d, want 0", got)
	}
}

func TestResumeContinuesFromWhatIsDurableAndDropsTheRest(t *testing.T) {
	s := openStore(t)
	payload := random(t, 4*C+100)
	size := int64(len(payload))
	u := write(t, s, "f_cut", payload[:2*C], size, false)
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	// A third chunk sealed after the last checkpoint and half of a fourth in
	// memory - and then the process dies: the part holds the third, the
	// record does not vouch for it.
	if _, err := u.Write(payload[2*C : 3*C+C/2]); err != nil {
		t.Fatalf("Write: %v", err)
	}
	_ = u.f.Close()

	if got := mustReceived(t, s, "f_cut"); got != 2*C {
		t.Fatalf("Received = %d, want the %d durable bytes, not the chunk sealed after them", got, 2*C)
	}
	u2, err := s.Resume("f_cut", 2*C, size)
	if err != nil {
		t.Fatalf("Resume at 2C: %v", err)
	}
	if _, err := u2.Write(payload[2*C:]); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u2.Finalize(); err != nil {
		t.Fatalf("Finalize: %v", err)
	}
	if got := readAll(t, s, "f_cut", size); !bytes.Equal(got, payload) {
		t.Fatal("the continued file is not the bytes that were sent")
	}
}

func TestReceivedIsTheSmallerOfTheRecordAndThePart(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_min", random(t, 3*C), 5*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	// Something outside the server cut the part below what the record says,
	// in the middle of a chunk.
	f, err := s.root.OpenFile("f_min"+partSuffix, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open part: %v", err)
	}
	if err := f.Truncate(CipherLen(C) + 100); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	_ = f.Close()
	if got := mustReceived(t, s, "f_min"); got != C {
		t.Fatalf("Received = %d, want the part's one whole chunk: a record cannot vouch for bytes that are gone", got)
	}
	if got := mustReceived(t, s, "f_never"); got != 0 {
		t.Fatalf("Received of an unknown id = %d, want 0", got)
	}
}

func TestAnUnreadableRecordOrHeaderVouchesForNothing(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_garbled", random(t, 2*C), 3*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	if err := s.root.WriteFile("f_garbled"+syncedSuffix, []byte("not a number"), 0o600); err != nil {
		t.Fatalf("garble record: %v", err)
	}
	if got := mustReceived(t, s, "f_garbled"); got != 0 {
		t.Fatalf("Received = %d, want 0", got)
	}

	// A part whose header this build does not write - a format from another
	// version, say - is nothing to continue: its bytes would not open.
	u = write(t, s, "f_other", random(t, 2*C), 3*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	f, err := s.root.OpenFile("f_other"+partSuffix, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open part: %v", err)
	}
	if _, err := f.WriteAt([]byte{2}, 4); err != nil {
		t.Fatalf("write version: %v", err)
	}
	_ = f.Close()
	if got := mustReceived(t, s, "f_other"); got != 0 {
		t.Fatalf("Received of a part with another header = %d, want 0", got)
	}
}

func TestResumeRefusesAnOffsetItCannotContinueFrom(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_short", random(t, 2*C), 4*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	if _, err := s.Resume("f_short", 3*C, 4*C); !errors.Is(err, ErrShortPart) {
		t.Fatalf("Resume past the durable bytes err = %v, want ErrShortPart", err)
	}
	// Inside a chunk: nothing but the chunk's first byte can be continued
	// from, because only whole chunks are on disk.
	if _, err := s.Resume("f_short", C+100, 4*C); !errors.Is(err, ErrShortPart) {
		t.Fatalf("Resume inside a chunk err = %v, want ErrShortPart", err)
	}
	if _, err := s.Resume("f_short", -1, 4*C); err == nil {
		t.Fatal("Resume at a negative offset succeeded")
	}
	if _, err := s.Resume("f_short", 0, 0); err == nil {
		t.Fatal("Resume of an empty file succeeded")
	}
}

func TestResumeLowersTheRecordBeforeCuttingThePart(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_back", random(t, 3*C), 4*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}

	u2, err := s.Resume("f_back", C, 4*C)
	if err != nil {
		t.Fatalf("Resume at C: %v", err)
	}
	// Before a single new byte: the record already says C. Left at 3C, it
	// would vouch after a crash for chunks of the NEXT write, which may never
	// reach the disk.
	if got := record(t, s, "f_back"); got != strconv.Itoa(C) {
		t.Fatalf("record after Resume at C = %q, want %d", got, C)
	}
	if got := partLen(t, s, "f_back"); got != CipherLen(C) {
		t.Fatalf("part after Resume at C holds %d bytes, want %d", got, CipherLen(C))
	}
	if err := u2.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
}

func TestRollbackDropsWhatThisRequestWrote(t *testing.T) {
	s := openStore(t)
	first := random(t, C)
	u := write(t, s, "f_roll", first, 4*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	u2, err := s.Resume("f_roll", C, 4*C)
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u2.Write(random(t, 2*C)); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u2.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	if err := u2.Rollback(C); err != nil {
		t.Fatalf("Rollback: %v", err)
	}
	if got := record(t, s, "f_roll"); got != strconv.Itoa(C) {
		t.Fatalf("record after rollback = %q, want %d", got, C)
	}
	if got := partLen(t, s, "f_roll"); got != CipherLen(C) {
		t.Fatalf("part after rollback holds %d bytes, want the one chunk from before", got)
	}
	// And the chunk from before is the one that was sent.
	payload := append(append([]byte{}, first...), random(t, 3*C)...)
	u4, err := s.Resume("f_roll", C, int64(len(payload)))
	if err != nil {
		t.Fatalf("Resume: %v", err)
	}
	if _, err := u4.Write(payload[C:]); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := u4.Finalize(); err != nil {
		t.Fatalf("Finalize: %v", err)
	}
	if got := readAll(t, s, "f_roll", int64(len(payload))); !bytes.Equal(got, payload) {
		t.Fatal("the file after a rollback is not the bytes that were kept and sent")
	}
}

func TestAWriteBeyondTheDeclaredSizeIsRefused(t *testing.T) {
	s := openStore(t)
	u, err := s.Create("f_over", 100)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	defer u.Abort()
	n, err := u.Write(random(t, 150))
	if err == nil || n != 100 {
		t.Fatalf("Write of 150 into a file of 100 = %d, %v; want 100 taken and a refusal", n, err)
	}
}

func TestFinalizeRefusesAFileNotYetWhole(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_early", random(t, C), 2*C, false)
	if err := u.Finalize(); err == nil {
		t.Fatal("Finalize of a file with half its bytes succeeded")
	}
	if s.Exists("f_early") {
		t.Fatal("a refused Finalize made the file visible")
	}
}

func TestFinalizeLeavesNoRecordBehind(t *testing.T) {
	s := openStore(t)
	u := write(t, s, "f_done", []byte("whole file"), 10, false)
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
	u := write(t, s, "f_stray", []byte("whole file"), 10, false)
	if err := u.Checkpoint(); err != nil {
		t.Fatalf("Checkpoint: %v", err)
	}
	// A crash in the middle of an earlier record left its temporary behind.
	if err := s.root.WriteFile("f_stray"+syncedSuffix+tmpSuffix, []byte("7"), 0o600); err != nil {
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
	u := write(t, s, "f_abort", random(t, C), 2*C, false)
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
	u := write(t, s, "f_sweep", random(t, C), 2*C, false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	// A crash in the middle of writing a record leaves its temporary.
	if err := s.root.WriteFile("f_sweep"+syncedSuffix+tmpSuffix, []byte("7"), 0o600); err != nil {
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

// FR-009: neither a finished file nor an unfinished part holds a byte of
// what was sent.
func TestNothingOnDiskIsTheBytesThatWereSent(t *testing.T) {
	s := openStore(t)
	marker := []byte("ATTACHMENT-MARKER-047")
	payload := bytes.Repeat(marker, 3*C/len(marker)+1)
	write(t, s, "f_whole", payload, int64(len(payload)), true)
	u := write(t, s, "f_half", payload[:2*C+10], int64(len(payload)), false)
	if err := u.Suspend(); err != nil {
		t.Fatalf("Suspend: %v", err)
	}
	dir := filepath.Dir(s.root.Name() + "/x")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatalf("read %s: %v", e.Name(), err)
		}
		if bytes.Contains(data, marker) {
			t.Fatalf("%s holds the sent bytes in the clear", e.Name())
		}
	}
}

// FR-010, SC-004: any range reads exactly the bytes of the file, across chunk
// boundaries and up to its last byte.
func TestARangeReadsExactlyItsBytes(t *testing.T) {
	s := openStore(t)
	payload := random(t, 5*C+1234)
	size := int64(len(payload))
	write(t, s, "f_range", payload, size, true)
	r, err := s.Open("f_range", size)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = r.Close() }()
	if end, err := r.Seek(0, io.SeekEnd); err != nil || end != size {
		t.Fatalf("Seek to the end = %d, %v; want %d", end, err, size)
	}
	for _, rg := range []struct{ off, n int64 }{
		{0, 1}, {0, C}, {C - 1, 2}, {C, C}, {3*C + 7, 2*C + 100}, {size - 1, 1}, {size - 1234, 1234}, {100, size - 100},
	} {
		if _, err := r.Seek(rg.off, io.SeekStart); err != nil {
			t.Fatalf("Seek %d: %v", rg.off, err)
		}
		got := make([]byte, rg.n)
		if _, err := io.ReadFull(r, got); err != nil {
			t.Fatalf("read %d bytes at %d: %v", rg.n, rg.off, err)
		}
		if !bytes.Equal(got, payload[rg.off:rg.off+rg.n]) {
			t.Fatalf("bytes %d..%d differ from the file", rg.off, rg.off+rg.n)
		}
	}
	if _, err := r.Seek(size, io.SeekStart); err != nil {
		t.Fatalf("Seek: %v", err)
	}
	if n, err := r.Read(make([]byte, 10)); n != 0 || !errors.Is(err, io.EOF) {
		t.Fatalf("a read at the end = %d, %v; want EOF", n, err)
	}
}

// Each chunk carries its own seal: a changed byte, chunks swapped, a file
// cut at a chunk boundary, a chunk carried over from another file - none of
// it opens, and none of it is served.
func TestBytesThatWereTamperedWithDoNotOpen(t *testing.T) {
	s := openStore(t)
	payload := random(t, 4*C+500)
	size := int64(len(payload))
	disk := filepath.Join(s.root.Name(), "f_t")

	reset := func() []byte {
		t.Helper()
		_ = s.Remove("f_t")
		write(t, s, "f_t", payload, size, true)
		data, err := os.ReadFile(disk)
		if err != nil {
			t.Fatalf("read: %v", err)
		}
		return data
	}
	readAt := func(off, n int64, wantSize int64) error {
		t.Helper()
		r, err := s.Open("f_t", wantSize)
		if err != nil {
			return err
		}
		defer func() { _ = r.Close() }()
		if _, err := r.Seek(off, io.SeekStart); err != nil {
			return err
		}
		_, err = io.ReadFull(r, make([]byte, n))
		return err
	}
	chunkAt := func(i int64) int64 { return HeaderSize + i*sealedSize }

	// A byte flipped in chunk 2: chunk 2 refuses, chunk 0 still reads.
	data := reset()
	data[chunkAt(2)+10] ^= 1
	if err := os.WriteFile(disk, data, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := readAt(2*C, 10, size); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("reading a changed chunk = %v, want ErrCorrupt", err)
	}
	if err := readAt(0, C, size); err != nil {
		t.Fatalf("reading an untouched chunk = %v", err)
	}

	// Chunks 0 and 1 swapped.
	data = reset()
	swapped := append([]byte{}, data...)
	copy(swapped[chunkAt(0):chunkAt(1)], data[chunkAt(1):chunkAt(2)])
	copy(swapped[chunkAt(1):chunkAt(2)], data[chunkAt(0):chunkAt(1)])
	if err := os.WriteFile(disk, swapped, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := readAt(0, 10, size); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("reading a chunk moved to another place = %v, want ErrCorrupt", err)
	}

	// The last chunk cut off: the length no longer fits the size, and claiming
	// the shorter size makes the new last chunk one sealed as not-last.
	data = reset()
	if err := os.WriteFile(disk, data[:chunkAt(4)], 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := readAt(0, 10, size); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("opening a cut file at its size = %v, want ErrCorrupt", err)
	}
	if err := readAt(3*C, 10, 4*C); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("reading a cut file as if it ended there = %v, want ErrCorrupt", err)
	}

	// Chunk 1 of another file under another id.
	data = reset()
	other := random(t, int(size))
	write(t, s, "f_u", other, size, true)
	otherData, err := os.ReadFile(filepath.Join(s.root.Name(), "f_u"))
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	copy(data[chunkAt(1):chunkAt(2)], otherData[chunkAt(1):chunkAt(2)])
	if err := os.WriteFile(disk, data, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := readAt(C, 10, size); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("reading another file's chunk = %v, want ErrCorrupt", err)
	}

	// Another header version.
	data = reset()
	data[4] = 2
	if err := os.WriteFile(disk, data, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := readAt(0, 10, size); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("opening a file of another version = %v, want ErrCorrupt", err)
	}

	// And a store with another data key opens nothing of this one's.
	data = reset()
	_ = data
	stranger, err := Open(s.root.Name(), bytes.Repeat([]byte{0x6c}, 32))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = stranger.Close() }()
	r, err := stranger.Open("f_t", size)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer func() { _ = r.Close() }()
	if _, err := io.ReadFull(r, make([]byte, 10)); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("reading with another data key = %v, want ErrCorrupt", err)
	}
}

// Size names the plaintext, and a file cut inside a chunk's tag is no file.
func TestSizeIsThePlaintextAndATornFileIsNoFile(t *testing.T) {
	s := openStore(t)
	payload := random(t, 2*C+5)
	write(t, s, "f_size", payload, int64(len(payload)), true)
	if n, err := s.Size("f_size"); err != nil || n != int64(len(payload)) {
		t.Fatalf("Size = %d, %v; want %d", n, err, len(payload))
	}
	disk := filepath.Join(s.root.Name(), "f_size")
	if err := os.Truncate(disk, CipherLen(2*C)+tagSize-3); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	if _, err := s.Size("f_size"); !errors.Is(err, ErrCorrupt) {
		t.Fatalf("Size of a torn file = %v, want ErrCorrupt", err)
	}
}

func TestWhatAPartCountsAsDurable(t *testing.T) {
	for _, c := range []struct {
		name         string
		synced, held int64
		want         int64
	}{
		{"nothing recorded", 0, 3 * C, 0},
		{"a chunk sealed after the last checkpoint", 2 * C, 3 * C, 2 * C},
		{"every byte, the shorter last chunk included", 2*C + 5, 2*C + 5, 2*C + 5},
		{"the last chunk sealed and not yet recorded", 2 * C, 2*C + 5, 2 * C},
		{"a part cut inside a chunk", 3 * C, C + 84, C},
		{"a record inside a chunk", 100, 2 * C, 0},
		{"a file of whole chunks, all in", 2 * C, 2 * C, 2 * C},
	} {
		if got := durable(c.synced, c.held); got != c.want {
			t.Errorf("%s: durable(%d, %d) = %d, want %d", c.name, c.synced, c.held, got, c.want)
		}
	}
}

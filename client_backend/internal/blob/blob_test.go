package blob

import (
	"bytes"
	"errors"
	"io"
	"io/fs"
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
}

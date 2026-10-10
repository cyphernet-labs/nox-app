package db

import (
	"bytes"
	"context"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"lukechampine.com/adiantum"
)

// otherKey is a data key that opens none of the test databases.
var otherKey = bytes.Repeat([]byte{0x5b}, KeySize)

// filesIn is every file in dir with its bytes: what a refused key must leave
// exactly as it found it, down to a file that was not there before.
func filesIn(t *testing.T, dir string) map[string]string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	files := map[string]string{}
	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatalf("read %s: %v", e.Name(), err)
		}
		files[e.Name()] = string(data)
	}
	return files
}

// committedInTheWAL makes a database whose newest committed row - a person
// labelled with the marker - lives in its WAL alone, and returns a copy of it
// as a crash leaves it: the database file and the WAL as they are while
// connections are still open. The -shm stays behind: a crash may leave one or
// not, and the next open rebuilds it either way.
func committedInTheWAL(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "nox.db")
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	if _, err := d.Write.Exec("INSERT INTO users (user_id, label, created_at) VALUES ('u_1', ?, 1)", marker); err != nil {
		t.Fatalf("insert: %v", err)
	}

	crashed := filepath.Join(t.TempDir(), "nox.db")
	copyFile(t, path, crashed)
	copyFile(t, path+"-wal", crashed+"-wal")

	// The test means something only if the row really is in the WAL alone:
	// the database file without its WAL has not a single table yet.
	bare := filepath.Join(t.TempDir(), "nox.db")
	copyFile(t, path, bare)
	b, err := Open(bare, testKey)
	if err != nil {
		t.Fatalf("open the database file without its WAL: %v", err)
	}
	defer func() { _ = b.Close() }()
	var tables int
	if err := b.Read.QueryRow("SELECT COUNT(1) FROM sqlite_master").Scan(&tables); err != nil || tables != 0 {
		t.Fatalf("the database file holds %d tables (%v) without its WAL, want none: the WAL was checkpointed", tables, err)
	}
	return crashed
}

func copyFile(t *testing.T, from, to string) {
	t.Helper()
	data, err := os.ReadFile(from)
	if err != nil {
		t.Fatalf("read %s: %v", from, err)
	}
	if err := os.WriteFile(to, data, 0o600); err != nil {
		t.Fatalf("write %s: %v", to, err)
	}
}

// readsTheMarker opens path with the test key and finds the marker row.
func readsTheMarker(t *testing.T, path string) {
	t.Helper()
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open with the right key: %v", err)
	}
	defer func() { _ = d.Close() }()
	var label string
	if err := d.Read.QueryRow("SELECT label FROM users WHERE user_id = 'u_1'").Scan(&label); err != nil || label != marker {
		t.Fatalf("the committed row = %q (%v), want it back", label, err)
	}
}

// A server killed with its newest commits still in the WAL, then offered a key
// file that is not its own: the key is refused and not one byte on disk moves -
// above all not the WAL, which SQLite, let near it with that key, reads as
// empty and deletes on close. The right key then finds every commit.
func TestAnotherKeyLeavesTheWALOfACrashedDatabaseAsItWas(t *testing.T) {
	crashed := committedInTheWAL(t)
	dir := filepath.Dir(crashed)
	before := filesIn(t, dir)

	if d, err := Open(crashed, otherKey); !errors.Is(err, ErrWrongKey) {
		if d != nil {
			_ = d.Close()
		}
		t.Fatalf("Open with another key = %v, want ErrWrongKey", err)
	}
	if after := filesIn(t, dir); !maps.Equal(before, after) {
		t.Fatalf("another key changed the files on disk: %v before, %v after",
			slices.Sorted(maps.Keys(before)), slices.Sorted(maps.Keys(after)))
	}
	readsTheMarker(t, crashed)
}

// A crash while a checkpoint writes the database's first page can tear that
// block - noise under every key - while the WAL still holds the page. The right
// key still opens the database (SQLite reads the page from the WAL, and the
// next checkpoint writes it whole), and another key is still refused untouched.
// A check of the database file alone would turn the right key away here.
func TestAFirstPageTornByACrashStillOpensWithItsKey(t *testing.T) {
	crashed := committedInTheWAL(t)
	f, err := os.OpenFile(crashed, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if _, err := f.WriteAt(make([]byte, blockSize/2), 0); err != nil {
		t.Fatalf("tear the first block: %v", err)
	}
	if err := f.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	dir := filepath.Dir(crashed)
	before := filesIn(t, dir)

	if d, err := Open(crashed, otherKey); !errors.Is(err, ErrWrongKey) {
		if d != nil {
			_ = d.Close()
		}
		t.Fatalf("Open with another key = %v, want ErrWrongKey", err)
	}
	if after := filesIn(t, dir); !maps.Equal(before, after) {
		t.Fatal("another key changed the files on disk")
	}
	readsTheMarker(t, crashed)
}

// A database that crashed in its very first transaction has nothing to show
// but its rollback journal - and the key that wrote the journal is the
// database's.
func TestTheKeyCheckReadsAHotJournal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nox.db")
	// The database's first block, torn: nothing a key can read.
	if err := os.WriteFile(path, bytes.Repeat([]byte{0xa5}, blockSize), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	block := make([]byte, blockSize)
	copy(block, journalHeader)
	var tweak [8]byte
	if err := os.WriteFile(path+"-journal", adiantum.New(testKey).Encrypt(block, tweak[:]), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := checkKey(path, testKey); err != nil {
		t.Fatalf("the key that wrote the journal = %v, want it taken", err)
	}
	if err := checkKey(path, otherKey); !errors.Is(err, ErrWrongKey) {
		t.Fatalf("another key = %v, want ErrWrongKey", err)
	}
}

// Nothing written yet is nothing to check against: no file, or one shorter
// than a block, takes any key - SQLite then makes the database.
func TestNothingWrittenYetTakesAnyKey(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nox.db")
	if err := checkKey(path, otherKey); err != nil {
		t.Fatalf("no database = %v, want nothing to check", err)
	}
	if err := os.WriteFile(path, []byte("SQLite format 3\x00"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := checkKey(path, otherKey); err != nil {
		t.Fatalf("a database shorter than a block = %v, want nothing to check", err)
	}
}

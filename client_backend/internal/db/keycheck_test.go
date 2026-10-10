package db

import (
	"bytes"
	"context"
	"errors"
	"io/fs"
	"maps"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/ncruces/go-sqlite3"
	"github.com/ncruces/go-sqlite3/util/vfsutil"
	"github.com/ncruces/go-sqlite3/vfs"
	adiantumvfs "github.com/ncruces/go-sqlite3/vfs/adiantum"
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

// A database whose first page tore while a rollback journal held the page to
// put back - the switch to WAL journals page 1 of a database that has one, a
// snapshot's say - shows its key only through that journal.
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
// than a block with nothing beside it, takes any key - SQLite then makes the
// database. So does an empty one, whatever lies beside it: SQLite deletes a
// WAL or a journal next to a database of zero pages without reading either.
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
	noise := bytes.Repeat([]byte{0xa5}, blockSize)
	for _, f := range []struct {
		path string
		data []byte
	}{{path, nil}, {path + "-wal", noise}, {path + "-journal", noise}} {
		if err := os.WriteFile(f.path, f.data, 0o600); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	if err := checkKey(path, otherKey); err != nil {
		t.Fatalf("an empty database beside a WAL and a journal = %v, want nothing to check", err)
	}
}

// crashVFS is the operating system's VFS with one moment of SQLite's work on a
// rollback journal caught: before the journal's header is written for the
// beforeHeader-th time, or right after the journal's afterSync-th sync, it
// copies the database and its journal into into - what a power cut at that
// moment leaves on disk. It sits under the encryption, registered through
// adiantum.Wrap the way the "adiantum" VFS wraps the operating system's, so
// what it copies are the bytes the disk holds.
type crashVFS struct {
	vfs.VFS
	db, into                string
	beforeHeader, afterSync int

	headers, syncs int
	copied         bool
	err            error
}

func (c *crashVFS) OpenFilename(name *vfs.Filename, flags vfs.OpenFlag) (vfs.File, vfs.OpenFlag, error) {
	f, flags, err := vfsutil.WrapOpenFilename(c.VFS, name, flags)
	if err == nil && flags&vfs.OPEN_MAIN_JOURNAL != 0 {
		f = &crashJournal{File: f, crash: c}
	}
	return f, flags, err
}

func (c *crashVFS) copy() {
	if c.copied {
		return
	}
	c.copied = true
	for _, suffix := range []string{"", "-journal"} {
		data, err := os.ReadFile(c.db + suffix)
		if err == nil {
			err = os.WriteFile(filepath.Join(c.into, "nox.db"+suffix), data, 0o600)
		}
		if err != nil {
			c.err = err
			return
		}
	}
}

type crashJournal struct {
	vfs.File
	crash *crashVFS
}

func (j *crashJournal) WriteAt(p []byte, off int64) (int, error) {
	if off == 0 {
		j.crash.headers++
		if j.crash.headers == j.crash.beforeHeader {
			j.crash.copy()
		}
	}
	return j.File.WriteAt(p, off)
}

func (j *crashJournal) Sync(flags vfs.SyncFlag) error {
	err := j.File.Sync(flags)
	j.crash.syncs++
	if j.crash.syncs == j.crash.afterSync {
		j.crash.copy()
	}
	return err
}

// newDatabaseCutOff makes a new database through crash - its first
// transaction is the switch to WAL, which SQLite makes with a rollback
// journal - and returns the copy crash caught on the way, after checking that
// it holds an empty database beside a whole journal block whose header does,
// or does not, hold its magic under the test key.
func newDatabaseCutOff(t *testing.T, crash *crashVFS, withMagic bool) string {
	t.Helper()
	crash.VFS = vfs.Find("")
	crash.db = filepath.Join(t.TempDir(), "nox.db")
	crash.into = t.TempDir()
	vfs.Register("nox-crash", adiantumvfs.Wrap(crash, nil))
	t.Cleanup(func() { vfs.Unregister("nox-crash") })
	c, err := sqlite3.Open(slashURI(filepath.ToSlash(crash.db), url.Values{"vfs": {"nox-crash"}}))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	err = connect(testKey)(c)
	if cerr := c.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		t.Fatalf("the first transaction: %v", err)
	}
	if !crash.copied || crash.err != nil {
		t.Fatalf("the moment was not caught (copied %v): %v", crash.copied, crash.err)
	}

	image := filepath.Join(crash.into, "nox.db")
	if info, err := os.Stat(image); err != nil || info.Size() != 0 {
		t.Fatalf("the database in the image is not empty (%v)", err)
	}
	journal, err := os.ReadFile(image + "-journal")
	if err != nil || len(journal) != blockSize {
		t.Fatalf("the journal in the image is %d bytes (%v), want one block", len(journal), err)
	}
	var tweak [8]byte
	header := adiantum.New(testKey).Decrypt(journal, tweak[:])
	if got := bytes.HasPrefix(header, journalHeader); got != withMagic {
		t.Fatalf("the journal's header holds its magic: %v, want %v - the image is not of the moment meant", got, withMagic)
	}
	return image
}

// opensInWAL opens path with the test key and finds a database in WAL mode
// with no journal left beside it.
func opensInWAL(t *testing.T, path string) {
	t.Helper()
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open with the right key: %v", err)
	}
	defer func() { _ = d.Close() }()
	var mode string
	if err := d.Write.QueryRow("PRAGMA journal_mode").Scan(&mode); err != nil || mode != "wal" {
		t.Fatalf("journal_mode = %q (%v), want wal", mode, err)
	}
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	if _, err := os.Stat(path + "-journal"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("the journal is still there (stat err %v)", err)
	}
}

// A new database cut off in its first transaction before its journal held its
// magic: SQLite writes the journal's header with zeros where the magic goes,
// syncs, and only then writes the magic, so the cut leaves an empty database
// beside a whole journal block that shows no header under any key. SQLite
// deletes that journal unread and makes the database; the key check must not
// turn the right key away over it - on this start, and on every later one.
func TestANewDatabaseCutOffBeforeItsJournalHadItsMagicOpens(t *testing.T) {
	image := newDatabaseCutOff(t, &crashVFS{beforeHeader: 2}, false)
	opensInWAL(t, image)
}

// The same first transaction cut off a moment later: the journal holds its
// magic, and the first write to the database tore - part of a block, which
// SQLite counts as one page, so it reads the journal beside it and rolls the
// database back to empty. Here the journal answers for the key. Another key is
// refused with nothing on disk changed - under it SQLite would read the
// journal as noise and delete it, leaving the torn page for good - and the
// right key opens the database.
func TestATornFirstWriteOfANewDatabaseKeepsItsJournalFromAnotherKey(t *testing.T) {
	image := newDatabaseCutOff(t, &crashVFS{afterSync: 2}, true)
	if err := os.WriteFile(image, bytes.Repeat([]byte{0x5a}, blockSize/2), 0o600); err != nil {
		t.Fatalf("tear the first write: %v", err)
	}
	dir := filepath.Dir(image)
	before := filesIn(t, dir)
	if d, err := Open(image, otherKey); !errors.Is(err, ErrWrongKey) {
		if d != nil {
			_ = d.Close()
		}
		t.Fatalf("Open with another key = %v, want ErrWrongKey", err)
	}
	if after := filesIn(t, dir); !maps.Equal(before, after) {
		t.Fatal("another key changed the files on disk")
	}
	opensInWAL(t, image)
}

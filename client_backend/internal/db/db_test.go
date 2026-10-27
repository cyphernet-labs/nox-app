package db

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"maps"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/ncruces/go-sqlite3"
	"github.com/ncruces/go-sqlite3/vfs"
)

// testKey is the data key every test database here is encrypted with.
var testKey = bytes.Repeat([]byte{0x5a}, KeySize)

func openMigrated(t *testing.T) *DB {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.db")
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	return d
}

func TestMigrateFromZeroSetsVersionAndSchema(t *testing.T) {
	d := openMigrated(t)

	var version int
	if err := d.Read.QueryRow("PRAGMA user_version").Scan(&version); err != nil {
		t.Fatalf("user_version: %v", err)
	}
	if version != 1 {
		t.Fatalf("user_version = %d, want 1", version)
	}

	for _, table := range []string{"chats", "messages", "events", "files"} {
		var name string
		err := d.Read.QueryRow(
			"SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", table,
		).Scan(&name)
		if err != nil {
			t.Fatalf("table %s missing: %v", table, err)
		}
	}
}

func TestMigrateIsIdempotent(t *testing.T) {
	d := openMigrated(t)

	version, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations"))
	if err != nil {
		t.Fatalf("second Migrate: %v", err)
	}
	if version != 1 {
		t.Fatalf("version after re-run = %d, want 1", version)
	}
}

func TestPragmasApplied(t *testing.T) {
	d := openMigrated(t)

	var journal string
	if err := d.Write.QueryRow("PRAGMA journal_mode").Scan(&journal); err != nil {
		t.Fatalf("journal_mode: %v", err)
	}
	if journal != "wal" {
		t.Fatalf("journal_mode = %q, want wal", journal)
	}

	var fk int
	if err := d.Write.QueryRow("PRAGMA foreign_keys").Scan(&fk); err != nil {
		t.Fatalf("foreign_keys: %v", err)
	}
	if fk != 1 {
		t.Fatalf("foreign_keys = %d, want 1", fk)
	}

	// On the read pool too: every connection runs the same list.
	var temp int
	if err := d.Read.QueryRow("PRAGMA temp_store").Scan(&temp); err != nil {
		t.Fatalf("temp_store: %v", err)
	}
	if temp != 2 {
		t.Fatalf("temp_store = %d, want 2 (memory)", temp)
	}
}

func TestSplitStatements(t *testing.T) {
	script := "CREATE TABLE a (x INT);\n\nCREATE INDEX i ON a (x);\n"
	got := splitStatements(script)
	if len(got) != 2 {
		t.Fatalf("statements = %d, want 2: %q", len(got), got)
	}
}

func TestSchemaHasFilesLinkage(t *testing.T) {
	d := openMigrated(t)

	// messages gained the file_id column.
	var cnt int
	err := d.Read.QueryRow(
		"SELECT COUNT(1) FROM pragma_table_info('messages') WHERE name = 'file_id'").Scan(&cnt)
	if err != nil || cnt != 1 {
		t.Fatalf("messages.file_id present = %d err=%v", cnt, err)
	}
	// The partial unique index guarding one-file-one-message exists.
	var name string
	err = d.Read.QueryRow(
		"SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_messages_file'").Scan(&name)
	if err != nil || name != "idx_messages_file" {
		t.Fatalf("idx_messages_file = %q err=%v", name, err)
	}
}

// marker is what the encryption tests write and then look for on disk.
const marker = "PLAINTEXT-MARKER-047"

// filesHolding lists every file beside the database whose bytes contain any
// of needles.
func filesHolding(t *testing.T, dir string, needles ...[]byte) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	var found []string
	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatalf("read %s: %v", e.Name(), err)
		}
		for _, n := range needles {
			if bytes.Contains(data, n) {
				found = append(found, e.Name())
				break
			}
		}
	}
	return found
}

// FR-008: no page of the database - nor of its WAL - lies on disk in the
// clear, neither while it is open and the WAL holds the newest pages nor
// after it closed.
func TestNoPageReachesTheDiskInTheClear(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nox.db")
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	tx, err := d.Write.Begin()
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	for i := range 3000 {
		if _, err := tx.Exec("INSERT INTO users (user_id, label, created_at) VALUES (?, ?, 1) ON CONFLICT DO NOTHING",
			"u_marker", marker); err != nil {
			t.Fatalf("insert: %v", err)
		}
		if _, err := tx.Exec(
			"INSERT INTO chats (chat_id, name, name_ci, created_at, created_by_label, last_activity_at) VALUES (?, ?, ?, 1, ?, 1)",
			fmt.Sprintf("c_%d", i), fmt.Sprintf("%s %d", marker, i), fmt.Sprintf("%s-%d", strings.ToLower(marker), i), marker); err != nil {
			t.Fatalf("insert chat: %v", err)
		}
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit: %v", err)
	}
	needles := [][]byte{[]byte(marker), []byte(strings.ToLower(marker)), []byte("CREATE TABLE")}
	if _, err := os.Stat(path + "-wal"); err != nil {
		t.Fatalf("the WAL is not there to be looked at: %v", err)
	}
	if found := filesHolding(t, dir, needles...); len(found) > 0 {
		t.Fatalf("open database: plaintext in %v", found)
	}
	if err := d.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if found := filesHolding(t, dir, needles...); len(found) > 0 {
		t.Fatalf("closed database: plaintext in %v", found)
	}

	// And the right key reads it all back.
	again, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer func() { _ = again.Close() }()
	var n int
	if err := again.Read.QueryRow("SELECT COUNT(1) FROM chats WHERE name LIKE ?", marker+"%").Scan(&n); err != nil || n != 3000 {
		t.Fatalf("rows back = %d (%v), want 3000", n, err)
	}
}

func TestAnotherKeyOpensNothing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nox.db")
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	if err := d.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	before := filesIn(t, filepath.Dir(path))
	if d, err := Open(path, otherKey); !errors.Is(err, ErrWrongKey) {
		if d != nil {
			_ = d.Close()
		}
		t.Fatalf("Open with another key = %v, want ErrWrongKey", err)
	}
	// Not even a WAL or an index beside it: the key was refused before SQLite
	// opened anything.
	if after := filesIn(t, filepath.Dir(path)); !maps.Equal(before, after) {
		t.Fatal("another key changed the files on disk")
	}
	if _, err := Open(path, testKey[:16]); err == nil {
		t.Fatal("a 16-byte key was taken")
	}
}

// A path is a file name, whatever is in it: a space, a percent sign and a
// question mark must not turn into a URI's escapes or its query.
func TestAPathIsAFileNameWhateverItHolds(t *testing.T) {
	name := "my 50% share?"
	if runtime.GOOS == "windows" {
		// No Windows file name holds a question mark.
		name = "my 50% share"
	}
	dir := filepath.Join(t.TempDir(), name)
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	path := filepath.Join(dir, "nox #1.db")
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	_ = d.Close()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the database is not where the path says: %v", err)
	}
}

// spyVFS records the names SQLite asks it to resolve, and opens nothing.
type spyVFS struct{ names []string }

func (s *spyVFS) FullPathname(name string) (string, error) {
	s.names = append(s.names, name)
	return "", sqlite3.CANTOPEN
}

func (*spyVFS) Open(string, vfs.OpenFlag) (vfs.File, vfs.OpenFlag, error) {
	return nil, 0, sqlite3.CANTOPEN
}

func (*spyVFS) Delete(string, bool) error { return sqlite3.IOERR_DELETE }

func (*spyVFS) Access(string, vfs.AccessFlag) (bool, error) { return false, nil }

// The VFS is handed the very path the URI was built from - a Windows one with
// its drive letter first. file:///C:/... handed it "/C:/...", which the Go VFS
// reads as a directory named "C:" on the current drive, so that no database
// ever opened on Windows. SQLite's reading of the URI is what is under test,
// not a file system, so it runs on every system.
func TestTheVFSIsHandedThePathTheURINames(t *testing.T) {
	spy := &spyVFS{}
	vfs.Register("nox-spy", spy)
	t.Cleanup(func() { vfs.Unregister("nox-spy") })
	for _, path := range []string{
		"/srv/nox/nox.db",
		"C:/srv/nox/nox.db",
		"C:/Users/me/my 50% share?/nox #1.db",
		"/home/me/my 50% share?/nox #1.db",
	} {
		spy.names = nil
		uri := slashURI(path, url.Values{"vfs": {"nox-spy"}})
		if c, err := sqlite3.Open(uri); err == nil {
			_ = c.Close()
			t.Fatalf("%s opened a database through a VFS that opens nothing", uri)
		}
		if len(spy.names) == 0 || spy.names[0] != path {
			t.Fatalf("%s reached the VFS as %q, want %q", uri, spy.names, path)
		}
	}
	for path, want := range map[string]string{
		"/srv/nox.db":   "file:/srv/nox.db?vfs=adiantum",
		"C:/srv/nox.db": "file:C:/srv/nox.db?vfs=adiantum",
	} {
		if got := slashURI(path, url.Values{"vfs": {"adiantum"}}); got != want {
			t.Fatalf("the URI for %s = %s, want %s", path, got, want)
		}
	}
}

// Every server on Windows keeps its database under a drive letter: it opens,
// takes a snapshot - VACUUM INTO builds its own URI - and opens again.
func TestADatabaseUnderADriveLetterOpens(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("drive letters are Windows paths")
	}
	dir := t.TempDir()
	if filepath.VolumeName(dir) == "" {
		t.Fatalf("the test directory %s has no drive letter", dir)
	}
	path := filepath.Join(dir, "nox.db")
	d, err := Open(path, testKey)
	if err != nil {
		t.Fatalf("Open %s: %v", path, err)
	}
	if _, err := Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	if _, err := d.Write.Exec("INSERT INTO users (user_id, label, created_at) VALUES ('u_1', ?, 1)", marker); err != nil {
		t.Fatalf("insert: %v", err)
	}
	snap := filepath.Join(dir, "snap.db")
	if err := Snapshot(context.Background(), d.Read, snap, testKey); err != nil {
		t.Fatalf("Snapshot: %v", err)
	}
	if err := d.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	for _, p := range []string{path, snap} {
		again, err := Open(p, testKey)
		if err != nil {
			t.Fatalf("reopen %s: %v", p, err)
		}
		var label string
		err = again.Read.QueryRow("SELECT label FROM users WHERE user_id = 'u_1'").Scan(&label)
		_ = again.Close()
		if err != nil || label != marker {
			t.Fatalf("%s reads back %q (%v)", p, label, err)
		}
	}
}

func TestASnapshotIsEncryptedConsistentAndKeyedAlike(t *testing.T) {
	dir := t.TempDir()
	d := openMigrated(t)
	if _, err := d.Write.Exec("INSERT INTO users (user_id, label, created_at) VALUES ('u_1', ?, 1)", marker); err != nil {
		t.Fatalf("insert: %v", err)
	}
	snap := filepath.Join(dir, "snap.db")
	if err := Snapshot(context.Background(), d.Read, snap, testKey); err != nil {
		t.Fatalf("Snapshot: %v", err)
	}
	if found := filesHolding(t, dir, []byte(marker), []byte("SQLite format 3")); len(found) > 0 {
		t.Fatalf("the snapshot holds plaintext: %v", found)
	}
	s, err := Open(snap, testKey)
	if err != nil {
		t.Fatalf("open the snapshot: %v", err)
	}
	defer func() { _ = s.Close() }()
	if err := QuickCheck(context.Background(), s.Read); err != nil {
		t.Fatalf("QuickCheck: %v", err)
	}
	var label string
	if err := s.Read.QueryRow("SELECT label FROM users WHERE user_id = 'u_1'").Scan(&label); err != nil || label != marker {
		t.Fatalf("snapshot row = %q (%v)", label, err)
	}
}

// SQLite's message for a snapshot it could not write quotes the file it
// could not open - URI, key and all. The key must not come out with it.
func TestASnapshotThatFailsDoesNotSayTheKey(t *testing.T) {
	d := openMigrated(t)
	target := filepath.Join(t.TempDir(), "no such dir", "snap.db")
	err := Snapshot(context.Background(), d.Read, target, testKey)
	if err == nil {
		t.Fatal("a snapshot into a missing directory succeeded")
	}
	hexKey := fmt.Sprintf("%x", testKey)
	if strings.Contains(strings.ToLower(err.Error()), hexKey) {
		t.Fatalf("the error carries the data key: %v", err)
	}
}

package backup

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/store"
	"nox.app/client-backend/internal/vault"
)

// cheap are Argon2id costs a test can afford; the real ones have their own
// test in the vault package.
var cheap = vault.Params{MemoryKiB: 64, Iterations: 1, Parallelism: 1}

const (
	password = "correct horse battery"
	marker   = "BACKUP-MARKER-047"
)

// server is a server's data on disk, as Write reads it.
type server struct {
	dbPath, filesPath string
	key               []byte
	dbs               *db.DB
	st                *store.Store
	files             *blob.Store
	finished          string
	content           []byte
	journal           string
	serverKey         string
}

// newServer makes a server's data in dir: a key file, a database with a
// person's chat and message carrying the marker, one finished attachment and
// one upload that never finished.
func newServer(t *testing.T, dir string) *server {
	t.Helper()
	ctx := context.Background()
	s := &server{dbPath: filepath.Join(dir, "nox.db"), filesPath: filepath.Join(dir, "nox.db-files")}
	key, err := vault.Create(s.dbPath+".key", password, cheap)
	if err != nil {
		t.Fatalf("vault.Create: %v", err)
	}
	s.key = key
	s.dbs, err = db.Open(s.dbPath, key)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = s.dbs.Close() })
	if _, err := db.Migrate(ctx, s.dbs.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("Migrate: %v", err)
	}
	s.st = store.New(s.dbs.Read, s.dbs.Write)
	id, err := s.st.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	s.serverKey = string(id.PublicKey)
	if err := s.st.EnsureJournal(ctx); err != nil {
		t.Fatalf("EnsureJournal: %v", err)
	}
	if s.journal, err = s.st.JournalID(ctx); err != nil {
		t.Fatalf("JournalID: %v", err)
	}
	if _, _, _, err := s.st.CreateChat(ctx, "", marker+" chat", "Anna", 1); err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	s.files, err = blob.Open(s.filesPath, key)
	if err != nil {
		t.Fatalf("blob.Open: %v", err)
	}
	t.Cleanup(func() { _ = s.files.Close() })

	s.content = bytes.Repeat([]byte(marker), 3*blob.ChunkSize/len(marker))
	att, err := s.st.CreateUpload(ctx, marker+".bin", int64(len(s.content)), "application/octet-stream", time.Now().Unix())
	if err != nil {
		t.Fatalf("CreateUpload: %v", err)
	}
	up, err := s.files.Create(att.FileID, att.Size)
	if err != nil {
		t.Fatalf("blob.Create: %v", err)
	}
	if _, err := up.Write(s.content); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := up.Finalize(); err != nil {
		t.Fatalf("finalize: %v", err)
	}
	if err := s.st.MarkUploaded(ctx, att.FileID); err != nil {
		t.Fatalf("MarkUploaded: %v", err)
	}
	s.finished = att.FileID

	half, err := s.st.CreateUpload(ctx, "half.bin", 2*blob.ChunkSize, "application/octet-stream", time.Now().Unix())
	if err != nil {
		t.Fatalf("CreateUpload: %v", err)
	}
	hup, err := s.files.Create(half.FileID, half.Size)
	if err != nil {
		t.Fatalf("blob.Create: %v", err)
	}
	if _, err := hup.Write(s.content[:blob.ChunkSize+10]); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := hup.Suspend(); err != nil {
		t.Fatalf("suspend: %v", err)
	}
	return s
}

func (s *server) source() Source {
	return Source{
		DBPath:  s.dbPath,
		KeyPath: s.dbPath + ".key",
		DataKey: s.key,
		Snapshot: func(ctx context.Context, path string) error {
			return s.st.Snapshot(ctx, path, s.key)
		},
		Files: s.files,
	}
}

// write makes a backup of s at a new path and returns it.
func (s *server) write(t *testing.T) string {
	t.Helper()
	dst := filepath.Join(t.TempDir(), "nox-backup.tar")
	sum, err := Write(context.Background(), dst, s.source(), time.Now())
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if sum.Files != 1 || sum.Missing != 1 {
		t.Fatalf("backup summary = %+v, want the finished file and the unfinished one skipped", sum)
	}
	return dst
}

// entries lists a backup's entries, in order.
func entries(t *testing.T, path string) []string {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer func() { _ = f.Close() }()
	tr := tar.NewReader(f)
	var names []string
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return names
		}
		if err != nil {
			t.Fatalf("tar: %v", err)
		}
		names = append(names, hdr.Name)
	}
}

func asked(pw string) func() (string, error) {
	return func() (string, error) { return pw, nil }
}

// emptyTarget is a place to restore to, on what may as well be another
// machine.
func emptyTarget(t *testing.T) Target {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "other")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	return Target{DBPath: filepath.Join(dir, "nox.db"), FilesPath: filepath.Join(dir, "nox.db-files")}
}

func isEmpty(t *testing.T, target Target) {
	t.Helper()
	entries, err := os.ReadDir(filepath.Dir(target.DBPath))
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	if len(entries) != 0 {
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Fatalf("the target is not as it was: %v", names)
	}
}

// FR-013: one file, the key, the database and the finished attachment in it,
// the manifest last - and none of it in the clear.
func TestABackupIsOneFileWithNothingInTheClear(t *testing.T) {
	s := newServer(t, t.TempDir())
	dst := s.write(t)
	got := entries(t, dst)
	want := []string{keyEntry, dbEntry, filesPrefix + s.finished, manifestEntry}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("entries = %v, want %v", got, want)
	}
	data, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	for _, secret := range [][]byte{[]byte(marker), []byte(strings.ToLower(marker)), s.key, []byte(s.journal), []byte("SQLite format 3")} {
		if bytes.Contains(data, secret) {
			t.Fatalf("the backup carries %q in the clear", secret)
		}
	}
	// Nothing is left beside the target or the database.
	if _, err := os.Stat(dst + partialSuffix); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a finished backup left its partial file (stat err %v)", err)
	}
	if matches, _ := filepath.Glob(s.dbPath + snapshotSuffix + "*"); len(matches) > 0 {
		t.Fatalf("the backup left its snapshot behind: %v", matches)
	}
}

// SC-005, FR-014, FR-015: restored elsewhere with the same password, the
// server is the same machine with the same conversation and files - and a new
// journal id.
func TestARestoredServerIsTheSameMachineWithANewJournal(t *testing.T) {
	s := newServer(t, t.TempDir())
	dst := s.write(t)
	target := emptyTarget(t)
	restored, err := Restore(context.Background(), dst, target, asked(password))
	if err != nil {
		t.Fatalf("Restore: %v", err)
	}
	journal := restored.JournalID
	if journal == "" || journal == s.journal {
		t.Fatalf("the restored journal id = %q, want a new one (was %q)", journal, s.journal)
	}
	// No staging is left beside it, and no journal of the database: the file
	// alone is the database.
	for _, p := range []string{target.DBPath + restoreSuffix, target.FilesPath + restoreSuffix, target.DBPath + "-wal"} {
		if _, err := os.Stat(p); !errors.Is(err, fs.ErrNotExist) {
			t.Fatalf("%s is left after the restore (stat err %v)", p, err)
		}
	}
	key, err := vault.Open(target.DBPath+".key", password)
	if err != nil {
		t.Fatalf("the restored key file does not open with the password: %v", err)
	}
	if !bytes.Equal(key, s.key) {
		t.Fatal("the restored data key is not the server's")
	}
	d, err := db.Open(target.DBPath, key)
	if err != nil {
		t.Fatalf("open the restored database: %v", err)
	}
	defer func() { _ = d.Close() }()
	st := store.New(d.Read, d.Write)
	ctx := context.Background()
	id, err := st.ServerIdentity(ctx)
	if err != nil || string(id.PublicKey) != s.serverKey {
		t.Fatalf("the restored machine's key differs (%v): devices would have to pair again", err)
	}
	if got, err := st.JournalID(ctx); err != nil || got != journal {
		t.Fatalf("stored journal id = %q (%v), want %q", got, err, journal)
	}
	chats, _, err := st.ListChats(ctx, 1, 10, "")
	if err != nil || len(chats) != 1 || chats[0].Name != marker+" chat" {
		t.Fatalf("restored chats = %+v (%v)", chats, err)
	}
	files, err := blob.Open(target.FilesPath, key)
	if err != nil {
		t.Fatalf("blob.Open: %v", err)
	}
	defer func() { _ = files.Close() }()
	r, err := files.Open(s.finished, int64(len(s.content)))
	if err != nil {
		t.Fatalf("open the restored attachment: %v", err)
	}
	defer func() { _ = r.Close() }()
	if got, err := io.ReadAll(r); err != nil || !bytes.Equal(got, s.content) {
		t.Fatalf("the restored attachment does not read back (%v)", err)
	}
}

// Revoking a device deletes its row, and a backup made before the revocation
// still holds it: the restored server lets that device in again. Nothing in
// the backup can know better, so the restore names every device it lets in
// and the moment the backup was made - the list a revoked device is found on.
func TestARestoreNamesTheDevicesItLetsBackIn(t *testing.T) {
	s := newServer(t, t.TempDir())
	ctx := context.Background()
	for i, device := range []struct{ key, platform string }{{"dev-phone", "android"}, {"dev-laptop", "macos"}} {
		now := int64(1000 + i)
		link, err := s.st.IssueMachineLink(ctx, now)
		if err != nil {
			t.Fatalf("IssueMachineLink: %v", err)
		}
		if _, err := s.st.Pair(ctx, link.Token, device.key, device.platform, now); err != nil {
			t.Fatalf("Pair %s: %v", device.key, err)
		}
	}
	before := time.Now().Truncate(time.Second)
	dst := s.write(t)
	// The phone is stolen after the backup, and revoked on the live server.
	if _, err := s.st.RevokeDevice(ctx, "dev-phone", 2000); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	restored, err := Restore(ctx, dst, emptyTarget(t), asked(password))
	if err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if restored.MadeAt.Before(before) || restored.MadeAt.After(time.Now()) {
		t.Fatalf("the backup's moment = %v, want the moment it was written (after %v)", restored.MadeAt, before)
	}
	var got []string
	for _, d := range restored.Devices {
		got = append(got, d.DeviceKey+"/"+d.Platform)
	}
	if strings.Join(got, ",") != "dev-phone/android,dev-laptop/macos" {
		t.Fatalf("the restore names %v, want both devices of the backup - the phone revoked since among them", got)
	}
}

func TestAWrongPasswordRestoresNothing(t *testing.T) {
	s := newServer(t, t.TempDir())
	dst := s.write(t)
	target := emptyTarget(t)
	if _, err := Restore(context.Background(), dst, target, asked("not the password")); !errors.Is(err, vault.ErrWrongPassword) {
		t.Fatalf("Restore with a wrong password = %v, want ErrWrongPassword", err)
	}
	isEmpty(t, target)
}

func TestARestoreOntoAServerIsRefused(t *testing.T) {
	s := newServer(t, t.TempDir())
	dst := s.write(t)
	asked := func() (string, error) {
		t.Fatal("the password was asked for a restore that cannot happen")
		return "", nil
	}
	for name, fill := range map[string]func(Target){
		"a database": func(tg Target) { _ = os.WriteFile(tg.DBPath, []byte("x"), 0o600) },
		"a key file": func(tg Target) { _ = os.WriteFile(tg.DBPath+".key", []byte("x"), 0o600) },
		"an attachment": func(tg Target) {
			_ = os.Mkdir(tg.FilesPath, 0o755)
			_ = os.WriteFile(filepath.Join(tg.FilesPath, "f_1"), nil, 0o600)
		},
		"a restore cut short": func(tg Target) { _ = os.Mkdir(tg.FilesPath+restoreSuffix, 0o755) },
	} {
		target := emptyTarget(t)
		fill(target)
		before, _ := os.ReadDir(filepath.Dir(target.DBPath))
		if _, err := Restore(context.Background(), dst, target, asked); !errors.Is(err, ErrNotEmpty) {
			t.Fatalf("%s: Restore = %v, want ErrNotEmpty", name, err)
		}
		after, _ := os.ReadDir(filepath.Dir(target.DBPath))
		if len(before) != len(after) {
			t.Fatalf("%s: the refused restore changed the target", name)
		}
	}
	// An empty attachments directory is an empty place.
	target := emptyTarget(t)
	if err := os.Mkdir(target.FilesPath, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if _, err := Restore(context.Background(), dst, target, func() (string, error) { return password, nil }); err != nil {
		t.Fatalf("Restore onto an empty attachments directory: %v", err)
	}
}

// rewrite copies a backup entry by entry, letting change alter each one.
func rewrite(t *testing.T, src string, change func(name string, data []byte) (string, []byte, bool)) string {
	t.Helper()
	in, err := os.Open(src)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer func() { _ = in.Close() }()
	dst := filepath.Join(t.TempDir(), "changed.tar")
	out, err := os.Create(dst)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	defer func() { _ = out.Close() }()
	tr := tar.NewReader(in)
	tw := tar.NewWriter(out)
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			t.Fatalf("tar: %v", err)
		}
		data, err := io.ReadAll(tr)
		if err != nil {
			t.Fatalf("read: %v", err)
		}
		name, data, keep := change(hdr.Name, data)
		if !keep {
			continue
		}
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o600, Size: int64(len(data)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatalf("header: %v", err)
		}
		if _, err := tw.Write(data); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	return dst
}

// The database's pages carry no seal of their own, so the backup's MAC is
// what refuses a changed backup: any byte of any entry, an entry dropped,
// added or renamed, a manifest changed or missing. Each refusal leaves the
// target as it was.
func TestAChangedBackupIsRefused(t *testing.T) {
	s := newServer(t, t.TempDir())
	dst := s.write(t)
	flip := func(target string, at int) func(string, []byte) (string, []byte, bool) {
		return func(name string, data []byte) (string, []byte, bool) {
			if name == target {
				data = append([]byte{}, data...)
				data[at%len(data)] ^= 1
			}
			return name, data, true
		}
	}
	cases := map[string]func(string, []byte) (string, []byte, bool){
		"a byte of the database":  flip(dbEntry, 5000),
		"a byte of an attachment": flip(filesPrefix+s.finished, 70000),
		"a byte of the manifest":  flip(manifestEntry, 20),
		"the attachment dropped":  func(n string, d []byte) (string, []byte, bool) { return n, d, n != filesPrefix+s.finished },
		"the manifest dropped":    func(n string, d []byte) (string, []byte, bool) { return n, d, n != manifestEntry },
		"the database dropped":    func(n string, d []byte) (string, []byte, bool) { return n, d, n != dbEntry },
		"an attachment renamed": func(n string, d []byte) (string, []byte, bool) {
			return strings.Replace(n, s.finished, "f_0", 1), d, true
		},
		"an entry outside its dir": func(n string, d []byte) (string, []byte, bool) {
			return strings.Replace(n, filesPrefix, "../", 1), d, true
		},
		"the moment changed": func(n string, d []byte) (string, []byte, bool) {
			if n == manifestEntry {
				var m manifest
				if err := json.Unmarshal(d, &m); err != nil {
					t.Fatalf("manifest: %v", err)
				}
				m.CreatedAt++
				d, _ = json.Marshal(m)
			}
			return n, d, true
		},
	}
	for name, change := range cases {
		changed := rewrite(t, dst, change)
		target := emptyTarget(t)
		if _, err := Restore(context.Background(), changed, target, asked(password)); !errors.Is(err, ErrDamaged) {
			t.Fatalf("%s: Restore = %v, want ErrDamaged", name, err)
		}
		isEmpty(t, target)
	}
	// A backup cut off in the middle of an entry.
	data, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	cut := filepath.Join(t.TempDir(), "cut.tar")
	if err := os.WriteFile(cut, data[:len(data)/2], 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	target := emptyTarget(t)
	if _, err := Restore(context.Background(), cut, target, asked(password)); !errors.Is(err, ErrDamaged) {
		t.Fatalf("a backup cut in half: Restore = %v, want ErrDamaged", err)
	}
	isEmpty(t, target)
	// And something that is not a backup at all is refused before the
	// password is asked.
	notBackup := filepath.Join(t.TempDir(), "notes.txt")
	if err := os.WriteFile(notBackup, []byte("shopping list"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if _, err := Restore(context.Background(), notBackup, emptyTarget(t), func() (string, error) {
		t.Fatal("the password was asked for a file that is no backup")
		return "", nil
	}); !errors.Is(err, ErrDamaged) {
		t.Fatalf("Restore of a text file = %v, want ErrDamaged", err)
	}
}

func TestABackupIsNeverWrittenOverAnotherOrOutsideADirectory(t *testing.T) {
	s := newServer(t, t.TempDir())
	dst := s.write(t)
	before, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var bad *PathError
	for name, path := range map[string]string{
		"an existing backup":  dst,
		"a relative path":     "nox-backup.tar",
		"a missing directory": filepath.Join(t.TempDir(), "nope", "b.tar"),
	} {
		if _, err := Write(context.Background(), path, s.source(), time.Now()); !errors.As(err, &bad) {
			t.Fatalf("%s: Write = %v, want a PathError", name, err)
		}
	}
	after, err := os.ReadFile(dst)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("a refused backup changed the one already there")
	}

	// A partial file - another backup in progress, or one cut off - is in the
	// way too, and is left for its owner.
	next := filepath.Join(t.TempDir(), "next.tar")
	if err := os.WriteFile(next+partialSuffix, []byte("half"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if _, err := Write(context.Background(), next, s.source(), time.Now()); !errors.As(err, &bad) {
		t.Fatalf("Write over a partial = %v, want a PathError", err)
	}
	if _, err := os.Stat(next); !errors.Is(err, fs.ErrNotExist) {
		t.Fatal("a refused backup appeared anyway")
	}
}

// A backup that stops half-way - its command gone, the server stopping -
// leaves no file that looks like a backup and no snapshot beside the database.
func TestABackupCutOffLeavesNothing(t *testing.T) {
	s := newServer(t, t.TempDir())
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	dst := filepath.Join(t.TempDir(), "b.tar")
	if _, err := Write(ctx, dst, s.source(), time.Now()); err == nil {
		t.Fatal("a backup on a cancelled context succeeded")
	}
	for _, p := range []string{dst, dst + partialSuffix, s.dbPath + snapshotSuffix} {
		if _, err := os.Stat(p); !errors.Is(err, fs.ErrNotExist) {
			t.Fatalf("%s is left after a cut-off backup (stat err %v)", p, err)
		}
	}
}

// A changed password goes into the next backup: a backup opens with the
// password the server had when it was made.
func TestABackupOpensWithThePasswordOfItsMoment(t *testing.T) {
	s := newServer(t, t.TempDir())
	old := s.write(t)
	const next = "staple orbit lantern"
	if err := vault.Change(s.dbPath+".key", password, next, cheap); err != nil {
		t.Fatalf("Change: %v", err)
	}
	fresh := s.write(t)
	if _, err := Restore(context.Background(), old, emptyTarget(t), asked(password)); err != nil {
		t.Fatalf("the earlier backup with the earlier password: %v", err)
	}
	if _, err := Restore(context.Background(), fresh, emptyTarget(t), asked(password)); !errors.Is(err, vault.ErrWrongPassword) {
		t.Fatalf("the later backup with the earlier password = %v, want ErrWrongPassword", err)
	}
	if _, err := Restore(context.Background(), fresh, emptyTarget(t), asked(next)); err != nil {
		t.Fatalf("the later backup with the later password: %v", err)
	}
}

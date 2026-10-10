// Package backup writes the server's backup and restores one (047).
//
// A backup is ONE tar file: the sealed data key (nox.key), a snapshot of the
// database (nox.db), the finished attachments (files/<id>) and, last, a
// manifest naming every entry with its size and a MAC over all of them. Every
// byte of it was encrypted before it went in - the key sealed by the
// password, the database page by page, each attachment chunk by chunk - so the
// file says nothing to whoever holds it without the password. The MAC is what
// the encryption does not give: the database's pages carry no seal of their
// own, so without it a changed backup would restore without a word. Its key
// comes from the data key, which only the password unseals.
//
// A restore needs the same password, an empty place and nothing else: no
// server running, no network. The restored server keeps its own key - the
// devices know it and go on without pairing - and gets a new journal id, so
// each device drops what it cached and reads the conversation again. Its list
// of devices is the backup's too: a device revoked after the backup was made
// is let in again, and the restore names every device it lets in so that one
// can be revoked again.
package backup

import (
	"archive/tar"
	"context"
	"crypto/hkdf"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"time"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/store"
	"nox.app/client-backend/internal/vault"
)

// The entries of a backup, in the order they are written and read.
const (
	keyEntry      = "nox.key"
	dbEntry       = "nox.db"
	filesPrefix   = "files/"
	manifestEntry = "manifest"

	formatVersion = 1
	// macInfo names the MAC key's purpose in HKDF, and opens the MAC's input.
	macInfo = "nox/backup/v1"
	// maxManifestBytes bounds the manifest: a line per attachment.
	maxManifestBytes = 16 << 20
	// partialSuffix marks a backup still being written. It is never a backup.
	partialSuffix = ".partial"
	// snapshotSuffix names the snapshot taken beside the live database while
	// a backup is being written - on the database's own disk, which is local
	// by the server's rule.
	snapshotSuffix = ".snapshot"
	// restoreSuffix names what a restore unpacks beside its target before the
	// renames that put it in place.
	restoreSuffix = ".restore"
)

// fileID is what an attachment's entry may be named: the server's own ids.
// Anything else is not from a backup this server made - and never becomes a
// path.
var fileID = regexp.MustCompile(`^f_[0-9a-f]{1,64}$`)

var (
	// ErrDamaged is a file that is not a backup this server made, or one that
	// changed after it was made.
	ErrDamaged = errors.New("not an intact backup of a NOX server")
	// ErrNotEmpty is a restore target that already holds a server.
	ErrNotEmpty = errors.New("the place to restore to is not empty")
)

// PathError is a backup path the server cannot write to: what the person
// typed, not what the server did.
type PathError struct {
	Path   string
	Reason string
}

func (e *PathError) Error() string {
	return e.Path + ": " + e.Reason
}

// manifest closes a backup: what is in it, and the MAC that vouches for it.
type manifest struct {
	Version   int     `json:"version"`
	CreatedAt int64   `json:"created_at"`
	Entries   []entry `json:"entries"`
	MAC       []byte  `json:"mac"`
}

type entry struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
}

// mac is the running MAC over a backup: the format's name, then each entry's
// name, size and bytes in order, then the moment the backup was made and the
// number of entries. Name and size go in with their lengths fixed, so no two
// different backups feed it the same stream; the moment goes last, so a
// restore can feed the MAC as it reads and learn the moment only from the
// manifest at the end.
type mac struct {
	h hash.Hash
}

func newMAC(dataKey []byte) (*mac, error) {
	key, err := hkdf.Key(sha256.New, dataKey, nil, macInfo, sha256.Size)
	if err != nil {
		return nil, fmt.Errorf("derive the backup's MAC key: %w", err)
	}
	m := &mac{h: hmac.New(sha256.New, key)}
	_, _ = m.h.Write([]byte(macInfo + "\n"))
	return m, nil
}

// begin feeds an entry's name and size; its bytes follow through m.h.
func (m *mac) begin(name string, size int64) {
	_ = binary.Write(m.h, binary.BigEndian, uint16(len(name))) //nolint:gosec // entry names are short by construction
	_, _ = m.h.Write([]byte(name))
	_ = binary.Write(m.h, binary.BigEndian, size)
}

// sum closes the MAC with the moment and the number of entries.
func (m *mac) sum(createdAt int64, entries int) []byte {
	_, _ = m.h.Write([]byte{0xff})
	_ = binary.Write(m.h, binary.BigEndian, createdAt)
	_ = binary.Write(m.h, binary.BigEndian, int64(entries))
	return m.h.Sum(nil)
}

// Source is what a backup is made from: the running server's pieces.
type Source struct {
	// DBPath is the live database; the snapshot is written beside it.
	DBPath string
	// KeyPath is the key file, carried as it is.
	KeyPath string
	// DataKey encrypts the snapshot and keys the MAC.
	DataKey []byte
	// Snapshot writes a consistent copy of the live database at path,
	// encrypted with DataKey.
	Snapshot func(ctx context.Context, path string) error
	// Files holds the attachments, carried as they lie on disk.
	Files *blob.Store
}

// Summary is what a backup holds, for the log: counts, never names.
type Summary struct {
	Files   int
	Missing int
	Bytes   int64
}

// Write makes a backup at dst, an absolute path whose directory exists and
// where no file is yet. The server keeps running: the database part is a
// snapshot, the attachments are files that never change once finished. The
// file appears at dst only whole - it is written as dst.partial, flushed and
// renamed - so a backup cut off half-way is never mistaken for one.
func Write(ctx context.Context, dst string, src Source, now time.Time) (Summary, error) {
	if err := checkTarget(dst); err != nil {
		return Summary{}, err
	}
	key, err := vault.ReadFile(src.KeyPath)
	if err != nil {
		return Summary{}, err
	}

	snapshot := src.DBPath + snapshotSuffix
	// A snapshot left by a backup the power cut off is in the way; it was
	// never anything but a temporary copy.
	removeDatabase(snapshot)
	defer removeDatabase(snapshot)
	if err := src.Snapshot(ctx, snapshot); err != nil {
		return Summary{}, err
	}
	ids, err := snapshotFiles(ctx, snapshot, src.DataKey)
	if err != nil {
		return Summary{}, err
	}

	partial := dst + partialSuffix
	out, err := os.OpenFile(partial, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, os.ErrExist) {
		return Summary{}, &PathError{Path: partial, Reason: "a backup is being written here, or one was cut off - remove it and try again"}
	}
	if err != nil {
		return Summary{}, &PathError{Path: dst, Reason: err.Error()}
	}
	done := false
	defer func() {
		if !done {
			_ = out.Close()
			_ = os.Remove(partial)
		}
	}()

	createdAt := now.Unix()
	m, err := newMAC(src.DataKey)
	if err != nil {
		return Summary{}, err
	}
	w := &archiveWriter{tw: tar.NewWriter(out), mac: m, now: now}
	if err := w.add(ctx, keyEntry, int64(len(key)), bytesReader(key)); err != nil {
		return Summary{}, err
	}
	if err := w.addFile(ctx, dbEntry, snapshot); err != nil {
		return Summary{}, err
	}
	var sum Summary
	for _, id := range ids {
		f, err := src.Files.OpenSealed(id)
		if errors.Is(err, os.ErrNotExist) {
			// A row whose upload never finished has no file to carry; after a
			// restore it is an upload that starts again.
			sum.Missing++
			continue
		}
		if err != nil {
			return Summary{}, err
		}
		size, err := w.addOpen(ctx, filesPrefix+id, f)
		_ = f.Close()
		if err != nil {
			return Summary{}, err
		}
		sum.Files++
		sum.Bytes += size
	}
	raw, err := json.Marshal(manifest{Version: formatVersion, CreatedAt: createdAt, Entries: w.entries,
		MAC: m.sum(createdAt, len(w.entries))})
	if err != nil {
		return Summary{}, fmt.Errorf("encode the manifest: %w", err)
	}
	if err := w.writeEntry(manifestEntry, int64(len(raw)), bytesReader(raw), nil); err != nil {
		return Summary{}, err
	}
	if err := w.tw.Close(); err != nil {
		return Summary{}, fmt.Errorf("finish the backup: %w", err)
	}
	if err := out.Sync(); err != nil {
		return Summary{}, fmt.Errorf("flush the backup: %w", err)
	}
	if err := out.Close(); err != nil {
		return Summary{}, fmt.Errorf("close the backup: %w", err)
	}
	done = true
	if err := os.Rename(partial, dst); err != nil {
		_ = os.Remove(partial)
		return Summary{}, fmt.Errorf("put the backup in place: %w", err)
	}
	if err := vault.SyncDir(filepath.Dir(dst)); err != nil {
		return Summary{}, err
	}
	return sum, nil
}

// checkTarget refuses a path a backup must not be written to: relative, in
// a directory that is not there, or where a file already is - an older
// backup is never written over.
func checkTarget(dst string) error {
	if !filepath.IsAbs(dst) {
		return &PathError{Path: dst, Reason: "the path must be absolute"}
	}
	dir := filepath.Dir(dst)
	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		return &PathError{Path: dst, Reason: "the directory " + dir + " does not exist on the server's machine"}
	}
	if _, err := os.Lstat(dst); err == nil {
		return &PathError{Path: dst, Reason: "a file is already there - backups are never written over; name a new file"}
	}
	return nil
}

// snapshotFiles opens the snapshot, checks it, and lists the attachments its
// rows name: the backup carries exactly those, no more and no fewer.
func snapshotFiles(ctx context.Context, path string, dataKey []byte) ([]string, error) {
	snap, err := db.Open(path, dataKey)
	if err != nil {
		return nil, fmt.Errorf("open the snapshot: %w", err)
	}
	ids, err := func() ([]string, error) {
		if err := db.QuickCheck(ctx, snap.Read); err != nil {
			return nil, err
		}
		return store.New(snap.Read, snap.Write).FileIDs(ctx)
	}()
	if cerr := snap.Close(); cerr != nil && err == nil {
		err = fmt.Errorf("close the snapshot: %w", cerr)
	}
	if err != nil {
		return nil, err
	}
	// Closing the last connection folds the WAL back in and removes it; one
	// still there would mean the file alone is not the snapshot.
	if _, err := os.Stat(path + "-wal"); err == nil {
		return nil, errors.New("the snapshot's journal was not folded back into it")
	}
	return ids, nil
}

// removeDatabase removes a database file with whatever SQLite keeps beside
// it.
func removeDatabase(path string) {
	for _, p := range []string{path, path + "-wal", path + "-shm", path + "-journal"} {
		_ = os.Remove(p)
	}
}

// archiveWriter writes entries into the tar, feeding the MAC as it goes and
// listing them for the manifest.
type archiveWriter struct {
	tw      *tar.Writer
	mac     *mac
	now     time.Time
	entries []entry
}

func (w *archiveWriter) addFile(ctx context.Context, name, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s for the backup: %w", name, err)
	}
	defer func() { _ = f.Close() }()
	_, err = w.addOpen(ctx, name, f)
	return err
}

func (w *archiveWriter) addOpen(ctx context.Context, name string, f *os.File) (int64, error) {
	info, err := f.Stat()
	if err != nil {
		return 0, fmt.Errorf("stat %s for the backup: %w", name, err)
	}
	return info.Size(), w.add(ctx, name, info.Size(), f)
}

func (w *archiveWriter) add(ctx context.Context, name string, size int64, r io.Reader) error {
	w.mac.begin(name, size)
	if err := w.writeEntry(name, size, &ctxReader{ctx: ctx, r: r}, w.mac.h); err != nil {
		return err
	}
	w.entries = append(w.entries, entry{Name: name, Size: size})
	return nil
}

// writeEntry writes one tar entry of exactly size bytes from r, also into
// tee when there is one.
func (w *archiveWriter) writeEntry(name string, size int64, r io.Reader, tee io.Writer) error {
	hdr := &tar.Header{Name: name, Mode: 0o600, Size: size, ModTime: w.now, Typeflag: tar.TypeReg}
	if err := w.tw.WriteHeader(hdr); err != nil {
		return fmt.Errorf("write the backup's %s: %w", name, err)
	}
	var dst io.Writer = w.tw
	if tee != nil {
		dst = io.MultiWriter(w.tw, tee)
	}
	if n, err := io.CopyN(dst, r, size); err != nil {
		return fmt.Errorf("write the backup's %s (%d of %d bytes): %w", name, n, size, err)
	}
	return nil
}

// ctxReader stops a copy when its context ends: a backup the command gave up
// on, or a server that is stopping, does not go on reading.
type ctxReader struct {
	ctx context.Context //nolint:containedctx // one copy's lifetime
	r   io.Reader
}

func (c *ctxReader) Read(p []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.r.Read(p)
}

func bytesReader(b []byte) io.Reader {
	return &sliceReader{b: b}
}

type sliceReader struct{ b []byte }

func (s *sliceReader) Read(p []byte) (int, error) {
	if len(s.b) == 0 {
		return 0, io.EOF
	}
	n := copy(p, s.b)
	s.b = s.b[n:]
	return n, nil
}

// Target is where a restore goes: the database path and the attachments
// directory. The key file goes beside the database.
type Target struct {
	DBPath    string
	FilesPath string
}

// Restored is what a restore put in place, as the person who ran it is told.
type Restored struct {
	// JournalID is the restored server's new journal id.
	JournalID string
	// MadeAt is the moment the backup was made, from its manifest.
	MadeAt time.Time
	// Devices are the devices the restored server lets in: the ones paired
	// when the backup was made. Revoking a device deletes its row, so one
	// revoked after that moment is among them - nothing in a backup can know
	// of a revocation that came later.
	Devices []store.Device
}

// Restore unpacks the backup at archive onto target, which must be empty.
// password is asked for once the backup's key file has been read and found
// to be one; a password that does not open it ends the restore with
// vault.ErrWrongPassword. Nothing is put in place until every entry checked
// out against the MAC and the database passed its check: a wrong password, a
// damaged backup or a target that is not empty changes nothing on disk.
func Restore(ctx context.Context, archive string, target Target, password func() (string, error)) (Restored, error) {
	if err := checkEmpty(target); err != nil {
		return Restored{}, err
	}
	in, err := os.Open(archive)
	if err != nil {
		return Restored{}, fmt.Errorf("open the backup: %w", err)
	}
	defer func() { _ = in.Close() }()
	tr := tar.NewReader(in)

	// The sealed key comes first, so a damaged or foreign file is refused
	// before anybody types a password.
	keyFile, err := readEntry(tr, keyEntry, 1<<16)
	if err != nil {
		return Restored{}, err
	}
	if err := vault.Validate(keyFile); err != nil {
		return Restored{}, fmt.Errorf("%w: its key file does not read", ErrDamaged)
	}
	pw, err := password()
	if err != nil {
		return Restored{}, err
	}
	dataKey, err := vault.Unseal(keyFile, pw)
	if err != nil {
		return Restored{}, err
	}

	st, err := unpack(ctx, tr, target, keyFile, dataKey)
	if err != nil {
		return Restored{}, err
	}
	defer st.cleanup()
	restored, err := st.prepare(ctx, dataKey)
	if err != nil {
		return Restored{}, err
	}
	if err := st.place(target, keyFile); err != nil {
		return Restored{}, err
	}
	return restored, nil
}

// checkEmpty refuses a target that holds anything of a server - and one whose
// directories are not there: a restore creates nothing it may have to take
// back but the files it puts in place.
func checkEmpty(t Target) error {
	for _, dir := range []string{filepath.Dir(t.DBPath), filepath.Dir(t.FilesPath)} {
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			return fmt.Errorf("the directory %s is not there - make it first", dir)
		}
	}
	for _, p := range []string{t.DBPath, t.DBPath + ".key", t.DBPath + "-wal", t.DBPath + "-shm", t.DBPath + restoreSuffix, t.FilesPath + restoreSuffix} {
		if _, err := os.Lstat(p); err == nil {
			return fmt.Errorf("%w: %s is there", ErrNotEmpty, p)
		} else if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("look at %s: %w", p, err)
		}
	}
	entries, err := os.ReadDir(t.FilesPath)
	switch {
	case errors.Is(err, os.ErrNotExist):
		return nil
	case err != nil:
		return fmt.Errorf("look at %s: %w", t.FilesPath, err)
	case len(entries) > 0:
		return fmt.Errorf("%w: %s holds files", ErrNotEmpty, t.FilesPath)
	}
	return nil
}

// readEntry reads the next entry, which must be name and no larger than max.
func readEntry(tr *tar.Reader, name string, maxSize int64) ([]byte, error) {
	hdr, err := tr.Next()
	if err != nil {
		return nil, fmt.Errorf("%w: %s is missing", ErrDamaged, name)
	}
	if hdr.Name != name || hdr.Typeflag != tar.TypeReg || hdr.Size < 0 || hdr.Size > maxSize {
		return nil, fmt.Errorf("%w: %q where %s belongs", ErrDamaged, hdr.Name, name)
	}
	data, err := io.ReadAll(tr)
	if err != nil {
		return nil, fmt.Errorf("%w: %s does not read: %v", ErrDamaged, name, err)
	}
	return data, nil
}

// staging is a restore unpacked beside its target and not yet in place.
type staging struct {
	db    string
	files string
	ids   []string
	// madeAt is the moment the backup was made, unix seconds, as its manifest
	// says - read only once the MAC vouched for it.
	madeAt int64
}

// cleanup removes whatever of the staging was not put in place.
func (s *staging) cleanup() {
	removeDatabase(s.db)
	_ = os.RemoveAll(s.files)
}

// unpack reads the rest of the backup into a staging area beside the target,
// feeding the MAC as it goes and checking it, with every entry, against the
// manifest at the end. Nothing is in the target yet; on any failure the
// staging goes too.
func unpack(ctx context.Context, tr *tar.Reader, target Target, keyFile, dataKey []byte) (*staging, error) {
	st := &staging{db: target.DBPath + restoreSuffix, files: target.FilesPath + restoreSuffix}
	m, err := newMAC(dataKey)
	if err != nil {
		return nil, err
	}
	if err := os.Mkdir(st.files, 0o755); err != nil {
		return nil, fmt.Errorf("make %s: %w", st.files, err)
	}
	ok := false
	defer func() {
		if !ok {
			st.cleanup()
		}
	}()

	seen := []entry{{Name: keyEntry, Size: int64(len(keyFile))}}
	m.begin(keyEntry, int64(len(keyFile)))
	_, _ = m.h.Write(keyFile)
	var man *manifest
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("%w: %v", ErrDamaged, err)
		}
		if man != nil {
			return nil, fmt.Errorf("%w: %q after the manifest", ErrDamaged, hdr.Name)
		}
		if hdr.Typeflag != tar.TypeReg || hdr.Size < 0 {
			return nil, fmt.Errorf("%w: %q is not a file", ErrDamaged, hdr.Name)
		}
		var path string
		switch id := fileIDOf(hdr.Name); {
		case hdr.Name == manifestEntry:
			raw, err := io.ReadAll(io.LimitReader(tr, maxManifestBytes+1))
			man = &manifest{}
			if err != nil || len(raw) > maxManifestBytes || json.Unmarshal(raw, man) != nil || man.Version != formatVersion {
				return nil, fmt.Errorf("%w: the manifest does not read", ErrDamaged)
			}
			continue
		case len(seen) == 1 && hdr.Name == dbEntry:
			path = st.db
		case len(seen) > 1 && id != "":
			if slices.Contains(st.ids, id) {
				return nil, fmt.Errorf("%w: %q twice", ErrDamaged, hdr.Name)
			}
			st.ids = append(st.ids, id)
			path = filepath.Join(st.files, id)
		default:
			return nil, fmt.Errorf("%w: an entry %q where this server never writes one", ErrDamaged, hdr.Name)
		}
		m.begin(hdr.Name, hdr.Size)
		if err := copyTo(ctx, path, io.TeeReader(tr, m.h), hdr.Size); errors.Is(err, io.ErrUnexpectedEOF) {
			return nil, fmt.Errorf("%w: it ends in the middle of %q - cut off", ErrDamaged, hdr.Name)
		} else if err != nil {
			return nil, err
		}
		seen = append(seen, entry{Name: hdr.Name, Size: hdr.Size})
	}
	switch {
	case man == nil:
		return nil, fmt.Errorf("%w: it has no manifest - a backup cut off before its end", ErrDamaged)
	case len(seen) < 2:
		return nil, fmt.Errorf("%w: it holds no database", ErrDamaged)
	case !slices.Equal(man.Entries, seen):
		return nil, fmt.Errorf("%w: its entries are not the ones its manifest names", ErrDamaged)
	case !hmac.Equal(m.sum(man.CreatedAt, len(seen)), man.MAC):
		return nil, fmt.Errorf("%w: it changed after it was made", ErrDamaged)
	}
	st.madeAt = man.CreatedAt
	ok = true
	return st, nil
}

// fileIDOf is the attachment id an entry name carries, or "".
func fileIDOf(name string) string {
	if len(name) <= len(filesPrefix) || name[:len(filesPrefix)] != filesPrefix {
		return ""
	}
	id := name[len(filesPrefix):]
	if !fileID.MatchString(id) {
		return ""
	}
	return id
}

// copyTo writes exactly size bytes from r into a new file at path.
func copyTo(ctx context.Context, path string, r io.Reader, size int64) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	_, err = io.CopyN(f, &ctxReader{ctx: ctx, r: r}, size)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); cerr != nil && err == nil {
		err = cerr
	}
	if err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// prepare checks the staged database, reads the devices it lets in and gives
// it a new journal id. It is opened with the backup's data key - the one any
// server restored from it opens it with - and closed again before anything
// moves, so no journal of it is left beside the staged file.
func (s *staging) prepare(ctx context.Context, dataKey []byte) (Restored, error) {
	d, err := db.Open(s.db, dataKey)
	if err != nil {
		return Restored{}, fmt.Errorf("%w: its database does not open: %v", ErrDamaged, err)
	}
	restored, err := func() (Restored, error) {
		if err := db.QuickCheck(ctx, d.Read); err != nil {
			return Restored{}, fmt.Errorf("%w: %v", ErrDamaged, err)
		}
		st := store.New(d.Read, d.Write)
		devices, err := st.AllDevices(ctx)
		if err != nil {
			return Restored{}, err
		}
		id, err := st.RotateJournal(ctx)
		if err != nil {
			return Restored{}, err
		}
		return Restored{JournalID: id, MadeAt: time.Unix(s.madeAt, 0), Devices: devices}, nil
	}()
	if cerr := d.Close(); cerr != nil && err == nil {
		err = fmt.Errorf("close the restored database: %w", cerr)
	}
	if err != nil {
		return Restored{}, err
	}
	if _, err := os.Stat(s.db + "-wal"); err == nil {
		return Restored{}, errors.New("the restored database's journal was not folded back into it")
	}
	return restored, nil
}

// place moves the staged backup into the target: the attachments, then the
// database, then the key file. The key file is the moment the place becomes a
// server - with it and the database there, a start finds a locked server -
// so it goes last; whatever went before it is taken back if a later step
// fails, and the place is left as empty as it was found.
func (s *staging) place(t Target, keyFile []byte) error {
	// An empty attachments directory may be there already, and checkEmpty
	// found it empty: the staged one takes its place.
	if err := os.Remove(t.FilesPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("make room for the attachments: %w", err)
	}
	if err := os.Rename(s.files, t.FilesPath); err != nil {
		return fmt.Errorf("put the attachments in place: %w", err)
	}
	if err := os.Rename(s.db, t.DBPath); err != nil {
		_ = os.Rename(t.FilesPath, s.files)
		return fmt.Errorf("put the database in place: %w", err)
	}
	if err := vault.WriteFile(t.DBPath+".key", keyFile); err != nil {
		_ = os.Rename(t.DBPath, s.db)
		_ = os.Rename(t.FilesPath, s.files)
		return err
	}
	if err := vault.SyncDir(filepath.Dir(t.FilesPath)); err != nil {
		return err
	}
	return nil
}

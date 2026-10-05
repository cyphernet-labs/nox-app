// Package blob stores attachment bytes on disk, one file per server-issued
// id, confined to a single directory via os.Root. Names supplied by users
// never touch paths. An upload is written to <id>.part and becomes visible
// atomically on Finalize - readers can never observe partial bytes.
//
// A part outlives a broken request (043). Through Tor a 100 MiB file takes
// tens of minutes and the circuit can break in the middle; a part thrown
// away on every break would never finish. <id>.synced records how many
// leading bytes of the part have reached stable storage, and the next
// request continues from there.
package blob

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"strconv"
	"strings"
)

const (
	partSuffix   = ".part"
	syncedSuffix = ".synced"
	// tmpSuffix is where a new synced record is written before the rename
	// that makes it current.
	tmpSuffix = ".tmp"
)

// ErrShortPart is returned by Resume when the part holds fewer durable bytes
// than the offset asked for: what the caller wants to continue is no longer
// all on disk.
var ErrShortPart = errors.New("part holds fewer durable bytes than the offset")

// Store is a handle to the files directory.
type Store struct {
	root *os.Root
}

// Open creates the directory if needed and confines all access to it.
func Open(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create files dir: %w", err)
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		return nil, fmt.Errorf("open files dir: %w", err)
	}
	return &Store{root: root}, nil
}

// Close releases the directory handle.
func (s *Store) Close() error {
	return s.root.Close()
}

// Upload is an in-progress write. Exactly one of Finalize, Suspend, Rollback
// or Abort must be called.
type Upload struct {
	root *os.Root
	id   string
	f    *os.File
	// size is how many bytes the part holds, durable or not.
	size int64
	// synced is what <id>.synced says right now.
	synced int64
}

// Create starts a fresh upload for id: whatever an earlier one left is
// dropped.
func (s *Store) Create(id string) (*Upload, error) {
	return s.Resume(id, 0)
}

// Resume opens id's part for writing at offset, keeping the bytes before it.
// Offset 0 on an id with no part starts a new one.
//
// It refuses with ErrShortPart when fewer than offset bytes are durable. When
// the part holds more, the record is lowered to offset BEFORE the part is cut:
// the bytes past offset are about to be written again, and a record still
// naming them would vouch, after a crash, for bytes that never reached the
// disk. A new upload writes no record until its first checkpoint.
func (s *Store) Resume(id string, offset int64) (*Upload, error) {
	if offset < 0 {
		return nil, fmt.Errorf("resume %s at %d: negative offset", id, offset)
	}
	received, err := s.Received(id)
	if err != nil {
		return nil, err
	}
	if received < offset {
		return nil, fmt.Errorf("resume %s at %d: %w", id, offset, ErrShortPart)
	}
	synced, err := readSynced(s.root, id)
	if err != nil {
		return nil, err
	}
	if synced > offset {
		if err := writeSynced(s.root, id, offset); err != nil {
			return nil, err
		}
		synced = offset
	}
	f, err := s.root.OpenFile(id+partSuffix, os.O_WRONLY|os.O_CREATE, 0o666)
	if err != nil {
		return nil, fmt.Errorf("open part for %s: %w", id, err)
	}
	if err := f.Truncate(offset); err != nil {
		_ = f.Close()
		return nil, fmt.Errorf("cut part for %s at %d: %w", id, offset, err)
	}
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		_ = f.Close()
		return nil, fmt.Errorf("seek part for %s to %d: %w", id, offset, err)
	}
	return &Upload{root: s.root, id: id, f: f, size: offset, synced: synced}, nil
}

// Received returns how many leading bytes of id's part are on stable
// storage: what the record says, but never more than the part holds. An id
// with no record has nothing durable, and an id with no part has nothing.
//
// A record lower than the truth only costs a few bytes sent again, so any
// version of it that survived a crash is safe; one higher than the truth
// would put whatever the disk held past the real end into the middle of
// somebody's file. That is why the record follows the fsync, never leads it.
func (s *Store) Received(id string) (int64, error) {
	synced, err := readSynced(s.root, id)
	if err != nil {
		return 0, err
	}
	info, err := s.root.Stat(id + partSuffix)
	if errors.Is(err, fs.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("stat part %s: %w", id, err)
	}
	return min(synced, info.Size()), nil
}

// Write streams bytes into the part file.
func (u *Upload) Write(p []byte) (int, error) {
	n, err := u.f.Write(p)
	u.size += int64(n)
	return n, err
}

// CopyFrom streams r into the upload, returning the byte count.
func (u *Upload) CopyFrom(r io.Reader) (int64, error) {
	return io.Copy(u, r)
}

// Size is how many bytes the part holds now, durable or not.
func (u *Upload) Size() int64 {
	return u.size
}

// Checkpoint makes everything written so far durable and records it: the
// part is flushed first and the record written second, so the record never
// names a byte that is not on stable storage.
func (u *Upload) Checkpoint() error {
	if u.size == u.synced {
		return nil
	}
	if err := u.f.Sync(); err != nil {
		return fmt.Errorf("sync part for %s: %w", u.id, err)
	}
	if err := writeSynced(u.root, u.id, u.size); err != nil {
		return err
	}
	u.synced = u.size
	return nil
}

// Suspend ends this request's writing and keeps the part for the next one,
// everything received made durable first.
func (u *Upload) Suspend() error {
	err := u.Checkpoint()
	if cerr := u.f.Close(); cerr != nil && err == nil {
		err = fmt.Errorf("close part for %s: %w", u.id, cerr)
	}
	return err
}

// Rollback drops what was written past offset and keeps the part. A request
// that delivered more than the rest of the file cannot be trusted with any of
// it, while the bytes before it came from requests that ended where they
// should. The record goes down first, for the reason Resume gives.
func (u *Upload) Rollback(offset int64) error {
	var err error
	if u.synced > offset {
		if werr := writeSynced(u.root, u.id, offset); werr != nil {
			err = werr
		} else {
			u.synced = offset
		}
	}
	if err == nil {
		if terr := u.f.Truncate(offset); terr != nil {
			err = fmt.Errorf("cut part for %s at %d: %w", u.id, offset, terr)
		} else {
			u.size = offset
		}
	}
	if cerr := u.f.Close(); cerr != nil && err == nil {
		err = fmt.Errorf("close part for %s: %w", u.id, cerr)
	}
	return err
}

// Finalize flushes the part file to stable storage, closes it and atomically
// renames it into place. The fsync matters: rename is metadata and can be
// journaled before the data blocks land, so a power loss could otherwise
// leave the finalized name holding truncated bytes that the database already
// promises (uploaded=1 commits right after this returns).
//
// The record goes last: a crash before its removal leaves a stray record next
// to a finished file, which nothing reads and Remove clears.
func (u *Upload) Finalize() error {
	if err := u.f.Sync(); err != nil {
		return fmt.Errorf("sync part for %s: %w", u.id, err)
	}
	if err := u.f.Close(); err != nil {
		return fmt.Errorf("close part for %s: %w", u.id, err)
	}
	if err := u.root.Rename(u.id+partSuffix, u.id); err != nil {
		return fmt.Errorf("finalize %s: %w", u.id, err)
	}
	if err := removeIfPresent(u.root, u.id+syncedSuffix); err != nil {
		return fmt.Errorf("drop record of %s: %w", u.id, err)
	}
	return nil
}

// Abort discards the part file and its record: bytes that failed to write
// cannot be trusted, and the next request starts from the first byte.
func (u *Upload) Abort() {
	_ = u.f.Close()
	_ = removeIfPresent(u.root, u.id+partSuffix)
	_ = removeIfPresent(u.root, u.id+syncedSuffix)
	_ = removeIfPresent(u.root, u.id+syncedSuffix+tmpSuffix)
}

// Open returns the finalized bytes for reading (ServeContent-compatible).
func (s *Store) Open(id string) (*os.File, error) {
	f, err := s.root.Open(id)
	if err != nil {
		return nil, fmt.Errorf("open blob %s: %w", id, err)
	}
	return f, nil
}

// Size returns the finalized size, or fs.ErrNotExist if the bytes are gone.
func (s *Store) Size(id string) (int64, error) {
	info, err := s.root.Stat(id)
	if err != nil {
		return 0, fmt.Errorf("stat blob %s: %w", id, err)
	}
	return info.Size(), nil
}

// Exists reports whether finalized bytes are present.
func (s *Store) Exists(id string) bool {
	_, err := s.root.Stat(id)
	return err == nil
}

// Remove deletes the finalized bytes, any leftover part and its record.
// Missing files are not an error: removal is idempotent.
func (s *Store) Remove(id string) error {
	for _, name := range []string{id, id + partSuffix, id + syncedSuffix, id + syncedSuffix + tmpSuffix} {
		if err := removeIfPresent(s.root, name); err != nil {
			return fmt.Errorf("remove %s: %w", name, err)
		}
	}
	return nil
}

// readSynced returns the durable length recorded for id's part. No record is
// zero, and so is a record that does not parse: it vouches for nothing.
func readSynced(root *os.Root, id string) (int64, error) {
	data, err := root.ReadFile(id + syncedSuffix)
	if errors.Is(err, fs.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("read record of %s: %w", id, err)
	}
	n, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil || n < 0 {
		return 0, nil
	}
	return n, nil
}

// writeSynced makes n the durable length recorded for id's part, atomically:
// written beside the record, flushed, then renamed over it, so a crash leaves
// either the old record or the new one and never half of either.
func writeSynced(root *os.Root, id string, n int64) error {
	tmp := id + syncedSuffix + tmpSuffix
	f, err := root.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o666)
	if err != nil {
		return fmt.Errorf("open record of %s: %w", id, err)
	}
	if _, err := f.WriteString(strconv.FormatInt(n, 10)); err != nil {
		_ = f.Close()
		return fmt.Errorf("write record of %s: %w", id, err)
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return fmt.Errorf("sync record of %s: %w", id, err)
	}
	if err := f.Close(); err != nil {
		return fmt.Errorf("close record of %s: %w", id, err)
	}
	if err := root.Rename(tmp, id+syncedSuffix); err != nil {
		return fmt.Errorf("commit record of %s: %w", id, err)
	}
	return nil
}

func removeIfPresent(root *os.Root, name string) error {
	if err := root.Remove(name); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

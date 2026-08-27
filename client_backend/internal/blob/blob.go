// Package blob stores attachment bytes on disk, one file per server-issued
// id, confined to a single directory via os.Root. Names supplied by users
// never touch paths. An upload is written to <id>.part and becomes visible
// atomically on Finalize - readers can never observe partial bytes.
package blob

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
)

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

// Upload is an in-progress write. Either Finalize or Abort must be called.
type Upload struct {
	root *os.Root
	id   string
	f    *os.File
}

// Create starts an upload for id, writing to a temporary part file.
func (s *Store) Create(id string) (*Upload, error) {
	f, err := s.root.Create(id + ".part")
	if err != nil {
		return nil, fmt.Errorf("create part for %s: %w", id, err)
	}
	return &Upload{root: s.root, id: id, f: f}, nil
}

// Write streams bytes into the part file.
func (u *Upload) Write(p []byte) (int, error) {
	return u.f.Write(p)
}

// Finalize flushes the part file to stable storage, closes it and atomically
// renames it into place. The fsync matters: rename is metadata and can be
// journaled before the data blocks land, so a power loss could otherwise
// leave the finalized name holding truncated bytes that the database already
// promises (uploaded=1 commits right after this returns).
func (u *Upload) Finalize() error {
	if err := u.f.Sync(); err != nil {
		return fmt.Errorf("sync part for %s: %w", u.id, err)
	}
	if err := u.f.Close(); err != nil {
		return fmt.Errorf("close part for %s: %w", u.id, err)
	}
	if err := u.root.Rename(u.id+".part", u.id); err != nil {
		return fmt.Errorf("finalize %s: %w", u.id, err)
	}
	return nil
}

// Abort discards the part file.
func (u *Upload) Abort() {
	_ = u.f.Close()
	_ = u.root.Remove(u.id + ".part")
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

// Remove deletes the finalized bytes and any leftover part file. Missing
// files are not an error: removal is idempotent.
func (s *Store) Remove(id string) error {
	err := s.root.Remove(id)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("remove blob %s: %w", id, err)
	}
	if err := s.root.Remove(id + ".part"); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("remove part %s: %w", id, err)
	}
	return nil
}

// CopyFrom streams r into the upload, returning the byte count.
func (u *Upload) CopyFrom(r io.Reader) (int64, error) {
	return io.Copy(u.f, r)
}

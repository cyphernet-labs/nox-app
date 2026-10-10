package db

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"

	"lukechampine.com/adiantum"
)

// The data key is checked before SQLite opens anything.
//
// SQLite tells a key that is not the database's only when it reads the first
// page, and by then it has been through the WAL: it opened it, ran its
// recovery with that key - under which every frame reads as noise, so the WAL
// looks empty - and a connection that closes alone over an empty WAL takes it
// for one it may delete, -shm and all. Whatever was committed and not yet
// copied into the database file goes with it: a server killed with recent
// writes in its WAL and then offered a key file that is not its own lost them
// the moment that key was tried. A hot rollback journal goes the same way.
//
// So the files are read here first, read-only and without SQLite, the way the
// "adiantum" VFS reads them: in 4 KiB blocks, each decrypted with Adiantum
// under the data key and a tweak that is the block's offset in its file. The
// first block of each file starts with that file's header, and a header comes
// out of a block only under the key that wrote it. A refused key has then
// changed nothing on disk: no file opened for writing, none created.
//
// Any one of the three files showing its header is enough. The database's
// alone would turn the right key away after a crash in the middle of a
// checkpoint, which can leave the database's first block torn - noise under
// every key - while the WAL still holds that page and SQLite reads it from
// there. A crash while the WAL starts over is the other way round, and a
// database that crashed in its very first transaction has only its journal.

const (
	// blockSize is what the VFS encrypts in: 4 KiB, SQLite's default page.
	blockSize = 4096
	// walMagic is the first word of a WAL, but for its last bit, which says
	// the byte order of the frame checksums. walVersion is the only WAL format
	// SQLite reads. Both are what SQLite's own recovery checks before it
	// believes a single frame.
	walMagic   = 0x377f0682
	walVersion = 3007000
)

var (
	databaseHeader = []byte("SQLite format 3\x00")
	journalHeader  = []byte{0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7}
)

// sqliteFiles are the files SQLite reads a database from - the database
// itself and, beside it, its WAL and its rollback journal - and the header
// each one starts with.
var sqliteFiles = []struct {
	suffix string
	header func(block []byte) bool
}{
	{"", func(b []byte) bool { return bytes.HasPrefix(b, databaseHeader) }},
	{"-wal", func(b []byte) bool {
		return binary.BigEndian.Uint32(b)&^1 == walMagic && binary.BigEndian.Uint32(b[4:]) == walVersion
	}},
	{"-journal", func(b []byte) bool { return bytes.HasPrefix(b, journalHeader) }},
}

// checkKey returns ErrWrongKey when key did not write the database at path,
// having read its files and changed nothing. A database nothing was written
// to yet - no file, or none with a whole block - has no key to check against,
// and any key makes it.
func checkKey(path string, key []byte) error {
	resolved, err := realPath(path)
	if err != nil || resolved == "" {
		return err
	}
	cipher := adiantum.New(key)
	written := false
	for _, f := range sqliteFiles {
		block, err := firstBlock(resolved + f.suffix)
		if err != nil {
			return err
		}
		if block == nil {
			continue
		}
		written = true
		// The first block's tweak: its offset, zero, as the eight
		// little-endian bytes the VFS writes it in.
		var tweak [8]byte
		if f.header(cipher.Decrypt(block, tweak[:])) {
			return nil
		}
	}
	if written {
		return ErrWrongKey
	}
	return nil
}

// realPath is the database at path with every symbolic link resolved, or ""
// when there is none yet. SQLite names the WAL and the journal after the full
// path the VFS resolves, so a database reached through a link keeps them
// beside its target, not beside the link.
func realPath(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", fmt.Errorf("resolve %q: %w", path, err)
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if errors.Is(err, fs.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("resolve %q: %w", path, err)
	}
	return resolved, nil
}

// firstBlock reads the first block of the file at path, or nil when there is
// no such file or it is shorter than a block: a header not all there says
// nothing about the key.
func firstBlock(path string) ([]byte, error) {
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("check the data key against %s: %w", path, err)
	}
	defer func() { _ = f.Close() }()
	block := make([]byte, blockSize)
	if _, err := io.ReadFull(f, block); err != nil {
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
			return nil, nil
		}
		return nil, fmt.Errorf("check the data key against %s: %w", path, err)
	}
	return block, nil
}

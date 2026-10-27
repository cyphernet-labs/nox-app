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
//
// Every byte on disk is encrypted (047), the part as much as the finished
// file. A file is a 32-byte header and then chunks of 64 KiB of plaintext,
// each sealed on its own with ChaCha20-Poly1305 under a key of the file's own
// (HKDF from the data key and the file id) - so a range is read by opening
// only the chunks it touches, and an upload that broke off continues from the
// start of the chunk it was in. A chunk is sealed only once all of it has
// arrived: until then its bytes wait in the memory of the request carrying
// them, and a request that breaks takes them with it. The record therefore
// only ever vouches for whole sealed chunks - and for the last one, which is
// shorter and sealed the moment the file's last byte arrives.
package blob

import (
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
)

const (
	partSuffix   = ".part"
	syncedSuffix = ".synced"
	// tmpSuffix is where a new synced record is written before the rename
	// that makes it current.
	tmpSuffix = ".tmp"

	// ChunkSize is how many plaintext bytes one sealed chunk holds (047,
	// decision 3): small enough that a break costs little and a range opens
	// little, large enough that the tag on each costs nothing.
	ChunkSize = 64 << 10
	// HeaderSize is the file's header: "NOXF", the format version, the chunk
	// size, and room to grow.
	HeaderSize = 32
	tagSize    = chacha20poly1305.Overhead
	sealedSize = ChunkSize + tagSize
	// formatVersion is the header's version byte. Version 1 is the first one
	// that is encrypted; nothing reads the plaintext files of before.
	formatVersion = 1
	magic         = "NOXF"
	// keyInfo names what a file key is for; the file id follows it.
	keyInfo = "nox/file/v1|"
)

// ErrShortPart is returned by Resume when the part holds fewer durable bytes
// than the offset asked for: what the caller wants to continue is no longer
// all on disk.
var ErrShortPart = errors.New("part holds fewer durable bytes than the offset")

// ErrCorrupt is bytes that do not open: a chunk whose seal fails, a header
// that is not this format, a file whose length is not the one its size
// makes. None of it is ever served.
var ErrCorrupt = errors.New("the file's bytes do not open")

// errPastTheEnd is a write beyond the size the upload was declared with. The
// caller bounds every body by the rest of the file, so it is a bug when it
// happens - and it must still not seal a chunk at the wrong place.
var errPastTheEnd = errors.New("more bytes than the file was declared with")

// Store is a handle to the files directory.
type Store struct {
	root *os.Root
	key  []byte
}

// Open creates the directory if needed and confines all access to it. key is
// the data key every file's own key is derived from.
func Open(dir string, key []byte) (*Store, error) {
	if len(key) != 32 {
		return nil, fmt.Errorf("open files dir: the data key is %d bytes, want 32", len(key))
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create files dir: %w", err)
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		return nil, fmt.Errorf("open files dir: %w", err)
	}
	return &Store{root: root, key: key}, nil
}

// Close releases the directory handle.
func (s *Store) Close() error {
	return s.root.Close()
}

// cipherFor is the AEAD of one file: its key is the data key run through
// HKDF with the file's id, so no two files share a key and a chunk moved from
// one file into another does not open there.
func (s *Store) cipherFor(id string) (cipher.AEAD, error) {
	key, err := hkdf.Key(sha256.New, s.key, nil, keyInfo+id, chacha20poly1305.KeySize)
	if err != nil {
		return nil, fmt.Errorf("derive the key of %s: %w", id, err)
	}
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, fmt.Errorf("make the cipher of %s: %w", id, err)
	}
	return aead, nil
}

// nonce of chunk i: four zero bytes and i. Each file has its own key, and
// within a file each chunk its own index.
func nonce(i int64) []byte {
	var n [chacha20poly1305.NonceSize]byte
	binary.BigEndian.PutUint64(n[4:], uint64(i)) //nolint:gosec // a chunk index is never negative
	return n[:]
}

// aad of chunk i binds its place and whether it ends the file: moving a
// chunk, or cutting the file short at a chunk boundary, fails the seal.
func aad(i int64, last bool) []byte {
	var a [9]byte
	binary.BigEndian.PutUint64(a[:8], uint64(i)) //nolint:gosec // a chunk index is never negative
	if last {
		a[8] = 1
	}
	return a[:]
}

// header is the 32 bytes every file and part starts with: the magic, the
// version, three zero bytes, the chunk size big-endian, twenty zero bytes.
func header() []byte {
	h := make([]byte, HeaderSize)
	copy(h, magic)
	h[4] = formatVersion
	binary.BigEndian.PutUint32(h[8:12], ChunkSize)
	return h
}

// validHeader says whether h is the header this package writes. Anything
// else - another version, another chunk size, a stray byte in the reserve -
// is a file this build cannot read.
func validHeader(h []byte) bool {
	want := header()
	return len(h) == HeaderSize && string(h) == string(want)
}

// CipherLen is how long a file of plain plaintext bytes is on disk.
func CipherLen(plain int64) int64 {
	n := HeaderSize + plain/ChunkSize*sealedSize
	if rem := plain % ChunkSize; rem > 0 {
		n += rem + tagSize
	}
	return n
}

// plainLen is how many plaintext bytes the sealed chunks of a file of n bytes
// on disk would hold. A tail too short to be a chunk holds none.
func plainLen(n int64) int64 {
	if n < HeaderSize {
		return 0
	}
	m := n - HeaderSize
	p := m / sealedSize * ChunkSize
	if rem := m % sealedSize; rem > tagSize {
		p += rem - tagSize
	}
	return p
}

// Upload is an in-progress write. Exactly one of Finalize, Suspend, Rollback
// or Abort must be called - except that Abort may follow a Rollback that
// failed.
type Upload struct {
	root *os.Root
	id   string
	f    *os.File
	aead cipher.AEAD
	// size is the plaintext size the file was declared with: the last chunk
	// is the one that reaches it.
	size int64
	// sealed is how many plaintext bytes the part holds sealed, durable or
	// not.
	sealed int64
	// synced is what <id>.synced says right now.
	synced int64
	// tail is the plaintext of the chunk still arriving. It never reaches the
	// disk until it is whole.
	tail []byte
	// out is where a chunk is sealed into before it is written.
	out []byte
}

// Create starts a fresh upload of a file of size bytes for id: whatever an
// earlier one left is dropped.
func (s *Store) Create(id string, size int64) (*Upload, error) {
	return s.Resume(id, 0, size)
}

// Resume opens id's part for writing at offset, keeping the sealed chunks
// before it. Offset 0 on an id with no part starts a new one. The offset is
// where a chunk starts - or the end of the file, when every byte is in.
//
// It refuses with ErrShortPart when fewer than offset bytes are durable. When
// the part holds more, the record is lowered to offset BEFORE the part is cut:
// the bytes past offset are about to be written again, and a record still
// naming them would vouch, after a crash, for bytes that never reached the
// disk. A new upload writes no record until its first checkpoint.
func (s *Store) Resume(id string, offset, size int64) (*Upload, error) {
	if size < 1 || offset < 0 || offset > size {
		return nil, fmt.Errorf("resume %s at %d of %d: out of range", id, offset, size)
	}
	if offset%ChunkSize != 0 && offset != size {
		// Only Received names offsets, and it names chunk boundaries; a token
		// for another one is a request to ask again.
		return nil, fmt.Errorf("resume %s at %d: not where a chunk starts: %w", id, offset, ErrShortPart)
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
	aead, err := s.cipherFor(id)
	if err != nil {
		return nil, err
	}
	f, err := s.root.OpenFile(id+partSuffix, os.O_WRONLY|os.O_CREATE, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open part for %s: %w", id, err)
	}
	if offset == 0 {
		// A new part: the header, written fresh over whatever was there.
		if err := f.Truncate(0); err != nil {
			_ = f.Close()
			return nil, fmt.Errorf("cut part for %s: %w", id, err)
		}
		if _, err := f.Write(header()); err != nil {
			_ = f.Close()
			return nil, fmt.Errorf("write the header of %s: %w", id, err)
		}
	} else {
		end := CipherLen(offset)
		if err := f.Truncate(end); err != nil {
			_ = f.Close()
			return nil, fmt.Errorf("cut part for %s at %d: %w", id, offset, err)
		}
		if _, err := f.Seek(end, io.SeekStart); err != nil {
			_ = f.Close()
			return nil, fmt.Errorf("seek part for %s to %d: %w", id, offset, err)
		}
	}
	return &Upload{
		root: s.root, id: id, f: f, aead: aead, size: size,
		sealed: offset, synced: synced,
		tail: make([]byte, 0, ChunkSize), out: make([]byte, 0, sealedSize),
	}, nil
}

// Received returns how many leading plaintext bytes of id's part are on
// stable storage: what the record says, but never more than the part's sealed
// chunks hold. An id with no record has nothing durable, an id with no part
// has nothing, and a part whose header this build cannot read has nothing.
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
	f, err := s.root.Open(id + partSuffix)
	if errors.Is(err, fs.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("open part %s: %w", id, err)
	}
	defer func() { _ = f.Close() }()
	info, err := f.Stat()
	if err != nil {
		return 0, fmt.Errorf("stat part %s: %w", id, err)
	}
	h := make([]byte, HeaderSize)
	if _, err := io.ReadFull(f, h); err != nil || !validHeader(h) {
		return 0, nil
	}
	return durable(synced, plainLen(info.Size())), nil
}

// durable is how much of a part to count, given what the record says and what
// the part's chunks hold. Whole chunks only - continuing inside one is
// impossible, because only whole chunks are on disk - unless the record names
// exactly everything in the part: then the part ends in the file's shorter
// last chunk, sealed and flushed, and every byte of the file is in.
func durable(synced, held int64) int64 {
	if synced == held {
		return held
	}
	return min(synced, held) / ChunkSize * ChunkSize
}

// Write takes plaintext into the upload. Whole chunks are sealed and written
// to the part as they complete; the rest waits in memory for its chunk to
// fill - or for the file's last byte, which seals the shorter last chunk.
func (u *Upload) Write(p []byte) (int, error) {
	n := 0
	for len(p) > 0 {
		if u.sealed+int64(len(u.tail)) >= u.size {
			return n, errPastTheEnd
		}
		want := int(min(int64(ChunkSize-len(u.tail)), u.size-u.sealed-int64(len(u.tail))))
		k := min(want, len(p))
		u.tail = append(u.tail, p[:k]...)
		p = p[k:]
		n += k
		if len(u.tail) == ChunkSize || u.sealed+int64(len(u.tail)) == u.size {
			if err := u.sealTail(); err != nil {
				return n, err
			}
		}
	}
	return n, nil
}

// sealTail seals the chunk in tail and appends it to the part.
func (u *Upload) sealTail() error {
	i := u.sealed / ChunkSize
	last := u.sealed+int64(len(u.tail)) == u.size
	u.out = u.aead.Seal(u.out[:0], nonce(i), u.tail, aad(i, last))
	if _, err := u.f.Write(u.out); err != nil {
		return fmt.Errorf("write chunk %d of %s: %w", i, u.id, err)
	}
	u.sealed += int64(len(u.tail))
	u.tail = u.tail[:0]
	return nil
}

// CopyFrom streams r into the upload, returning the byte count.
func (u *Upload) CopyFrom(r io.Reader) (int64, error) {
	return io.Copy(u, r)
}

// Size is how many bytes the upload holds now: the sealed chunks in the part,
// durable or not, and the chunk still arriving in memory.
func (u *Upload) Size() int64 {
	return u.sealed + int64(len(u.tail))
}

// Durable is how many leading bytes of the part are on stable storage and
// recorded as such: where a request that failed to write goes back to.
func (u *Upload) Durable() int64 {
	return u.synced
}

// Checkpoint makes every sealed chunk durable and records it: the part is
// flushed first and the record written second, so the record never names a
// byte that is not on stable storage. The chunk still arriving is not on disk
// at all, and is not counted.
func (u *Upload) Checkpoint() error {
	if u.sealed == u.synced {
		return nil
	}
	if err := u.f.Sync(); err != nil {
		return fmt.Errorf("sync part for %s: %w", u.id, err)
	}
	if err := writeSynced(u.root, u.id, u.sealed); err != nil {
		return err
	}
	u.synced = u.sealed
	return nil
}

// Suspend ends this request's writing and keeps the part for the next one,
// every sealed chunk made durable first. The chunk still arriving goes with
// the request: the next one starts at its first byte.
func (u *Upload) Suspend() error {
	err := u.Checkpoint()
	if cerr := u.f.Close(); cerr != nil && err == nil {
		err = fmt.Errorf("close part for %s: %w", u.id, cerr)
	}
	u.tail = u.tail[:0]
	return err
}

// Rollback drops what was written past offset and keeps the part. A request
// that delivered more than the rest of the file cannot be trusted with any of
// it, while the bytes before it came from requests that ended where they
// should. The record goes down first, for the reason Resume gives. offset is
// one this upload started at or made durable - a chunk boundary.
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
		if terr := u.f.Truncate(CipherLen(offset)); terr != nil {
			err = fmt.Errorf("cut part for %s at %d: %w", u.id, offset, terr)
		} else {
			u.sealed = offset
		}
	}
	u.tail = u.tail[:0]
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
// Every byte must be in and sealed by then: a file is finished whole or not
// at all. The record goes last, with whatever temporary of it a crash left: a
// crash before their removal leaves strays next to a finished file, which
// nothing reads and Remove clears. A failure at any step leaves the part
// closed.
func (u *Upload) Finalize() error {
	if u.sealed != u.size || len(u.tail) > 0 {
		_ = u.f.Close()
		return fmt.Errorf("finalize %s with %d of %d bytes sealed", u.id, u.sealed, u.size)
	}
	if err := u.f.Sync(); err != nil {
		_ = u.f.Close()
		return fmt.Errorf("sync part for %s: %w", u.id, err)
	}
	if err := u.f.Close(); err != nil {
		return fmt.Errorf("close part for %s: %w", u.id, err)
	}
	if err := u.root.Rename(u.id+partSuffix, u.id); err != nil {
		return fmt.Errorf("finalize %s: %w", u.id, err)
	}
	for _, name := range []string{u.id + syncedSuffix, u.id + syncedSuffix + tmpSuffix} {
		if err := removeIfPresent(u.root, name); err != nil {
			return fmt.Errorf("drop record of %s: %w", u.id, err)
		}
	}
	return nil
}

// Abort discards the part file and its record: bytes that failed to write
// cannot be trusted, and the next request starts from the first byte.
func (u *Upload) Abort() {
	_ = u.f.Close()
	u.tail = u.tail[:0]
	_ = removeIfPresent(u.root, u.id+partSuffix)
	_ = removeIfPresent(u.root, u.id+syncedSuffix)
	_ = removeIfPresent(u.root, u.id+syncedSuffix+tmpSuffix)
}

// Reader reads the plaintext of one finished file: an io.ReadSeeker for
// http.ServeContent, which brings Range and If-Range. Only the chunks a read
// touches are opened, one at a time.
type Reader struct {
	f       *os.File
	aead    cipher.AEAD
	size    int64
	modTime time.Time
	pos     int64
	// chunk is the index of the chunk in plain, or -1 for none yet.
	chunk int64
	plain []byte
	in    []byte
}

// Open returns the finalized plaintext of id for reading. size is what the
// file was declared with: a file of any other length on disk - torn by a
// crash, cut, or grown - is ErrCorrupt rather than something to serve.
func (s *Store) Open(id string, size int64) (*Reader, error) {
	f, err := s.root.Open(id)
	if err != nil {
		return nil, fmt.Errorf("open blob %s: %w", id, err)
	}
	r, err := s.reader(f, id, size)
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	return r, nil
}

func (s *Store) reader(f *os.File, id string, size int64) (*Reader, error) {
	info, err := f.Stat()
	if err != nil {
		return nil, fmt.Errorf("stat blob %s: %w", id, err)
	}
	if size < 1 || info.Size() != CipherLen(size) {
		return nil, fmt.Errorf("blob %s is %d bytes on disk, want %d: %w", id, info.Size(), CipherLen(size), ErrCorrupt)
	}
	h := make([]byte, HeaderSize)
	if _, err := f.ReadAt(h, 0); err != nil || !validHeader(h) {
		return nil, fmt.Errorf("blob %s has no header this build reads: %w", id, ErrCorrupt)
	}
	aead, err := s.cipherFor(id)
	if err != nil {
		return nil, err
	}
	return &Reader{
		f: f, aead: aead, size: size, modTime: info.ModTime(), chunk: -1,
		plain: make([]byte, 0, ChunkSize), in: make([]byte, sealedSize),
	}, nil
}

// Read reads plaintext at the current position.
func (r *Reader) Read(p []byte) (int, error) {
	if r.pos >= r.size {
		return 0, io.EOF
	}
	i := r.pos / ChunkSize
	if i != r.chunk {
		if err := r.load(i); err != nil {
			return 0, err
		}
	}
	n := copy(p, r.plain[r.pos-i*ChunkSize:])
	r.pos += int64(n)
	return n, nil
}

// load opens chunk i.
func (r *Reader) load(i int64) error {
	start := i * ChunkSize
	length := min(int64(ChunkSize), r.size-start)
	in := r.in[:length+tagSize]
	if _, err := r.f.ReadAt(in, HeaderSize+i*sealedSize); err != nil {
		return fmt.Errorf("read chunk %d: %w", i, err)
	}
	plain, err := r.aead.Open(r.plain[:0], nonce(i), in, aad(i, start+length == r.size))
	if err != nil {
		r.chunk = -1
		return fmt.Errorf("chunk %d: %w", i, ErrCorrupt)
	}
	r.plain = plain
	r.chunk = i
	return nil
}

// Seek moves the position in plaintext terms; ServeContent asks for the end
// to learn the size, then for where a range starts.
func (r *Reader) Seek(offset int64, whence int) (int64, error) {
	var at int64
	switch whence {
	case io.SeekStart:
		at = offset
	case io.SeekCurrent:
		at = r.pos + offset
	case io.SeekEnd:
		at = r.size + offset
	default:
		return 0, fmt.Errorf("seek: whence %d", whence)
	}
	if at < 0 {
		return 0, errors.New("seek before the start")
	}
	r.pos = at
	return at, nil
}

// Size is the file's plaintext size.
func (r *Reader) Size() int64 {
	return r.size
}

// ModTime is when the file on disk last changed - what Last-Modified and
// If-Range compare.
func (r *Reader) ModTime() time.Time {
	return r.modTime
}

// Close releases the file.
func (r *Reader) Close() error {
	return r.f.Close()
}

// Size returns the finalized plaintext size, or fs.ErrNotExist if the bytes
// are gone. A file whose length on disk no file of any size would have -
// cut inside a chunk's tag - is ErrCorrupt.
func (s *Store) Size(id string) (int64, error) {
	info, err := s.root.Stat(id)
	if err != nil {
		return 0, fmt.Errorf("stat blob %s: %w", id, err)
	}
	plain := plainLen(info.Size())
	if plain < 1 || CipherLen(plain) != info.Size() {
		return 0, fmt.Errorf("blob %s is %d bytes on disk: %w", id, info.Size(), ErrCorrupt)
	}
	return plain, nil
}

// Exists reports whether finalized bytes are present.
func (s *Store) Exists(id string) bool {
	_, err := s.root.Stat(id)
	return err == nil
}

// OpenSealed returns the finished file of id exactly as it lies on disk,
// encrypted: what a backup carries. Nothing is opened and nothing checked; the
// backup's own seal covers it.
func (s *Store) OpenSealed(id string) (*os.File, error) {
	f, err := s.root.Open(id)
	if err != nil {
		return nil, fmt.Errorf("open blob %s: %w", id, err)
	}
	return f, nil
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
	f, err := root.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
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

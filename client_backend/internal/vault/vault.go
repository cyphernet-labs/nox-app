// Package vault keeps the server's data key (047): 32 random bytes that
// encrypt the database and every attachment, and that exist on disk only
// sealed by a key derived from the owner's password.
//
// The password is stored nowhere. What lies beside the database is the key
// file - the data key sealed with XChaCha20-Poly1305 under a key Argon2id
// derives from the password - so a wrong password is a failed seal and
// nothing else: nothing is written, nothing is learned. A forgotten password
// is lost data, by decision: there is no second way in.
//
// Changing the password re-seals the same data key and touches nothing else.
// The database and the files stay as they are, which is why a change takes a
// second whatever the server holds.
package vault

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/chacha20poly1305"
)

const (
	// KeySize is the data key's length.
	KeySize = 32
	// MinPasswordChars is the shortest password the server takes (decision 3).
	MinPasswordChars = 12

	fileVersion = 1
	kdfName     = "argon2id"
	saltSize    = 16
	// sealedAAD binds the seal to what it holds: a sealed blob made for any
	// other purpose does not open as a data key.
	sealedAAD = "nox/datakey/v1"
	// maxKeyFileBytes bounds what is read as a key file. The real one is a few
	// hundred bytes; anything far larger is not one.
	maxKeyFileBytes = 64 << 10

	// The bounds on the parameters a key file may name. A key file read from
	// a backup came from elsewhere, and its parameters are read before the
	// password can say anything about it: without bounds a damaged one could
	// ask Argon2 for a terabyte. Sixteen times the defaults and more.
	maxMemoryKiB   = 1 << 20
	maxIterations  = 64
	maxParallelism = 64
)

var (
	// ErrWrongPassword is a password that does not open the key file.
	ErrWrongPassword = errors.New("wrong password")
	// ErrShortPassword is a password the server does not take: under twelve
	// characters, or nothing but whitespace.
	ErrShortPassword = errors.New("the password needs at least 12 characters")
	// ErrExists is a key file already in place where a new one was to go. A
	// new key over an existing one would leave the database it opens behind
	// it unreadable for good.
	ErrExists = errors.New("a key file is already there")
	// ErrMalformed is a key file that does not read as one.
	ErrMalformed = errors.New("not a key file this server can read")
)

// Params are the Argon2id costs a key is sealed with. They are written into
// the key file, so a file sealed with any of them opens with its own.
type Params struct {
	MemoryKiB   uint32
	Iterations  uint32
	Parallelism uint8
}

// DefaultParams are the costs every key the server seals uses: 64 MiB, three
// passes, four lanes - about a second of work on a small board, a fraction of
// one on a desktop. Tests seal with smaller ones through the same parameter.
func DefaultParams() Params {
	return Params{MemoryKiB: 64 << 10, Iterations: 3, Parallelism: 4}
}

// keyFile is the key file as it lies on disk (data-model.md). The byte fields
// travel as standard base64, which is what encoding/json makes of them.
type keyFile struct {
	Version     int    `json:"version"`
	KDF         string `json:"kdf"`
	MemoryKiB   uint32 `json:"memory_kib"`
	Iterations  uint32 `json:"iterations"`
	Parallelism uint8  `json:"parallelism"`
	Salt        []byte `json:"salt"`
	Nonce       []byte `json:"nonce"`
	Sealed      []byte `json:"sealed"`
}

// CheckPassword says whether the server takes p as a new password: at least
// twelve characters, and not whitespace alone. Characters, not bytes - a
// password in Cyrillic is not half as long as the same one in Latin.
//
// Nothing is trimmed or normalised: the password is exactly what was typed,
// spaces at its ends included, and opens the key only typed the same way.
func CheckPassword(p string) error {
	if utf8.RuneCountInString(p) < MinPasswordChars || strings.TrimSpace(p) == "" {
		return ErrShortPassword
	}
	return nil
}

// Create makes a new data key, seals it with password and writes the key file
// at path. It refuses a password the server does not take and a path that
// already holds a key file; the new data key is returned only once its file
// is on stable storage.
func Create(path, password string, params Params) ([]byte, error) {
	if err := CheckPassword(password); err != nil {
		return nil, err
	}
	if _, err := os.Lstat(path); err == nil {
		return nil, ErrExists
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("look for a key file: %w", err)
	}
	key := make([]byte, KeySize)
	if _, err := rand.Read(key); err != nil {
		return nil, fmt.Errorf("make a data key: %w", err)
	}
	data, err := seal(key, password, params)
	if err != nil {
		return nil, err
	}
	if err := WriteFile(path, data); err != nil {
		return nil, err
	}
	return key, nil
}

// Open reads the key file at path and opens it with password.
func Open(path, password string) ([]byte, error) {
	data, err := ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Unseal(data, password)
}

// ReadFile reads a key file without opening it - what a backup carries.
func ReadFile(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("read the key file: %w", err)
	}
	defer func() { _ = f.Close() }()
	data, err := io.ReadAll(io.LimitReader(f, maxKeyFileBytes+1))
	if err != nil {
		return nil, fmt.Errorf("read the key file: %w", err)
	}
	if len(data) > maxKeyFileBytes {
		return nil, ErrMalformed
	}
	return data, nil
}

// Change re-seals the data key behind the key file at path: current must open
// it, and next becomes the only password that does. The data key itself does
// not change, so nothing it encrypts is touched.
//
// The new file is written beside the old one, flushed, and renamed over it: a
// power cut at any moment leaves either the old file or the new one, and the
// data key opens with one of the two passwords.
func Change(path, current, next string, params Params) error {
	if err := CheckPassword(next); err != nil {
		return err
	}
	data, err := ReadFile(path)
	if err != nil {
		return err
	}
	key, err := Unseal(data, current)
	if err != nil {
		return err
	}
	resealed, err := seal(key, next, params)
	if err != nil {
		return err
	}
	return WriteFile(path, resealed)
}

// Validate says whether data reads as a key file, without a password: its
// version, its parameters and its sizes. A restore asks it before asking for
// the password, so a damaged backup is refused before anyone types anything.
func Validate(data []byte) error {
	_, err := parse(data)
	return err
}

// Unseal opens the key file bytes in data with password.
func Unseal(data []byte, password string) ([]byte, error) {
	kf, err := parse(data)
	if err != nil {
		return nil, err
	}
	kek := derive(password, kf.Salt, Params{MemoryKiB: kf.MemoryKiB, Iterations: kf.Iterations, Parallelism: kf.Parallelism})
	aead, err := chacha20poly1305.NewX(kek)
	if err != nil {
		return nil, fmt.Errorf("open the seal: %w", err)
	}
	key, err := aead.Open(nil, kf.Nonce, kf.Sealed, []byte(sealedAAD))
	if err != nil {
		// The only thing a failed seal says is that this is not the password.
		// The parameters and the salt are bound to it as well: changed, they
		// derive another key, and the seal fails the same way.
		return nil, ErrWrongPassword
	}
	return key, nil
}

// seal makes the bytes of a key file holding key, sealed with password: a new
// salt and a new nonce every time, so two seals of one key share nothing.
func seal(key []byte, password string, params Params) ([]byte, error) {
	if err := params.check(); err != nil {
		return nil, err
	}
	salt := make([]byte, saltSize)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("make a salt: %w", err)
	}
	aead, err := chacha20poly1305.NewX(derive(password, salt, params))
	if err != nil {
		return nil, fmt.Errorf("make the seal: %w", err)
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("make a nonce: %w", err)
	}
	data, err := json.Marshal(keyFile{
		Version:     fileVersion,
		KDF:         kdfName,
		MemoryKiB:   params.MemoryKiB,
		Iterations:  params.Iterations,
		Parallelism: params.Parallelism,
		Salt:        salt,
		Nonce:       nonce,
		Sealed:      aead.Seal(nil, nonce, key, []byte(sealedAAD)),
	})
	if err != nil {
		return nil, fmt.Errorf("encode the key file: %w", err)
	}
	return data, nil
}

// derive is the key that seals the data key: Argon2id over the password.
func derive(password string, salt []byte, p Params) []byte {
	return argon2.IDKey([]byte(password), salt, p.Iterations, p.MemoryKiB, p.Parallelism, chacha20poly1305.KeySize)
}

// parse reads and checks a key file's structure.
func parse(data []byte) (keyFile, error) {
	var kf keyFile
	if len(data) > maxKeyFileBytes || json.Unmarshal(data, &kf) != nil {
		return keyFile{}, ErrMalformed
	}
	if kf.Version != fileVersion || kf.KDF != kdfName {
		return keyFile{}, fmt.Errorf("%w: version %d of %q", ErrMalformed, kf.Version, kf.KDF)
	}
	p := Params{MemoryKiB: kf.MemoryKiB, Iterations: kf.Iterations, Parallelism: kf.Parallelism}
	if err := p.check(); err != nil {
		return keyFile{}, err
	}
	if len(kf.Salt) != saltSize || len(kf.Nonce) != chacha20poly1305.NonceSizeX ||
		len(kf.Sealed) != KeySize+chacha20poly1305.Overhead {
		return keyFile{}, ErrMalformed
	}
	return kf, nil
}

// check refuses costs Argon2 cannot run or should not be asked to.
func (p Params) check() error {
	if p.Parallelism < 1 || p.Parallelism > maxParallelism ||
		p.Iterations < 1 || p.Iterations > maxIterations ||
		p.MemoryKiB < 8*uint32(p.Parallelism) || p.MemoryKiB > maxMemoryKiB {
		return fmt.Errorf("%w: argon2id costs out of bounds", ErrMalformed)
	}
	return nil
}

// WriteFile puts data at path so that a crash leaves either the old file or
// the new one, never half of either: written beside it, flushed, renamed over
// it, and the directory flushed so the rename itself survives a power cut. The
// file is the owner's alone.
func WriteFile(path string, data []byte) error {
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("write the key file: %w", err)
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close()
		_ = os.Remove(tmp)
		return fmt.Errorf("write the key file: %w", err)
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		_ = os.Remove(tmp)
		return fmt.Errorf("flush the key file: %w", err)
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("close the key file: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("put the key file in place: %w", err)
	}
	return SyncDir(filepath.Dir(path))
}

// SyncDir flushes a directory, so a rename or a new name in it survives a
// power cut. Windows cannot open a directory for that and orders its own
// metadata, so there it is a no-op.
func SyncDir(dir string) error {
	if runtime.GOOS == "windows" {
		return nil
	}
	d, err := os.Open(dir)
	if err != nil {
		return fmt.Errorf("open %s to flush it: %w", dir, err)
	}
	defer func() { _ = d.Close() }()
	if err := d.Sync(); err != nil {
		return fmt.Errorf("flush %s: %w", dir, err)
	}
	return nil
}

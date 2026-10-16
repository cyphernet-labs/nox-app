package store

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"

	"nox.app/client-backend/internal/securebox"
)

// ServerIdentity is the machine's own long-lived identity: the key a device
// recognises it by.
//
// The key comes from RustSecureBox (feature 050), the library the app and the
// server share for the connection check: the server proves it in every
// answer to POST /auth (internal/connauth), and the pairing link carries it
// whole - thirty-two bytes. It never touches TLS: TLS gets a throwaway
// certificate of its own on every start, so the two roles cannot be confused.
//
// Both halves live in the database file rather than beside it, because the
// authentication model's case 6 warns that a backup holding only the DB would
// lock out every paired device at once; one artifact makes that impossible.
// Anyone who can read this file has already read every message, so the key adds
// no new class of exposure.
//
// The private half is deliberately NOT a field here. This struct is handed to
// the status page and to device.invite, two paths that have no use for a
// secret - it is reached through ServerKey instead.
//
// There is no owner here any more (046). The machine holds one person, and
// whether a device can still reach it is the device count - one fact, kept in
// one place, rather than a marker beside it that could disagree.
type ServerIdentity struct {
	// PublicKey is the machine's public key, 32 bytes: what the pairing link
	// carries, and what the answer to POST /auth presents.
	PublicKey []byte
}

// KeySource is RustSecureBox as the store needs it: a new pair, and the public
// key of a private one. internal/securebox.Box is the one in production.
type KeySource interface {
	GenerateKeys() (securebox.KeyPair, error)
	PublicKey(own securebox.PrivateKey) (securebox.PublicKey, error)
}

// ErrNoServerIdentity is returned when the machine has no key yet. Callers
// bootstrap with EnsureServerIdentity rather than treating it as a failure.
var ErrNoServerIdentity = errors.New("server identity not initialised")

// EnsureServerIdentity returns the machine's identity, generating it with keys
// on the first ever call. Idempotent: a second caller finds the row the first
// wrote.
//
// Generation and insertion share one immediate transaction, so two goroutines
// racing at startup cannot end up with two different keys - which would be
// worse than a failure, because devices paired against the losing key would
// expect a key the server no longer has.
func (s *Store) EnsureServerIdentity(ctx context.Context, keys KeySource) (ServerIdentity, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("begin ensure server identity: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	id, err := readServerIdentity(ctx, tx)
	if err == nil {
		return id, tx.Commit()
	}
	if !errors.Is(err, ErrNoServerIdentity) {
		return ServerIdentity{}, err
	}

	// Minting a key for a store that ALREADY holds people would silently lock
	// out every device paired against the old one - the exact outcome case 6 of
	// the authentication model warns about. It happens when a restore brings
	// back users without server_identity, and it must be loud: the right answer
	// is to finish the restore, not to hand out a new identity.
	people, err := countPeople(ctx, tx)
	if err != nil {
		return ServerIdentity{}, err
	}
	if people > 0 {
		return ServerIdentity{}, fmt.Errorf(
			"this database holds %d people but no server identity: minting a new key would lock out every "+
				"paired device - restore server_identity from the same backup as the rest of the database", people)
	}

	pair, err := keys.GenerateKeys()
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("generate server key: %w", err)
	}
	_, err = tx.ExecContext(ctx,
		"INSERT INTO server_identity (id, public_key, private_key) VALUES (1, ?, ?)",
		base64.StdEncoding.EncodeToString(pair.PublicKey[:]), base64.StdEncoding.EncodeToString(pair.PrivateKey[:]))
	clear(pair.PrivateKey[:])
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("insert server identity: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return ServerIdentity{}, fmt.Errorf("commit ensure server identity: %w", err)
	}
	return ServerIdentity{PublicKey: pair.PublicKey[:]}, nil
}

// ServerKey reads the private half. Narrow on purpose: it is the only way in,
// and it is reached once, at startup, by the code that answers the channel
// check.
//
// The two columns say one thing twice - the link is built from one, the check
// is signed with the other - so the stored public key is checked against the
// one keys gives for the private key. They disagree when the key was made by
// ANOTHER implementation: the Eidolon check before feature 050, the stub
// before the real RustSecureBox (FR-021). Every device's key came from that
// other implementation too, so none of them can pass the check any more. The
// server then keeps its private key, writes the public key keys gives for it,
// and lets every device go - rekeyed reports it, for the caller to say so in
// the log. Everything the person wrote stays; the next machine link joins a
// device to them with all of it.
func (s *Store) ServerKey(ctx context.Context, keys KeySource) (key securebox.PrivateKey, rekeyed bool, err error) {
	var pubB64, privB64 string
	err = s.read.QueryRowContext(ctx,
		"SELECT public_key, private_key FROM server_identity WHERE id = 1").Scan(&pubB64, &privB64)
	if errors.Is(err, sql.ErrNoRows) {
		return key, false, ErrNoServerIdentity
	}
	if err != nil {
		return key, false, fmt.Errorf("read server private key: %w", err)
	}
	priv, err := base64.StdEncoding.DecodeString(privB64)
	if err != nil {
		return key, false, fmt.Errorf("decode server private key: %w", err)
	}
	if len(priv) != securebox.PrivateKeySize {
		return key, false, fmt.Errorf("server private key is %d bytes, want %d", len(priv), securebox.PrivateKeySize)
	}
	copy(key[:], priv)
	clear(priv)
	stored, err := decodeServerPublicKey(pubB64)
	if err != nil {
		return securebox.PrivateKey{}, false, err
	}
	public, err := keys.PublicKey(key)
	if err != nil {
		return securebox.PrivateKey{}, false, fmt.Errorf("the public key of the server key: %w", err)
	}
	if bytes.Equal(stored, public[:]) {
		return key, false, nil
	}
	if err := s.rekeyServerIdentity(ctx, public); err != nil {
		return securebox.PrivateKey{}, false, err
	}
	return key, true, nil
}

// rekeyServerIdentity writes the public key of another implementation and lets
// every device go, in ONE transaction: the devices, every pairing token - an
// unspent one would pair against a key no device can check, a spent one
// carries no rights - and every request, which names a token. Pairing is
// off-journal (invariant 3): no event is written.
func (s *Store) rekeyServerIdentity(ctx context.Context, public securebox.PublicKey) error {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin rekey server identity: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	for _, q := range []string{
		"DELETE FROM pair_requests",
		"DELETE FROM pair_tokens",
		"DELETE FROM devices",
	} {
		if _, err := tx.ExecContext(ctx, q); err != nil {
			return fmt.Errorf("rekey server identity: %w", err)
		}
	}
	if _, err := tx.ExecContext(ctx, "UPDATE server_identity SET public_key = ? WHERE id = 1",
		base64.StdEncoding.EncodeToString(public[:])); err != nil {
		return fmt.Errorf("rekey server identity: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit rekey server identity: %w", err)
	}
	return nil
}

// ServerIdentity reads the machine's identity without creating one.
func (s *Store) ServerIdentity(ctx context.Context) (ServerIdentity, error) {
	return readServerIdentity(ctx, s.read)
}

// countDevices is the ONE spelling of "can anybody still reach this machine".
//
// Not scoped to a person: this machine holds one, so every device is theirs.
// The machine link, the service page and the last device going away all ask
// this one question, and nothing else answers it.
func countDevices(ctx context.Context, q rowQuerier) (int, error) {
	var devices int
	if err := q.QueryRowContext(ctx, "SELECT COUNT(1) FROM devices").Scan(&devices); err != nil {
		return 0, fmt.Errorf("count devices: %w", err)
	}
	return devices, nil
}

type rowQuerier interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func readServerIdentity(ctx context.Context, q rowQuerier) (ServerIdentity, error) {
	var pubB64 string
	err := q.QueryRowContext(ctx, "SELECT public_key FROM server_identity WHERE id = 1").Scan(&pubB64)
	if errors.Is(err, sql.ErrNoRows) {
		return ServerIdentity{}, ErrNoServerIdentity
	}
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("read server identity: %w", err)
	}
	pub, err := decodeServerPublicKey(pubB64)
	if err != nil {
		return ServerIdentity{}, err
	}
	return ServerIdentity{PublicKey: pub}, nil
}

// decodeServerPublicKey reads the stored public key and refuses anything that
// is not thirty-two bytes: a link built from it would carry a key no channel
// check can ever match.
func decodeServerPublicKey(b64 string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode server public key: %w", err)
	}
	if len(raw) != securebox.PublicKeySize {
		return nil, fmt.Errorf("server public key is %d bytes, want %d", len(raw), securebox.PublicKeySize)
	}
	return raw, nil
}

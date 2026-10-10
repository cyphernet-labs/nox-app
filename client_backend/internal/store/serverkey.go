package store

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
)

// ServerIdentity is the machine's own long-lived identity: the key a device
// recognises it by.
//
// The key is Ed25519 and it never touches TLS (feature 044). The server proves
// it inside every channel, signing the session's binding (internal/eidolon),
// and the pairing link carries it whole - thirty-two bytes, where the P-256
// point of 036 needed a fingerprint to fit. TLS gets a throwaway certificate of
// its own on every start, so the two roles cannot be confused: this key names
// the MACHINE and is never handed to a TLS stack, which is also why nothing
// about what Dart's BoringSSL offers in a handshake constrains it any more.
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
	// PublicKey is the machine's Ed25519 public key: what the pairing link
	// carries, and what the server's message in the channel check presents.
	PublicKey ed25519.PublicKey
}

// ErrNoServerIdentity is returned when the machine has no key yet. Callers
// bootstrap with EnsureServerIdentity rather than treating it as a failure.
var ErrNoServerIdentity = errors.New("server identity not initialised")

// EnsureServerIdentity returns the machine's identity, generating it on the
// first ever call. Idempotent: a second caller finds the row the first wrote.
//
// Generation and insertion share one immediate transaction, so two goroutines
// racing at startup cannot end up with two different keys - which would be
// worse than a failure, because devices paired against the losing key would
// expect a key the server no longer has.
func (s *Store) EnsureServerIdentity(ctx context.Context) (ServerIdentity, error) {
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

	// The SEED is stored, not Go's 64-byte private key: it is the standard
	// shape of an Ed25519 private key, the one every other implementation
	// reads, and the rest of the key follows from it.
	var seed [ed25519.SeedSize]byte
	if _, err := rand.Read(seed[:]); err != nil {
		return ServerIdentity{}, fmt.Errorf("generate server key: %w", err)
	}
	pub := ed25519.NewKeyFromSeed(seed[:]).Public().(ed25519.PublicKey)

	_, err = tx.ExecContext(ctx,
		"INSERT INTO server_identity (id, public_key, private_key) VALUES (1, ?, ?)",
		base64.StdEncoding.EncodeToString(pub), base64.StdEncoding.EncodeToString(seed[:]))
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("insert server identity: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return ServerIdentity{}, fmt.Errorf("commit ensure server identity: %w", err)
	}
	return ServerIdentity{PublicKey: pub}, nil
}

// ServerKey reads the private half. Narrow on purpose: it is the only way in,
// and it is reached once, at startup, by the code that answers the channel
// check.
//
// The seed is checked against the stored public key before it is handed out.
// The two columns say one thing twice - the link is built from one, the check
// is signed with the other - and a pair that disagrees would hand every device
// a key the server cannot prove. Refusing to start says so where it can be
// fixed; serving would say it as a refusal on every device.
func (s *Store) ServerKey(ctx context.Context) (ed25519.PrivateKey, error) {
	var pubB64, seedB64 string
	err := s.read.QueryRowContext(ctx,
		"SELECT public_key, private_key FROM server_identity WHERE id = 1").Scan(&pubB64, &seedB64)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNoServerIdentity
	}
	if err != nil {
		return nil, fmt.Errorf("read server private key: %w", err)
	}
	seed, err := base64.StdEncoding.DecodeString(seedB64)
	if err != nil {
		return nil, fmt.Errorf("decode server private key: %w", err)
	}
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("server private key is %d bytes, want a %d-byte Ed25519 seed", len(seed), ed25519.SeedSize)
	}
	pub, err := decodeServerPublicKey(pubB64)
	if err != nil {
		return nil, err
	}
	priv := ed25519.NewKeyFromSeed(seed)
	if !pub.Equal(priv.Public()) {
		return nil, errors.New("server_identity is inconsistent: the stored public key is not the private key's")
	}
	return priv, nil
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
func decodeServerPublicKey(b64 string) (ed25519.PublicKey, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode server public key: %w", err)
	}
	if len(raw) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("server public key is %d bytes, want a %d-byte Ed25519 key", len(raw), ed25519.PublicKeySize)
	}
	return ed25519.PublicKey(raw), nil
}

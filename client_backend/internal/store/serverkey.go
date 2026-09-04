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
// pins the connection against, and the moment somebody claimed this server.
//
// PrivateKey is the 32-byte Ed25519 seed, base64. It lives in the database
// file rather than beside it because the authentication model's case 6 warns
// that a backup holding only the DB breaks pinning for every paired device at
// once - one artifact makes that impossible. Anyone who can read this file has
// already read every message, so the key adds no new class of exposure.
type ServerIdentity struct {
	PublicKey string
	// Claimed reports whether this server already has an owner. While it is
	// false only claim tokens are accepted; once true, claim is dead forever.
	Claimed bool
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
// pin something the server no longer has.
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

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("generate server key: %w", err)
	}
	// The seed, not the expanded private key: 32 bytes instead of 64, and the
	// pair derives from it deterministically.
	seed := base64.StdEncoding.EncodeToString(priv.Seed())
	pubB64 := base64.StdEncoding.EncodeToString(pub)

	_, err = tx.ExecContext(ctx,
		"INSERT INTO server_identity (id, public_key, private_key, claimed_at) VALUES (1, ?, ?, NULL)",
		pubB64, seed)
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("insert server identity: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return ServerIdentity{}, fmt.Errorf("commit ensure server identity: %w", err)
	}
	return ServerIdentity{PublicKey: pubB64}, nil
}

// ServerIdentity reads the machine's identity without creating one.
func (s *Store) ServerIdentity(ctx context.Context) (ServerIdentity, error) {
	return readServerIdentity(ctx, s.read)
}

// MarkClaimed records that this server now has an owner, killing the claim
// token type forever. Idempotent, and deliberately never un-sets: ownership
// is not something a later call may quietly hand back.
func (s *Store) MarkClaimed(ctx context.Context, tx *sql.Tx, now int64) error {
	_, err := tx.ExecContext(ctx,
		"UPDATE server_identity SET claimed_at = ? WHERE id = 1 AND claimed_at IS NULL", now)
	if err != nil {
		return fmt.Errorf("mark claimed: %w", err)
	}
	return nil
}

type rowQuerier interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func readServerIdentity(ctx context.Context, q rowQuerier) (ServerIdentity, error) {
	var pub string
	var claimedAt sql.NullInt64
	err := q.QueryRowContext(ctx,
		"SELECT public_key, claimed_at FROM server_identity WHERE id = 1").Scan(&pub, &claimedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return ServerIdentity{}, ErrNoServerIdentity
	}
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("read server identity: %w", err)
	}
	return ServerIdentity{PublicKey: pub, Claimed: claimedAt.Valid}, nil
}

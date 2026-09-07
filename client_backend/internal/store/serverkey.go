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
	// OwnerUserID is the person this machine belongs to, empty while nobody
	// owns it. It is the ONLY definition of "claimed": deciding by ClaimedAt
	// instead would put one fact in two records, and two records of one fact
	// eventually disagree.
	OwnerUserID string
	// ClaimedAt is when the machine was claimed, zero while it has no owner.
	// Nothing decides by it - it is there because the moment is unrecoverable
	// and the service page will want to show it. Read today only by the test
	// that pins it still being written.
	ClaimedAt int64
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

	// Minting a key for a store that ALREADY holds people would silently break
	// pinning for every device paired against the old one - the exact outcome
	// case 6 of the authentication model warns about. It happens when a restore
	// brings back users without server_identity, and it must be loud: the right
	// answer is to finish the restore, not to hand out a new identity.
	people, err := countPeople(ctx, tx)
	if err != nil {
		return ServerIdentity{}, err
	}
	if people > 0 {
		return ServerIdentity{}, fmt.Errorf(
			"this database holds %d people but no server identity: minting a new key would break pinning for every "+
				"paired device - restore server_identity from the same backup as the rest of the database", people)
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

// setOwner records the person this machine belongs to. Called from inside the
// claim transaction in Pair, so ownership and the person that holds it are
// committed together or not at all.
//
// Conditional on the column still being empty: a claim racing another one must
// not move ownership. The caller does not read the outcome back - the branch
// that reaches here already knows which of the two cases it is in.
func setOwner(ctx context.Context, tx *sql.Tx, userID string, now int64) error {
	// claimed_at is written in the SAME statement on purpose. It decides
	// nothing, but the moment is unrecoverable, and keeping the two writes
	// apart is how one of them gets dropped by a later edit.
	if _, err := tx.ExecContext(ctx,
		"UPDATE server_identity SET owner_user_id = ?, claimed_at = ? WHERE id = 1 AND owner_user_id IS NULL",
		userID, now); err != nil {
		return fmt.Errorf("set server owner: %w", err)
	}
	return nil
}

// OwnershipState is everything startup needs to know about who owns this
// machine, read in ONE transaction.
//
// One read, because the three questions are one fact: taken apart they can
// straddle a committing claim and describe a store that never existed, and the
// answers then have to be threaded between functions to keep them agreeing.
type OwnershipState struct {
	// Owned is true when the machine has an owner recorded.
	Owned bool
	// OwnerCanGetIn is true when that owner still has a device to reach it
	// with. "Occupied" means this, never "any device is here": counting every
	// device locks an owner out of their own machine as soon as somebody else's
	// is running.
	OwnerCanGetIn bool
	// Stranded is the state no code path produces and a partial restore can:
	// people in the store, nobody recorded as the owner.
	Stranded bool
	// People is the count, for the operator-facing warning. Never an id
	// (Principle I).
	People int
}

// ReadOwnershipState answers all of it at once.
//
// A MISSING machine row is deliberately not Stranded: that state is fatal and
// has its own remedy - EnsureServerIdentity refuses to mint a key for a store
// that already holds people, because a new key breaks pinning for every device
// paired against the old one.
func (s *Store) ReadOwnershipState(ctx context.Context) (OwnershipState, error) {
	tx, err := s.read.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return OwnershipState{}, fmt.Errorf("begin ownership read: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	owner, err := ownerUserID(ctx, tx)
	if errors.Is(err, ErrNoServerIdentity) {
		return OwnershipState{}, nil
	}
	if err != nil {
		return OwnershipState{}, err
	}
	people, err := countPeople(ctx, tx)
	if err != nil {
		return OwnershipState{}, err
	}
	if owner == "" {
		return OwnershipState{Stranded: people > 0, People: people}, nil
	}
	devices, err := ownerDeviceCount(ctx, tx, owner)
	if err != nil {
		return OwnershipState{}, err
	}
	return OwnershipState{Owned: true, OwnerCanGetIn: devices > 0, People: people}, nil
}

// ownerDeviceCount is the ONE spelling of "how many devices can the owner still
// reach this machine with".
func ownerDeviceCount(ctx context.Context, q rowQuerier, owner string) (int, error) {
	var devices int
	if err := q.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM devices WHERE user_id = ?", owner).Scan(&devices); err != nil {
		return 0, fmt.Errorf("count owner devices: %w", err)
	}
	return devices, nil
}

// ownsServer reports whether userID is the person this machine belongs to.
//
// The one place the rule lives. It was hand-copied into four reply paths, and
// the next one would have been copied from whichever of them its author found
// first: forget the empty-string guard and every identity with a blank id owns
// the server; read claimed_at instead and the two-records-of-one-fact split
// this feature removed comes straight back.
//
// A machine with no row yet owns nothing and belongs to nobody, which is not an
// error for a caller asking about ownership - only for one asking for the key.
func ownsServer(ctx context.Context, q rowQuerier, userID string) (bool, error) {
	owner, err := ownerUserID(ctx, q)
	if errors.Is(err, ErrNoServerIdentity) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return owner != "" && owner == userID, nil
}

// ownerUserID reads the owner inside a transaction that is already open.
func ownerUserID(ctx context.Context, q rowQuerier) (string, error) {
	var owner sql.NullString
	err := q.QueryRowContext(ctx, "SELECT owner_user_id FROM server_identity WHERE id = 1").Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNoServerIdentity
	}
	if err != nil {
		return "", fmt.Errorf("read server owner: %w", err)
	}
	return owner.String, nil
}

type rowQuerier interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func readServerIdentity(ctx context.Context, q rowQuerier) (ServerIdentity, error) {
	var pub string
	var claimedAt sql.NullInt64
	var owner sql.NullString
	err := q.QueryRowContext(ctx,
		"SELECT public_key, claimed_at, owner_user_id FROM server_identity WHERE id = 1").Scan(&pub, &claimedAt, &owner)
	if errors.Is(err, sql.ErrNoRows) {
		return ServerIdentity{}, ErrNoServerIdentity
	}
	if err != nil {
		return ServerIdentity{}, fmt.Errorf("read server identity: %w", err)
	}
	return ServerIdentity{PublicKey: pub, OwnerUserID: owner.String, ClaimedAt: claimedAt.Int64}, nil
}

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
// recognises it by, and the moment somebody claimed it.
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
type ServerIdentity struct {
	// PublicKey is the machine's Ed25519 public key: what the pairing link
	// carries, and what the server's message in the channel check presents.
	PublicKey ed25519.PublicKey
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
		"INSERT INTO server_identity (id, public_key, private_key, claimed_at) VALUES (1, ?, ?, NULL)",
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
	// HasPerson is true when the store already holds somebody, whether or not
	// the ownership marker survived. It exists because "unclaimed" and "empty"
	// stopped being the same thing: a claim on a store that holds a person
	// ATTACHES to them and their whole conversation, and telling the operator
	// "the first device to use this becomes the owner" there is simply false.
	HasPerson bool
	// OwnerCanGetIn is true when a device can still reach this machine.
	//
	// It answers REACHABILITY, not ownership, and the name is kept for the one
	// decision it drives: whether to offer a claim link. Read without the owner
	// id on purpose - a store that lost its marker still has a person who can
	// get in, and answering "no" there prints a link over a machine in use that
	// Pair would refuse anyway. Use Owned when the question is who the machine
	// belongs to.
	OwnerCanGetIn bool
}

// ReadOwnershipState answers all of it at once.
func (s *Store) ReadOwnershipState(ctx context.Context) (OwnershipState, error) {
	tx, err := s.read.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return OwnershipState{}, fmt.Errorf("begin ownership read: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	owner, err := ownerUserID(ctx, tx)
	if err != nil && !errors.Is(err, ErrNoServerIdentity) {
		return OwnershipState{}, err
	}
	// The device count is read even when the machine row itself is missing.
	// Answering "nobody can get in" from the absence of that row is the same
	// mistake as answering it from a missing ownership marker: startup would
	// print a claim link over a store somebody is still using, and Pair would
	// refuse every presentation of it. One predicate, one answer.
	devices, err := countDevices(ctx, tx)
	if err != nil {
		return OwnershipState{}, err
	}
	people, err := countPeople(ctx, tx)
	if err != nil {
		return OwnershipState{}, err
	}
	// Owned means the marker names somebody who is THERE. A marker pointing at a
	// row that is gone - reachable by a hand edit with foreign keys off - would
	// otherwise have startup promise "you are back in with your chats and
	// messages" over a store whose claim mints a brand-new person instead, and
	// every surviving message would render as somebody else's.
	owned := false
	if owner != "" {
		found, err := ownerRowExists(ctx, tx, owner)
		if err != nil {
			return OwnershipState{}, err
		}
		owned = found
	}
	return OwnershipState{Owned: owned, HasPerson: people > 0, OwnerCanGetIn: devices > 0}, nil
}

// countDevices is the ONE spelling of "can anybody still reach this machine".
//
// Not scoped to a person: this machine holds one, so every device is theirs.
// Reading it without the owner id matters - the claim path needs the answer
// even when the ownership marker is missing, which is exactly the state where
// scoping by owner silently counted zero and let the machine be taken over.
func countDevices(ctx context.Context, q rowQuerier) (int, error) {
	var devices int
	if err := q.QueryRowContext(ctx, "SELECT COUNT(1) FROM devices").Scan(&devices); err != nil {
		return 0, fmt.Errorf("count devices: %w", err)
	}
	return devices, nil
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
	var pubB64 string
	var claimedAt sql.NullInt64
	var owner sql.NullString
	err := q.QueryRowContext(ctx,
		"SELECT public_key, claimed_at, owner_user_id FROM server_identity WHERE id = 1").Scan(&pubB64, &claimedAt, &owner)
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
	return ServerIdentity{
		PublicKey:   pub,
		OwnerUserID: owner.String,
		ClaimedAt:   claimedAt.Int64,
	}, nil
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

// ownerRowExists reports whether the person named by the ownership marker is
// actually in the store.
//
// A bool question, answered with a bool. It used to fill an *Identity that its
// only caller declared and never read - and on the false path Scan leaves that
// struct zeroed, so the next caller to trust the out-parameter would read a
// person with no id and no name and be told nothing was wrong.
func ownerRowExists(ctx context.Context, q rowQuerier, userID string) (bool, error) {
	var present int
	err := q.QueryRowContext(ctx, "SELECT 1 FROM users WHERE user_id = ?", userID).Scan(&present)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("read the recorded owner: %w", err)
	}
	return true, nil
}

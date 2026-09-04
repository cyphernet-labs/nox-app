package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"math/big"
)

// Identity is the person a connection speaks as. UserID is the public author
// id carried on the wire (contract §3); Label is the current display name.
//
// Every identity is a paired one since feature 032. The anonymous shape that
// used to exist here - a connection presenting no key, served an in-memory
// person - was justified by "the contract forbids refusing such a greeting",
// which misread contract §3: the rule that may not refuse is about the LABEL,
// never about the key. §3 says the opposite for keys, and the whole point of
// the phase is that an unproved connection gets nothing.
type Identity struct {
	UserID string
	Label  string
	// Created reports whether THIS resolution brought the person into being,
	// which is what tells the client to offer the naming step (contract §3).
	// It describes the answer, not the person: a reconnect before the person
	// has named themselves legitimately reports false, because the row already
	// exists. The client therefore treats the onboarding decision as monotonic.
	Created bool
}

// assignedLabelAttempts bounds the search for an unused generated name. There
// is no UNIQUE index on users.label by owner decision, so this is politeness
// rather than a constraint: running out of attempts hands back the last
// candidate instead of failing, because a greeting may never be refused
// because of a name (contract §3).
const assignedLabelAttempts = 8

// ResolveIdentity finds the person a connection speaks as, from the PUBLIC KEY
// of the device that connected. It never creates a person: people come into
// being through pairing (see Pair), and a connection whose key nobody knows is
// not a new person but an unauthorised one.
//
// Recognition is single-valued now. Stage 1 also accepted a one-way derivation
// of a login identifier, which meant anyone who learned that identifier became
// that person - the identifier WAS the secret, and it travelled through
// clipboards and QR codes. Pairing replaced presenting a secret with proving
// possession of a key that never leaves the device, so the derivation is gone
// from the wire, from this lookup and from the schema.
//
// A connection presenting no key at all is refused exactly like one presenting
// an unknown key: there is nothing to recognise it by, and serving it anyway
// was the hole this phase exists to close.
//
// One immediate transaction on the single-connection write pool, so a device
// reconnecting while another of the same person is greeting cannot interleave.
// It writes NO events row: a person being recognised is not visible on the wire.
func (s *Store) ResolveIdentity(ctx context.Context, deviceKey, label string, now int64) (Identity, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return Identity{}, fmt.Errorf("begin resolve identity: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	if deviceKey == "" {
		return Identity{}, ErrDeviceUnknown
	}

	id, found, err := lookupByDevice(ctx, tx, deviceKey)
	if err != nil {
		return Identity{}, err
	}
	if !found {
		// The key is not in the allowed list. Revoked, or belonging to a store
		// that was rebuilt - the device cannot tell those apart and must not:
		// both mean "this is not my server any more".
		return Identity{}, ErrDeviceUnknown
	}

	if err := touchDevice(ctx, tx, deviceKey, now); err != nil {
		return Identity{}, err
	}

	// A greeting without a label does NOT rename. The client states a name only
	// when it has just changed one; a device carrying a stale cache would
	// otherwise push the old name back over a rename made elsewhere, and the
	// two devices of one person would flip-flop forever.
	if label != "" && label != id.Label {
		_, err = tx.ExecContext(ctx, "UPDATE users SET label = ? WHERE user_id = ?", label, id.UserID)
		if err != nil {
			return Identity{}, fmt.Errorf("update label: %w", err)
		}
		id.Label = label
	}

	if err := tx.Commit(); err != nil {
		return Identity{}, fmt.Errorf("commit resolve identity: %w", err)
	}
	return id, nil
}

// ErrDeviceUnknown means the presented key is not in the allowed list. The
// caller answers `unauthenticated`; the device treats it exactly as a
// revocation, because from where it stands the two are the same event.
var ErrDeviceUnknown = errors.New("device key not paired")

func lookupByDevice(ctx context.Context, tx *sql.Tx, deviceKey string) (Identity, bool, error) {
	var id Identity
	err := tx.QueryRowContext(ctx,
		"SELECT u.user_id, u.label FROM devices d JOIN users u ON u.user_id = d.user_id WHERE d.device_key = ?",
		deviceKey).Scan(&id.UserID, &id.Label)
	if errors.Is(err, sql.ErrNoRows) {
		return Identity{}, false, nil
	}
	if err != nil {
		return Identity{}, false, fmt.Errorf("lookup user by device: %w", err)
	}
	return id, true, nil
}

func insertUser(ctx context.Context, tx *sql.Tx, label string, now int64) (Identity, error) {
	assigned, err := assignedLabelTx(ctx, tx, label)
	if err != nil {
		return Identity{}, err
	}
	id := Identity{UserID: "u_" + randomID(), Label: assigned}

	_, err = tx.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES (?, ?, ?)",
		id.UserID, id.Label, now)
	if err != nil {
		return Identity{}, fmt.Errorf("insert user: %w", err)
	}
	return id, nil
}

// insertDevice authorises a key for a person. Called only from pairing: a
// greeting can no longer bring a device into existence, which is the whole
// point - an unknown key is refused, not enrolled.
func insertDevice(ctx context.Context, tx *sql.Tx, deviceKey, userID, platform string, now int64) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO devices (device_key, user_id, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT (device_key) DO UPDATE SET last_seen_at = excluded.last_seen_at`,
		deviceKey, userID, platform, now, now)
	if err != nil {
		return fmt.Errorf("insert device: %w", err)
	}
	return nil
}

// touchDevice records that an already-authorised device was seen. It never
// re-binds the key to another person: a device belongs to whoever paired it.
func touchDevice(ctx context.Context, tx *sql.Tx, deviceKey string, now int64) error {
	_, err := tx.ExecContext(ctx,
		"UPDATE devices SET last_seen_at = ? WHERE device_key = ?", now, deviceKey)
	if err != nil {
		return fmt.Errorf("touch device: %w", err)
	}
	return nil
}

func (s *Store) assignedLabel(ctx context.Context, tx *sql.Tx, label string) (string, error) {
	return assignedLabelTx(ctx, tx, label)
}

// assignedLabelTx returns the stated label, or mints User<random> per the
// design spec. The counter this replaces lived in process memory, so it both
// repeated names after a restart and reset to User1 - random satisfies "survives
// a restart" and "not handed to two people" at once, and does not tell every
// newcomer how many people are on the server.
func assignedLabelTx(ctx context.Context, tx *sql.Tx, label string) (string, error) {
	if label != "" {
		return label, nil
	}
	var candidate string
	for attempt := 0; attempt < assignedLabelAttempts; attempt++ {
		candidate = fmt.Sprintf("User%d", 1000+randomBelow(9000))
		var taken int
		err := tx.QueryRowContext(ctx, "SELECT COUNT(1) FROM users WHERE label = ?", candidate).Scan(&taken)
		if err != nil {
			return "", fmt.Errorf("check assigned label: %w", err)
		}
		if taken == 0 {
			return candidate, nil
		}
	}
	// Exhausting the attempts is not a failure: a greeting may never be refused
	// because of a name, and labels are not unique by owner decision.
	return candidate, nil
}

func randomBelow(n int64) int64 {
	v, err := rand.Int(rand.Reader, big.NewInt(n))
	if err != nil {
		panic(fmt.Sprintf("crypto/rand: %v", err))
	}
	return v.Int64()
}

// JournalID returns this store's identity, minted once by EnsureJournal. A
// client that sees a different value knows the world it cached is gone.
func (s *Store) JournalID(ctx context.Context) (string, error) {
	var id string
	err := s.read.QueryRowContext(ctx, "SELECT journal_id FROM journal WHERE id = 1").Scan(&id)
	if err != nil {
		return "", fmt.Errorf("read journal id: %w", err)
	}
	return id, nil
}

// EnsureJournal mints the store identity on first start and is a no-op after.
// It cannot live in the migration: SQL has no source of randomness fit for it.
func (s *Store) EnsureJournal(ctx context.Context) error {
	_, err := s.write.ExecContext(ctx,
		"INSERT INTO journal (id, journal_id) VALUES (1, ?) ON CONFLICT (id) DO NOTHING",
		"j_"+randomID())
	if err != nil {
		return fmt.Errorf("ensure journal: %w", err)
	}
	return nil
}

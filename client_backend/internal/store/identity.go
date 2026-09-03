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
// Ephemeral is true for a connection that presented neither a login_ref nor a
// device_key - hand tools, the live probe, a port scanner speaking WebSocket.
// The contract forbids refusing such a greeting, but writing a row for every
// one of them is unbounded growth, so the row is deferred until the first
// message.send, the only path that needs a parent row for the author_id
// foreign key. See MaterialiseUser.
type Identity struct {
	UserID string
	Label  string
	// Created reports whether THIS resolution brought the person into being,
	// which is what tells the client to offer the naming step (contract §3).
	// It describes the answer, not the person: a reconnect before the person
	// has named themselves legitimately reports false, because the row already
	// exists. The client therefore treats the onboarding decision as monotonic.
	Created   bool
	Ephemeral bool
}

// assignedLabelAttempts bounds the search for an unused generated name. There
// is no UNIQUE index on users.label by owner decision, so this is politeness
// rather than a constraint: running out of attempts hands back the last
// candidate instead of failing, because a greeting may never be refused
// because of a name (contract §3).
const assignedLabelAttempts = 8

// ResolveIdentity finds or creates the person a connection speaks as, and
// records the device it speaks from. It is the only place identities come
// into being.
//
// Recognition splits in two. idDigest identifies the PERSON: it is the one-way
// derivation of the login identifier the person holds, so re-entering that
// identifier on a reinstalled app or a second machine lands on the same row.
// deviceKey identifies the INSTALL. The person wins on conflict - a known
// device presenting another person's digest is re-bound - because the reverse
// would let an old install keep hold of someone else's history.
//
// Stage 1 proves neither: both are presented, not demonstrated. That is no
// weaker than today, where a bare display name is taken at face value, and it
// is the exact shape stage 2 needs, which only adds signature verification
// over the same lookup.
//
// The whole resolution is one immediate transaction on the single-connection
// write pool, so two first connections of the same person serialise and the
// second finds the row the first created. It writes NO events row: a person
// coming into being is not visible on the wire.
func (s *Store) ResolveIdentity(ctx context.Context, idDigest, deviceKey, label string, now int64) (Identity, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return Identity{}, fmt.Errorf("begin resolve identity: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var id Identity
	var found bool

	if idDigest != "" {
		id, found, err = lookupByDigest(ctx, tx, idDigest)
		if err != nil {
			return Identity{}, err
		}
		if !found {
			id, err = insertUser(ctx, tx, idDigest, label, now)
			if err != nil {
				return Identity{}, err
			}
			id.Created = true
			found = true
		}
	}

	if !found && deviceKey != "" {
		id, found, err = lookupByDevice(ctx, tx, deviceKey)
		if err != nil {
			return Identity{}, err
		}
		if !found {
			id, err = insertUser(ctx, tx, "", label, now)
			if err != nil {
				return Identity{}, err
			}
			id.Created = true
			found = true
		}
	}

	if !found {
		// Neither presented: mint in memory, write nothing.
		label, err = s.assignedLabel(ctx, tx, label)
		if err != nil {
			return Identity{}, err
		}
		if err := tx.Commit(); err != nil {
			return Identity{}, fmt.Errorf("commit resolve identity: %w", err)
		}
		// Created: until this answer no such person existed anywhere, row or not.
		return Identity{UserID: "u_" + randomID(), Label: label, Created: true, Ephemeral: true}, nil
	}

	if deviceKey != "" {
		if err := upsertDevice(ctx, tx, deviceKey, id.UserID, now); err != nil {
			return Identity{}, err
		}
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

// MaterialiseUser writes the row for an identity that was minted in memory by
// ResolveIdentity. It takes a transaction because it must land together with
// whatever needed the parent row: half a person with no message is pointless,
// half a message with no person violates the foreign key.
//
// Idempotent by design: the connection keeps carrying an Ephemeral identity
// after the first send, so every later message re-enters here with the same
// row. The values are identical, so conflict means "already done".
func MaterialiseUser(ctx context.Context, tx *sql.Tx, id Identity, now int64) error {
	_, err := tx.ExecContext(ctx,
		"INSERT INTO users (user_id, label, id_digest, created_at) VALUES (?, ?, NULL, ?) ON CONFLICT (user_id) DO NOTHING",
		id.UserID, id.Label, now)
	if err != nil {
		return fmt.Errorf("materialise user: %w", err)
	}
	return nil
}

func lookupByDigest(ctx context.Context, tx *sql.Tx, idDigest string) (Identity, bool, error) {
	var id Identity
	err := tx.QueryRowContext(ctx,
		"SELECT user_id, label FROM users WHERE id_digest = ?", idDigest).Scan(&id.UserID, &id.Label)
	if errors.Is(err, sql.ErrNoRows) {
		return Identity{}, false, nil
	}
	if err != nil {
		return Identity{}, false, fmt.Errorf("lookup user by digest: %w", err)
	}
	return id, true, nil
}

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

func insertUser(ctx context.Context, tx *sql.Tx, idDigest, label string, now int64) (Identity, error) {
	assigned, err := assignedLabelTx(ctx, tx, label)
	if err != nil {
		return Identity{}, err
	}
	id := Identity{UserID: "u_" + randomID(), Label: assigned}

	var digest any
	if idDigest != "" {
		digest = idDigest
	}
	_, err = tx.ExecContext(ctx,
		"INSERT INTO users (user_id, label, id_digest, created_at) VALUES (?, ?, ?, ?)",
		id.UserID, id.Label, digest, now)
	if err != nil {
		return Identity{}, fmt.Errorf("insert user: %w", err)
	}
	return id, nil
}

// upsertDevice records the install and binds it to the person. created_at is
// the moment the device first appeared and survives a re-binding; last_seen_at
// always moves.
func upsertDevice(ctx context.Context, tx *sql.Tx, deviceKey, userID string, now int64) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO devices (device_key, user_id, created_at, last_seen_at) VALUES (?, ?, ?, ?)
		 ON CONFLICT (device_key) DO UPDATE SET user_id = excluded.user_id, last_seen_at = excluded.last_seen_at`,
		deviceKey, userID, now, now)
	if err != nil {
		return fmt.Errorf("upsert device: %w", err)
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

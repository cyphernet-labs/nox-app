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
// Every identity is a paired one: a connection presenting no key, or a key
// nobody paired, is refused (contract §3) rather than served an in-memory
// person - an unproved connection gets nothing.
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
// candidate instead of failing, because the server refuses nothing because of
// a name (contract §2.1) - least of all the pairing that brings the person
// into being.
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
// It never renames: the greeting carries no name (contract §3), and SetLabel -
// identity.setLabel on the wire - is the only write of one. A greeting that
// could rename would let a device with a stale cache push an old name back
// over a rename made on another device, and the two would flip-flop forever.
//
// One immediate transaction on the single-connection write pool, so a device
// reconnecting while another of the same person is greeting cannot interleave.
// It writes NO events row: a person being recognised is not visible on the wire.
func (s *Store) ResolveIdentity(ctx context.Context, deviceKey string, now int64) (Identity, error) {
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
	err := tx.QueryRowContext(ctx, `
		SELECT u.user_id, u.label
		FROM devices d
		JOIN users u ON u.user_id = d.user_id
		WHERE d.device_key = ?`,
		deviceKey).Scan(&id.UserID, &id.Label)
	if errors.Is(err, sql.ErrNoRows) {
		return Identity{}, false, nil
	}
	if err != nil {
		return Identity{}, false, fmt.Errorf("lookup user by device: %w", err)
	}
	return id, true, nil
}

func insertUser(ctx context.Context, tx *sql.Tx, now int64) (Identity, error) {
	assigned, err := assignedLabelTx(ctx, tx)
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
		// The row is refreshed but NEVER re-bound to another person. Rebinding
		// looks like the fix for "the reply and the row must say the same
		// thing", and it is a device takeover: device_key is public -
		// device.list lists it - and a pairing that ever got a key other than
		// the one its channel proved would let anyone able to issue an invite
		// for themselves walk off with somebody else's paired device. The other
		// way to make the two agree is to refuse the pair, and that is what
		// Pair does (see deviceOwnerOf below).
		`INSERT INTO devices (device_key, user_id, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT (device_key) DO UPDATE SET
		     platform = excluded.platform,
		     last_seen_at = excluded.last_seen_at`,
		deviceKey, userID, platform, now, now)
	if err != nil {
		return fmt.Errorf("insert device: %w", err)
	}
	return nil
}

// deviceOwnerOf reports which person a device key is bound to, empty if the key
// is unknown.
// The ONE definition of "whose device is this". Store.DeviceOwner delegates to
// it, so the security-relevant caller (Pair's takeover refusal) and the
// ordinary one (revoking only your own devices) cannot drift apart about what
// an unknown key means.
func deviceOwnerOf(ctx context.Context, q rowQuerier, deviceKey string) (string, error) {
	var userID string
	err := q.QueryRowContext(ctx, "SELECT user_id FROM devices WHERE device_key = ?", deviceKey).Scan(&userID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("read device owner: %w", err)
	}
	return userID, nil
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

// assignedLabelTx mints the name a new person starts with, User<random> per
// the design spec. Random rather than a counter: it survives a restart, is not
// handed out twice when it can be helped, and does not tell a newcomer how
// many people were here before.
func assignedLabelTx(ctx context.Context, tx *sql.Tx) (string, error) {
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
	// Exhausting the attempts is not a failure: a pairing may never be refused
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

// RotateJournal gives the store a new identity and returns it (047). A
// restored backup is exactly the case the identity exists for: the devices
// may have seen more than the backup holds, and a new journal_id is what makes
// each of them drop its cached world and read the conversation again
// (contract §3). Everything else stays, the machine's key and the paired
// devices included, so nobody pairs again.
func (s *Store) RotateJournal(ctx context.Context) (string, error) {
	id := "j_" + randomID()
	res, err := s.write.ExecContext(ctx, "UPDATE journal SET journal_id = ? WHERE id = 1", id)
	if err != nil {
		return "", fmt.Errorf("rotate journal: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil || n != 1 {
		return "", fmt.Errorf("rotate journal: the store has no journal to rotate")
	}
	return id, nil
}

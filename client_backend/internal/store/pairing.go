package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
)

// Token kinds. The kind is the server's own knowledge: it never travels in the
// link, so a presenter cannot tell a claim from a device invite - and does not
// need to, because the server looks the token up by value.
const (
	TokenClaim        = "claim"
	TokenInviteDevice = "invite_device"
)

// InviteTTLSeconds is how long a device invite stays usable. Ten minutes is
// long enough to carry a phone into the next room and short enough that a
// screenshot of the QR code stops working. Claim tokens deliberately get no
// deadline at all - see IssueClaimToken.
const InviteTTLSeconds int64 = 600

// PairToken is a one-shot pairing right.
type PairToken struct {
	Token  string
	Kind   string
	UserID string
}

// Errors a caller maps onto the wire codes of contract §8A.
var (
	// ErrTokenInvalid covers "no such token", "already spent" and "claim on a
	// server that already has an owner". They are one answer on the wire on
	// purpose: telling them apart would say whether a guessed token exists.
	ErrTokenInvalid = errors.New("pairing token invalid")
	// ErrTokenExpired is a real invite that outlived its deadline. Separated
	// from the above because the person's next action differs: issue a new
	// invite rather than wonder whether they mistyped.
	ErrTokenExpired = errors.New("pairing token expired")
)

// IssueClaimToken mints the token that hands ownership of an unclaimed server
// to the first device that presents it.
//
// It has NO expiry, and that is a decision rather than an omission: the token
// dies by being used, only someone with access to the machine ever sees it,
// and an expiring claim would leave a freshly installed server unclaimable
// forever with no way to mint another.
func (s *Store) IssueClaimToken(ctx context.Context, now int64) (string, error) {
	return s.issueToken(ctx, TokenClaim, "", now, 0)
}

// IssueDeviceInvite mints a token that binds a new device to an EXISTING
// person. Any already-paired device of that person may issue one.
func (s *Store) IssueDeviceInvite(ctx context.Context, userID string, now int64) (string, error) {
	return s.issueToken(ctx, TokenInviteDevice, userID, now, now+InviteTTLSeconds)
}

func (s *Store) issueToken(ctx context.Context, kind, userID string, now, expiresAt int64) (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", fmt.Errorf("generate pairing token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(raw[:])

	var user any
	if userID != "" {
		user = userID
	}
	var expires any
	if expiresAt > 0 {
		expires = expiresAt
	}

	_, err := s.write.ExecContext(ctx,
		"INSERT INTO pair_tokens (token, kind, user_id, created_at, expires_at, used_at) VALUES (?, ?, ?, ?, ?, NULL)",
		token, kind, user, now, expires)
	if err != nil {
		return "", fmt.Errorf("insert pairing token: %w", err)
	}
	return token, nil
}

// burnToken spends a token inside the caller's transaction and reports what it
// was for. It must be called in the same transaction as whatever the token
// authorises, or a crash between the two would spend a token for nothing.
//
// Spending is a conditional UPDATE whose affected-row count decides the race:
// two devices presenting the same invite at the same moment both reach this
// statement, exactly one sees a row change, and the other is told the token is
// invalid. Checking-then-updating would let both through.
func burnToken(ctx context.Context, tx *sql.Tx, token, deviceKey string, now int64) (PairToken, error) {
	var kind string
	var userID sql.NullString
	var expiresAt, usedAt sql.NullInt64

	err := tx.QueryRowContext(ctx,
		"SELECT kind, user_id, expires_at, used_at FROM pair_tokens WHERE token = ?", token).
		Scan(&kind, &userID, &expiresAt, &usedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return PairToken{}, ErrTokenInvalid
	}
	if err != nil {
		return PairToken{}, fmt.Errorf("read pairing token: %w", err)
	}
	if usedAt.Valid {
		return PairToken{}, ErrTokenInvalid
	}
	// NULL expires_at means "no deadline" - the claim token's shape.
	if expiresAt.Valid && expiresAt.Int64 <= now {
		return PairToken{}, ErrTokenExpired
	}

	res, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = ?, used_by = ? WHERE token = ? AND used_at IS NULL", now, deviceKey, token)
	if err != nil {
		return PairToken{}, fmt.Errorf("burn pairing token: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return PairToken{}, fmt.Errorf("burn pairing token rows: %w", err)
	}
	if affected == 0 {
		// Somebody else spent it between the read and the update.
		return PairToken{}, ErrTokenInvalid
	}

	return PairToken{Token: token, Kind: kind, UserID: userID.String}, nil
}

// Pair spends a token and authorises a device key, returning the person the
// device now speaks as.
//
// Everything happens in ONE transaction: burning the token, creating or
// finding the person, writing the device row and - for a claim - marking the
// server owned. A crash between any two of those would either spend a token
// for nothing or authorise a key against a server nobody owns.
//
// Created reports whether a person was brought into being here. It is computed
// from what actually happened, not from the token kind: that distinction is
// what tells the client to offer the naming step, and deriving it from
// anything else is the mistake feature 031 spent a phase removing.
func (s *Store) Pair(ctx context.Context, token, deviceKey, platform string, now int64) (Identity, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return Identity{}, fmt.Errorf("begin pair: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// A token this very device already spent means its reply was lost, not that
	// somebody is replaying one. `pair` commits and THEN replies, so a dropped
	// connection in that window leaves the device paired and the client
	// believing nothing happened - and with a one-shot claim there is no second
	// chance: the token is burned, the server is owned, and a single-device
	// install would be locked out for good. Answering with the same identity is
	// the at-least-once story `message.send` gets from its idempotency key.
	same, found, err := pairedBy(ctx, tx, token, deviceKey)
	if err != nil {
		return Identity{}, err
	}
	if found {
		if err := tx.Commit(); err != nil {
			return Identity{}, fmt.Errorf("commit pair replay: %w", err)
		}
		return same, nil
	}

	pt, err := burnToken(ctx, tx, token, deviceKey, now)
	if err != nil {
		return Identity{}, err
	}

	var id Identity
	switch pt.Kind {
	case TokenClaim:
		// A claim on an already-owned server is refused with the same answer as
		// a token that never existed: the claim died the moment somebody used
		// it, and staying silent about which is which says nothing useful.
		// Read from the OWNER, never from claimed_at. The two say the same
		// thing, and deciding by the poorer of the two records is how they end
		// up disagreeing.
		owner, err := ownerUserID(ctx, tx)
		if err != nil {
			return Identity{}, err
		}
		// Owned means "the OWNER can still get in", not "somebody once did" and
		// not "anybody is here". Revoking the last device - which logout is -
		// would otherwise lock the machine forever: the claim is spent, there is
		// no device to issue an invite from, and recovery is Q16.
		//
		// Counting every device on the server would reintroduce that lockout the
		// moment a second person exists (034): a guest's device left running
		// would keep the owner's own claim link refused for ever, on a machine
		// that is theirs.
		if owner != "" {
			devices, err := ownerDeviceCount(ctx, tx, owner)
			if err != nil {
				return Identity{}, err
			}
			if devices > 0 {
				return Identity{}, ErrTokenInvalid
			}
		}

		switch {
		case owner != "":
			// Re-claiming a server that lost every device attaches to the person
			// who OWNS it. Not to "the only person", and above all not to the
			// oldest row: that inference is what this whole feature exists to
			// delete, and once a second person can exist it would hand a fresh
			// device somebody else's identity and history.
			//
			// A new identity here would orphan the old one instead: their
			// messages keep an author_id nobody can sign in as, and "the
			// identity survives its devices" would be true on paper only.
			if err := loadUser(ctx, tx, owner, &id); err != nil {
				return Identity{}, err
			}
			// Not Created: this person existed before this operation, so there
			// is no naming step ahead - they already have a name.
		default:
			// No owner recorded. If the store also holds no people it is simply
			// fresh, and this claim is the one that names its owner.
			people, err := countPeople(ctx, tx)
			if err != nil {
				return Identity{}, err
			}
			if people > 0 {
				// People but no owner: unreachable through any code path, so
				// the store has been edited by hand. Refuse rather than guess.
				// The two available guesses are both worse than a refusal -
				// attaching to somebody by row order hands a stranger their
				// history, and minting a new person orphans it - and unlike a
				// refusal neither is undoable.
				return Identity{}, ErrTokenInvalid
			}
			id, err = insertUser(ctx, tx, "", now)
			if err != nil {
				return Identity{}, err
			}
			id.Created = true
		}
		// Ownership is recorded HERE, in the transaction that creates the
		// person, rather than derived later from who happens to be oldest: the
		// order rows were created in is not a right, and it stops being even a
		// decent proxy the moment a second person can exist. The write is
		// conditional on the column being empty, so a re-claim attaches to the
		// person who is already the owner and moves ownership nowhere.
		if err := setOwner(ctx, tx, id.UserID, now); err != nil {
			return Identity{}, err
		}
		// True on every path that reaches here, and deliberately not read back
		// to prove it: the branch above resolved `id` either from the recorded
		// owner or from a store that had nobody at all, and setOwner's
		// condition covers exactly the second case.
		id.Owner = true
		// Every OTHER unused claim token dies with this one. They were printed
		// to the server log on earlier starts, and a log is not a secret store:
		// without this, each of them comes back to life the moment the device
		// count drops to zero again, and the oldest scrap of terminal scrollback
		// becomes a way in.
		if _, err := tx.ExecContext(ctx,
			"UPDATE pair_tokens SET used_at = ? WHERE kind = ? AND used_at IS NULL AND token <> ?",
			now, TokenClaim, token); err != nil {
			return Identity{}, fmt.Errorf("retire other claim tokens: %w", err)
		}

	case TokenInviteDevice:
		if err := tx.QueryRowContext(ctx,
			"SELECT user_id, label FROM users WHERE user_id = ?", pt.UserID).Scan(&id.UserID, &id.Label); err != nil {
			return Identity{}, fmt.Errorf("read invited person: %w", err)
		}
		// Deliberately NOT Created: the person existed before this operation,
		// so there is no naming step ahead.
		//
		// Ownership, unlike Created, is whatever it already was: an invite adds
		// a DEVICE to a person, and a person's second device owns exactly what
		// their first one does.
		id.Owner, err = ownsServer(ctx, tx, id.UserID)
		if err != nil {
			return Identity{}, err
		}

	default:
		return Identity{}, ErrTokenInvalid
	}

	// A key already belonging to somebody else is refused outright. It is a
	// PUBLIC value - it rides every greeting and device.list prints it - so
	// without this anyone who can issue an invite for themselves could name a
	// stranger's key and take that device: it would keep working, resolve as
	// the attacker on its next greeting, author every message as them, and
	// vanish from its real owner's device list.
	//
	// Refusing is the other way to satisfy "the row and the reply must agree",
	// and it is the one that does not hand a device away.
	bound, err := deviceOwnerOf(ctx, tx, deviceKey)
	if err != nil {
		return Identity{}, err
	}
	if bound != "" && bound != id.UserID {
		return Identity{}, ErrTokenInvalid
	}
	if err := insertDevice(ctx, tx, deviceKey, id.UserID, platform, now); err != nil {
		return Identity{}, err
	}
	// Record WHO this spending produced and WHAT it did, so a replay can answer
	// with those instead of re-deriving them. Both are only known here, after
	// the branch above resolved the person and whether one came into being.
	//
	// The person matters as much as the outcome: re-deriving it from the device
	// row answers about whoever holds that key at replay time, which after a
	// logout and a re-pair is not who the token produced.
	created := 0
	if id.Created {
		created = 1
	}
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET paired_user_id = ?, created_person = ? WHERE token = ?",
		id.UserID, created, token); err != nil {
		return Identity{}, fmt.Errorf("record pairing outcome: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Identity{}, fmt.Errorf("commit pair: %w", err)
	}
	return id, nil
}

// pairedBy reports the identity a spent token produced, but only when the SAME
// device key is asking. A different key presenting a used token is an ordinary
// replay and stays refused.
//
// It answers exactly what the lost reply said, including `created`. Returning
// false unconditionally would be a DIFFERENT answer from the one being
// replayed: a claim that minted the person reported created, and a retry that
// says otherwise walks the owner of a brand-new server straight past the
// naming step, into the chats list under an auto-assigned User<random>.
func pairedBy(ctx context.Context, tx *sql.Tx, token, deviceKey string) (Identity, bool, error) {
	var id Identity
	// The whole answer comes from the TOKEN's own record - who it produced and
	// what it did - and it is handed only to the device that spent it.
	//
	// Nothing is re-derived here on purpose. Matching through the device's
	// current binding answers about whoever holds that key now, which after a
	// logout and a re-pair is not the person the token produced; and deriving
	// the outcome from the token kind reports "created" for a re-claim that
	// created nobody, walking a named person back through the naming screen.
	//
	// used_by is what keeps a spent token from answering a stranger: the key is
	// public - it rides every greeting and device.list prints it - the token
	// sits in the server log across restarts, and `pair` is the one command
	// that carries no signature.
	// The device must STILL belong to the person the token produced. Without
	// that join the replay path answers before Pair's takeover refusal is ever
	// reached: a key rebound to somebody else - a restore today, an ordinary
	// invite once 034 lands - would be handed the original person's id, label
	// and ownership, and the client writes all three into the wrong device.
	var created int
	err := tx.QueryRowContext(ctx, `
		SELECT u.user_id, u.label, t.created_person
		FROM pair_tokens t
		JOIN users u ON u.user_id = t.paired_user_id
		JOIN devices d ON d.device_key = t.used_by AND d.user_id = t.paired_user_id
		WHERE t.token = ? AND t.used_at IS NOT NULL AND t.used_by = ?`,
		token, deviceKey).Scan(&id.UserID, &id.Label, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return Identity{}, false, nil
	}
	if err != nil {
		return Identity{}, false, fmt.Errorf("read pairing replay: %w", err)
	}
	id.Created = created != 0
	// Ownership is read, not inferred from the kind: a replayed claim answers
	// about a person who owns the machine, and a replayed invite about one who
	// may or may not.
	id.Owner, err = ownsServer(ctx, tx, id.UserID)
	if err != nil {
		return Identity{}, false, err
	}
	return id, true, nil
}

// loadUser fills id with the person named by userID.
func loadUser(ctx context.Context, tx *sql.Tx, userID string, id *Identity) error {
	err := tx.QueryRowContext(ctx,
		"SELECT user_id, label FROM users WHERE user_id = ?", userID).Scan(&id.UserID, &id.Label)
	if errors.Is(err, sql.ErrNoRows) {
		// The foreign key forbids it, so reaching here means the row went away
		// underneath a live transaction. Refusing beats improvising.
		return ErrTokenInvalid
	}
	if err != nil {
		return fmt.Errorf("read owner: %w", err)
	}
	return nil
}

// countPeople reports how many people this server holds.
func countPeople(ctx context.Context, q rowQuerier) (int, error) {
	var people int
	if err := q.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&people); err != nil {
		return 0, fmt.Errorf("count people: %w", err)
	}
	return people, nil
}

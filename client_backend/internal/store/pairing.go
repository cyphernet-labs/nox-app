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

// BurnToken spends a token inside the caller's transaction and reports what it
// was for. It must be called in the same transaction as whatever the token
// authorises, or a crash between the two would spend a token for nothing.
//
// Spending is a conditional UPDATE whose affected-row count decides the race:
// two devices presenting the same invite at the same moment both reach this
// statement, exactly one sees a row change, and the other is told the token is
// invalid. Checking-then-updating would let both through.
func BurnToken(ctx context.Context, tx *sql.Tx, token string, now int64) (PairToken, error) {
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
		"UPDATE pair_tokens SET used_at = ? WHERE token = ? AND used_at IS NULL", now, token)
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

	pt, err := BurnToken(ctx, tx, token, now)
	if err != nil {
		return Identity{}, err
	}

	var id Identity
	switch pt.Kind {
	case TokenClaim:
		// A claim on an already-owned server is refused with the same answer as
		// a token that never existed: the claim died the moment somebody used
		// it, and staying silent about which is which says nothing useful.
		var claimedAt sql.NullInt64
		if err := tx.QueryRowContext(ctx,
			"SELECT claimed_at FROM server_identity WHERE id = 1").Scan(&claimedAt); err != nil {
			return Identity{}, fmt.Errorf("read claim state: %w", err)
		}
		// Owned means "somebody can still get in", not "somebody once did".
		// Revoking the last device - which logout is - would otherwise lock the
		// machine forever: the claim is spent, there is no device to issue an
		// invite from, and recovery is Q16. The person's row survives either
		// way; this is only about being able to attach a device to it again.
		var devices int
		if err := tx.QueryRowContext(ctx, "SELECT COUNT(1) FROM devices").Scan(&devices); err != nil {
			return Identity{}, fmt.Errorf("count devices: %w", err)
		}
		if claimedAt.Valid && devices > 0 {
			return Identity{}, ErrTokenInvalid
		}
		id, err = insertUser(ctx, tx, "", now)
		if err != nil {
			return Identity{}, err
		}
		id.Created = true
		if _, err := tx.ExecContext(ctx,
			"UPDATE server_identity SET claimed_at = ? WHERE id = 1 AND claimed_at IS NULL", now); err != nil {
			return Identity{}, fmt.Errorf("mark claimed: %w", err)
		}

	case TokenInviteDevice:
		if err := tx.QueryRowContext(ctx,
			"SELECT user_id, label FROM users WHERE user_id = ?", pt.UserID).Scan(&id.UserID, &id.Label); err != nil {
			return Identity{}, fmt.Errorf("read invited person: %w", err)
		}
		// Deliberately NOT Created: the person existed before this operation,
		// so there is no naming step ahead.

	default:
		return Identity{}, ErrTokenInvalid
	}

	if err := insertDevice(ctx, tx, deviceKey, id.UserID, platform, now); err != nil {
		return Identity{}, err
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
// Created is deliberately false on this path: the person exists by now, and the
// device is asking again because it never heard the first answer. Saying
// created would send a returning person through onboarding.
func pairedBy(ctx context.Context, tx *sql.Tx, token, deviceKey string) (Identity, bool, error) {
	var id Identity
	err := tx.QueryRowContext(ctx, `
		SELECT u.user_id, u.label
		FROM pair_tokens t
		JOIN devices d ON d.device_key = ?
		JOIN users u ON u.user_id = d.user_id
		WHERE t.token = ? AND t.used_at IS NOT NULL`,
		deviceKey, token).Scan(&id.UserID, &id.Label)
	if errors.Is(err, sql.ErrNoRows) {
		return Identity{}, false, nil
	}
	if err != nil {
		return Identity{}, false, fmt.Errorf("read pairing replay: %w", err)
	}
	return id, true, nil
}

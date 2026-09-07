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
	// TokenInviteUser brings a new PERSON into the circle rather than a new
	// device into an existing person, and it is the only kind whose outcome is
	// decided by a human (contract §8B).
	TokenInviteUser = "invite_user"
)

// InviteTTLSeconds is how long a device invite stays usable. Ten minutes is
// long enough to carry a phone into the next room and short enough that a
// screenshot of the QR code stops working. Claim tokens deliberately get no
// deadline at all - see IssueClaimToken.
const InviteTTLSeconds int64 = 600

// PersonInviteTTLSeconds is how long an invite for a new PERSON stays usable.
// A day rather than the device invite's ten minutes: you carry your own second
// device into the next room, while a stranger has to be reached through a
// messenger first and will not open it the same minute.
const PersonInviteTTLSeconds int64 = 86400

// ApprovalWindowSeconds is how long the owner has to answer once somebody has
// presented a person invite. Chosen for a person rather than for a network -
// long enough to notice a notification, pick up the phone and read the
// question, short enough that the person at the door is not left staring at a
// screen. It is the only deadline in the protocol measured in human reaction
// time, because it is the only place an answer waits on a human.
const ApprovalWindowSeconds int64 = 300

// PairToken is a one-shot pairing right.
type PairToken struct {
	Token  string
	Kind   string
	UserID string
}

// PairResult is what presenting a token produced.
//
// Pair stopped returning a bare Identity when person invites arrived: they have
// an outcome in which there is no identity yet, and "accepted, waiting for the
// owner" is a normal result rather than a failure. Squeezing it into a sentinel
// error would have made every caller tell it apart from real refusals by error
// type - which is exactly the distinction a result type states plainly.
type PairResult struct {
	// Identity is who the device now speaks as. Empty while Pending.
	Identity Identity
	// Pending means the answer belongs to the owner and has not been given.
	Pending bool
	// RequestID names the waiting request on the wire. Empty unless Pending.
	RequestID string
	// ExpiresAt is the owner's deadline. Zero unless Pending.
	ExpiresAt int64
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

// ClaimTokenUsable reports whether a claim token can still be presented.
//
// The service page holds the one token this process minted, and a token can be
// spent between two page loads: somebody claims the server, the owner then
// revokes their last device, and the page is asked for a link again. Handing
// back the burnt one would show the only recovery tool there is, pointing at a
// door that no longer opens.
func (s *Store) ClaimTokenUsable(ctx context.Context, token string) (bool, error) {
	if token == "" {
		return false, nil
	}
	var usedAt sql.NullInt64
	err := s.read.QueryRowContext(ctx,
		"SELECT used_at FROM pair_tokens WHERE token = ? AND kind = ?", token, TokenClaim).Scan(&usedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("read claim token: %w", err)
	}
	return !usedAt.Valid, nil
}

// IssuePersonInvite mints a token that brings a NEW person into the circle.
//
// Only the owner may call it, and the check lives HERE rather than in the
// handler: the right belongs to the operation, not to one way of reaching it.
// The ownership read and the insert share a transaction so a claim landing
// between them cannot produce an invite issued by somebody who was not the
// owner when it was written.
func (s *Store) IssuePersonInvite(ctx context.Context, userID string, now int64) (string, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("begin person invite: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	owns, err := ownsServer(ctx, tx, userID)
	if err != nil {
		return "", err
	}
	if !owns {
		return "", ErrNotOwner
	}

	token, err := newTokenValue()
	if err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx,
		"INSERT INTO pair_tokens (token, kind, user_id, created_at, expires_at, used_at) VALUES (?, ?, ?, ?, ?, NULL)",
		token, TokenInviteUser, userID, now, now+PersonInviteTTLSeconds); err != nil {
		return "", fmt.Errorf("insert person invite: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return "", fmt.Errorf("commit person invite: %w", err)
	}
	return token, nil
}

// newTokenValue mints the 16 random bytes a pairing link carries.
func newTokenValue() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", fmt.Errorf("generate pairing token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(raw[:]), nil
}

func (s *Store) issueToken(ctx context.Context, kind, userID string, now, expiresAt int64) (string, error) {
	token, err := newTokenValue()
	if err != nil {
		return "", err
	}

	var user any
	if userID != "" {
		user = userID
	}
	var expires any
	if expiresAt > 0 {
		expires = expiresAt
	}

	_, err = s.write.ExecContext(ctx,
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
func (s *Store) Pair(ctx context.Context, token, deviceKey, platform string, now int64) (PairResult, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return PairResult{}, fmt.Errorf("begin pair: %w", err)
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
		return PairResult{}, err
	}
	if found {
		if err := tx.Commit(); err != nil {
			return PairResult{}, fmt.Errorf("commit pair replay: %w", err)
		}
		return PairResult{Identity: same}, nil
	}

	// A person invite this device already presented but that produced nobody -
	// still waiting, declined, or timed out. It has to be answered before
	// burnToken, which would report a spent token as simply invalid and lose
	// the three answers the person actually needs (contract §8B).
	res, handled, err := pendingOutcome(ctx, tx, token, deviceKey, now)
	if handled {
		// The expiry branch WRITES, so the transaction is committed even when
		// the answer is an error.
		if cerr := tx.Commit(); cerr != nil {
			return PairResult{}, fmt.Errorf("commit pending outcome: %w", cerr)
		}
		return res, err
	}
	if err != nil {
		return PairResult{}, err
	}

	pt, err := burnToken(ctx, tx, token, deviceKey, now)
	if err != nil {
		return PairResult{}, err
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
			return PairResult{}, err
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
				return PairResult{}, err
			}
			if devices > 0 {
				return PairResult{}, ErrTokenInvalid
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
				return PairResult{}, err
			}
			// Not Created: this person existed before this operation, so there
			// is no naming step ahead - they already have a name.
		default:
			// No owner recorded. If the store also holds no people it is simply
			// fresh, and this claim is the one that names its owner.
			people, err := countPeople(ctx, tx)
			if err != nil {
				return PairResult{}, err
			}
			if people > 0 {
				// People but no owner: unreachable through any code path, so
				// the store has been edited by hand. Refuse rather than guess.
				// The two available guesses are both worse than a refusal -
				// attaching to somebody by row order hands a stranger their
				// history, and minting a new person orphans it - and unlike a
				// refusal neither is undoable.
				return PairResult{}, ErrTokenInvalid
			}
			id, err = insertUser(ctx, tx, "", now)
			if err != nil {
				return PairResult{}, err
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
			return PairResult{}, err
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
			return PairResult{}, fmt.Errorf("retire other claim tokens: %w", err)
		}

	case TokenInviteUser:
		// Refused BEFORE the owner is asked anything. A key that already
		// belongs to somebody cannot be handed over (the rule of phase 032),
		// so approving this request could never work - and waking the owner
		// with a question whose "yes" does nothing would let them authorise
		// something that will not happen.
		bound, err := deviceOwnerOf(ctx, tx, deviceKey)
		if err != nil {
			return PairResult{}, err
		}
		if bound != "" {
			return PairResult{}, ErrTokenInvalid
		}
		req, err := recordPendingRequest(ctx, tx, token, platform, now)
		if err != nil {
			return PairResult{}, err
		}
		// Committed here and returned early: no person exists yet, so none of
		// the tail below - the device row, the recorded outcome - applies. The
		// token is already spent, which is what stops a second presenter from
		// raising a second question about one invite.
		if err := tx.Commit(); err != nil {
			return PairResult{}, fmt.Errorf("commit pairing request: %w", err)
		}
		return PairResult{Pending: true, RequestID: req.RequestID, ExpiresAt: req.ExpiresAt}, nil

	case TokenInviteDevice:
		if err := tx.QueryRowContext(ctx,
			"SELECT user_id, label FROM users WHERE user_id = ?", pt.UserID).Scan(&id.UserID, &id.Label); err != nil {
			return PairResult{}, fmt.Errorf("read invited person: %w", err)
		}
		// Deliberately NOT Created: the person existed before this operation,
		// so there is no naming step ahead.
		//
		// Ownership, unlike Created, is whatever it already was: an invite adds
		// a DEVICE to a person, and a person's second device owns exactly what
		// their first one does.
		id.Owner, err = ownsServer(ctx, tx, id.UserID)
		if err != nil {
			return PairResult{}, err
		}

	default:
		return PairResult{}, ErrTokenInvalid
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
		return PairResult{}, err
	}
	if bound != "" && bound != id.UserID {
		return PairResult{}, ErrTokenInvalid
	}
	if err := insertDevice(ctx, tx, deviceKey, id.UserID, platform, now); err != nil {
		return PairResult{}, err
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
		return PairResult{}, fmt.Errorf("record pairing outcome: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return PairResult{}, fmt.Errorf("commit pair: %w", err)
	}
	return PairResult{Identity: id}, nil
}

// pendingOutcome answers a person invite that THIS device already presented.
//
// handled is false for every other case - a fresh token, another kind, another
// device - and the caller carries on into burnToken. A different key presenting
// a spent invite falls through on purpose: burnToken refuses it as invalid, and
// a burned token must not tell a stranger even that it once existed.
func pendingOutcome(ctx context.Context, tx *sql.Tx, token, deviceKey string, now int64) (PairResult, bool, error) {
	var kind string
	var usedBy sql.NullString
	var createdAt int64
	var awaitingUntil sql.NullInt64
	var outcome, requestID sql.NullString
	err := tx.QueryRowContext(ctx,
		`SELECT kind, used_by, created_at, awaiting_until, outcome, request_id
		 FROM pair_tokens WHERE token = ? AND used_at IS NOT NULL`, token).
		Scan(&kind, &usedBy, &createdAt, &awaitingUntil, &outcome, &requestID)
	if errors.Is(err, sql.ErrNoRows) {
		return PairResult{}, false, nil
	}
	if err != nil {
		return PairResult{}, false, fmt.Errorf("read pending outcome: %w", err)
	}
	if kind != TokenInviteUser || !usedBy.Valid || usedBy.String != deviceKey {
		return PairResult{}, false, nil
	}

	switch {
	case outcome.String == OutcomeDeclined:
		return PairResult{}, true, ErrPairDeclined
	case outcome.String == OutcomeExpired:
		return PairResult{}, true, ErrPairTimeout
	case outcome.String == OutcomeApproved:
		// Approved, yet pairedBy found nothing: the device row is gone, which
		// means this device was revoked after joining - a logout. The person
		// survives; the invite does not. A spent invite is spent.
		return PairResult{}, true, ErrTokenInvalid
	case !awaitingUntil.Valid:
		// Spent, unresolved and with no deadline: not reachable through any
		// code path, so the row has been edited by hand. Refuse rather than
		// improvise.
		return PairResult{}, true, ErrTokenInvalid
	case awaitingUntil.Int64 <= now:
		// The deadline passed and the sweeper has not reached it yet. Settle it
		// here so the answer is the same whichever gets there first.
		if err := setOutcome(ctx, tx, token, OutcomeExpired); err != nil {
			return PairResult{}, true, err
		}
		// The id rides along WITH the error: settling here takes the row out of
		// both the sweeper's predicate and the greeting re-send, so this is the
		// last moment anything can tell the owner the question is dead. Without
		// it their screen keeps a question nothing will ever close.
		return PairResult{RequestID: requestID.String}, true, ErrPairTimeout
	default:
		// Still waiting. The same request, not a second one: the answer the
		// owner eventually gives has to reach whoever is asking now.
		return PairResult{Pending: true, RequestID: requestID.String, ExpiresAt: awaitingUntil.Int64}, true, nil
	}
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

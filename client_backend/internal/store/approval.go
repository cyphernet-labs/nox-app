package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
)

// Outcomes a person invite can reach. They are written once and never
// revisited: a recorded outcome is what makes presenting the same link again
// safe, and re-deriving one from the state of the store is the mistake feature
// 031 spent a phase removing and feature 032 wrote into the contract.
const (
	OutcomeApproved = "approved"
	OutcomeDeclined = "declined"
	OutcomeExpired  = "expired"
)

var (
	// ErrNotOwner is "you are not the owner of this machine". Deliberately not
	// ErrTokenInvalid: the person's next action differs completely - there is
	// nothing wrong with their link, their network or their app, and repeating
	// will not help.
	ErrNotOwner = errors.New("not the server owner")
	// ErrPairDeclined is "the owner said no". Terminal: do not insist.
	ErrPairDeclined = errors.New("the owner declined the invite")
	// ErrPairTimeout is "the owner did not answer in time". Separated from the
	// above because it means the opposite thing about what to do next: ask
	// again.
	ErrPairTimeout = errors.New("the owner did not answer the invite")
	// ErrRequestNotFound covers "no such request" and "already decided". One
	// answer, because a request that has been settled is no longer a request.
	ErrRequestNotFound = errors.New("no such pairing request")
)

// PendingRequest is a person invite that has been presented and is waiting for
// the owner. AwaitingDevice never leaves the server: it is how the waiting
// connection is found again, not something the owner is told.
type PendingRequest struct {
	RequestID      string
	InvitedAt      int64
	ExpiresAt      int64
	AwaitingDevice string
}

// ConfirmOutcome is what the owner's decision produced. Identity is filled
// only when the answer was yes.
type ConfirmOutcome struct {
	Outcome  string
	Identity Identity
}

// randomRequestID names a waiting request on the wire.
//
// Random rather than derived from the token, and separate from it: the token
// is a credential that already lives in somebody else's chat history, and the
// confirming device names a request rather than presenting a right. Sending
// the token to the owner's devices would widen where a credential can be
// logged, cached or screenshotted for exactly no benefit.
func randomRequestID() string {
	var buf [8]byte
	if _, err := rand.Read(buf[:]); err != nil {
		// crypto/rand failing means the platform RNG is broken; treat as fatal,
		// the same way randomID does.
		panic(fmt.Sprintf("crypto/rand: %v", err))
	}
	return "r_" + hex.EncodeToString(buf[:])
}

// recordPendingRequest turns a freshly burned person invite into a question
// for the owner, inside the caller's transaction.
//
// The presenting device is NOT written to a column of its own: it is used_by,
// which burnToken has already set and which already means exactly this. A
// second copy of one fact is what phase 033 spent itself deleting.
func recordPendingRequest(ctx context.Context, tx *sql.Tx, token, platform string, now int64) (PendingRequest, error) {
	req := PendingRequest{RequestID: randomRequestID(), ExpiresAt: now + ApprovalWindowSeconds}
	err := tx.QueryRowContext(ctx,
		`UPDATE pair_tokens SET request_id = ?, awaiting_platform = ?, awaiting_until = ?
		 WHERE token = ? RETURNING created_at`,
		req.RequestID, platform, req.ExpiresAt, token).Scan(&req.InvitedAt)
	if err != nil {
		return PendingRequest{}, fmt.Errorf("record pairing request: %w", err)
	}
	return req, nil
}

// ConfirmPair records the owner's decision about one waiting request.
//
// Everything happens in ONE transaction: reading the request, creating the
// person, writing the device row and recording the outcome. A crash between
// any two of those would leave a request that says "approved" with nobody to
// show for it, or a person nobody can sign in as.
func (s *Store) ConfirmPair(ctx context.Context, requestID, callerUserID string, approve bool, now int64) (ConfirmOutcome, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return ConfirmOutcome{}, fmt.Errorf("begin confirm: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// The right is checked against the CURRENT owner, not against whoever
	// issued the invite. They are the same person today - ownership does not
	// move - but the question being answered is "may this caller decide who
	// lives on this machine", and that is about the machine.
	owns, err := ownsServer(ctx, tx, callerUserID)
	if err != nil {
		return ConfirmOutcome{}, err
	}
	if !owns {
		return ConfirmOutcome{}, ErrNotOwner
	}

	var token, deviceKey, platform string
	var awaitingUntil sql.NullInt64
	var outcome sql.NullString
	err = tx.QueryRowContext(ctx,
		`SELECT token, COALESCE(used_by, ''), COALESCE(awaiting_platform, ''), awaiting_until, outcome
		 FROM pair_tokens WHERE request_id = ? AND kind = ?`, requestID, TokenInviteUser).
		Scan(&token, &deviceKey, &platform, &awaitingUntil, &outcome)
	if errors.Is(err, sql.ErrNoRows) {
		return ConfirmOutcome{}, ErrRequestNotFound
	}
	if err != nil {
		return ConfirmOutcome{}, fmt.Errorf("read pairing request: %w", err)
	}
	// Already settled. A decided request is no longer a request, and the second
	// answer must not overwrite the first: the person on the other side has
	// already been told what the first one was.
	if outcome.Valid {
		return ConfirmOutcome{}, ErrRequestNotFound
	}
	if !awaitingUntil.Valid || awaitingUntil.Int64 <= now {
		// The decision arrived too late. Record it as expired rather than
		// leaving it open: the waiting device has already been told, or is
		// about to be, and a request that outlives its own deadline would be
		// answerable forever.
		if err := setOutcome(ctx, tx, token, OutcomeExpired); err != nil {
			return ConfirmOutcome{}, err
		}
		if err := tx.Commit(); err != nil {
			return ConfirmOutcome{}, fmt.Errorf("commit late confirm: %w", err)
		}
		return ConfirmOutcome{}, ErrPairTimeout
	}

	if !approve {
		if err := setOutcome(ctx, tx, token, OutcomeDeclined); err != nil {
			return ConfirmOutcome{}, err
		}
		if err := tx.Commit(); err != nil {
			return ConfirmOutcome{}, fmt.Errorf("commit decline: %w", err)
		}
		return ConfirmOutcome{Outcome: OutcomeDeclined}, nil
	}

	// Re-checked, not assumed: the key was unbound when the link was presented,
	// and the wait is long enough for that to have changed. insertDevice keeps
	// the existing owner on conflict, so approving here would answer with a
	// person the device row does not name - the exact mismatch the takeover
	// refusal exists to prevent.
	//
	// Nothing is recorded and the transaction rolls back: the request stays
	// open and expires on its own. Writing "declined" would tell the person at
	// the door that the owner said no, which is not what happened.
	bound, err := deviceOwnerOf(ctx, tx, deviceKey)
	if err != nil {
		return ConfirmOutcome{}, err
	}
	if bound != "" {
		return ConfirmOutcome{}, ErrTokenInvalid
	}

	id, err := insertUser(ctx, tx, "", now)
	if err != nil {
		return ConfirmOutcome{}, err
	}
	// A person invite always brings somebody into being, so the naming step is
	// always ahead of them.
	id.Created = true
	// And it never grants ownership. Not read back to prove it: ownership is
	// written only in the claim branch of Pair, and this person was created
	// three lines ago.
	id.Owner = false

	if err := insertDevice(ctx, tx, deviceKey, id.UserID, platform, now); err != nil {
		return ConfirmOutcome{}, err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE pair_tokens SET outcome = ?, paired_user_id = ?, created_person = 1 WHERE token = ?`,
		OutcomeApproved, id.UserID, token); err != nil {
		return ConfirmOutcome{}, fmt.Errorf("record approval: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return ConfirmOutcome{}, fmt.Errorf("commit approval: %w", err)
	}
	return ConfirmOutcome{Outcome: OutcomeApproved, Identity: id}, nil
}

func setOutcome(ctx context.Context, tx *sql.Tx, token, outcome string) error {
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET outcome = ? WHERE token = ?", outcome, token); err != nil {
		return fmt.Errorf("record outcome: %w", err)
	}
	return nil
}

// PendingRequests lists the questions still waiting for the owner.
//
// Read on every greeting of the owner, so a device that was switched off - or a
// server that was restarted - still learns about a request that is waiting.
// Without it the question is only ever seen by whoever happened to be online in
// the right second, and a five-minute wait would almost always expire for
// nothing.
func (s *Store) PendingRequests(ctx context.Context, now int64) ([]PendingRequest, error) {
	rows, err := s.read.QueryContext(ctx,
		`SELECT request_id, created_at, awaiting_until, COALESCE(used_by, '')
		 FROM pair_tokens
		 WHERE outcome IS NULL AND awaiting_until IS NOT NULL AND awaiting_until > ?
		 ORDER BY awaiting_until`, now)
	if err != nil {
		return nil, fmt.Errorf("list pending requests: %w", err)
	}
	defer func() { _ = rows.Close() }()
	return scanPending(rows)
}

// ExpirePendingPairs settles every request whose deadline has passed and
// reports what it settled, so the caller can tell both sides.
//
// The predicate needs all three conditions. `outcome IS NULL` alone is true of
// every claim token and every device invite as well - they have no outcome and
// never will - so `awaiting_until IS NOT NULL` is what actually means "waiting
// for a human".
func (s *Store) ExpirePendingPairs(ctx context.Context, now int64) ([]PendingRequest, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin expire: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	rows, err := tx.QueryContext(ctx,
		`SELECT request_id, created_at, awaiting_until, COALESCE(used_by, '')
		 FROM pair_tokens
		 WHERE outcome IS NULL AND awaiting_until IS NOT NULL AND awaiting_until <= ?`, now)
	if err != nil {
		return nil, fmt.Errorf("select expired requests: %w", err)
	}
	expired, err := scanPending(rows)
	_ = rows.Close()
	if err != nil {
		return nil, err
	}
	if len(expired) == 0 {
		return nil, nil
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE pair_tokens SET outcome = ?
		 WHERE outcome IS NULL AND awaiting_until IS NOT NULL AND awaiting_until <= ?`,
		OutcomeExpired, now); err != nil {
		return nil, fmt.Errorf("expire pending requests: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit expire: %w", err)
	}
	return expired, nil
}

func scanPending(rows *sql.Rows) ([]PendingRequest, error) {
	var out []PendingRequest
	for rows.Next() {
		var req PendingRequest
		if err := rows.Scan(&req.RequestID, &req.InvitedAt, &req.ExpiresAt, &req.AwaitingDevice); err != nil {
			return nil, fmt.Errorf("scan pending request: %w", err)
		}
		out = append(out, req)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate pending requests: %w", err)
	}
	return out, nil
}

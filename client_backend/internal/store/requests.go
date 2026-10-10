package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// Requests to join through an invite (046, contract §8A).
//
// An invite pairs nothing by itself. The device that presents it opens a
// request, and the device that issued the invite answers it - Allow or Deny -
// while the request waits; the new device may cancel it, and ten minutes after
// the invite was issued the server closes it on its own. A request is closed
// exactly once, and closing it spends the invite whatever the outcome.
//
// Like identity resolution, none of this writes an events row: who may join
// the machine is not the shared world the journal records, and the events that
// carry it (pair.resolved, device.pairRequested, device.pairResolved) are
// off-journal by construction.

// Outcomes of a request. Empty means it is still waiting.
const (
	OutcomeAllowed   = "allowed"
	OutcomeDenied    = "denied"
	OutcomeExpired   = "expired"
	OutcomeCancelled = "cancelled"
)

// ErrRequestNotFound covers "no such request", "not addressed to this device"
// and "no longer waiting". One answer on purpose: a device learns nothing about
// requests that are not its own, and an Allow pressed after the request closed
// does nothing at all.
var ErrRequestNotFound = errors.New("pairing request not found")

// PairRequest is one request as the server tells devices about it.
//
// The token it was opened with is deliberately unexported: it is a credential,
// and nothing outside the store has a reason to hold it - an event built from
// this struct cannot carry what it cannot reach.
type PairRequest struct {
	RequestID string
	// DeviceKey is the new device's key, the one its channel proved. The server
	// finds the connections waiting for the answer by it; it never travels.
	DeviceKey string
	// Platform is the new device's OS family - all the issuer is shown.
	Platform string
	// IssuerKey is the device that issued the invite and is asked to answer.
	IssuerKey string
	ExpiresAt int64
	// Outcome is one of the Outcome* constants, empty while waiting.
	Outcome string

	token string
}

const requestColumns = "request_id, token, device_key, platform, issuer_key, expires_at, outcome"

func scanRequest(row rowScanner) (PairRequest, error) {
	var r PairRequest
	var outcome sql.NullString
	if err := row.Scan(&r.RequestID, &r.token, &r.DeviceKey, &r.Platform, &r.IssuerKey, &r.ExpiresAt, &outcome); err != nil {
		return PairRequest{}, err
	}
	r.Outcome = outcome.String
	return r, nil
}

func requestBy(ctx context.Context, tx *sql.Tx, column, value string) (PairRequest, bool, error) {
	// column is one of the two literals below, never input.
	r, err := scanRequest(tx.QueryRowContext(ctx, "SELECT "+requestColumns+" FROM pair_requests WHERE "+column+" = ?", value))
	if errors.Is(err, sql.ErrNoRows) {
		return PairRequest{}, false, nil
	}
	if err != nil {
		return PairRequest{}, false, fmt.Errorf("read pairing request: %w", err)
	}
	return r, true, nil
}

func requestByToken(ctx context.Context, tx *sql.Tx, token string) (PairRequest, bool, error) {
	return requestBy(ctx, tx, "token", token)
}

func requestByID(ctx context.Context, tx *sql.Tx, requestID string) (PairRequest, bool, error) {
	return requestBy(ctx, tx, "request_id", requestID)
}

// requestByInvite is Pair for an invite: open the request, or find the one
// this key opened before.
func requestByInvite(ctx context.Context, tx *sql.Tx, pt pairToken, deviceKey, platform string, now int64) (PairResult, error) {
	r, found, err := requestByToken(ctx, tx, pt.token)
	if err != nil {
		return PairResult{}, err
	}
	if found {
		return repeatRequest(ctx, tx, r, pt, deviceKey, now)
	}
	if pt.used {
		// Voided before anybody presented it: its issuer was revoked.
		return PairResult{}, ErrTokenInvalid
	}
	if pt.expiresAt <= now {
		return PairResult{}, ErrTokenExpired
	}
	// The issuer has to be there to be asked. Revoking it voids this token in
	// the same transaction, so an issuer missing behind an unspent token is a
	// store edited by hand - refused the same way, rather than opening a request
	// nobody can ever answer.
	issuerOwner, err := deviceOwnerOf(ctx, tx, pt.issuerKey)
	if err != nil {
		return PairResult{}, err
	}
	if issuerOwner == "" {
		return PairResult{}, ErrTokenInvalid
	}
	// A key that belongs to somebody else does not get as far as a request; the
	// same rule bindDevice applies once Allow is pressed, asked early so the
	// issuer is never shown a request that cannot be allowed.
	bound, err := deviceOwnerOf(ctx, tx, deviceKey)
	if err != nil {
		return PairResult{}, err
	}
	if bound != "" && bound != pt.userID {
		return PairResult{}, ErrTokenInvalid
	}
	// The deadline is the invite's own: the request does not buy the new
	// device more time than the link it scanned had left.
	r = PairRequest{
		RequestID: "r_" + randomID(),
		DeviceKey: deviceKey,
		Platform:  platform,
		IssuerKey: pt.issuerKey,
		ExpiresAt: pt.expiresAt,
		token:     pt.token,
	}
	// token is UNIQUE, so a second request for one invite cannot come into
	// being even if the read above ever stops being inside this transaction.
	if _, err := tx.ExecContext(ctx,
		"INSERT INTO pair_requests (request_id, token, device_key, platform, issuer_key, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
		r.RequestID, r.token, r.DeviceKey, r.Platform, r.IssuerKey, r.ExpiresAt); err != nil {
		return PairResult{}, fmt.Errorf("open pairing request: %w", err)
	}
	return PairResult{Request: &r, Opened: true}, nil
}

// repeatRequest answers a presentation of an invite whose request exists.
//
// The device that opened it gets the same request back - still waiting, or the
// outcome recorded for it - which is how it survives a dropped connection and
// a restart inside the ten minutes (FR-011). The event that carries the outcome
// does not survive a disconnect; this does.
func repeatRequest(ctx context.Context, tx *sql.Tx, r PairRequest, pt pairToken, deviceKey string, now int64) (PairResult, error) {
	// One request per invite, and it belongs to the key that opened it: a
	// second device presenting the same QR code is told it was already used.
	if r.DeviceKey != deviceKey {
		return PairResult{}, ErrTokenInvalid
	}
	switch r.Outcome {
	case "":
		if r.ExpiresAt > now {
			return PairResult{Request: &r}, nil
		}
		// Its time ran out before the sweep got to it. Closed here, so the
		// answer is the truth rather than a "still waiting" nobody can end.
		if err := closeRequest(ctx, tx, &r, OutcomeExpired, now); err != nil {
			return PairResult{}, err
		}
		return PairResult{Request: &r, Closed: true}, nil
	case OutcomeAllowed:
		// Allowed means paired: the answer is the identity, exactly as for a
		// machine link, and only while the device still belongs to the person
		// the request produced.
		id, paired, err := pairedBy(ctx, tx, pt.token, deviceKey)
		if err != nil {
			return PairResult{}, err
		}
		if !paired {
			return PairResult{}, ErrTokenInvalid
		}
		return PairResult{Paired: true, Identity: id, Request: &r}, nil
	default:
		return PairResult{Request: &r}, nil
	}
}

// closeRequest closes a waiting request with outcome and spends its token, in
// the caller's transaction.
//
// Conditional on the request still waiting: a request is closed once, by
// whichever of the five ways got there first, and the loser is told it was not
// found. The token is spent by the device that held the request whatever the
// outcome - a denied, expired or cancelled invite cannot be presented again -
// unless it is spent already; only an allowed request ever names a person
// (recordOutcome), so only its repeat finds anybody.
func closeRequest(ctx context.Context, tx *sql.Tx, r *PairRequest, outcome string, now int64) error {
	res, err := tx.ExecContext(ctx,
		"UPDATE pair_requests SET outcome = ?, decided_at = ? WHERE request_id = ? AND outcome IS NULL",
		outcome, now, r.RequestID)
	if err != nil {
		return fmt.Errorf("close pairing request: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("close pairing request rows: %w", err)
	}
	if affected == 0 {
		return ErrRequestNotFound
	}
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = ?, used_by = ? WHERE token = ? AND used_at IS NULL",
		now, r.DeviceKey, r.token); err != nil {
		return fmt.Errorf("spend the request's invite: %w", err)
	}
	r.Outcome = outcome
	return nil
}

// Decision is what answering a request did.
type Decision struct {
	// Request is the request, closed.
	Request PairRequest
	// Identity is who the new device now speaks as. Set only when allowed.
	Identity Identity
}

// DecidePairRequest is device.approve: the issuing device's answer.
//
// Allow writes the device, spends the token and closes the request in ONE
// transaction (FR-009): a crash between them would either pair a device whose
// request still waits, or close a request whose device was never written.
// Deny closes the request and spends the token.
//
// Refused with ErrDeviceUnknown when the answering device is no longer paired,
// and with ErrRequestNotFound when the request is not there, is addressed to
// another device, or is no longer waiting - including one whose time ran out a
// moment ago and that the sweep has not closed yet: Allow pressed after the
// deadline does nothing.
func (s *Store) DecidePairRequest(ctx context.Context, requestID, issuerKey string, allow bool, now int64) (Decision, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return Decision{}, fmt.Errorf("begin decide pairing request: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// The answering device first. One revoked while its answer was on the way
	// is told so, in the order the single writer put the two in - the rule
	// IssueDeviceInvite follows for the same reason.
	person, err := deviceOwnerOf(ctx, tx, issuerKey)
	if err != nil {
		return Decision{}, err
	}
	if person == "" {
		return Decision{}, ErrDeviceUnknown
	}
	r, found, err := requestByID(ctx, tx, requestID)
	if err != nil {
		return Decision{}, err
	}
	if !found || r.IssuerKey != issuerKey || r.Outcome != "" || r.ExpiresAt <= now {
		return Decision{}, ErrRequestNotFound
	}

	if !allow {
		if err := closeRequest(ctx, tx, &r, OutcomeDenied, now); err != nil {
			return Decision{}, err
		}
		if err := tx.Commit(); err != nil {
			return Decision{}, fmt.Errorf("commit deny pairing request: %w", err)
		}
		return Decision{Request: r}, nil
	}

	// Spent first, and strictly: the token must still be the request's to
	// spend. closeRequest below then finds it spent and leaves it.
	if err := spendToken(ctx, tx, r.token, r.DeviceKey, now); err != nil {
		if errors.Is(err, ErrTokenInvalid) {
			return Decision{}, ErrRequestNotFound
		}
		return Decision{}, err
	}
	if err := closeRequest(ctx, tx, &r, OutcomeAllowed, now); err != nil {
		return Decision{}, err
	}
	var id Identity
	if err := tx.QueryRowContext(ctx,
		"SELECT user_id, label FROM users WHERE user_id = ?", person).Scan(&id.UserID, &id.Label); err != nil {
		return Decision{}, fmt.Errorf("read the person allowing a device: %w", err)
	}
	// The device joins the person the ANSWERING device belongs to - with one
	// person on the machine, the person the invite was issued for. Not Created:
	// the person existed, and has a name.
	if err := bindDevice(ctx, tx, r.DeviceKey, id.UserID, r.Platform, now); err != nil {
		if errors.Is(err, ErrTokenInvalid) {
			// The new key belongs to somebody else. Unreachable with one person,
			// refused loudly rather than turned into an answer: nothing is
			// written, and the request keeps waiting until its time runs out.
			return Decision{}, errors.New("the requesting device key is paired to another person")
		}
		return Decision{}, err
	}
	if err := recordOutcome(ctx, tx, r.token, id); err != nil {
		return Decision{}, err
	}
	if err := tx.Commit(); err != nil {
		return Decision{}, fmt.Errorf("commit allow pairing request: %w", err)
	}
	return Decision{Request: r, Identity: id}, nil
}

// CancelPairRequest is pair.cancel: the new device withdraws the request it
// opened with token. found is false when there is nothing waiting for this key
// under this token - never opened, another key's, or closed already - and that
// is not an error: the state the device asked for already holds, so pair.cancel
// answers the same either way.
//
// A request whose time ran out before the cancel arrived is closed as expired,
// not cancelled: the outcome says what happened, and the issuer's dialog was
// due to close anyway.
func (s *Store) CancelPairRequest(ctx context.Context, token, deviceKey string, now int64) (PairRequest, bool, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return PairRequest{}, false, fmt.Errorf("begin cancel pairing request: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	r, found, err := requestByToken(ctx, tx, token)
	if err != nil {
		return PairRequest{}, false, err
	}
	if !found || r.DeviceKey != deviceKey || r.Outcome != "" {
		return PairRequest{}, false, nil
	}
	outcome := OutcomeCancelled
	if r.ExpiresAt <= now {
		outcome = OutcomeExpired
	}
	if err := closeRequest(ctx, tx, &r, outcome, now); err != nil {
		return PairRequest{}, false, err
	}
	if err := tx.Commit(); err != nil {
		return PairRequest{}, false, fmt.Errorf("commit cancel pairing request: %w", err)
	}
	return r, true, nil
}

// PairRequestOutcome reads how the request with requestID stands: its outcome,
// or "" while it still waits. ErrRequestNotFound when there is no such request.
//
// The server asks it after a connection's wait on the request took hold (046),
// to catch a close that landed in between with nobody waiting on it yet - so
// it reads the latest committed state, on the read pool, and nothing else.
func (s *Store) PairRequestOutcome(ctx context.Context, requestID string) (string, error) {
	var outcome sql.NullString
	err := s.read.QueryRowContext(ctx, "SELECT outcome FROM pair_requests WHERE request_id = ?", requestID).Scan(&outcome)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrRequestNotFound
	}
	if err != nil {
		return "", fmt.Errorf("read pairing request outcome: %w", err)
	}
	return outcome.String, nil
}

// WaitingPairRequests lists the requests waiting for issuerKey's answer whose
// time has not run out, soonest deadline first. A greeting re-sends them all:
// the event that first announced each does not survive a disconnect.
func (s *Store) WaitingPairRequests(ctx context.Context, issuerKey string, now int64) ([]PairRequest, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT "+requestColumns+" FROM pair_requests WHERE issuer_key = ? AND outcome IS NULL AND expires_at > ? ORDER BY expires_at, request_id",
		issuerKey, now)
	if err != nil {
		return nil, fmt.Errorf("list waiting pairing requests: %w", err)
	}
	return collectRequests(rows)
}

// ExpirePairRequests closes, as expired, every waiting request whose time ran
// out by now, and returns them so both sides can be told. The sweep calls it
// every few seconds, and nobody has to act for a request to end (FR-007).
//
// Asked on the read pool first, and the writer is taken only when something is
// due: the sweep runs whether or not anybody is pairing, and a write
// transaction every few seconds would queue every command behind it for
// nothing.
func (s *Store) ExpirePairRequests(ctx context.Context, now int64) ([]PairRequest, error) {
	var due int
	if err := s.read.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM pair_requests WHERE outcome IS NULL AND expires_at <= ?", now).Scan(&due); err != nil {
		return nil, fmt.Errorf("count expired pairing requests: %w", err)
	}
	if due == 0 {
		return nil, nil
	}

	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin expire pairing requests: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	rows, err := tx.QueryContext(ctx,
		"SELECT "+requestColumns+" FROM pair_requests WHERE outcome IS NULL AND expires_at <= ? ORDER BY expires_at, request_id", now)
	if err != nil {
		return nil, fmt.Errorf("list expired pairing requests: %w", err)
	}
	expired, err := collectRequests(rows)
	if err != nil {
		return nil, err
	}
	for i := range expired {
		if err := closeRequest(ctx, tx, &expired[i], OutcomeExpired, now); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit expire pairing requests: %w", err)
	}
	return expired, nil
}

// closeRequestsOf closes every waiting request the device with deviceKey takes
// part in - as the one asked to answer it, or as the one asking to join -
// denied, or expired when its time had already run out. Called from
// RevokeDevice, in its transaction.
//
// As the issuer: a revoked device can answer nothing, and a request left
// waiting for it would hold the new device at its screen for the rest of the
// ten minutes. As the one asking: a device the person has just revoked must
// not come back through an Allow pressed on a request it opened before.
func closeRequestsOf(ctx context.Context, tx *sql.Tx, deviceKey string, now int64) ([]PairRequest, error) {
	rows, err := tx.QueryContext(ctx,
		"SELECT "+requestColumns+" FROM pair_requests WHERE (issuer_key = ? OR device_key = ?) AND outcome IS NULL ORDER BY expires_at, request_id",
		deviceKey, deviceKey)
	if err != nil {
		return nil, fmt.Errorf("list the revoked device's requests: %w", err)
	}
	waiting, err := collectRequests(rows)
	if err != nil {
		return nil, err
	}
	for i := range waiting {
		outcome := OutcomeDenied
		if waiting[i].ExpiresAt <= now {
			outcome = OutcomeExpired
		}
		if err := closeRequest(ctx, tx, &waiting[i], outcome, now); err != nil {
			return nil, err
		}
	}
	return waiting, nil
}

// collectRequests drains rows into requests and closes them - before the
// caller writes anything on the same transaction.
func collectRequests(rows *sql.Rows) ([]PairRequest, error) {
	defer func() { _ = rows.Close() }()
	var out []PairRequest
	for rows.Next() {
		r, err := scanRequest(rows)
		if err != nil {
			return nil, fmt.Errorf("scan pairing request: %w", err)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate pairing requests: %w", err)
	}
	return out, nil
}

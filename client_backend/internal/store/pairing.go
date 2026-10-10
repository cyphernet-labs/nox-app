package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
)

// Token kinds (046). The kind is the server's own knowledge: it never travels
// in the link, so a presenter cannot tell a machine link from a device invite -
// and does not need to, because the server looks the token up by value.
const (
	// TokenMachine is the machine link, issued on the service page or by
	// `noxd link`. It pairs a device at once: it creates the person when there
	// is nobody and joins them when there is.
	TokenMachine = "machine"
	// TokenInviteDevice is an invite issued by a paired device. Presenting it
	// opens a request that pairs nothing until the issuing device allows it.
	TokenInviteDevice = "invite_device"
)

// TokenTTLSeconds is how long both kinds of token stay usable. Ten minutes is
// long enough to carry a phone into the next room and short enough that a
// screenshot of the QR code stops working - which matters more since a device
// can pair through the onion service from anywhere. Nobody is locked out by
// the deadline: the machine link can always be issued again on the machine.
const TokenTTLSeconds int64 = 600

// Errors a caller maps onto the wire codes of contract §8A.
var (
	// ErrTokenInvalid covers "no such token", "already spent", "spent by
	// another key", "its request is another key's" and "the key belongs to
	// somebody else". They are one answer on the wire on purpose: telling them
	// apart would say whether a guessed token exists.
	ErrTokenInvalid = errors.New("pairing token invalid")
	// ErrTokenExpired is a real token presented after its deadline. Separated
	// from the above because the person's next action differs: get a new link
	// rather than wonder whether they mistyped.
	ErrTokenExpired = errors.New("pairing token expired")
)

// MachineLink is the token of a machine link and the moment it runs out. The
// link a person carries is built from it by the server, which alone knows the
// addresses to put in it.
type MachineLink struct {
	Token     string
	ExpiresAt int64
}

// Live reports whether the link can still be presented at now. The boundary is
// the one Pair applies: a link presented at its expiry second is already late.
func (l MachineLink) Live(now int64) bool {
	return now < l.ExpiresAt
}

// IssueMachineLink mints the machine link and spends every earlier unspent one
// in the same transaction, so at most one is ever live: whatever the page
// showed a moment ago, or `noxd link` printed, stops working the moment a new
// one exists (SC-004).
func (s *Store) IssueMachineLink(ctx context.Context, now int64) (MachineLink, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return MachineLink{}, fmt.Errorf("begin issue machine link: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	link, err := insertMachineLink(ctx, tx, now)
	if err != nil {
		return MachineLink{}, err
	}
	if err := tx.Commit(); err != nil {
		return MachineLink{}, fmt.Errorf("commit issue machine link: %w", err)
	}
	return link, nil
}

// insertMachineLink voids every unspent machine link and writes a new one, in
// the caller's transaction - the only way a machine link comes into being, so
// "one live link" cannot depend on a caller remembering the first statement.
func insertMachineLink(ctx context.Context, tx *sql.Tx, now int64) (MachineLink, error) {
	token, err := newTokenValue()
	if err != nil {
		return MachineLink{}, err
	}
	// Voided the way spending marks a token, through used_at: a voided link and
	// a spent one answer the same invalid_token, and neither may come back.
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = ? WHERE kind = ? AND used_at IS NULL", now, TokenMachine); err != nil {
		return MachineLink{}, fmt.Errorf("void earlier machine links: %w", err)
	}
	link := MachineLink{Token: token, ExpiresAt: now + TokenTTLSeconds}
	if _, err := tx.ExecContext(ctx,
		"INSERT INTO pair_tokens (token, kind, created_at, expires_at) VALUES (?, ?, ?, ?)",
		link.Token, TokenMachine, now, link.ExpiresAt); err != nil {
		return MachineLink{}, fmt.Errorf("insert machine link: %w", err)
	}
	return link, nil
}

// PageLink is what the service page knows about pairing, read at one moment.
type PageLink struct {
	// Devices is how many devices can reach the machine.
	Devices int
	// Link is the machine link to show, when Found.
	Link  MachineLink
	Found bool
}

// PageMachineLink is the machine link the service page shows: the unspent one,
// live or already run out - there is at most one - and, when the machine has no
// device and no unspent link at all, a new one minted first. Found is false
// when there is nothing to show: devices exist and nobody has asked for a link,
// so the page offers `Add a device` instead.
//
// The minting happens once for every stretch of time nobody can reach the
// machine. The link it mints stays unspent - live, then run out - until
// somebody pairs with it or asks for another, so reloading the page never mints
// again and a link that ran out is never replaced behind anybody's back: the
// page says `Link expired` and waits for `New link`. A link spent by a pairing
// is gone, and if every device is later lost the page mints afresh;
// RevokeDevice voids one that ran out unused for the same reason.
//
// The device count is read in the same transaction as the link: whether the
// page leads with a link and which one it shows are one fact.
func (s *Store) PageMachineLink(ctx context.Context, now int64) (PageLink, error) {
	// Read first, on the read pool: the page is opened far more often than a
	// link needs minting, and only minting needs the writer.
	read, err := s.read.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return PageLink{}, fmt.Errorf("begin read machine link: %w", err)
	}
	page, err := pageLinkState(ctx, read)
	_ = read.Rollback()
	if err != nil || page.Found || page.Devices > 0 {
		return page, err
	}

	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return PageLink{}, fmt.Errorf("begin mint machine link: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	// Asked again inside the write transaction: two page loads racing here must
	// not mint two links, the second voiding the one the first is showing.
	page, err = pageLinkState(ctx, tx)
	if err != nil {
		return PageLink{}, err
	}
	if !page.Found && page.Devices == 0 {
		if page.Link, err = insertMachineLink(ctx, tx, now); err != nil {
			return PageLink{}, err
		}
		page.Found = true
	}
	if err := tx.Commit(); err != nil {
		return PageLink{}, fmt.Errorf("commit mint machine link: %w", err)
	}
	return page, nil
}

// pageLinkState reads the unspent machine link and the device count in one
// transaction, so the page never decides on a link and a count from two
// different moments.
func pageLinkState(ctx context.Context, tx *sql.Tx) (PageLink, error) {
	devices, err := countDevices(ctx, tx)
	if err != nil {
		return PageLink{}, err
	}
	page := PageLink{Devices: devices}
	err = tx.QueryRowContext(ctx,
		"SELECT token, expires_at FROM pair_tokens WHERE kind = ? AND used_at IS NULL ORDER BY created_at DESC, rowid DESC LIMIT 1",
		TokenMachine).Scan(&page.Link.Token, &page.Link.ExpiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		return page, nil
	}
	if err != nil {
		return PageLink{}, fmt.Errorf("read machine link: %w", err)
	}
	page.Found = true
	return page, nil
}

// IssueDeviceInvite mints a token for a new device of the person whose device -
// issuer - asks for it. The token remembers its issuer: that device, and only
// that one, is asked to allow whoever presents it.
//
// The person and the issuer are read from the ISSUER's row by the very
// statement that writes the token, and a device that is no longer there gets
// ErrDeviceUnknown. A device revoked from another one may still have a command
// on the way; the single writer puts that command and the revocation in one
// order, and only this way does the order decide. Checked any earlier, the
// revocation could land in between, and its voiding of the device's invites
// would miss the one minted after it - a door opened by a device that had just
// been told to leave.
func (s *Store) IssueDeviceInvite(ctx context.Context, issuer string, now int64) (string, error) {
	token, err := newTokenValue()
	if err != nil {
		return "", err
	}
	res, err := s.write.ExecContext(ctx,
		`INSERT INTO pair_tokens (token, kind, user_id, issuer_key, created_at, expires_at)
		 SELECT ?, ?, user_id, device_key, ?, ? FROM devices WHERE device_key = ?`,
		token, TokenInviteDevice, now, now+TokenTTLSeconds, issuer)
	if err != nil {
		return "", fmt.Errorf("insert invite: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return "", fmt.Errorf("insert invite: %w", err)
	}
	if n == 0 {
		return "", ErrDeviceUnknown
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

// pairToken is one pair_tokens row as Pair needs it. Never logged and never
// handed out of this package: the value is a credential.
type pairToken struct {
	token     string
	kind      string
	userID    string
	issuerKey string
	expiresAt int64
	used      bool
}

func readToken(ctx context.Context, tx *sql.Tx, token string) (pairToken, error) {
	pt := pairToken{token: token}
	var userID, issuerKey sql.NullString
	var usedAt sql.NullInt64
	err := tx.QueryRowContext(ctx,
		"SELECT kind, user_id, issuer_key, expires_at, used_at FROM pair_tokens WHERE token = ?", token).
		Scan(&pt.kind, &userID, &issuerKey, &pt.expiresAt, &usedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return pairToken{}, ErrTokenInvalid
	}
	if err != nil {
		return pairToken{}, fmt.Errorf("read pairing token: %w", err)
	}
	pt.userID, pt.issuerKey, pt.used = userID.String, issuerKey.String, usedAt.Valid
	return pt, nil
}

// PairResult is what presenting a token did.
type PairResult struct {
	// Paired says the device now speaks as Identity: a machine link, or an
	// invite whose request was already allowed - the repeat of an answer that
	// was lost on the way.
	Paired   bool
	Identity Identity
	// Request is the invite's request as it stands after the call, nil for a
	// machine link. It is waiting while its Outcome is empty.
	Request *PairRequest
	// Opened says THIS call opened the request, so the issuing device is to be
	// asked.
	Opened bool
	// Closed says THIS call closed it - it had run out before the sweep got to
	// it - so both sides are to be told.
	Closed bool
}

// Pair presents a token for the device key the connection proved.
//
// A machine link pairs at once, and everything happens in ONE transaction:
// spending the token, creating or finding the person, writing the device row
// and recording the outcome. A crash between any two of those would spend a
// token for nothing or authorise a key nobody can account for.
//
// An invite pairs nothing (046): it opens a request - or finds the one this
// key already opened - and the device row is written only when the issuing
// device allows it (DecidePairRequest). A leaked QR code is then worth nothing
// without a press of Allow on a device the person holds.
//
// Nothing here asks which path the connection came by (045). A pairing through
// the onion service is a pairing like any other: the connection from tor
// reaches the same port as one from the next room and is indistinguishable
// from it, and the token and the channel check are what decide.
func (s *Store) Pair(ctx context.Context, token, deviceKey, platform string, now int64) (PairResult, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return PairResult{}, fmt.Errorf("begin pair: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	pt, err := readToken(ctx, tx, token)
	if err != nil {
		return PairResult{}, err
	}
	var res PairResult
	switch pt.kind {
	case TokenMachine:
		res.Identity, err = pairByMachineLink(ctx, tx, pt, deviceKey, platform, now)
		res.Paired = err == nil
	case TokenInviteDevice:
		res, err = requestByInvite(ctx, tx, pt, deviceKey, platform, now)
	default:
		err = ErrTokenInvalid
	}
	if err != nil {
		// A refusal spends nothing: the rollback takes back whatever the branch
		// had written before it refused.
		return PairResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return PairResult{}, fmt.Errorf("commit pair: %w", err)
	}
	return res, nil
}

// pairByMachineLink pairs the device through the machine link: it creates the
// person when the machine holds nobody, and joins them otherwise (FR-004).
//
// There is no refusal for a machine that already has devices any more. The
// machine link is how a person who lost every device gets back in, and how one
// who still has some adds a device without one in hand; whoever can issue it
// already has the machine, and with it the database.
func pairByMachineLink(ctx context.Context, tx *sql.Tx, pt pairToken, deviceKey, platform string, now int64) (Identity, error) {
	// A token this very device already spent means its reply was lost, not that
	// somebody is replaying one. `pair` commits and THEN replies, so a dropped
	// connection in that window leaves the device paired and the client
	// believing nothing happened. Answering with the same identity is the
	// at-least-once story `message.send` gets from its idempotency key - and it
	// comes before the deadline, because the deadline was met by the spending.
	same, found, err := pairedBy(ctx, tx, pt.token, deviceKey)
	if err != nil {
		return Identity{}, err
	}
	if found {
		return same, nil
	}
	if pt.used {
		return Identity{}, ErrTokenInvalid
	}
	if pt.expiresAt <= now {
		return Identity{}, ErrTokenExpired
	}
	if err := spendToken(ctx, tx, pt.token, deviceKey, now); err != nil {
		return Identity{}, err
	}
	id, err := resolveSolePerson(ctx, tx, now)
	if err != nil {
		return Identity{}, err
	}
	if err := bindDevice(ctx, tx, deviceKey, id.UserID, platform, now); err != nil {
		return Identity{}, err
	}
	if err := recordOutcome(ctx, tx, pt.token, id); err != nil {
		return Identity{}, err
	}
	return id, nil
}

// spendToken marks a token used by deviceKey.
//
// Conditional on it being unspent, and the affected-row count decides a race:
// two presentations of one token both reach this statement, exactly one
// changes a row, and the other is told the token is invalid. Checking-then-
// updating would let both through.
func spendToken(ctx context.Context, tx *sql.Tx, token, deviceKey string, now int64) error {
	res, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET used_at = ?, used_by = ? WHERE token = ? AND used_at IS NULL", now, deviceKey, token)
	if err != nil {
		return fmt.Errorf("spend pairing token: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("spend pairing token rows: %w", err)
	}
	if affected == 0 {
		return ErrTokenInvalid
	}
	return nil
}

// bindDevice writes the device row for the person, refusing a key that
// already belongs to somebody else.
//
// The key is the one the connection PROVED in the channel check (044), so a
// caller cannot name a stranger's - but a device key is a public value
// (device.list prints it), and were one ever to arrive unproved, this is what
// stops the takeover: the device would keep working, resolve as the attacker
// on its next greeting, author every message as them, and vanish from its real
// owner's device list. Unreachable while the schema admits one person, and
// kept anyway: it is two lines on the path a key the server does not know
// walks, and it should hold the invariant rather than assume it.
//
// Re-pairing one's OWN key is an ordinary repeat and is accepted: the row is
// refreshed, never re-bound (insertDevice).
func bindDevice(ctx context.Context, tx *sql.Tx, deviceKey, userID, platform string, now int64) error {
	bound, err := deviceOwnerOf(ctx, tx, deviceKey)
	if err != nil {
		return err
	}
	if bound != "" && bound != userID {
		return ErrTokenInvalid
	}
	return insertDevice(ctx, tx, deviceKey, userID, platform, now)
}

// recordOutcome writes WHO a spent token produced and WHAT it did, so a
// replay can answer with those instead of re-deriving them. Both are only
// known once the person is resolved and the device written.
//
// The person matters as much as the outcome: re-deriving it from the device
// row answers about whoever holds that key at replay time, which after a
// logout and a re-pair is not who the token produced.
func recordOutcome(ctx context.Context, tx *sql.Tx, token string, id Identity) error {
	created := 0
	if id.Created {
		created = 1
	}
	if _, err := tx.ExecContext(ctx,
		"UPDATE pair_tokens SET paired_user_id = ?, created_person = ? WHERE token = ?",
		id.UserID, created, token); err != nil {
		return fmt.Errorf("record pairing outcome: %w", err)
	}
	return nil
}

// pairedBy reports the identity a spent token produced, but only when the SAME
// device key is asking. A different key presenting a used token is an ordinary
// replay and stays refused.
//
// It answers exactly what the lost reply said, including `created`. Returning
// false unconditionally would be a DIFFERENT answer from the one being
// replayed: a machine link that minted the person reported created, and a
// retry that says otherwise walks the person of a brand-new server straight
// past the naming step, into the chats list under an auto-assigned
// User<random>.
func pairedBy(ctx context.Context, tx *sql.Tx, token, deviceKey string) (Identity, bool, error) {
	var id Identity
	// The whole answer comes from the TOKEN's own record - who it produced and
	// what it did - and it is handed only to the device that spent it.
	//
	// Nothing is re-derived here on purpose. Matching through the device's
	// current binding answers about whoever holds that key now, which after a
	// logout and a re-pair is not the person the token produced; and deriving
	// the outcome from the token kind reports "created" for a pairing that
	// created nobody, walking a named person back through the naming screen.
	//
	// used_by is what keeps a spent token from answering a stranger: `pair` is
	// the one command a key the server does not know may send. The channel
	// proves that key is the caller's own (044) - not that it is the key that
	// spent the token. The device must STILL belong to the person the token
	// produced: without that join a key that has since been revoked and
	// re-paired would be handed the original person's id and label. A token
	// whose request was not allowed produced nobody (paired_user_id is NULL),
	// so it never answers here.
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
	return id, true, nil
}

// resolveSolePerson answers "whose device is this going to be" for a machine
// link: the one person the machine holds, or a new one when it holds nobody.
func resolveSolePerson(ctx context.Context, tx *sql.Tx, now int64) (Identity, error) {
	people, err := countPeople(ctx, tx)
	if err != nil {
		return Identity{}, err
	}
	switch people {
	case 1:
		// Not Created: this person existed before the link was presented, so
		// there is no naming step ahead of them - they have a name, and every
		// chat and message they had is theirs again (FR-004).
		return soleUser(ctx, tx)
	case 0:
		id, err := insertUser(ctx, tx, "", now)
		if err != nil {
			return Identity{}, err
		}
		id.Created = true
		return id, nil
	default:
		// More people than the singleton index admits, so the schema this store
		// carries is not the one this build wrote. Attaching to a row picked by
		// order would hand somebody else's history away. Refuse rather than
		// guess.
		return Identity{}, ErrTokenInvalid
	}
}

// soleUser reads the one person this server holds.
//
// Called only where countPeople has just reported exactly one - the caller
// refuses on any other count rather than trusting the schema.
func soleUser(ctx context.Context, tx *sql.Tx) (Identity, error) {
	var id Identity
	if err := tx.QueryRowContext(ctx,
		"SELECT user_id, label FROM users LIMIT 1").Scan(&id.UserID, &id.Label); err != nil {
		return Identity{}, fmt.Errorf("read sole person: %w", err)
	}
	return id, nil
}

// countPeople reports how many people this server holds.
func countPeople(ctx context.Context, q rowQuerier) (int, error) {
	var people int
	if err := q.QueryRowContext(ctx, "SELECT COUNT(1) FROM users").Scan(&people); err != nil {
		return 0, fmt.Errorf("count people: %w", err)
	}
	return people, nil
}

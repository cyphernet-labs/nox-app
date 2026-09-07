package server

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// challengePrefix separates domains: without it a signature taken over a
// challenge would be a valid signature over the same bytes anywhere else the
// protocol later decides to sign something. Sixteen bytes now is cheaper than
// proving the absence of an overlap later.
const challengePrefix = "nox/challenge/v1:"

// verifyChallenge reports whether sig is deviceKey's signature over the
// prefixed challenge. Every input arrives as base64 from an untrusted peer, so
// every decode failure is simply "does not verify" - there is nothing useful
// to tell the caller apart.
//
// The RAW challenge bytes are signed, not their base64 spelling: two
// implementations disagreeing about padding would disagree about the
// signature, and one of them would be locked out for reasons neither could see.
func verifyChallenge(deviceKey, challenge, sig string) bool {
	pub, err := base64.StdEncoding.DecodeString(deviceKey)
	if err != nil || len(pub) != ed25519.PublicKeySize {
		return false
	}
	raw, err := base64.StdEncoding.DecodeString(challenge)
	if err != nil {
		return false
	}
	signature, err := base64.StdEncoding.DecodeString(sig)
	if err != nil || len(signature) != ed25519.SignatureSize {
		return false
	}
	return ed25519.Verify(ed25519.PublicKey(pub), append([]byte(challengePrefix), raw...), signature)
}

type pairRequest struct {
	Token     string `json:"token"`
	DeviceKey string `json:"device_key"`
	Platform  string `json:"platform"`
}

// pairReply carries contract §8A's status: `paired` with an identity beside it,
// or `pending` when the answer belongs to the owner and has not been given.
//
// Status is written ALWAYS, without omitempty, for the reason `created` and
// `owner` are: a missing value reads as "not stated", not as a default. A
// client that saw no status on a pending reply would take the absent identity
// for a failure and send the person back to the pairing screen while the owner
// is still being asked.
type pairReply struct {
	Status    string    `json:"status"`
	Identity  *identity `json:"identity,omitempty"`
	RequestID string    `json:"request_id,omitempty"`
	ExpiresAt int64     `json:"expires_at,omitempty"`
}

const (
	pairStatusPaired  = "paired"
	pairStatusPending = "pending"
)

// handlePair is the only command accepted before the greeting: an unpaired
// device has nothing to sign the challenge with, so requiring hello first
// would make pairing impossible rather than merely awkward.
func (c *client) handlePair(cmd protocol.Command) {
	if c.helloDone {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "already greeted"))
		return
	}

	var req pairRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed pair data"))
		return
	}

	token := strings.TrimSpace(req.Token)
	deviceKey := strings.TrimSpace(req.DeviceKey)
	platform := strings.TrimSpace(req.Platform)
	if token == "" || deviceKey == "" || platform == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "token, device_key and platform are required"))
		return
	}
	if raw, err := base64.StdEncoding.DecodeString(deviceKey); err != nil || len(raw) != ed25519.PublicKeySize {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "device_key is not an Ed25519 public key"))
		return
	}

	res, err := c.srv.store.Pair(c.ctx, token, deviceKey, platform, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrTokenInvalid):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidToken, "pairing token is not usable"))
		return
	case errors.Is(err, store.ErrTokenExpired):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrTokenExpired, "pairing token has expired"))
		return
	case errors.Is(err, store.ErrPairDeclined):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrPairDeclined, "the owner declined this invite"))
		return
	case errors.Is(err, store.ErrPairTimeout):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrPairTimeout, "the owner did not answer in time"))
		// Settled right here, by this presentation, rather than by the sweeper:
		// the row now carries an outcome, so neither the sweeper nor the
		// greeting re-send will look at it again. If the owner is not told now,
		// nothing will ever tell them, and a dead question stays on screen.
		c.announcePairOutcome(res.RequestID, store.OutcomeExpired)
		return
	case err != nil:
		c.logger.Error("pair", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to pair"))
		return
	}

	if res.Pending {
		// The mark goes on BEFORE the reply: the owner could answer between the
		// two, and an outcome delivered to a connection nobody has marked yet
		// would be dropped on the floor.
		c.srv.markPendingRequest(c, res.RequestID)
		c.sendFrame(protocol.OKReply(cmd.ID, pairReply{
			Status:    pairStatusPending,
			RequestID: res.RequestID,
			ExpiresAt: res.ExpiresAt,
		}))
		// The window the mark cannot cover is the one BEFORE it: the store
		// transaction has already committed, so an owner answering in that
		// instant addressed the outcome to a connection nobody had marked yet -
		// and nothing re-sends it to the waiting side. Re-reading settles that:
		// if the request is already decided, this connection is told now.
		if c.deliverSettledOutcome(res.RequestID) {
			return
		}
		// Asked after the reply is queued, so the person at the door is told
		// they are waiting even if the owner has no device online at all.
		c.announcePairRequest(res.RequestID)
		return
	}

	id := res.Identity
	// Created is the whole reason this reply exists: it says whether the person
	// was brought into being by THIS operation, which is what tells the client
	// to offer the naming step. Computed from whether a row was inserted - not
	// from the token kind, and not from the fact that pairing succeeded.
	c.sendFrame(protocol.OKReply(cmd.ID, pairReply{
		Status: pairStatusPaired,
		Identity: &identity{
			greetingIdentity: greetingIdentity{ID: id.UserID, Label: id.Label, Owner: id.Owner},
			Created:          id.Created,
		},
	}))
}

// announcePairRequest wakes the owner's devices about one waiting request.
//
// The request is re-read from the store rather than assembled from what Pair
// returned, so a repeat presentation on a new connection - the shape a dropped
// socket takes - announces the SAME question with the same issue time instead
// of a second one.
func (c *client) announcePairRequest(requestID string) {
	owner, err := c.srv.store.OwnerUserID(c.ctx)
	if err != nil {
		c.logger.Error("read owner for pair request", "err", err)
		return
	}
	if owner == "" {
		// No owner means nobody can answer. The request still stands and still
		// expires on its own; there is simply nowhere to send the question.
		return
	}
	pending, err := c.srv.store.PendingRequests(c.ctx, time.Now().Unix())
	if err != nil {
		c.logger.Error("read pending requests", "err", err)
		return
	}
	for _, req := range pending {
		if req.RequestID == requestID {
			c.srv.notifyPairRequested(owner, req)
			return
		}
	}
}

// deliverSettledOutcome reports whether the request was already decided, and
// hands this connection the outcome if it was.
//
// The read is cheap and only happens on the pending path, which is the one
// place a decision can have landed between the commit and the mark.
func (c *client) deliverSettledOutcome(requestID string) bool {
	settled, id, decided, err := c.srv.store.RequestOutcome(c.ctx, requestID)
	if err != nil {
		c.logger.Error("read settled outcome", "err", err)
		return false
	}
	if !decided {
		return false
	}
	owner, err := c.srv.store.OwnerUserID(c.ctx)
	if err != nil {
		c.logger.Error("read owner for settled outcome", "err", err)
		owner = ""
	}
	c.srv.notifyPairResolved(owner, requestID, settled, id)
	return true
}

// announcePairOutcome tells the owner's devices that a question is closed, for
// the one path where nothing else will: a request this presentation expired.
func (c *client) announcePairOutcome(requestID, outcome string) {
	if requestID == "" {
		return
	}
	owner, err := c.srv.store.OwnerUserID(c.ctx)
	if err != nil {
		c.logger.Error("read owner for expired request", "err", err)
		return
	}
	c.srv.notifyPairResolved(owner, requestID, outcome, store.Identity{})
}

type deviceListReply struct {
	Devices []store.Device `json:"devices"`
}

// handleDeviceList answers with the person's own devices. There is nothing to
// scope: a connection speaks as exactly one person, so it can only ever see
// its own.
func (c *client) handleDeviceList(cmd protocol.Command) {
	devices, err := c.srv.store.ListDevices(c.ctx, c.identity.UserID)
	if err != nil {
		c.logger.Error("device.list", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list devices"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, deviceListReply{Devices: devices}))
}

type deviceRevokeRequest struct {
	DeviceKey string `json:"device_key"`
}

// handleDeviceRevoke removes a key from the allowed list and cuts the revoked
// device off immediately.
//
// Dropping the live connection matters as much as the row: waiting for the
// device to reconnect would leave a sold tablet reading the conversation for
// as long as it stays online.
func (c *client) handleDeviceRevoke(cmd protocol.Command) {
	var req deviceRevokeRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed device.revoke data"))
		return
	}
	key := strings.TrimSpace(req.DeviceKey)
	if key == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "device_key is required"))
		return
	}

	// Only one's own devices. Without this check anyone could cut off anyone.
	owner, found, err := c.srv.store.DeviceOwner(c.ctx, key)
	if err != nil {
		c.logger.Error("device owner", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read the device"))
		return
	}
	if found && owner != c.identity.UserID {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "no such device"))
		return
	}

	if err := c.srv.store.RevokeDevice(c.ctx, key); err != nil {
		c.logger.Error("device.revoke", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to revoke the device"))
		return
	}
	// Revoking a key that is not there is a success: the caller asked for a
	// state and that state holds, so a retry after a dropped connection does
	// not look like a failure.
	c.sendFrame(protocol.OKReply(cmd.ID, struct{}{}))
	c.srv.dropDevice(key)
}

type inviteReply struct {
	Token string `json:"token"`
	Link  string `json:"link"`
}

// handleDeviceInvite mints a token that binds another device to this person,
// and renders the link to show.
//
// The link is built here rather than on the device because only the server
// knows its own public key and the address it is reachable at.
func (c *client) handleDeviceInvite(cmd protocol.Command) {
	token, err := c.srv.store.IssueDeviceInvite(c.ctx, c.identity.UserID, time.Now().Unix())
	if err != nil {
		c.logger.Error("device.invite", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to issue an invite"))
		return
	}
	id, err := c.srv.store.ServerIdentity(c.ctx)
	if err != nil {
		c.logger.Error("server identity", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read the server identity"))
		return
	}
	link, err := BuildPairingLink(inviteAddress(c.srv.cfg.Addr, c.requestHost), id.PublicKey, token)
	if err != nil {
		c.logger.Error("build invite link", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to build the link"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, inviteReply{Token: token, Link: link}))
}

// personInviteReply is the invite for a new PERSON: the same shape as a device
// invite plus the deadline, because this link lives a day rather than ten
// minutes and the app shows how long is left.
type personInviteReply struct {
	Token     string `json:"token"`
	Link      string `json:"link"`
	ExpiresAt int64  `json:"expires_at"`
}

// handlePersonInvite mints a token that brings a NEW person into the circle.
//
// Only the owner may do it (Q15, owner 2026-09-04): an invite is the decision
// of whoever operates the machine, not a right of everyone in the space - it is
// their disk, their traffic and their legal exposure. The check itself lives in
// the store, with the operation rather than with one way of reaching it.
func (c *client) handlePersonInvite(cmd protocol.Command) {
	now := time.Now().Unix()
	token, err := c.srv.store.IssuePersonInvite(c.ctx, c.identity.UserID, now)
	switch {
	case errors.Is(err, store.ErrNotOwner):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotOwner, "only the server owner may invite a person"))
		return
	case err != nil:
		c.logger.Error("person.invite", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to issue an invite"))
		return
	}
	id, err := c.srv.store.ServerIdentity(c.ctx)
	if err != nil {
		c.logger.Error("server identity", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read the server identity"))
		return
	}
	link, err := BuildPairingLink(inviteAddress(c.srv.cfg.Addr, c.requestHost), id.PublicKey, token)
	if err != nil {
		c.logger.Error("build person invite link", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to build the link"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, personInviteReply{
		Token:     token,
		Link:      link,
		ExpiresAt: now + store.PersonInviteTTLSeconds,
	}))
}

type personListReply struct {
	People []store.Person `json:"people"`
}

// handlePersonList answers with the people of the circle.
//
// Open to any paired device, not just the owner: names are not a secret - they
// ride every message as author_label - and the owner mark answers the same
// question a person's own greeting already answers about themselves. The SCREEN
// belongs to the owner because the action on it is theirs; the list does not.
func (c *client) handlePersonList(cmd protocol.Command) {
	people, err := c.srv.store.ListPeople(c.ctx)
	if err != nil {
		c.logger.Error("person.list", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list people"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, personListReply{People: people}))
}

type personConfirmRequest struct {
	RequestID string `json:"request_id"`
	Approve   bool   `json:"approve"`
}

type personConfirmReply struct {
	Outcome string `json:"outcome"`
}

// handlePersonConfirm records the owner's decision about one waiting invite.
//
// One request, not "let somebody in": two people knocking is two decisions, and
// an answer that meant "yes to whoever is at the door" would let the second one
// through on the first one's permission.
func (c *client) handlePersonConfirm(cmd protocol.Command) {
	var req personConfirmRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed person.confirm data"))
		return
	}
	requestID := strings.TrimSpace(req.RequestID)
	if requestID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "request_id is required"))
		return
	}

	res, err := c.srv.store.ConfirmPair(c.ctx, requestID, c.identity.UserID, req.Approve, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrNotOwner):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotOwner, "only the server owner may answer this"))
		return
	case errors.Is(err, store.ErrRequestNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "no such pairing request"))
		return
	case errors.Is(err, store.ErrPairTimeout):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrPairTimeout, "this request has already expired"))
		// The waiting device is told too: the answer came too late for it, and
		// the question has to leave every owner screen as well.
		c.srv.notifyPairResolved(c.identity.UserID, requestID, store.OutcomeExpired, store.Identity{})
		return
	case errors.Is(err, store.ErrTokenInvalid):
		// The presenting key acquired an owner while the request waited, so the
		// approval could not be carried out. Nothing is recorded and the
		// request stands; it expires on its own.
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidToken, "this device can no longer be paired"))
		return
	case err != nil:
		c.logger.Error("person.confirm", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to answer the request"))
		return
	}

	c.sendFrame(protocol.OKReply(cmd.ID, personConfirmReply{Outcome: res.Outcome}))
	// Both sides: the person at the door needs the outcome, and the owner's
	// OTHER devices need the question to leave their screens rather than only
	// the one that answered it.
	c.srv.notifyPairResolved(c.identity.UserID, requestID, res.Outcome, res.Identity)
}

type setLabelRequest struct {
	Label string `json:"label"`
}

type setLabelReply struct {
	Label string `json:"label"`
}

// handleIdentitySetLabel renames the person.
//
// Nothing here checks availability: names are not unique, the server neither
// enforces nor reports uniqueness, so there is no refusal to make. Before this
// command a name could only travel in a greeting, which meant a rename had to
// reconnect the session - workable with one device, a source of divergence with
// two.
func (c *client) handleIdentitySetLabel(cmd protocol.Command) {
	var req setLabelRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed identity.setLabel data"))
		return
	}
	label := strings.TrimSpace(req.Label)
	if label == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "label is required"))
		return
	}
	if err := c.srv.store.SetLabel(c.ctx, c.identity.UserID, label); err != nil {
		c.logger.Error("identity.setLabel", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to set the label"))
		return
	}
	// Every live connection of this person, not just the one that asked. The
	// name is copied into `messages.author_label` at send time and frozen
	// there, so a second device left with a stale identity would stamp the OLD
	// name into history permanently. The others are told as well: a stable
	// socket never re-greets, so without the event they would show the old name
	// until something happened to reconnect them.
	c.srv.refreshLabel(c.identity.UserID, label, c)
	c.sendFrame(protocol.OKReply(cmd.ID, setLabelReply{Label: label}))
}

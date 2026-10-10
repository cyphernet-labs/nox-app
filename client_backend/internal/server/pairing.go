package server

import (
	"encoding/json"
	"errors"
	"strings"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// pairRequest mirrors contract §8A. There is no device_key since 044: the key
// being paired is the one this connection proved in the channel check, so a
// device can only ever pair itself - and an older client that still sends the
// field has it ignored, never believed. The same goes for access_key since
// 045: there are no onion access keys any more, and the field is skipped like
// any other this server does not know.
type pairRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

// pairReply is one of two shapes (contract §8A), never both:
//
//   - {identity} - the device is paired: a machine link, or an invite whose
//     request was allowed already (the repeat of an answer that got lost);
//   - {status, request_id, expires_at} - an invite's request: "pending" while
//     it waits for the issuing device, or the outcome it closed with -
//     "denied", "expired" or "cancelled".
//
// status reuses pair.resolved's outcome words on purpose: the event and the
// repeat of `pair` are the two halves of one answer, and the device reads the
// outcome the same way whichever reached it.
type pairReply struct {
	Identity  *identity `json:"identity,omitempty"`
	Status    string    `json:"status,omitempty"`
	RequestID string    `json:"request_id,omitempty"`
	ExpiresAt int64     `json:"expires_at,omitempty"`
}

// statusPending is the status of a request still waiting for an answer.
const statusPending = "pending"

// handlePair is one of the two commands accepted before the greeting: an
// unpaired device's key is one the server does not know, and its greeting
// would be refused - so requiring hello first would make pairing impossible
// rather than merely awkward.
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
	platform := strings.TrimSpace(req.Platform)
	if token == "" || platform == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "token and platform are required"))
		return
	}
	if !knownPlatform(platform) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "platform must be ios, android, macos, windows or linux"))
		return
	}
	// Whatever path this connection came by (FR-008): a connection from tor
	// arrives on the main port like any other, proved its key the same way,
	// and nothing here could tell it apart if it tried.
	res, err := c.srv.store.Pair(c.ctx, token, c.deviceKey, platform, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrTokenInvalid):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidToken, "pairing token is not usable"))
		return
	case errors.Is(err, store.ErrTokenExpired):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrTokenExpired, "pairing token has expired"))
		return
	case err != nil:
		c.logger.Error("pair", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to pair"))
		return
	}

	if !res.Paired {
		// An invite: the device waits for the issuing device's answer, or is
		// told how its request already ended.
		r := *res.Request
		status := r.Outcome
		if status == "" {
			status = statusPending
		}
		c.sendFrame(protocol.OKReply(cmd.ID, pairReply{Status: status, RequestID: r.RequestID, ExpiresAt: r.ExpiresAt}))
		// After the reply, like every fan-out (§9): the issuing device is asked
		// only when THIS call opened the request - a repeat is the same request,
		// and the issuer already has it - and both sides hear of a request this
		// call found run out and closed.
		switch {
		case res.Opened:
			c.logger.Info("pairing request opened")
			c.srv.announcePairRequested(r)
		case res.Closed:
			c.srv.announcePairClosed(r, nil)
		}
		return
	}

	// Created is the whole reason this reply exists: it says whether the person
	// was brought into being by THIS operation, which is what tells the client
	// to offer the naming step. Computed from whether a row was inserted - not
	// from the token kind, and not from the fact that pairing succeeded.
	c.sendFrame(protocol.OKReply(cmd.ID, pairReply{Identity: wireIdentity(res.Identity)}))

	// The other devices of this person learn about the new one here: nothing
	// else on the wire says the set of devices changed.
	//
	// AFTER the reply, the way device.revoke does it, and the order is
	// load-bearing. send blocks on a full queue until that connection's context
	// is cancelled, so announcing first puts this device's answer behind a
	// stranger's backlog: one wedged connection of the same person - a slow
	// consumer whose drop is still finishing its close handshake - and the
	// device waits out the client's send timeout for a command that has already
	// spent a one-shot token and written its row.
	//
	// What it does NOT buy: the fan-out still runs on this connection's read
	// goroutine, so the same wedged recipient delays whatever this device sends
	// NEXT - its greeting. That wait is bounded by the library's close handshake
	// rather than open-ended, and moving the fan-out onto its own goroutine
	// would buy the difference at the cost of making these events the only ones
	// with no order relative to the frames around them.
	//
	// It fires on a replayed pair too, where nothing changed: the store answers
	// a device that spent this token before, and the event is a hint the
	// receiver answers by re-reading the list (contract §8A, "at least once").
	c.announcePaired(res.Identity.UserID)
}

// wireIdentity is the identity object of the pair reply and of pair.resolved:
// the same person, described the same way, whichever frame carried it.
func wireIdentity(id store.Identity) *identity {
	return &identity{greetingIdentity: greetingIdentity{ID: id.UserID, Label: id.Label}, Created: id.Created}
}

type pairCancelRequest struct {
	Token string `json:"token"`
}

// handlePairCancel withdraws the request this device opened with an invite
// (FR-010): the token is spent, the issuing device's dialog closes, and Allow
// pressed afterwards does nothing.
//
// Accepted before the greeting, like `pair`: the device asking is not paired -
// that is what it is waiting for. Idempotent: no waiting request of this key
// under this token is answered with the same {} - the state the device asked
// for holds. Closing the app does NOT cancel (FR-011); only this does.
func (c *client) handlePairCancel(cmd protocol.Command) {
	var req pairCancelRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed pair.cancel data"))
		return
	}
	token := strings.TrimSpace(req.Token)
	if token == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "token is required"))
		return
	}
	r, cancelled, err := c.srv.store.CancelPairRequest(c.ctx, token, c.deviceKey, time.Now().Unix())
	if err != nil {
		c.logger.Error("pair.cancel", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to cancel the request"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, struct{}{}))
	if cancelled {
		// Both sides, the new device included (contract §8A): pair.resolved is
		// how every connection of the device learns the request is over, the
		// one that asked among them, and device.pairResolved closes the dialog.
		c.srv.announcePairClosed(r, nil)
	}
}

type deviceApproveRequest struct {
	RequestID string `json:"request_id"`
	// Allow is a pointer so a missing answer is told apart from "deny": a
	// frame that forgot the field must not decide anything.
	Allow *bool `json:"allow"`
}

// handleDeviceApprove is the issuing device's answer to a request (FR-009).
//
// Allow pairs the new device - written, token spent, request closed in one
// transaction - and then the new device is told with its identity, the
// issuing device that the request is over, and the person's devices that the
// set of devices changed. Deny closes the request; the new device and the
// issuer are told. The reply goes first, the fan-out after it (§9).
func (c *client) handleDeviceApprove(cmd protocol.Command) {
	var req deviceApproveRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed device.approve data"))
		return
	}
	requestID := strings.TrimSpace(req.RequestID)
	if requestID == "" || req.Allow == nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "request_id and allow are required"))
		return
	}
	dec, err := c.srv.store.DecidePairRequest(c.ctx, requestID, c.deviceKey, *req.Allow, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrDeviceUnknown):
		// Revoked while the answer was on its way: the answer its next greeting
		// would get.
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnauthenticated, "device is not paired"))
		return
	case errors.Is(err, store.ErrRequestNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "no such request waiting for this device"))
		return
	case err != nil:
		c.logger.Error("device.approve", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to answer the request"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, struct{}{}))

	if dec.Request.Outcome != store.OutcomeAllowed {
		c.srv.announcePairClosed(dec.Request, nil)
		return
	}
	c.srv.announcePairClosed(dec.Request, wireIdentity(dec.Identity))
	// Every connection of the person, the answering one included: its device
	// list is as stale as the others', and the new device is not among them -
	// it has not greeted yet.
	c.srv.announceDevicesChanged(dec.Identity.UserID, nil)
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

	rev, err := c.srv.store.RevokeDevice(c.ctx, key, time.Now().Unix())
	if err != nil {
		c.logger.Error("device.revoke", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to revoke the device"))
		return
	}
	// Revoking a key that is not there is a success: the caller asked for a
	// state and that state holds, so a retry after a dropped connection does
	// not look like a failure.
	c.sendFrame(protocol.OKReply(cmd.ID, struct{}{}))
	c.srv.dropDevice(key)
	// The requests the revoked device took part in closed with it. The device
	// waiting on each is told; so is the device asked to answer it, unless that
	// is the one just revoked - its connections are closing, and the dialog
	// goes with the device.
	for _, r := range rev.Closed {
		c.logger.Info("pairing request closed", "outcome", r.Outcome)
		c.srv.tellNewDevice(r, nil)
		if r.IssuerKey != key {
			c.srv.tellIssuer(r)
		}
	}
}

type inviteReply struct {
	Token string `json:"token"`
	Link  string `json:"link"`
	// Onion says the link names the onion address, Public that it names the
	// public one (045, contract §8A). With both false the invite works only
	// at home, and the app says so under it. Written out, never omitted: an
	// older client reads a missing field as "unknown".
	Onion  bool `json:"onion"`
	Public bool `json:"public"`
}

// handleDeviceInvite mints a token that binds another device to this person,
// and renders the link to show.
//
// The request's `onion` is accepted and ignored (contract §8A): true, false,
// junk or nothing, the link names every address this machine has to offer, so
// there is nothing left to read it for - and nothing in it can refuse the
// command.
//
// The link is built here rather than on the device because only the server
// knows its own public key and the addresses it is reachable at. A device
// revoked while this command was on its way is told unauthenticated: the store
// issues nothing for a device that is gone.
func (c *client) handleDeviceInvite(cmd protocol.Command) {
	id, err := c.srv.store.ServerIdentity(c.ctx)
	if err != nil {
		c.logger.Error("server identity", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read the server identity"))
		return
	}
	// Read before the token is minted: a failure after it would leave an
	// invite nobody was handed alive for ten minutes.
	conf, err := c.srv.configuredAddresses(c.ctx)
	if err != nil {
		c.logger.Error("read addresses", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read the addresses"))
		return
	}
	// The direct host. Through the onion service, Host is the onion name -
	// useless to a device at home - so the list is asked. The name is the only
	// sign of that path left: the connection itself came in on the main port
	// like any other (045).
	addr := inviteAddress(c.srv.cfg.Addr, c.requestHost)
	if onionHost(c.requestHost) {
		addr = c.srv.inviteDirectAddress()
	}

	token, err := c.srv.store.IssueDeviceInvite(c.ctx, c.deviceKey, time.Now().Unix())
	if errors.Is(err, store.ErrDeviceUnknown) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnauthenticated, "device is not paired"))
		return
	}
	if err != nil {
		c.logger.Error("device.invite", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to issue an invite"))
		return
	}
	link, carries, err := buildLink(id.PublicKey, token, addr, conf)
	if err != nil {
		// The error can quote the host it could not encode, and that host came
		// from the Host header.
		c.logger.Error("build invite link", "err", maskOnion(err.Error()))
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to build the link"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, inviteReply{Token: token, Link: link, Onion: carries.Onion, Public: carries.Public}))
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
	c.sendFrame(protocol.OKReply(cmd.ID, setLabelReply{Label: label}))

	// Every live connection of this person, not just the one that asked. The
	// name is copied into `messages.author_label` at send time and frozen
	// there, so a second device left with a stale identity would stamp the OLD
	// name into history permanently. The others are told as well: a stable
	// socket never re-greets, so without the event they would show the old name
	// until something happened to reconnect them.
	//
	// After the reply, the way `pair` and `device.revoke` do it: send blocks on
	// a full write queue until that connection's context is cancelled, so a
	// fan-out ahead of the answer puts the caller behind a stranger's backlog.
	// Nothing in the reply depends on this - the label it echoes is the one
	// already written to the store.
	c.srv.refreshLabel(c.identity.UserID, label, c)
}

// knownPlatform reports whether p is one of the OS families a device may name
// itself by (contract §8A). Anything else is refused before a token is looked
// at: the name is shown in the Allow dialog of the device that issued the
// invite, and free text there would let whoever holds a leaked invite pass
// itself off as whatever it liked.
func knownPlatform(p string) bool {
	switch p {
	case "ios", "android", "macos", "windows", "linux":
		return true
	}
	return false
}

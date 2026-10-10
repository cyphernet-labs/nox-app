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

// pairReply carries the identity `pair` produced. There is no status field:
// the command always finishes, so a field with one possible value would only
// look like information - the same argument the contract makes about `owner`.
type pairReply struct {
	Identity *identity `json:"identity"`
}

// handlePair is the only command accepted before the greeting: an unpaired
// device's key is one the server does not know, and its greeting would be
// refused - so requiring hello first would make pairing impossible rather than
// merely awkward.
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
	// Whatever path this connection came by, the claim included (FR-008): a
	// connection from tor arrives on the main port like any other, proved its
	// key the same way, and nothing here could tell it apart if it tried.
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
	// The key is a paired device's now, so the connection leaves the limits
	// a stranger's is held to - before the reply, so its deadline cannot land
	// between the two.
	c.srv.settleUnpaired(c)

	// Created is the whole reason this reply exists: it says whether the person
	// was brought into being by THIS operation, which is what tells the client
	// to offer the naming step. Computed from whether a row was inserted - not
	// from the token kind, and not from the fact that pairing succeeded.
	c.sendFrame(protocol.OKReply(cmd.ID, pairReply{
		Identity: &identity{
			greetingIdentity: greetingIdentity{ID: res.UserID, Label: res.Label},
			Created:          res.Created,
		},
	}))

	// The other devices of this person learn about the new one here, and only
	// here: nothing else on the wire says the set of devices changed.
	//
	// AFTER the reply, the way device.revoke does it, and the order is
	// load-bearing. send blocks on a full queue until that connection's context
	// is cancelled, so announcing first puts this device's answer behind a
	// stranger's backlog: one wedged connection of the same person - a slow
	// consumer whose drop is still finishing its close handshake - and the
	// device waits out the client's send timeout for a command that has already
	// burned a one-shot token and written its row.
	//
	// What it does NOT buy: the fan-out still runs on this connection's read
	// goroutine, so the same wedged recipient delays whatever this device sends
	// NEXT - its greeting. That wait is bounded by the library's close handshake
	// rather than open-ended, and moving the fan-out onto its own goroutine
	// would buy the difference at the cost of making these events the only ones
	// with no order relative to the frames around them.
	//
	// It fires on a replayed pair too, where nothing changed: the store answers
	// a device that spent this token before, and the handler cannot tell that
	// from a first pass. The receiver re-reads either way, so the cost of the
	// repeat is one list read - and the alternative, teaching the store to
	// report a replay, spreads a pairing detail through a type the greeting
	// shares. Written down in contract §8A rather than papered over.
	c.announcePaired(res.UserID)
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
		// from the Host header - the onion name, through the onion service. The
		// log's handler masks it (logscrub.go).
		c.logger.Error("build invite link", "err", err)
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

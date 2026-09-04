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

type pairReply struct {
	Identity identity `json:"identity"`
}

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

	id, err := c.srv.store.Pair(c.ctx, token, deviceKey, platform, time.Now().Unix())
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

	// Created is the whole reason this reply exists: it says whether the person
	// was brought into being by THIS operation, which is what tells the client
	// to offer the naming step. Computed from whether a row was inserted - not
	// from the token kind, and not from the fact that pairing succeeded.
	c.sendFrame(protocol.OKReply(cmd.ID, pairReply{
		Identity: identity{ID: id.UserID, Label: id.Label, Created: id.Created},
	}))
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
	link, err := BuildPairingLink(listenAddress(c.srv.cfg.Addr), id.PublicKey, token)
	if err != nil {
		c.logger.Error("build invite link", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to build the link"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, inviteReply{Token: token, Link: link}))
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
	c.identity.Label = label
	c.label = label
	c.sendFrame(protocol.OKReply(cmd.ID, setLabelReply{Label: label}))
}

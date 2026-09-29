package server

import (
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
	"nox.app/client-backend/internal/tor"
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
	// AccessKey is the device's onion access key (039): an x25519 PUBLIC
	// key, base64, optional. An older server ignores it; this one writes it in
	// the same transaction as the device row.
	AccessKey string `json:"access_key"`
}

// pairReply carries the identity `pair` produced. There is no status field:
// the command always finishes, so a field with one possible value would only
// look like information - the same argument the contract makes about `owner`.
type pairReply struct {
	Identity *identity `json:"identity"`
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
	// A malformed key refuses the pairing rather than pairing without one: a
	// client that sends garbage here has a bug, and a device paired without
	// onion access looks fine until the day it leaves the house.
	accessKey := strings.TrimSpace(req.AccessKey)
	if accessKey != "" {
		if _, err := tor.ParseAccessKey(accessKey); err != nil {
			c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "access_key is not a usable x25519 public key"))
			return
		}
	}

	res, err := c.srv.store.Pair(c.ctx, token, deviceKey, platform,
		store.PairOptions{AccessKey: accessKey, ViaOnion: c.viaOnion}, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrTokenInvalid):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidToken, "pairing token is not usable"))
		return
	case errors.Is(err, store.ErrTokenExpired):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrTokenExpired, "pairing token has expired"))
		return
	case errors.Is(err, store.ErrAccessKeyTaken):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "access_key is already in use"))
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
	// The key set may have moved: a new device key, or an onion invite's
	// one-time key spent by this very pairing. After the reply, like every
	// fan-out - a republish ahead of it could cut the connection the reply is
	// travelling on. An unchanged set is a no-op in the supervisor.
	c.srv.tor.KeysChanged()
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
	// Its access key went with the row, and its live invites were burned:
	// the onion service has to lose them, and its circuits cut, now.
	c.srv.tor.KeysChanged()
}

type setAccessKeyRequest struct {
	AccessKey string `json:"access_key"`
}

// handleDeviceSetAccessKey registers the onion access key of the device this
// connection greeted as (039, contract §8A).
//
// There is no parameter naming the device: a connection can only ever set its
// own key. A device that vanished mid-session - revoked from another device -
// is told unauthenticated, the same answer its next greeting would get.
func (c *client) handleDeviceSetAccessKey(cmd protocol.Command) {
	var req setAccessKeyRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed device.setAccessKey data"))
		return
	}
	accessKey := strings.TrimSpace(req.AccessKey)
	if _, err := tor.ParseAccessKey(accessKey); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "access_key is not a usable x25519 public key"))
		return
	}
	changed, err := c.srv.store.SetAccessKey(c.ctx, c.srv.currentDeviceKey(c), accessKey)
	if errors.Is(err, store.ErrDeviceUnknown) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnauthenticated, "device is not paired"))
		return
	}
	if errors.Is(err, store.ErrAccessKeyTaken) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "access_key is already in use"))
		return
	}
	if err != nil {
		c.logger.Error("device.setAccessKey", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to set the access key"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, struct{}{}))
	if changed {
		c.srv.tor.KeysChanged()
	}
}

type inviteReply struct {
	Token string `json:"token"`
	Link  string `json:"link"`
	// Onion says the link is version 2 and carries the onion address with a
	// one-time access key (039). An older client ignores it.
	Onion bool `json:"onion"`
}

// inviteRequest is read leniently: `onion` absent, null or anything but a
// boolean is false. The field is a wish, not an obligation, and a client that
// sends something odd still gets the invite it would have got before 039.
type inviteRequest struct {
	Onion any `json:"onion"`
}

// handleDeviceInvite mints a token that binds another device to this person,
// and renders the link to show.
//
// The link is built here rather than on the device because only the server
// knows its own public key and the address it is reachable at. A device
// revoked while this command was on its way is told unauthenticated, as
// device.setAccessKey tells it: the store issues nothing for a device that is
// gone.
func (c *client) handleDeviceInvite(cmd protocol.Command) {
	var req inviteRequest
	_ = json.Unmarshal(cmd.Data, &req) // lenient by contract: anything odd is "no onion"
	wantOnion, _ := req.Onion.(bool)

	id, err := c.srv.store.ServerIdentity(c.ctx)
	if err != nil {
		c.logger.Error("server identity", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read the server identity"))
		return
	}
	// The direct host. Over onion, Host is the onion name - useless to a
	// device at home and to an older client alike - so the list is asked.
	addr := inviteAddress(c.srv.cfg.Addr, c.requestHost)
	if c.viaOnion {
		addr = c.srv.inviteDirectAddress()
	}

	// An onion invite only when it would work: Tor on and tor connected. One
	// that cannot be used outside is worse than an honest "home only".
	if wantOnion && c.srv.tor.ReadyForInvite() {
		c.issueOnionInvite(cmd, addr, id.Fingerprint)
		return
	}

	token, err := c.srv.store.IssueDeviceInvite(c.ctx, c.srv.currentDeviceKey(c), time.Now().Unix())
	if errors.Is(err, store.ErrDeviceUnknown) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnauthenticated, "device is not paired"))
		return
	}
	if err != nil {
		c.logger.Error("device.invite", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to issue an invite"))
		return
	}
	link, err := BuildPairingLink(addr, id.Fingerprint, token)
	if err != nil {
		c.logger.Error("build invite link", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to build the link"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, inviteReply{Token: token, Link: link}))
}

// issueOnionInvite mints an invite carrying the onion address and a one-time
// access key (039).
//
// The key pair is made here and the halves part at once: the PUBLIC half goes
// to the store, where it opens the onion service for as long as the invite
// lives; the PRIVATE half goes into the link and nowhere else - not the
// store, not the log (FR-020).
func (c *client) issueOnionInvite(cmd protocol.Command, addr, fingerprint string) {
	oneTime, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		c.logger.Error("generate one-time access key", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to issue an invite"))
		return
	}
	accessPub := base64.StdEncoding.EncodeToString(oneTime.PublicKey().Bytes())
	token, err := c.srv.store.IssueOnionInvite(c.ctx, c.srv.currentDeviceKey(c), accessPub, time.Now().Unix())
	if errors.Is(err, store.ErrDeviceUnknown) {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnauthenticated, "device is not paired"))
		return
	}
	if err != nil {
		c.logger.Error("device.invite onion", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to issue an invite"))
		return
	}
	link, err := BuildPairingLinkV2(addr, fingerprint, token, c.srv.tor.OnionPublicKey(), tor.OnionPort, oneTime.Bytes())
	if err != nil {
		c.logger.Error("build onion invite link", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to build the link"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, inviteReply{Token: token, Link: link, Onion: true}))
	// The one-time key has to be in the service before the new device dials
	// it. After the reply, like every other change of the set.
	c.srv.tor.KeysChanged()
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

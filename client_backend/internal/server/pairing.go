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

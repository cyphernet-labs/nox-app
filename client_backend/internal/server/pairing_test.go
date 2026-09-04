package server

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

func TestPairClaimCreatesThePersonAndRefusesASecondClaim(t *testing.T) {
	ts, srv := newTestServer(t)

	dev, data := claimDevice(t, ts, srv)
	var id identity
	mustUnmarshal(t, data["identity"], &id)
	if !id.Created || id.ID == "" {
		t.Fatalf("identity = %+v, want a created person", id)
	}

	// A brand-new claim token on an owned server is refused just the same:
	// ownership is not something a later token may hand over again.
	token, err := srv.store.IssueClaimToken(context.Background(), time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	second := dialWS(t, ts, srv)
	second.expectGreeting()
	other := newDevice(t)
	second.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, token, other.pub))
	if code := expectErrCode(t, second, 1); code != protocol.ErrInvalidToken {
		t.Fatalf("second claim code = %q, want %q", code, protocol.ErrInvalidToken)
	}
	_ = dev
}

// The whole point of the phase, at its narrowest: a connection that cannot
// prove possession of a paired key does not get in.
func TestGreetingWithoutAValidSignatureIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	t.Run("no signature at all", func(t *testing.T) {
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q}}`, dev.pub))
		if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
			t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
		}
	})

	t.Run("a signature from another key", func(t *testing.T) {
		impostor := newDevice(t)
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		// The real device's public key with somebody else's signature: this is
		// what an intercepted key without the private half looks like.
		c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":%q}}`,
			dev.pub, impostor.sign(t, c.challenge)))
		if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
			t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
		}
	})

	t.Run("a signature over ANOTHER connection's challenge", func(t *testing.T) {
		// The reason the challenge is per connection. Without this, one captured
		// greeting would be a permanent key: replaying it on a fresh socket
		// would authenticate as its author forever.
		other := dialWS(t, ts, srv)
		other.expectGreeting()
		stolen := dev.sign(t, other.challenge)

		c := dialWS(t, ts, srv)
		c.expectGreeting()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":%q}}`, dev.pub, stolen))
		if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
			t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
		}
	})

	t.Run("a key the server does not know", func(t *testing.T) {
		// Revoked, or a rebuilt store. The device cannot tell them apart and
		// must not: both mean "this is not my server any more".
		stranger := newDevice(t)
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":%q}}`,
			stranger.pub, stranger.sign(t, c.challenge)))
		if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
			t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
		}
	})
}

func TestInviteAddsADeviceToTheSamePerson(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, claimed := claimDevice(t, ts, srv)
	var owner identity
	mustUnmarshal(t, claimed["identity"], &owner)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")
	invite := c.expectOKAfter(2, `{"id":2,"cmd":"device.invite","data":{}}`)
	var reply struct {
		Token string `json:"token"`
		Link  string `json:"link"`
	}
	mustUnmarshal(t, mustRaw(t, invite), &reply)
	if reply.Token == "" || reply.Link == "" {
		t.Fatalf("invite reply = %+v, want a token and a link to show", reply)
	}

	_, added := pairDevice(t, ts, reply.Token)
	var second identity
	mustUnmarshal(t, added["identity"], &second)
	if second.ID != owner.ID {
		t.Fatalf("invited device belongs to %q, want %q", second.ID, owner.ID)
	}
	if second.Created {
		t.Fatal("adding a device must not report having created a person")
	}
}

func TestRevokeDropsTheLiveConnectionRatherThanWaiting(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	owner := dialWS(t, ts, srv)
	owner.expectGreeting()
	owner.greet(t, 1, dev, "")
	invite := owner.expectOKAfter(2, `{"id":2,"cmd":"device.invite","data":{}}`)
	var reply struct {
		Token string `json:"token"`
	}
	mustUnmarshal(t, mustRaw(t, invite), &reply)
	second, _ := pairDevice(t, ts, reply.Token)

	// The device being revoked is live and idle, exactly like a sold tablet
	// left switched on.
	victim := dialWS(t, ts, srv)
	victim.expectGreeting()
	victim.greet(t, 1, second, "")

	owner.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.revoke","data":{"device_key":%q}}`, second.pub))

	// It learns about it without having to try anything first.
	_, name, _ := victim.expectEvent()
	if name != protocol.EventDeviceRevoked {
		t.Fatalf("event = %s, want %s", name, protocol.EventDeviceRevoked)
	}

	back := dialWS(t, ts, srv)
	back.expectGreeting()
	back.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":%q}}`,
		second.pub, second.sign(t, back.challenge)))
	if code := expectErrCode(t, back, 1); code != protocol.ErrUnauthenticated {
		t.Fatalf("revoked device reconnected with code %q", code)
	}
}

func TestRevokingSomebodyElsesDeviceIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")

	// A key that exists but belongs to nobody here. Without the ownership check
	// anyone could cut off anyone.
	stranger := newDevice(t)
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, stranger.pub))
	// Unknown to this person, so it reads as "no such device" - and revoking a
	// key that is not in the list is a success, which is why the reply is ok.
	frame := c.expectReply(2)
	var ok bool
	mustUnmarshal(t, frame["ok"], &ok)
	if !ok {
		t.Fatalf("revoking an absent key must succeed: %v", rawString(frame["error"]))
	}
}

func TestDeviceListShowsWhatDistinguishesADevice(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")
	data := c.expectOKAfter(2, `{"id":2,"cmd":"device.list","data":{}}`)
	var reply struct {
		Devices []struct {
			DeviceKey  string `json:"device_key"`
			Platform   string `json:"platform"`
			CreatedAt  int64  `json:"created_at"`
			LastSeenAt int64  `json:"last_seen_at"`
		} `json:"devices"`
	}
	mustUnmarshal(t, mustRaw(t, data), &reply)
	if len(reply.Devices) != 1 {
		t.Fatalf("devices = %d, want 1", len(reply.Devices))
	}
	d := reply.Devices[0]
	if d.DeviceKey != dev.pub || d.Platform == "" || d.CreatedAt == 0 || d.LastSeenAt == 0 {
		t.Fatalf("device = %+v: a row has to let a person recognise their own", d)
	}
}

func TestSetLabelRenamesWithoutReconnecting(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")
	data := c.expectOKAfter(2, `{"id":2,"cmd":"identity.setLabel","data":{"label":"Anna"}}`)
	var reply struct {
		Label string `json:"label"`
	}
	mustUnmarshal(t, mustRaw(t, data), &reply)
	if reply.Label != "Anna" {
		t.Fatalf("label = %q, want Anna", reply.Label)
	}

	// The name survives on the next connection, so it really landed rather than
	// living in this session only.
	back := dialWS(t, ts, srv)
	back.expectGreeting()
	var id identity
	mustUnmarshal(t, back.greet(t, 1, dev, "")["identity"], &id)
	if id.Label != "Anna" {
		t.Fatalf("label after reconnect = %q, want Anna", id.Label)
	}
}

// expectErrCode reads the reply for id and returns its error code.
func expectErrCode(t *testing.T, c *wsClient, id int) string {
	t.Helper()
	frame := c.expectReply(id)
	var ok bool
	mustUnmarshal(t, frame["ok"], &ok)
	if ok {
		t.Fatalf("reply %d unexpectedly succeeded", id)
	}
	var e struct {
		Code string `json:"code"`
	}
	mustUnmarshal(t, frame["error"], &e)
	return e.Code
}

// mustRaw re-marshals a decoded data object so it can be unmarshalled into a
// typed struct.
func mustRaw(t *testing.T, data map[string]json.RawMessage) json.RawMessage {
	t.Helper()
	raw, err := json.Marshal(data)
	if err != nil {
		t.Fatalf("marshal reply data: %v", err)
	}
	return raw
}

var _ = websocket.StatusNormalClosure

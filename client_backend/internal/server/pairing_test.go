package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"sync"
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

// US2 scenario 5: the OTHER device of the same person has to see the new name.
// A stable socket never re-greets, so before this event a second device carried
// the old name for as long as it stayed connected - and stamped it into message
// history, which freezes the name at send time.
func TestARenameReachesTheOtherDeviceOfTheSamePerson(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	first := dialWS(t, ts, srv)
	first.expectGreeting()
	first.greet(t, 1, dev, "")
	invite := first.expectOKAfter(2, `{"id":2,"cmd":"device.invite","data":{}}`)
	var reply struct {
		Token string `json:"token"`
	}
	mustUnmarshal(t, mustRaw(t, invite), &reply)
	secondKey, _ := pairDevice(t, ts, reply.Token)

	second := dialWS(t, ts, srv)
	second.expectGreeting()
	second.greet(t, 1, secondKey, "")

	first.expectOKAfter(3, `{"id":3,"cmd":"identity.setLabel","data":{"label":"Anna"}}`)

	_, name, data := second.expectEvent()
	if name != protocol.EventIdentityUpdated {
		t.Fatalf("event = %s, want %s", name, protocol.EventIdentityUpdated)
	}
	var label string
	mustUnmarshal(t, data["label"], &label)
	if label != "Anna" {
		t.Fatalf("label = %q, want Anna", label)
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

// The machine never names its owner on the wire. It has no reason to: there is
// one person here, so "who owns this" answers nothing a device could act on -
// and a field carrying an id would have to be explained, and honoured, later.
func TestTheOwnersIdentifierNeverReachesTheWire(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, claimed := claimDevice(t, ts, srv)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	greeting := c.greet(t, 1, dev, "")

	for name, frame := range map[string]map[string]json.RawMessage{"pair": claimed, "greeting": greeting} {
		for _, forbidden := range []string{"owner_id", "owner_user_id", "owner_label"} {
			for key, raw := range frame {
				if bytes.Contains(raw, []byte(`"`+forbidden+`"`)) {
					t.Fatalf("%s frame names the owner explicitly in %q: %s", name, key, raw)
				}
			}
		}
	}
}

// US3 end to end: the machine outlives its devices and gives the same person
// back the SAME identity - the same id, and no naming step, because they
// existed before the claim. The path is rare and irreversible: getting it wrong
// costs either the machine or the history.
func TestReClaimAfterLosingEveryDeviceReturnsTheSamePerson(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, claimed := claimDevice(t, ts, srv)
	var before identity
	mustUnmarshal(t, claimed["identity"], &before)

	// Revoking the last device is what logout does.
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")
	c.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, dev.pub))

	token, err := srv.store.IssueClaimToken(context.Background(), time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	_, reclaimed := pairDevice(t, ts, token)
	var after identity
	mustUnmarshal(t, reclaimed["identity"], &after)

	if after.ID != before.ID {
		t.Fatalf("came back as %q, want the same person %q", after.ID, before.ID)
	}
	if after.Created {
		t.Fatal("re-claim reported creating a person who already existed")
	}
}

// Principle I: the flag is a role, and a role logged next to the person it
// belongs to is a record of who runs the machine. The count is what an
// operator needs; the identifier is not.
func TestOwnershipIsNeverLoggedBesideTheIdentifier(t *testing.T) {
	// A plain bytes.Buffer would be read here while connection goroutines are
	// still writing to it - the race detector is right about that, and the log
	// sink has to be safe rather than the assertion carefully timed.
	buf := &syncBuffer{}
	logger := slog.New(slog.NewJSONHandler(buf, nil))

	ts, srv := newTestServerLogging(t, logger)
	dev, claimed := claimDevice(t, ts, srv)
	var id identity
	mustUnmarshal(t, claimed["identity"], &id)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")

	// Per RECORD, not per buffer. Two whole-buffer substring checks ANDed
	// together are satisfied by an empty log and by two unrelated lines alike -
	// the test would have been green without ever exercising the property.
	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) == 0 || lines[0] == "" {
		t.Fatal("no log records at all: the assertion below would pass vacuously")
	}
	for _, line := range lines {
		var record map[string]any
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			t.Fatalf("log line is not JSON: %v (%s)", err, line)
		}
		var namesPerson, statesOwnership bool
		for k, v := range record {
			if s, ok := v.(string); ok && s == id.ID {
				namesPerson = true
			}
			if strings.Contains(strings.ToLower(k), "owner") {
				statesOwnership = true
			}
			if s, ok := v.(string); ok && strings.Contains(strings.ToLower(s), "owner") {
				statesOwnership = true
			}
		}
		if namesPerson && statesOwnership {
			t.Fatalf("one record carries both the person and their ownership: %s", line)
		}
	}
}

// syncBuffer is a log sink that survives being read while the server is still
// writing to it.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// inviteFrom mints a device invite on an already greeted connection and returns
// the token, so the two tests below can share a setup without sharing a subject.
func inviteFrom(t *testing.T, owner *wsClient, id int) string {
	t.Helper()
	reply := owner.expectOKAfter(id, fmt.Sprintf(`{"id":%d,"cmd":"device.invite","data":{}}`, id))
	var got struct {
		Token string `json:"token"`
	}
	mustUnmarshal(t, mustRaw(t, reply), &got)
	if got.Token == "" {
		t.Fatal("invite reply carried no token")
	}
	return got.Token
}

// The point of the phase: a device joining is news to the person's OTHER
// devices, and to nobody else.
//
// Both halves are asserted, and the negative one is not decoration: a broadcast
// that simply tells everyone would pass the positive half alone.
func TestPairingTellsTheOtherDevicesAndNotTheOneThatJustJoined(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	owner := dialWS(t, ts, srv)
	owner.expectGreeting()
	owner.greet(t, 1, dev, "")
	token := inviteFrom(t, owner, 2)

	// Kept open, unlike pairDevice's connection: what this one does NOT receive
	// is half the assertion.
	joiner := newDevice(t)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, token, joiner.pub))

	// announcePaired runs BEFORE the reply is written, so a connection wrongly
	// included would see the event ahead of its own answer. Reading the raw
	// frame rather than expectReply, which skips events and would hide exactly
	// the mistake this is looking for.
	first := c.read()
	if _, isEvent := first["event"]; isEvent {
		t.Fatalf("the device that just joined was told about itself: %v", first)
	}

	// And the device that was already here finds out without asking.
	seq, name, data := owner.expectEvent()
	if name != protocol.EventDevicePaired || seq != 0 {
		t.Fatalf("event = %s/%d, want %s/0", name, seq, protocol.EventDevicePaired)
	}
	if len(data) != 0 {
		t.Fatalf("device.paired carries %v, want an empty object", data)
	}
}

// Principle I on a frame nobody thinks to look at: the event must not carry the
// token that was just spent or the key of the device that joined.
func TestThePairedEventCarriesNoCredentialAndNoKey(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	owner := dialWS(t, ts, srv)
	owner.expectGreeting()
	owner.greet(t, 1, dev, "")
	token := inviteFrom(t, owner, 2)

	joiner := newDevice(t)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, token, joiner.pub))
	c.expectOK(1)

	seq, name, data := owner.expectEvent()
	if name != protocol.EventDevicePaired || seq != 0 {
		t.Fatalf("event = %s/%d, want %s/0", name, seq, protocol.EventDevicePaired)
	}
	// Serialised back rather than inspected field by field: a field added later
	// under any name is caught, which is the whole point of asking this way.
	whole, err := json.Marshal(map[string]any{"seq": seq, "event": name, "data": data})
	if err != nil {
		t.Fatalf("marshal the event back: %v", err)
	}
	if strings.Contains(string(whole), token) {
		t.Fatalf("device.paired carries the spent token: %s", whole)
	}
	if strings.Contains(string(whole), joiner.pub) {
		t.Fatalf("device.paired carries the new device key: %s", whole)
	}
}

// The claim is the one pairing with nobody to tell: it is only allowed while no
// device exists, so there is no live connection of this person to find.
func TestClaimingAnEmptyServerAnnouncesToNobody(t *testing.T) {
	ts, srv := newTestServer(t)
	ctx := context.Background()
	if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := srv.store.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}

	first := newDevice(t)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, token, first.pub))

	frame := c.read()
	if _, isEvent := frame["event"]; isEvent {
		t.Fatalf("claiming an empty server produced an event: %v", frame)
	}
}

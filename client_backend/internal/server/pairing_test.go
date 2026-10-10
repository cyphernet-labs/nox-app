package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// FR-004 over the wire: the machine link creates the person when there is
// nobody, joins them - no naming step - when there is, and a spent link answers
// nobody else.
func TestTheMachineLinkCreatesThePersonThenJoinsThem(t *testing.T) {
	ts, srv := newTestServer(t)

	first := mustMachineLink(t, srv)
	_, data := pairDevice(t, ts, first)
	var created identity
	mustUnmarshal(t, data["identity"], &created)
	if !created.Created || created.ID == "" {
		t.Fatalf("identity = %+v, want a created person", created)
	}

	_, joined := pairDevice(t, ts, mustMachineLink(t, srv))
	var second identity
	mustUnmarshal(t, joined["identity"], &second)
	if second.ID != created.ID || second.Created {
		t.Fatalf("second device = %+v, want the same person %q and created=false", second, created.ID)
	}

	// The spent first link presented by a key that never used it.
	other := dialWS(t, ts, srv)
	other.expectGreeting()
	other.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, first))
	if code := expectErrCode(t, other, 1); code != protocol.ErrInvalidToken {
		t.Fatalf("a spent link = %q, want %q", code, protocol.ErrInvalidToken)
	}
}

// A device names itself by its OS family and nothing else: the name lands in
// the Allow dialog of the device that issued the invite, so free text there is
// a stolen invite's chance to pass itself off as anything. Refused before the
// token is looked at, so the refusal spends nothing.
func TestPairTakesOnlyAKnownPlatform(t *testing.T) {
	ts, srv := newTestServer(t)
	token := mustMachineLink(t, srv)
	for _, platform := range []string{"test", "iPhone of a friend", "IOS", "ios ios"} {
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":%q}}`, token, platform))
		if code := expectErrCode(t, c, 1); code != protocol.ErrInvalidRequest {
			t.Fatalf("platform %q = %q, want %q", platform, code, protocol.ErrInvalidRequest)
		}
	}
	// The link is still whole: a refused name took nothing from it.
	_, data := pairDevice(t, ts, token)
	var created identity
	mustUnmarshal(t, data["identity"], &created)
	if !created.Created {
		t.Fatalf("identity = %+v, want the person the unspent link creates", created)
	}
}

// The whole point of the phase, at its narrowest: a connection whose key
// nobody paired does not get in, whatever its greeting says.
func TestAGreetingFromAKeyNobodyPairedIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	t.Run("a key the server does not know", func(t *testing.T) {
		// Revoked, or a rebuilt store. The device cannot tell them apart and
		// must not: both mean "this is not my server any more".
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		c.send(`{"id":1,"cmd":"session.hello","data":{"schema":1}}`)
		if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
			t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
		}
	})

	t.Run("naming a paired key in the greeting borrows nothing", func(t *testing.T) {
		// What a pre-044 client sent, and what an impostor would send: the
		// key a connection speaks as is the one its channel proved, and a
		// field cannot lend it another.
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"session.hello","data":{"schema":1,"device_key":%q,"signature":"AAAA"}}`, dev.pub))
		if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
			t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
		}
	})

	t.Run("anything but pair before the greeting is still invalid_request", func(t *testing.T) {
		// Contract §3, unchanged by 044: the order of commands is checked
		// before who is asking. An unknown key learns nothing more from
		// trying a command than a known one does.
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		for i, cmd := range []string{"device.list", "chat.create", "file.uploadBegin"} {
			c.send(fmt.Sprintf(`{"id":%d,"cmd":%q,"data":{}}`, i+1, cmd))
			if code := expectErrCode(t, c, i+1); code != protocol.ErrInvalidRequest {
				t.Fatalf("%s before the greeting = %q, want %q", cmd, code, protocol.ErrInvalidRequest)
			}
		}
	})
}

// A paired device greets with the schema and nothing else: no key, no
// signature. The channel already said who it is.
func TestAPairedDeviceGreetsWithoutAKeyOrASignature(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, claimed := firstDevice(t, ts, srv)
	var owner identity
	mustUnmarshal(t, claimed["identity"], &owner)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.send(`{"id":1,"cmd":"session.hello","data":{"schema":1}}`)
	var greeted identity
	mustUnmarshal(t, c.expectOK(1)["identity"], &greeted)
	if greeted.ID != owner.ID {
		t.Fatalf("greeted as %q, want the person the pairing made, %q", greeted.ID, owner.ID)
	}
}

// The invite is the link a person carries to their second device, built from
// this machine's key and the token the reply names - and the token remembers
// which device issued it, the one that will be asked to allow it.
func TestAnInviteCarriesThisMachinesKeyAndItsToken(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
	invite := c.expectOKAfter(2, `{"id":2,"cmd":"device.invite","data":{}}`)
	var reply struct {
		Token string `json:"token"`
		Link  string `json:"link"`
	}
	mustUnmarshal(t, mustRaw(t, invite), &reply)
	if reply.Token == "" || reply.Link == "" {
		t.Fatalf("invite reply = %+v, want a token and a link to show", reply)
	}
	// The second device accepts only the channel that proves the key it finds
	// in the link. A link built from anything but this machine's key refuses
	// the very server that issued it.
	link, err := ParsePairingLink(reply.Link)
	if err != nil {
		t.Fatalf("the invite does not read back: %v", err)
	}
	if !link.ServerKey.Equal(serverKeyOf(t, srv)) {
		t.Fatalf("the invite carries %x, want this machine's key %x", link.ServerKey, serverKeyOf(t, srv))
	}
	if link.Token != reply.Token {
		t.Fatalf("the link carries token %q, the reply %q", link.Token, reply.Token)
	}
	var issuer string
	if err := readDB(t, srv).QueryRowContext(context.Background(),
		"SELECT issuer_key FROM pair_tokens WHERE token = ?", reply.Token).Scan(&issuer); err != nil {
		t.Fatalf("read the invite: %v", err)
	}
	if issuer != dev.pub {
		t.Fatalf("the invite remembers issuer %q, want the device that asked", issuer)
	}
}

func TestRevokeDropsTheLiveConnectionRatherThanWaiting(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")
	second, _ := pairDevice(t, ts, mustMachineLink(t, srv))

	// The device being revoked is live and idle, exactly like a sold tablet
	// left switched on.
	victim := dialAs(t, ts, srv, second)
	victim.expectGreeting()
	victim.hello(1, "")

	owner.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.revoke","data":{"device_key":%q}}`, second.pub))

	// It learns about it without having to try anything first.
	_, name, _ := victim.expectEvent()
	if name != protocol.EventDeviceRevoked {
		t.Fatalf("event = %s, want %s", name, protocol.EventDeviceRevoked)
	}

	// The revoked key still passes the channel - it proves a key, and the
	// check knows no list - and is refused by the greeting, which does.
	back := dialAs(t, ts, srv, second)
	back.expectGreeting()
	back.send(`{"id":1,"cmd":"session.hello","data":{"schema":1}}`)
	if code := expectErrCode(t, back, 1); code != protocol.ErrUnauthenticated {
		t.Fatalf("revoked device reconnected with code %q", code)
	}
}

func TestRevokingSomebodyElsesDeviceIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")

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
	dev, _ := firstDevice(t, ts, srv)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
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
	dev, _ := firstDevice(t, ts, srv)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
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
	back := dialAs(t, ts, srv, dev)
	back.expectGreeting()
	var id identity
	mustUnmarshal(t, back.hello(1, "")["identity"], &id)
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
	dev, _ := firstDevice(t, ts, srv)

	first := dialAs(t, ts, srv, dev)
	first.expectGreeting()
	first.hello(1, "")
	secondKey, _ := pairDevice(t, ts, mustMachineLink(t, srv))

	second := dialAs(t, ts, srv, secondKey)
	second.expectGreeting()
	second.hello(1, "")

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

// The machine never names an owner on the wire (FR-017). It has no reason to:
// there is one person here, so "who owns this" answers nothing a device could
// act on - and a field carrying an id would have to be explained, and
// honoured, later.
func TestNoOwnerReachesTheWire(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, claimed := firstDevice(t, ts, srv)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	greeting := c.hello(1, "")

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

// US3 / SC-003 end to end: every device gone, the page offers a machine link
// at once, and it pairs a new device to the SAME person - the same id, no
// naming step, and the whole conversation.
func TestAMachineLinkBringsTheWholeConversationBackAfterEveryDeviceIsGone(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, paired := firstDevice(t, ts, srv)
	var before identity
	mustUnmarshal(t, paired["identity"], &before)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
	chatID := seedChat(t, c, "kept")
	sendText(t, c, 3, chatID, "m-1", "the boiler is leaking")
	// Signing out of the only device is revoking its own key.
	c.expectOKAfter(4, fmt.Sprintf(`{"id":4,"cmd":"device.revoke","data":{"device_key":%q}}`, dev.pub))

	back, reclaimed := pairDevice(t, ts, linkTokenOnPage(t, srv))
	var after identity
	mustUnmarshal(t, reclaimed["identity"], &after)
	if after.ID != before.ID || after.Created {
		t.Fatalf("came back as %+v, want %q with no naming step", after, before.ID)
	}

	nc := dialAs(t, ts, srv, back)
	nc.expectGreeting()
	nc.hello(1, "")
	page := nc.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"messages.list","data":{"chat_id":%q,"limit":10}}`, chatID))
	var listed []protocol.Message
	mustUnmarshal(t, page["messages"], &listed)
	if len(listed) != 1 || listed[0].AuthorID != before.ID {
		t.Fatalf("history after coming back = %+v, want the message, as the person's own", listed)
	}
}

// T012: while devices exist the page hands out no link until `Add a device`;
// the device that pairs with it joins the same person without any Allow; and
// from it the person revokes the device they lost - whose connection is cut at
// once, not when it next tries.
func TestAddADeviceJoinsWithoutAllowAndTheLostOneIsCutOff(t *testing.T) {
	ts, srv := newTestServer(t)
	lost, paired := firstDevice(t, ts, srv)
	var person identity
	mustUnmarshal(t, paired["identity"], &person)

	thief := dialAs(t, ts, srv, lost)
	thief.expectGreeting()
	thief.hello(1, "")

	if body := statusBody(t, srv); strings.Contains(body, "nox://pair/") || !strings.Contains(body, "Add a device") {
		t.Fatalf("with a device paired the page shows a link before anybody asked: %s", body)
	}
	if rec := postLink(t, srv, pageHost, pageOrigin, url.Values{"token": {srv.formToken}}); rec.Code != http.StatusSeeOther {
		t.Fatalf("Add a device = %d", rec.Code)
	}
	fresh, joined := pairDevice(t, ts, linkTokenOnPage(t, srv))
	var got identity
	mustUnmarshal(t, joined["identity"], &got)
	if got.ID != person.ID || got.Created {
		t.Fatalf("the new device = %+v, want the same person and no naming step", got)
	}
	// The lost device hears about the new one - then that it is revoked.
	if _, name, _ := thief.expectEvent(); name != protocol.EventDevicePaired {
		t.Fatalf("the lost device got %s, want %s", name, protocol.EventDevicePaired)
	}

	nc := dialAs(t, ts, srv, fresh)
	nc.expectGreeting()
	nc.hello(1, "")
	nc.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, lost.pub))
	if _, name, _ := thief.expectEvent(); name != protocol.EventDeviceRevoked {
		t.Fatalf("the lost device got %s, want %s", name, protocol.EventDeviceRevoked)
	}
	waitClosed(t, thief, websocket.StatusNormalClosure)
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
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")
	token := mustMachineLink(t, srv)

	// Kept open, unlike pairDevice's connection: what this one does NOT receive
	// is half the assertion.
	joiner := newDevice(t)
	c := dialAs(t, ts, srv, joiner)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))

	// Raw frames, not expectReply: that helper SKIPS events, which is exactly
	// the mistake being looked for here. The reply comes first (the fan-out
	// runs after it), and then nothing at all.
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

	// Last, because it spends the connection: the owner has its event by now,
	// so anything still on its way to the joiner would have arrived.
	c.expectNoFrame(300 * time.Millisecond)
}

// The event is addressed to the connections of ONE PERSON, and the filter that
// does that is the only thing keeping it off a connection that has not said who
// it is - the pairing screen of some other install, dialled in and waiting.
//
// Worth its own test because the exclusion of the joining connection hides it:
// a fan-out to EVERYONE except the sender passes every other test in this file.
func TestThePairedEventGoesOnlyToConnectionsOfThisPerson(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")
	token := mustMachineLink(t, srv)

	// Dialled, greeted BY the server, and silent ever since: identity.UserID is
	// empty, so it belongs to nobody and must hear nothing.
	bystander := dialWS(t, ts, srv)
	bystander.expectGreeting()

	joiner := newDevice(t)
	c := dialAs(t, ts, srv, joiner)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))
	c.expectOK(1)

	// The owner first: it proves the fan-out ran at all, so the silence below
	// is a filter doing its job rather than an event that never happened.
	seq, name, _ := owner.expectEvent()
	if name != protocol.EventDevicePaired || seq != 0 {
		t.Fatalf("event = %s/%d, want %s/0", name, seq, protocol.EventDevicePaired)
	}
	bystander.expectNoFrame(300 * time.Millisecond)
}

// The answer to `pair` must not be able to queue behind a stranger's backlog.
//
// A connection with a full write queue and a live context is not a contrivance:
// it is where a slow consumer sits while its drop finishes the close handshake,
// and send() waits there until the context is cancelled. Announcing before
// replying puts the joining device's answer behind that wait - on a command
// that has already burned a one-shot token and written the device row, so the
// client times out on work the server has committed.
func TestTheJoiningDeviceIsAnsweredEvenWhileAnotherConnectionIsWedged(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")
	token := mustMachineLink(t, srv)

	wedged := stubClient(t, srv, personOn(t, srv), 1)
	wedged.out <- []byte("{}") // full from here on

	joiner := newDevice(t)
	c := dialAs(t, ts, srv, joiner)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))
	// Fails by timing out rather than by comparing anything: with the fan-out
	// first, this reply is behind a queue nobody is draining.
	c.expectOK(1)
}

// The same for a rename, which fans out through the same helper and had the
// same defect until this was written: `identity.setLabel` told the other
// devices BEFORE answering the one that asked.
func TestTheRenamingDeviceIsAnsweredEvenWhileAnotherConnectionIsWedged(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")

	wedged := stubClient(t, srv, personOn(t, srv), 1)
	wedged.out <- []byte("{}")

	owner.send(`{"id":2,"cmd":"identity.setLabel","data":{"label":"Nyx"}}`)
	owner.expectOK(2)
}

// The third fan-out, and the one that set the order the other two now follow.
//
// It had no test of its own: moving `dropDevice` above the reply passes the
// whole package, because the only connection it usually reaches is the caller's
// own and an empty queue swallows the difference. Give the revoked key a wedged
// connection and the defect is plain - `device.revoked` blocks on it, and the
// OK for a revocation the store has already applied never leaves.
func TestTheRevokingDeviceIsAnsweredEvenWhileTheRevokedOneIsWedged(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")
	token := mustMachineLink(t, srv)

	joiner := newDevice(t)
	pairing := dialAs(t, ts, srv, joiner)
	pairing.expectGreeting()
	pairing.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))
	pairing.expectOK(1)
	// The owner is told about the pairing; read it so the assertion below is
	// about the revoke and nothing else.
	owner.expectEvent()

	// The joined device, as a connection nobody is draining.
	wedged := stubClientWithKey(t, srv, personOn(t, srv), joiner.pub, 1)
	wedged.out <- []byte("{}")

	owner.send(fmt.Sprintf(`{"id":3,"cmd":"device.revoke","data":{"device_key":%q}}`, joiner.pub))
	owner.expectOK(3)
}

// The exclusion of the connection the pairing came from, asked directly.
//
// It cannot be asked through a socket: a device that is pairing has not greeted
// and therefore has no identity to match on, so the person filter excludes it
// anyway and the term is invisible from outside. It is still live - a greeting
// that fails on the journal id or the cursor leaves the identity written and
// `helloDone` false, and `pair` is still admitted on such a connection - so it
// is asked of the helper itself, with the registry entries built by hand.
func TestTheAnnouncementSkipsTheConnectionItCameFrom(t *testing.T) {
	_, srv := newTestServer(t)
	origin := stubClient(t, srv, "u_someone", 4)
	other := stubClient(t, srv, "u_someone", 4)
	stranger := stubClient(t, srv, "u_else", 4)

	origin.announcePaired("u_someone")

	if len(origin.out) != 0 {
		t.Fatal("the connection the pairing came from was told about its own pairing")
	}
	if len(other.out) != 1 {
		t.Fatalf("the other connection of this person got %d frames, want 1", len(other.out))
	}
	if len(stranger.out) != 0 {
		t.Fatal("a connection of somebody else was told")
	}
}

// stubClient is a registry entry and nothing else: no socket, no read
// goroutine, just a queue to look into afterwards. It is how a test asks what
// the fan-out DID rather than what a device saw.
//
// It carries a real logger and is removed from the registry on cleanup, and the
// ORDER of that cleanup is what keeps it safe: stubClient is called after
// newTestServer, so its t.Cleanup runs before the one that closes the stack.
// CloseConnections would dereference the nil conn - a test that calls it
// directly, or a stack that learns to shut down through Config.Shutdown, needs
// this entry gone first.
func stubClient(t *testing.T, srv *Server, userID string, queue int) *client {
	t.Helper()
	return stubClientWithKey(t, srv, userID, "", queue)
}

// stubClientWithKey is stubClient for the fan-out that matches on the DEVICE
// key rather than on the person: dropDevice looks for the connections holding
// one key and closes them.
func stubClientWithKey(t *testing.T, srv *Server, userID, deviceKey string, queue int) *client {
	t.Helper()
	c := &client{
		srv:       srv,
		logger:    slog.New(slog.NewTextHandler(io.Discard, nil)),
		out:       make(chan []byte, queue),
		identity:  store.Identity{UserID: userID},
		deviceKey: deviceKey,
	}
	c.ctx, c.cancel = context.WithCancel(context.Background())
	srv.mu.Lock()
	srv.conns[c] = struct{}{}
	srv.mu.Unlock()
	t.Cleanup(func() {
		srv.mu.Lock()
		delete(srv.conns, c)
		srv.mu.Unlock()
		c.cancel()
	})
	return c
}

// personOn returns the id of the one person a greeted connection speaks as.
func personOn(t *testing.T, srv *Server) string {
	t.Helper()
	srv.mu.Lock()
	defer srv.mu.Unlock()
	for c := range srv.conns {
		if c.identity.UserID != "" {
			return c.identity.UserID
		}
	}
	t.Fatal("no greeted connection, so there is no person to build a second connection for")
	return ""
}

// Principle I on a frame nobody thinks to look at: the event must not carry the
// token that was just spent or the key of the device that joined.
func TestThePairedEventCarriesNoCredentialAndNoKey(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := firstDevice(t, ts, srv)

	owner := dialAs(t, ts, srv, dev)
	owner.expectGreeting()
	owner.hello(1, "")
	token := mustMachineLink(t, srv)

	joiner := newDevice(t)
	c := dialAs(t, ts, srv, joiner)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))
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

// The first device is the one pairing with nobody to tell: no device of the
// person exists, so there is no connection of theirs to find - and a stranger's
// connection that merely dialled in hears nothing either.
func TestTheFirstDeviceAnnouncesToNobody(t *testing.T) {
	ts, srv := newTestServer(t)
	token := mustMachineLink(t, srv)

	// A second connection that is simply there. Without it this test watches
	// only the pairing connection, which every version of the fan-out excludes
	// anyway - so it would assert nothing at all.
	bystander := dialWS(t, ts, srv)
	bystander.expectGreeting()

	first := newDevice(t)
	c := dialAs(t, ts, srv, first)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))

	frame := c.read()
	if _, isEvent := frame["event"]; isEvent {
		t.Fatalf("pairing the first device produced an event: %v", frame)
	}
	bystander.expectNoFrame(300 * time.Millisecond)
}

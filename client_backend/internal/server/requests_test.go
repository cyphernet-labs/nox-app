package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/protocol"
)

// Pairing with approval over the wire (046, contract §8A). The property under
// every test here is SC-002: an invite adds no device without Allow on the
// device that issued it.

// pendingReply is pair's answer for an invite.
type pendingReply struct {
	Status    string `json:"status"`
	RequestID string `json:"request_id"`
	ExpiresAt int64  `json:"expires_at"`
}

// issuerSetup pairs the first device, greets it, and has it issue an invite.
// It returns the issuing device's connection and the invite's token.
func issuerSetup(t *testing.T, ts *httptest.Server, srv *Server) (*device, *wsClient, string) {
	t.Helper()
	dev, _ := firstDevice(t, ts, srv)
	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
	return dev, c, inviteFrom(t, c, 2)
}

// presentInvite dials as d, presents token, and returns the connection - kept
// open, it is where the outcome arrives - and pair's answer.
func presentInvite(t *testing.T, ts *httptest.Server, srv *Server, d *device, token string) (*wsClient, pendingReply) {
	t.Helper()
	c := dialAs(t, ts, srv, d)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"windows"}}`, token))
	data := c.expectOK(1)
	if _, paired := data["identity"]; paired {
		t.Fatalf("an invite paired the device at once: %v", data)
	}
	var got pendingReply
	mustUnmarshal(t, mustRaw(t, data), &got)
	return c, got
}

// expectNamedEvent reads frames until an event arrives, and insists on its
// name and on seq 0: every pairing event is off-journal.
func expectNamedEvent(t *testing.T, c *wsClient, name string) map[string]json.RawMessage {
	t.Helper()
	seq, got, data := c.expectEvent()
	if got != name || seq != 0 {
		t.Fatalf("event = %s/%d, want %s/0", got, seq, name)
	}
	return data
}

// paired reports whether the key is a paired device now.
func paired(t *testing.T, srv *Server, d *device) bool {
	t.Helper()
	_, found, err := srv.store.DeviceOwner(context.Background(), d.pub)
	if err != nil {
		t.Fatalf("DeviceOwner: %v", err)
	}
	return found
}

// The whole of US1, frame by frame: the new device waits, the issuer is asked
// with the new device's OS family, Allow answers first and tells everybody
// after - the new device with its identity, the issuer that the request is
// over, the person's devices that the list changed - and the new device greets
// as the person, with no naming step.
func TestAnInviteWaitsForAllowAndThenJoinsThePerson(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	person := personOn(t, srv)

	newcomer := newDevice(t)
	waiting, pending := presentInvite(t, ts, srv, newcomer, token)
	if pending.Status != "pending" || !regexp.MustCompile(`^r_[0-9a-f]{16}$`).MatchString(pending.RequestID) {
		t.Fatalf("pair = %+v, want pending with an r_ request id", pending)
	}
	if left := pending.ExpiresAt - time.Now().Unix(); left < 590 || left > 600 {
		t.Fatalf("expires_at is %d s away, want the invite's ten minutes", left)
	}
	if paired(t, srv, newcomer) {
		t.Fatal("SC-002: the device was paired before Allow")
	}

	asked := expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)
	var request pairRequestedData
	mustUnmarshal(t, mustRaw(t, asked), &request)
	if request != (pairRequestedData{RequestID: pending.RequestID, Platform: "windows", ExpiresAt: pending.ExpiresAt}) {
		t.Fatalf("device.pairRequested = %+v, want the request %+v from windows", request, pending)
	}

	issuer.send(fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	// The answer first, the fan-out after it (§9): read raw, because the
	// helpers skip events and the order is what is being asked.
	first := issuer.read()
	if _, isEvent := first["event"]; isEvent {
		t.Fatalf("the issuer heard %v before the answer to its own command", first)
	}
	var ok bool
	mustUnmarshal(t, first["ok"], &ok)
	if !ok {
		t.Fatalf("Allow refused: %s", rawString(first["error"]))
	}
	closed := expectNamedEvent(t, issuer, protocol.EventDevicePairResolved)
	var over devicePairResolvedData
	mustUnmarshal(t, mustRaw(t, closed), &over)
	if over.RequestID != pending.RequestID {
		t.Fatalf("device.pairResolved names %q, want %q", over.RequestID, pending.RequestID)
	}
	expectNamedEvent(t, issuer, protocol.EventDevicePaired)

	resolved := expectNamedEvent(t, waiting, protocol.EventPairResolved)
	var outcome struct {
		Outcome  string    `json:"outcome"`
		Identity *identity `json:"identity"`
	}
	mustUnmarshal(t, mustRaw(t, resolved), &outcome)
	if outcome.Outcome != "allowed" || outcome.Identity == nil || outcome.Identity.ID != person || outcome.Identity.Created {
		t.Fatalf("pair.resolved = %+v, want allowed into %q with created=false", outcome, person)
	}
	if !strings.Contains(string(resolved["identity"]), `"created":false`) {
		t.Fatalf("pair.resolved dropped created=false: %s", resolved["identity"])
	}
	// It greets on the very connection it waited on.
	var greeted identity
	mustUnmarshal(t, waiting.hello(2, "")["identity"], &greeted)
	if greeted.ID != person {
		t.Fatalf("the allowed device greets as %q, want %q", greeted.ID, person)
	}
}

// Deny: the new device is told, the issuer's dialog closes, nothing is paired,
// and a repeat of `pair` answers with the outcome - the reliable half of an
// event that does not survive a disconnect.
func TestDenyTellsBothSidesAndPairsNothing(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	newcomer := newDevice(t)
	waiting, pending := presentInvite(t, ts, srv, newcomer, token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":false}}`, pending.RequestID))
	expectNamedEvent(t, issuer, protocol.EventDevicePairResolved)
	data := expectNamedEvent(t, waiting, protocol.EventPairResolved)
	if string(data["outcome"]) != `"denied"` || data["identity"] != nil {
		t.Fatalf("pair.resolved = %v, want denied and no identity", data)
	}
	if paired(t, srv, newcomer) {
		t.Fatal("SC-002: a denied device was paired")
	}

	again, repeat := presentInvite(t, ts, srv, newcomer, token)
	if repeat.Status != "denied" || repeat.RequestID != pending.RequestID {
		t.Fatalf("a repeat after Deny = %+v, want the denied request %s", repeat, pending.RequestID)
	}
	again.send(`{"id":2,"cmd":"session.hello","data":{"schema":1}}`)
	again.expectErr(2, protocol.ErrUnauthenticated)
}

// FR-007: nobody answers, and the request ends on its own when the invite's
// ten minutes run out - both sides told, nothing paired, and the expiry is what
// a repeat of `pair` says from then on.
func TestARequestNobodyAnswersEndsOnItsOwn(t *testing.T) {
	ts, srv := newTestServer(t)
	issuerKey, issuer, _ := issuerSetup(t, ts, srv)
	// Issued almost ten minutes ago, as far as the deadline goes: two seconds
	// are left, which is time to present it and not much more.
	token, err := srv.store.IssueDeviceInvite(context.Background(), issuerKey.pub, time.Now().Unix()-598)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	newcomer := newDevice(t)
	waiting, pending := presentInvite(t, ts, srv, newcomer, token)
	if pending.Status != "pending" {
		t.Fatalf("pair = %+v, want pending", pending)
	}
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	data := expectNamedEvent(t, waiting, protocol.EventPairResolved)
	if string(data["outcome"]) != `"expired"` {
		t.Fatalf("pair.resolved = %v, want expired", data)
	}
	expectNamedEvent(t, issuer, protocol.EventDevicePairResolved)
	if paired(t, srv, newcomer) {
		t.Fatal("SC-002: an expired request paired the device")
	}
	_, repeat := presentInvite(t, ts, srv, newcomer, token)
	if repeat.Status != "expired" {
		t.Fatalf("a repeat after expiry = %+v, want expired", repeat)
	}
	issuer.send(fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	issuer.expectErr(3, protocol.ErrNotFound)
}

// FR-010: the new device withdraws its request - before it could ever greet -
// and both sides hear it is over; an Allow pressed afterwards does nothing.
func TestCancelEndsTheRequestOnBothSides(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	newcomer := newDevice(t)
	waiting, pending := presentInvite(t, ts, srv, newcomer, token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	waiting.send(fmt.Sprintf(`{"id":2,"cmd":"pair.cancel","data":{"token":%q}}`, token))
	reply := waiting.read()
	if _, isEvent := reply["event"]; isEvent {
		t.Fatalf("the cancelling device heard %v before its answer", reply)
	}
	var answered struct {
		ID int  `json:"id"`
		OK bool `json:"ok"`
	}
	mustUnmarshal(t, mustRaw(t, reply), &answered)
	if answered.ID != 2 || !answered.OK {
		t.Fatalf("pair.cancel = %v, want ok", reply)
	}
	data := expectNamedEvent(t, waiting, protocol.EventPairResolved)
	if string(data["outcome"]) != `"cancelled"` {
		t.Fatalf("pair.resolved = %v, want cancelled", data)
	}
	expectNamedEvent(t, issuer, protocol.EventDevicePairResolved)

	// Idempotent: nothing waits for this key any more, and the answer is the same.
	waiting.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"pair.cancel","data":{"token":%q}}`, token))
	issuer.send(fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	issuer.expectErr(3, protocol.ErrNotFound)
	if paired(t, srv, newcomer) {
		t.Fatal("SC-002: a cancelled request paired the device")
	}
}

// FR-011: the same key presenting the same invite again - after a dropped
// connection, a restart - gets the same request, and the issuer is not asked a
// second time. After Allow the repeat answers with the identity.
func TestARepeatOfPairFindsTheSameRequest(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	person := personOn(t, srv)
	newcomer := newDevice(t)
	first, pending := presentInvite(t, ts, srv, newcomer, token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)
	_ = first.conn.CloseNow()

	_, again := presentInvite(t, ts, srv, newcomer, token)
	if again != pending {
		t.Fatalf("the repeat = %+v, want the same request %+v", again, pending)
	}
	// Room for a second device.pairRequested to land, had the repeat asked
	// again: it would then be the first frame the issuer reads below.
	time.Sleep(200 * time.Millisecond)
	issuer.send(fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	if first := issuer.read(); first["event"] != nil {
		t.Fatalf("the repeat asked the issuer again: %v", first)
	}
	expectNamedEvent(t, issuer, protocol.EventDevicePairResolved)

	c := dialAs(t, ts, srv, newcomer)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"windows"}}`, token))
	var id identity
	mustUnmarshal(t, c.expectOK(1)["identity"], &id)
	if id.ID != person || id.Created {
		t.Fatalf("a repeat after Allow = %+v, want the identity, created=false", id)
	}
}

// An invite has one request: a second device presenting the same QR code is
// told it was used, and the issuer is not asked about it.
func TestASecondDeviceWithTheSameInviteIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	presentInvite(t, ts, srv, newDevice(t), token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	other := dialWS(t, ts, srv)
	other.expectGreeting()
	other.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"ios"}}`, token))
	other.expectErr(1, protocol.ErrInvalidToken)
	issuer.expectNoFrame(300 * time.Millisecond)
}

// A revoked issuer can answer nothing: the device waiting on it is told its
// request was declined, and the issuer's unpresented invites die with it.
func TestRevokingTheIssuerDeclinesTheWaitingDevice(t *testing.T) {
	ts, srv := newTestServer(t)
	issuerKey, issuer, token := issuerSetup(t, ts, srv)
	spare := inviteFrom(t, issuer, 3)
	newcomer := newDevice(t)
	waiting, _ := presentInvite(t, ts, srv, newcomer, token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	// Another device of the person revokes the issuer.
	laptop := pairedDevice(t, ts, srv)
	lc := dialAs(t, ts, srv, laptop)
	lc.expectGreeting()
	lc.hello(1, "")
	lc.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, issuerKey.pub))

	data := expectNamedEvent(t, waiting, protocol.EventPairResolved)
	if string(data["outcome"]) != `"denied"` {
		t.Fatalf("pair.resolved = %v, want denied", data)
	}
	if paired(t, srv, newcomer) {
		t.Fatal("SC-002: revoking the issuer paired the device")
	}
	other := dialWS(t, ts, srv)
	other.expectGreeting()
	other.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"ios"}}`, spare))
	other.expectErr(1, protocol.ErrInvalidToken)
}

// device.approve's refusals: a request that is not there, not this device's,
// or no longer waiting is not_found - one answer, so a device learns nothing
// about requests that are not its own - a missing field is invalid_request,
// and a device revoked while its answer was on the way is unauthenticated.
func TestDeviceApproveRefusals(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	_, pending := presentInvite(t, ts, srv, newDevice(t), token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	for i, tc := range []struct {
		data string
		code string
	}{
		{`{"request_id":"r_0000000000000000","allow":true}`, protocol.ErrNotFound},
		{`{"request_id":"` + pending.RequestID + `"}`, protocol.ErrInvalidRequest},
		{`{"allow":true}`, protocol.ErrInvalidRequest},
		{`[]`, protocol.ErrInvalidRequest},
	} {
		issuer.send(fmt.Sprintf(`{"id":%d,"cmd":"device.approve","data":%s}`, 10+i, tc.data))
		issuer.expectErr(10+i, tc.code)
	}

	// Another device of the same person - not the one the request asks.
	other := pairedDevice(t, ts, srv)
	oc := dialAs(t, ts, srv, other)
	oc.expectGreeting()
	oc.hello(1, "")
	oc.send(fmt.Sprintf(`{"id":2,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	oc.expectErr(2, protocol.ErrNotFound)

	// Before a greeting the command is not even looked at.
	early := dialWS(t, ts, srv)
	early.expectGreeting()
	early.send(fmt.Sprintf(`{"id":1,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	early.expectErr(1, protocol.ErrInvalidRequest)

	// Answered once, it is not waiting any more.
	issuer.expectOKAfter(20, fmt.Sprintf(`{"id":20,"cmd":"device.approve","data":{"request_id":%q,"allow":false}}`, pending.RequestID))
	issuer.send(fmt.Sprintf(`{"id":21,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	issuer.expectErr(21, protocol.ErrNotFound)

	// A device revoked from elsewhere while its socket is still open.
	_, second := presentInvite(t, ts, srv, newDevice(t), inviteFrom(t, oc, 3))
	if _, err := srv.store.RevokeDevice(context.Background(), other.pub, time.Now().Unix()); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	oc.send(fmt.Sprintf(`{"id":4,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, second.RequestID))
	oc.expectErr(4, protocol.ErrUnauthenticated)
}

// device.pairRequested does not survive a disconnect, so a greeting re-sends
// every request still waiting for the device's answer: one whose app was
// closed is asked the moment it is back. Another device of the same person is
// not the one asked, and hears nothing.
func TestAGreetingReSendsTheRequestsStillWaiting(t *testing.T) {
	ts, srv := newTestServer(t)
	issuerKey, issuer, token := issuerSetup(t, ts, srv)
	_ = issuer.conn.CloseNow()

	_, pending := presentInvite(t, ts, srv, newDevice(t), token)

	other := pairedDevice(t, ts, srv)
	oc := dialAs(t, ts, srv, other)
	oc.expectGreeting()
	oc.hello(1, "")

	back := dialAs(t, ts, srv, issuerKey)
	back.expectGreeting()
	back.hello(1, "")
	data := expectNamedEvent(t, back, protocol.EventDevicePairRequested)
	var request pairRequestedData
	mustUnmarshal(t, mustRaw(t, data), &request)
	if request.RequestID != pending.RequestID || request.Platform != "windows" {
		t.Fatalf("the re-sent request = %+v, want %s from windows", request, pending.RequestID)
	}
	oc.expectNoFrame(300 * time.Millisecond)
}

// Each event reaches its own devices and nobody else: the request goes to the
// issuing device only - not to the person's other devices, not to a stranger's
// connection - and the outcome to the waiting device only.
func TestPairingEventsReachOnlyTheirDevices(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	other := pairedDevice(t, ts, srv)
	expectNamedEvent(t, issuer, protocol.EventDevicePaired) // the other device joining
	oc := dialAs(t, ts, srv, other)
	oc.expectGreeting()
	oc.hello(1, "")
	bystander := dialWS(t, ts, srv)
	bystander.expectGreeting()

	waiting, pending := presentInvite(t, ts, srv, newDevice(t), token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)
	issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":false}}`, pending.RequestID))
	expectNamedEvent(t, issuer, protocol.EventDevicePairResolved)
	expectNamedEvent(t, waiting, protocol.EventPairResolved)

	// Denied, so nobody's device list changed either: the other device of the
	// person and the stranger hear nothing at all.
	oc.expectNoFrame(300 * time.Millisecond)
	bystander.expectNoFrame(300 * time.Millisecond)
}

// Principle I on the frames nobody thinks to look at: none of the pairing
// events carries the invite's token or a device key.
func TestPairingEventsCarryNoKeyAndNoToken(t *testing.T) {
	ts, srv := newTestServer(t)
	issuerKey, issuer, token := issuerSetup(t, ts, srv)
	newcomer := newDevice(t)
	waiting, pending := presentInvite(t, ts, srv, newcomer, token)

	var frames []map[string]json.RawMessage
	frames = append(frames, expectNamedEvent(t, issuer, protocol.EventDevicePairRequested))
	issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	frames = append(frames,
		expectNamedEvent(t, issuer, protocol.EventDevicePairResolved),
		expectNamedEvent(t, issuer, protocol.EventDevicePaired),
		expectNamedEvent(t, waiting, protocol.EventPairResolved))
	for _, data := range frames {
		whole, err := json.Marshal(data)
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		for _, secret := range []string{token, newcomer.pub, issuerKey.pub} {
			if strings.Contains(string(whole), secret) {
				t.Fatalf("a pairing event carries %q: %s", secret, whole)
			}
		}
	}
}

// The answer to device.approve must not queue behind a stranger's backlog: a
// connection of the person with a full queue is where a slow consumer sits
// while its drop finishes, and device.paired goes there after the answer.
func TestTheApprovingDeviceIsAnsweredEvenWhileAnotherConnectionIsWedged(t *testing.T) {
	ts, srv := newTestServer(t)
	_, issuer, token := issuerSetup(t, ts, srv)
	_, pending := presentInvite(t, ts, srv, newDevice(t), token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	wedged := stubClient(t, srv, personOn(t, srv), 1)
	wedged.out <- []byte("{}") // full from here on

	issuer.send(fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	// Fails by timing out: with the fan-out first, this answer would sit behind
	// a queue nobody drains.
	issuer.expectOK(3)
}

// pair.cancel is the second command a device that has not greeted may send -
// it is waiting for Allow, it cannot greet - and it is refused nothing for an
// unknown token: nothing waits, and that is the state it asked for.
func TestPairCancelNeedsNoGreeting(t *testing.T) {
	ts, srv := newTestServer(t)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.expectOKAfter(1, `{"id":1,"cmd":"pair.cancel","data":{"token":"AAAAAAAAAAAAAAAAAAAAAA"}}`)
	c.send(`{"id":2,"cmd":"pair.cancel","data":{}}`)
	c.expectErr(2, protocol.ErrInvalidRequest)
	c.send(`{"id":3,"cmd":"device.list","data":{}}`)
	c.expectErr(3, protocol.ErrInvalidRequest)
}

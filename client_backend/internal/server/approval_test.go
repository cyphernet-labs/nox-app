package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// ownerSession claims the server and returns a greeted connection for the
// owner, plus their device.
func ownerSession(t *testing.T, ts *httptest.Server, srv *Server) (*wsClient, *device) {
	t.Helper()
	dev, _ := claimDevice(t, ts, srv)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")
	return c, dev
}

// personInvite asks for a person invite on an owner connection and returns the
// link's token.
func personInvite(t *testing.T, c *wsClient, id int) string {
	t.Helper()
	c.send(fmt.Sprintf(`{"id":%d,"cmd":"person.invite","data":{}}`, id))
	data := c.expectOK(id)
	var token string
	mustUnmarshal(t, data["token"], &token)
	if token == "" {
		t.Fatal("person.invite returned no token")
	}
	return token
}

// presentInvite offers a token on a fresh unauthenticated connection - the one
// command allowed before a greeting - and returns the connection and the
// request id it is now waiting on.
func presentInvite(t *testing.T, ts *httptest.Server, token string, d *device) (*wsClient, string) {
	t.Helper()
	c := dialWS(t, ts, nil)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"ios"}}`, token, d.pub))
	data := c.expectOK(1)

	var status string
	mustUnmarshal(t, data["status"], &status)
	if status != pairStatusPending {
		t.Fatalf("status = %q, want %q", status, pairStatusPending)
	}
	if _, ok := data["identity"]; ok {
		t.Fatalf("a pending reply carried an identity: %v", data)
	}
	var requestID string
	mustUnmarshal(t, data["request_id"], &requestID)
	return c, requestID
}

func TestAPersonInviteWaitsForTheOwnerAndThenLetsSomebodyIn(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, _ := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)

	// The owner is asked, and told nothing about who is knocking.
	seq, name, data := owner.expectEvent()
	if seq != 0 || name != protocol.EventPairRequested {
		t.Fatalf("event = (%d, %q), want (0, %q)", seq, name, protocol.EventPairRequested)
	}
	for field := range data {
		switch field {
		case "request_id", "invited_at", "expires_at":
		default:
			t.Fatalf("person.pairRequested carried %q; the server knows nothing else about the invitee", field)
		}
	}
	var announced string
	mustUnmarshal(t, data["request_id"], &announced)
	if announced != requestID {
		t.Fatalf("announced request %q, waiting on %q", announced, requestID)
	}
	raw, err := json.Marshal(data)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(raw), token) {
		t.Fatalf("the invite token rode out to the owner: %s", raw)
	}

	// The owner says yes.
	owner.send(fmt.Sprintf(`{"id":3,"cmd":"person.confirm","data":{"request_id":%q,"approve":true}}`, requestID))
	confirmed := owner.expectOK(3)
	var outcome string
	mustUnmarshal(t, confirmed["outcome"], &outcome)
	if outcome != store.OutcomeApproved {
		t.Fatalf("outcome = %q, want %q", outcome, store.OutcomeApproved)
	}

	// The waiting device learns who it now is.
	_, name, resolved := guest.expectEvent()
	if name != protocol.EventPairResolved {
		t.Fatalf("event = %q, want %q", name, protocol.EventPairResolved)
	}
	var got struct {
		RequestID string    `json:"request_id"`
		Outcome   string    `json:"outcome"`
		Identity  *identity `json:"identity"`
	}
	mustUnmarshal(t, mustJSONRaw(t, resolved), &got)
	if got.RequestID != requestID || got.Outcome != store.OutcomeApproved {
		t.Fatalf("resolved = %+v, want approved for %q", got, requestID)
	}
	if got.Identity == nil || got.Identity.ID == "" {
		t.Fatalf("resolved carried no identity: %+v", got)
	}
	if !got.Identity.Created {
		t.Fatal("created = false: a person invite always brings somebody into being")
	}
	if got.Identity.Owner {
		t.Fatal("the invited person owns the server")
	}

	// And the circle now has two people, one of them the owner.
	owner.send(`{"id":4,"cmd":"person.list","data":{}}`)
	listed := owner.expectOK(4)
	var people []store.Person
	mustUnmarshal(t, listed["people"], &people)
	if len(people) != 2 {
		t.Fatalf("people = %+v, want two", people)
	}
	owners := 0
	for _, p := range people {
		if p.Owner {
			owners++
		}
	}
	if owners != 1 {
		t.Fatalf("owner marks = %d, want one", owners)
	}
}

func TestOnlyTheOwnerIsOfferedAPersonInviteOnTheWire(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, _ := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()
	owner.send(fmt.Sprintf(`{"id":3,"cmd":"person.confirm","data":{"request_id":%q,"approve":true}}`, requestID))
	owner.expectOK(3)
	guest.expectEvent()
	_ = guest.conn.Close(websocket.StatusNormalClosure, "")

	// The person who just joined greets on their own connection and asks for an
	// invite. The refusal has to be its own code: nothing is wrong with their
	// link, their network or their app, and repeating will not help.
	joined := dialWS(t, ts, srv)
	joined.expectGreeting()
	joined.greet(t, 1, guestDev, "")
	joined.send(`{"id":2,"cmd":"person.invite","data":{}}`)
	if code := expectErrCode(t, joined, 2); code != protocol.ErrNotOwner {
		t.Fatalf("code = %q, want %q", code, protocol.ErrNotOwner)
	}
	// And cannot answer a question that is not theirs.
	joined.send(`{"id":3,"cmd":"person.confirm","data":{"request_id":"r_whatever","approve":true}}`)
	if code := expectErrCode(t, joined, 3); code != protocol.ErrNotOwner {
		t.Fatalf("confirm code = %q, want %q", code, protocol.ErrNotOwner)
	}
	// The circle itself is not secret: names ride every message already.
	joined.send(`{"id":4,"cmd":"person.list","data":{}}`)
	joined.expectOK(4)
}

func TestADeclinedInviteIsRefusedDistinguishably(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, _ := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()

	owner.send(fmt.Sprintf(`{"id":3,"cmd":"person.confirm","data":{"request_id":%q,"approve":false}}`, requestID))
	owner.expectOK(3)

	_, name, resolved := guest.expectEvent()
	if name != protocol.EventPairResolved {
		t.Fatalf("event = %q, want %q", name, protocol.EventPairResolved)
	}
	var outcome string
	mustUnmarshal(t, resolved["outcome"], &outcome)
	if outcome != store.OutcomeDeclined {
		t.Fatalf("outcome = %q, want %q", outcome, store.OutcomeDeclined)
	}
	if _, ok := resolved["identity"]; ok {
		t.Fatalf("a decline carried an identity: %v", resolved)
	}
	_ = guest.conn.Close(websocket.StatusNormalClosure, "")

	// The link is dead, and says "do not insist" rather than "try again".
	retry := dialWS(t, ts, nil)
	retry.expectGreeting()
	retry.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"ios"}}`, token, guestDev.pub))
	if code := expectErrCode(t, retry, 1); code != protocol.ErrPairDeclined {
		t.Fatalf("code = %q, want %q", code, protocol.ErrPairDeclined)
	}
}

// The question is asked of every device the owner has, and the answer from one
// closes it on the others.
func TestEveryOwnerDeviceSeesTheQuestionAndOneAnswerClosesIt(t *testing.T) {
	ts, srv := newTestServer(t)
	first, ownerDev := ownerSession(t, ts, srv)

	// A second device of the same person, paired through an ordinary device
	// invite.
	token := personInvite(t, first, 2)
	inviteData := func() string {
		first.send(`{"id":3,"cmd":"device.invite","data":{}}`)
		d := first.expectOK(3)
		var tok string
		mustUnmarshal(t, d["token"], &tok)
		return tok
	}()
	secondDev, _ := pairDevice(t, ts, inviteData)
	second := dialWS(t, ts, srv)
	second.expectGreeting()
	second.greet(t, 1, secondDev, "")
	_ = ownerDev

	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)

	for _, c := range []*wsClient{first, second} {
		_, name, data := c.expectEvent()
		if name != protocol.EventPairRequested {
			t.Fatalf("event = %q, want %q", name, protocol.EventPairRequested)
		}
		var got string
		mustUnmarshal(t, data["request_id"], &got)
		if got != requestID {
			t.Fatalf("request %q, want %q", got, requestID)
		}
	}

	// The SECOND device answers. The first has to hear about it too, or the
	// question stays on a screen nobody will answer again.
	second.send(fmt.Sprintf(`{"id":2,"cmd":"person.confirm","data":{"request_id":%q,"approve":true}}`, requestID))
	second.expectOK(2)

	for _, c := range []*wsClient{first, second, guest} {
		_, name, data := c.expectEvent()
		if name != protocol.EventPairResolved {
			t.Fatalf("event = %q, want %q", name, protocol.EventPairResolved)
		}
		var outcome string
		mustUnmarshal(t, data["outcome"], &outcome)
		if outcome != store.OutcomeApproved {
			t.Fatalf("outcome = %q, want approved", outcome)
		}
	}
}

// A device that was switched off while somebody was waiting still gets the
// question when it comes back.
func TestAWaitingQuestionIsResentOnTheNextGreeting(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, ownerDev := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	_, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()
	_ = owner.conn.Close(websocket.StatusNormalClosure, "")

	back := dialWS(t, ts, srv)
	back.expectGreeting()
	back.greet(t, 1, ownerDev, "")
	_, name, data := back.expectEvent()
	if name != protocol.EventPairRequested {
		t.Fatalf("event = %q, want %q", name, protocol.EventPairRequested)
	}
	var got string
	mustUnmarshal(t, data["request_id"], &got)
	if got != requestID {
		t.Fatalf("request %q, want %q", got, requestID)
	}
}

// Nobody answered. Both sides have to be told, and told the thing that means
// "ask again" rather than "do not insist".
func TestAnUnansweredQuestionExpiresOnBothScreens(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, _ := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()

	// The sweeper reads the clock, so the test moves the deadline rather than
	// the clock: expiring by hand is exactly what the loop does on its tick.
	ctx := context.Background()
	expired, err := srv.store.ExpirePendingPairs(ctx, time.Now().Unix()+store.ApprovalWindowSeconds+1)
	if err != nil {
		t.Fatalf("ExpirePendingPairs: %v", err)
	}
	if len(expired) != 1 {
		t.Fatalf("expired = %+v, want one", expired)
	}
	ownerID, err := srv.store.OwnerUserID(ctx)
	if err != nil {
		t.Fatalf("OwnerUserID: %v", err)
	}
	srv.notifyPairResolved(ownerID, expired[0].RequestID, store.OutcomeExpired, store.Identity{})

	for _, c := range []*wsClient{owner, guest} {
		_, name, data := c.expectEvent()
		if name != protocol.EventPairResolved {
			t.Fatalf("event = %q, want %q", name, protocol.EventPairResolved)
		}
		var outcome, got string
		mustUnmarshal(t, data["outcome"], &outcome)
		mustUnmarshal(t, data["request_id"], &got)
		if outcome != store.OutcomeExpired || got != requestID {
			t.Fatalf("resolved = (%q, %q), want (expired, %q)", got, outcome, requestID)
		}
	}
	_ = guest.conn.Close(websocket.StatusNormalClosure, "")

	retry := dialWS(t, ts, nil)
	retry.expectGreeting()
	retry.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"ios"}}`, token, guestDev.pub))
	if code := expectErrCode(t, retry, 1); code != protocol.ErrPairTimeout {
		t.Fatalf("code = %q, want %q", code, protocol.ErrPairTimeout)
	}
}

// The sweeper itself: a request nobody touched has to expire on its own, on
// both screens, without anybody asking about it.
func TestTheSweeperExpiresARequestNobodyTouched(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, _ := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()

	// The clock moves rather than the test: the deadline is five minutes away
	// and the loop reads seconds.
	srv.pairSweep = 5 * time.Millisecond
	srv.now = func() int64 { return time.Now().Unix() + store.ApprovalWindowSeconds + 1 }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = srv.runPairSweeper(ctx) }()

	for _, c := range []*wsClient{guest, owner} {
		_, name, data := c.expectEvent()
		if name != protocol.EventPairResolved {
			t.Fatalf("event = %q, want %q", name, protocol.EventPairResolved)
		}
		var outcome, got string
		mustUnmarshal(t, data["outcome"], &outcome)
		mustUnmarshal(t, data["request_id"], &got)
		if outcome != store.OutcomeExpired || got != requestID {
			t.Fatalf("resolved = (%q, %q), want (expired, %q)", got, outcome, requestID)
		}
	}
}

func mustJSONRaw(t *testing.T, data map[string]json.RawMessage) json.RawMessage {
	t.Helper()
	raw, err := json.Marshal(data)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return raw
}

// Principle I: an invite is a credential. It already lives in somebody else's
// chat history; a copy in the server log is a second place it can be read from,
// and logs are read over shoulders and pasted into issues.
func TestTheInviteTokenNeverReachesTheLog(t *testing.T) {
	buf := &syncBuffer{}
	logger := slog.New(slog.NewJSONHandler(buf, nil))

	ts, srv := newTestServerLogging(t, logger)
	owner, _ := ownerSession(t, ts, srv)

	token := personInvite(t, owner, 2)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()
	owner.send(fmt.Sprintf(`{"id":3,"cmd":"person.confirm","data":{"request_id":%q,"approve":true}}`, requestID))
	owner.expectOK(3)
	guest.expectEvent()

	logged := buf.String()
	if strings.TrimSpace(logged) == "" {
		t.Fatal("no log records at all: the assertion below would pass vacuously")
	}
	if strings.Contains(logged, token) {
		t.Fatalf("the invite token is in the log: %s", logged)
	}
	// The link carries the token, so a logged link leaks it just as well.
	if strings.Contains(logged, "nox.app/p/#") {
		t.Fatalf("a pairing link is in the log: %s", logged)
	}
}

// The paths this phase must NOT change, guarded together because it changed the
// signature of the one function all three go through.
func TestClaimAndDeviceInvitesAreUntouchedByPersonInvites(t *testing.T) {
	ts, srv := newTestServer(t)
	owner, _ := ownerSession(t, ts, srv)

	// A claim still produces an owner, and still says so.
	owner.send(`{"id":2,"cmd":"person.list","data":{}}`)
	var people []store.Person
	mustUnmarshal(t, owner.expectOK(2)["people"], &people)
	if len(people) != 1 || !people[0].Owner {
		t.Fatalf("people = %+v, want one owner", people)
	}

	// A person invite so there is somebody who is NOT the owner.
	token := personInvite(t, owner, 3)
	guestDev := newDevice(t)
	guest, requestID := presentInvite(t, ts, token, guestDev)
	owner.expectEvent()
	owner.send(fmt.Sprintf(`{"id":4,"cmd":"person.confirm","data":{"request_id":%q,"approve":true}}`, requestID))
	owner.expectOK(4)
	guest.expectEvent()
	_ = guest.conn.Close(websocket.StatusNormalClosure, "")

	joined := dialWS(t, ts, srv)
	joined.expectGreeting()
	joined.greet(t, 1, guestDev, "")

	// A DEVICE invite is still everybody's right - the owner-only rule is about
	// inviting people, and reading it as "invites" would strand a guest on one
	// device forever.
	joined.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	invite := joined.expectOK(2)
	var deviceToken string
	mustUnmarshal(t, invite["token"], &deviceToken)
	if deviceToken == "" {
		t.Fatal("device.invite returned no token")
	}
	// ...and it still lands immediately, with created=false and no waiting.
	second := dialWS(t, ts, nil)
	second.expectGreeting()
	other := newDevice(t)
	second.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, deviceToken, other.pub))
	paired := second.expectOK(1)
	var status string
	mustUnmarshal(t, paired["status"], &status)
	if status != pairStatusPaired {
		t.Fatalf("device invite status = %q, want %q", status, pairStatusPaired)
	}
	var id identity
	mustUnmarshal(t, paired["identity"], &id)
	if id.Created {
		t.Fatal("a device invite created a person")
	}
	if id.Owner {
		t.Fatal("a guest's second device owns the server")
	}
	_ = second.conn.Close(websocket.StatusNormalClosure, "")

	// A device invite still dies after ten minutes, not after a day.
	ctx := context.Background()
	late, err := srv.store.IssueDeviceInvite(ctx, id.ID, 1000)
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, err := srv.store.Pair(ctx, late, "dev-late", "test", 1000+store.InviteTTLSeconds+1); err == nil {
		t.Fatal("a device invite outlived its ten minutes")
	}

	// And device.list still says nothing about ownership: it returns ONE
	// person's devices, so the flag would read the same in every row.
	joined.send(`{"id":3,"cmd":"device.list","data":{}}`)
	rows := joined.expectOK(3)
	var listed []map[string]json.RawMessage
	mustUnmarshal(t, rows["devices"], &listed)
	if len(listed) == 0 {
		t.Fatal("no devices listed: the assertion below would pass vacuously")
	}
	for _, row := range listed {
		for field := range row {
			if strings.Contains(strings.ToLower(field), "owner") {
				t.Fatalf("device.list grew an ownership field %q", field)
			}
		}
	}
}

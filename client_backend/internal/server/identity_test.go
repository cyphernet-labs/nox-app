package server

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/protocol"
)

// replyKey reads the send key out of a command reply, where the message is
// nested; eventKey reads it out of an event frame, whose data IS the message.
// Both return "" for the stripped variant every non-author receives.
func replyKey(t *testing.T, data map[string]json.RawMessage) string {
	t.Helper()
	var msg protocol.Message
	mustUnmarshal(t, data["message"], &msg)
	return msg.ClientMessageID
}

func eventKey(t *testing.T, data map[string]json.RawMessage) string {
	t.Helper()
	raw, ok := data["client_message_id"]
	if !ok {
		return ""
	}
	var key string
	mustUnmarshal(t, raw, &key)
	return key
}

// TestIdentityOwnKeyReachesTheAuthorOnAllThreePaths pins the consequence of the
// three sites where the server decides own-vs-other. Missing any one of them
// strips the author's own client_message_id, which severs the link between a
// queued send and its confirmation - the message then shows twice until the
// next drain and is sent a second time.
func TestIdentityOwnKeyReachesTheAuthorOnAllThreePaths(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.greet(t, 1, dev, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "three-paths")

	// Path 1 - the echo of her own send.
	echo := anna.expectOKAfter(3, fmt.Sprintf(
		`{"id":3,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"own-1","body":{"type":"text","text":"hi"}}}`,
		chatID))
	if got := replyKey(t, echo); got != "own-1" {
		t.Fatalf("echo client_message_id = %q, want own-1", got)
	}

	// Path 2 - live delivery to a second connection of the same person.
	// A second connection of the SAME person - which now means a second
	// device of hers, paired through an invite.
	invite, err := srv.store.IssueDeviceInvite(context.Background(), ownerOf(t, srv, dev), time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	second, _ := pairDevice(t, ts, invite)
	live := dialWS(t, ts)
	live.expectGreeting()
	live.greet(t, 1, second, "")
	sendText(t, anna, 4, chatID, "own-2", "second")
	_, name, data := live.expectEvent()
	if name != protocol.EventMessageNew {
		t.Fatalf("live event = %s, want message.new", name)
	}
	if got := eventKey(t, data); got != "own-2" {
		t.Fatalf("live client_message_id = %q, want own-2 - own is the person, not the device", got)
	}

	// Path 3 - the history read.
	page := anna.expectOKAfter(5, fmt.Sprintf(
		`{"id":5,"cmd":"messages.list","data":{"chat_id":%q,"limit":10}}`, chatID))
	var listed struct {
		Messages []protocol.Message `json:"messages"`
	}
	mustUnmarshal(t, page["messages"], &listed.Messages)
	if len(listed.Messages) != 2 {
		t.Fatalf("listed %d messages, want 2", len(listed.Messages))
	}
	for _, m := range listed.Messages {
		if m.ClientMessageID == "" {
			t.Fatalf("message %s came back stripped to its own author", m.MessageID)
		}
	}

	// Path 4 - replay after a reconnect.
	back := dialWS(t, ts)
	back.expectGreeting()
	helloCursor(t, back, 1, fmt.Sprintf(`,"device_key":%q,"signature":%q`, dev.pub, dev.sign(t, back.challenge)))
	for range 2 {
		_, name, data := back.expectEvent()
		if name != protocol.EventMessageNew {
			continue
		}
		if got := eventKey(t, data); got == "" {
			t.Fatal("replayed own message came back stripped")
		}
	}
}

// TestIdentityStrangersDoNotSeeEachOthersSendKeys is the other half of the same
// rule: the key is the author's alone.
//
// The stranger is an anonymous connection rather than a second paired person:
// a stage-2 server holds exactly one person until invite-user arrives (Q15),
// and an unpaired listener is the only other party that can exist today.
func TestIdentityStrangersDoNotSeeEachOthersSendKeys(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.greet(t, 1, dev, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "strangers")

	stranger := dialWS(t, ts)
	stranger.expectGreeting()
	stranger.hello(1, "")

	sendText(t, anna, 3, chatID, "annas-key", "hello")
	_, _, data := stranger.expectEvent()
	if got := eventKey(t, data); got != "" {
		t.Fatalf("the stranger received anna's send key %q", got)
	}
}

// TestIdentityRenameLeavesPastMessagesAlone is the second of the three defects
// this feature exists to fix: with the author id and the display name being one
// string, a rename used to make one's own history look like a stranger's.
func TestIdentityRenameLeavesPastMessagesAlone(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	var before identity
	mustUnmarshal(t, anna.greet(t, 1, dev, `,"label":"Anna"`)["identity"], &before)
	chatID := seedChat(t, anna, "rename")
	sendText(t, anna, 3, chatID, "old-1", "written as Anna")

	renamed := dialWS(t, ts)
	renamed.expectGreeting()
	var after identity
	mustUnmarshal(t, renamed.greet(t, 1, dev, `,"label":"Anna2"`)["identity"], &after)
	if after.ID != before.ID {
		t.Fatalf("identity changed from %q to %q on a rename", before.ID, after.ID)
	}
	if after.Label != "Anna2" {
		t.Fatalf("label = %q, want Anna2", after.Label)
	}
	sendText(t, renamed, 3, chatID, "new-1", "written as Anna2")

	page := renamed.expectOKAfter(4, fmt.Sprintf(
		`{"id":4,"cmd":"messages.list","data":{"chat_id":%q,"limit":10}}`, chatID))
	var msgs []protocol.Message
	mustUnmarshal(t, page["messages"], &msgs)
	if len(msgs) != 2 {
		t.Fatalf("listed %d messages, want 2", len(msgs))
	}
	labels := map[string]string{}
	for _, m := range msgs {
		labels[m.ClientMessageID] = m.AuthorLabel
		if m.AuthorID != before.ID {
			t.Fatalf("message %s author = %q, want the unchanged %q", m.ClientMessageID, m.AuthorID, before.ID)
		}
		if m.ClientMessageID == "" {
			t.Fatalf("message came back stripped to its own author after a rename")
		}
	}
	if labels["old-1"] != "Anna" {
		t.Fatalf("the old signature became %q; it must stay the name in use then", labels["old-1"])
	}
	if labels["new-1"] != "Anna2" {
		t.Fatalf("the new signature = %q, want Anna2", labels["new-1"])
	}
}

// TestIdentityAnonymousConnectionIsServedAndLeavesNoRow covers the hand tools,
// the live probe and anything else that speaks the protocol without presenting
// credentials. Refusing them is forbidden; recording them is unbounded growth.
func TestIdentityAnonymousConnectionIsServedAndLeavesNoRow(t *testing.T) {
	ts, srv := newTestServer(t)

	probe := dialWS(t, ts)
	probe.expectGreeting()
	data := probe.hello(1, ``)
	var ident identity
	mustUnmarshal(t, data["identity"], &ident)
	if ident.ID == "" || ident.Label == "" {
		t.Fatalf("identity = %+v, want a served identity", ident)
	}

	var users int
	if err := readDB(t, srv).QueryRow("SELECT COUNT(1) FROM users").Scan(&users); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if users != 0 {
		t.Fatalf("users = %d, want 0: a greeting alone must not write a person", users)
	}
}

// TestAssertIdentitySchemaRefusesAStaleDatabase is the loud failure the feature
// needs. The runner skips migrations it has already applied, so an edited
// 001_init.sql never reaches a database written before this feature; without
// this check the mismatch degrades into an internal error on every greeting.
func TestAssertIdentitySchemaRefusesAStaleDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stale.db")
	d, err := db.Open(path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })

	// A database that already reports the current schema version but has none
	// of the identity tables - exactly what a pre-030 database looks like.
	if _, err := d.Write.Exec("PRAGMA user_version = 1"); err != nil {
		t.Fatalf("set user_version: %v", err)
	}
	if err := assertIdentitySchema(context.Background(), d.Read, path); err == nil {
		t.Fatal("assertIdentitySchema accepted a database with no identity tables")
	}
}

func TestAssertIdentitySchemaAcceptsAFreshDatabase(t *testing.T) {
	_, srv := newTestServer(t)
	if err := assertIdentitySchema(context.Background(), readDB(t, srv), srv.cfg.DBPath); err != nil {
		t.Fatalf("assertIdentitySchema rejected a freshly migrated database: %v", err)
	}
}

// TestPairCreatedTellsTheClientWhetherToOnboard is the wire half of the rule.
// The false case is asserted on the RAW frame, not on the decoded struct: with
// omitempty the field would vanish, the client would read "outcome not stated",
// and an ordinary returning person would be refused sign-in instead of walking
// into their conversation.
//
// The flag moved from the greeting to the pair reply with feature 032, which is
// where the decision actually belongs: a greeting is by definition a device
// that was already paired.
func TestPairCreatedTellsTheClientWhetherToOnboard(t *testing.T) {
	ts, srv := newTestServer(t)

	dev, claimed := claimDevice(t, ts, srv)
	var newcomer identity
	mustUnmarshal(t, claimed["identity"], &newcomer)
	if !newcomer.Created {
		t.Fatal("claiming a fresh server brings the person into being")
	}

	invite, err := srv.store.IssueDeviceInvite(context.Background(), ownerOf(t, srv, dev), time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	_, added := pairDevice(t, ts, invite)
	raw := added["identity"]
	var returning identity
	mustUnmarshal(t, raw, &returning)
	if returning.Created {
		t.Fatal("adding a device to an existing person must not report created")
	}
	if returning.ID != newcomer.ID {
		t.Fatalf("identity changed from %q to %q", newcomer.ID, returning.ID)
	}
	if !strings.Contains(string(raw), `"created"`) {
		t.Fatalf("the false case dropped out of the frame: %s", raw)
	}
}

// A greeting never reports created: by the time one happens the device is
// already paired, so nobody was brought into being by it.
func TestGreetingNeverReportsCreated(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	c := dialWS(t, ts)
	c.expectGreeting()
	var ident identity
	mustUnmarshal(t, c.greet(t, 1, dev, "")["identity"], &ident)
	if ident.Created {
		t.Fatal("a greeting is a device that was already paired")
	}
}

// ownerOf reads which person a device key belongs to.
func ownerOf(t *testing.T, srv *Server, d *device) string {
	t.Helper()
	owner, found, err := srv.store.DeviceOwner(context.Background(), d.pub)
	if err != nil || !found {
		t.Fatalf("DeviceOwner(%s): %v found=%v", d.pub, err, found)
	}
	return owner
}

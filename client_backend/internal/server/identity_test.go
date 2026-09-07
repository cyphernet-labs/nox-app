package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
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

	anna := dialWS(t, ts, srv)
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
	live := dialWS(t, ts, srv)
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
	back := dialWS(t, ts, srv)
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

// TestIdentityRenameLeavesPastMessagesAlone is the second of the three defects
// this feature exists to fix: with the author id and the display name being one
// string, a rename used to make one's own history look like a stranger's.
func TestIdentityRenameLeavesPastMessagesAlone(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)

	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	var before identity
	mustUnmarshal(t, anna.greet(t, 1, dev, `,"label":"Anna"`)["identity"], &before)
	chatID := seedChat(t, anna, "rename")
	sendText(t, anna, 3, chatID, "old-1", "written as Anna")

	renamed := dialWS(t, ts, srv)
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

	c := dialWS(t, ts, srv)
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

// A greeting that presents no key at all is refused, exactly like one
// presenting an unknown key.
//
// This replaces two tests that pinned the opposite. They rested on reading
// "the server may not refuse a greeting" as covering keys, but that rule
// (contract §3) is about the LABEL - and taking it for a key rule handed any
// connection that simply omitted the field a full session: the whole journal
// replayed, live events streamed, and the ability to post.
func TestGreetingWithNoDeviceKeyIsRefused(t *testing.T) {
	ts, srv := newTestServer(t)
	pairedDevice(t, ts, srv) // somebody owns the server, and has history

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.send(`{"id":1,"cmd":"session.hello","data":{"schema":1,"since":0}}`)
	if code := expectErrCode(t, c, 1); code != protocol.ErrUnauthenticated {
		t.Fatalf("code = %q, want %q", code, protocol.ErrUnauthenticated)
	}

	people, err := srv.store.CountUsers(context.Background())
	if err != nil {
		t.Fatalf("count users: %v", err)
	}
	if people != 1 {
		t.Fatalf("users = %d, want 1: a refused greeting writes nothing", people)
	}
}

// The guard exists to replace a raw "no such column" with an instruction, so
// the case it exists for - a feature-032 database, every table present and the
// owner column missing - has to be the case it is tested on. A typo in the
// predicate would otherwise either refuse every good database or wave every
// stale one through to die deeper in.
func TestSchemaGuardRefusesADatabaseWithoutTheOwnerColumn(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stale.db")
	dbs, err := db.Open(path)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = dbs.Close() })
	if _, err := db.Migrate(context.Background(), dbs.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	ctx := context.Background()

	// A freshly migrated database passes.
	if err := assertIdentitySchema(ctx, dbs.Read, path); err != nil {
		t.Fatalf("a current database was refused: %v", err)
	}

	// Now make it look like the previous phase's. SQLite can drop a column.
	if _, err := dbs.Write.ExecContext(ctx, "ALTER TABLE server_identity DROP COLUMN owner_user_id"); err != nil {
		t.Fatalf("drop column: %v", err)
	}
	err = assertIdentitySchema(ctx, dbs.Read, path)
	if err == nil {
		t.Fatal("a database without the owner column was allowed to start")
	}
	if !strings.Contains(err.Error(), path) {
		t.Fatalf("the refusal does not say which file to delete: %v", err)
	}
}

// The warning is the only thing standing between a hand-edited store and a
// silent guess, so the state it reports has to be right - and it must not fire
// for a store whose machine row is merely missing, which is a fatal case with
// its own, different remedy.
func TestOwnerlessStoreIsReportedOnlyWhenItHasPeopleAndAMachineRow(t *testing.T) {
	path := filepath.Join(t.TempDir(), "ownerless.db")
	dbs, err := db.Open(path)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = dbs.Close() })
	if _, err := db.Migrate(context.Background(), dbs.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	ctx := context.Background()
	st := store.New(dbs.Read, dbs.Write)

	state, err := st.ReadOwnershipState(ctx)
	if err != nil {
		t.Fatalf("ReadOwnershipState: %v", err)
	}
	if state.Stranded {
		t.Fatal("an empty store reported itself stranded")
	}

	if _, err := st.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := st.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := st.Pair(ctx, token, "dev-a", "test", 100); err != nil {
		t.Fatalf("Pair: %v", err)
	}
	state, err = st.ReadOwnershipState(ctx)
	if err != nil {
		t.Fatalf("ReadOwnershipState: %v", err)
	}
	if state.Stranded {
		t.Fatal("a properly owned store reported itself stranded")
	}

	if _, err := dbs.Write.ExecContext(ctx, "UPDATE server_identity SET owner_user_id = NULL WHERE id = 1"); err != nil {
		t.Fatalf("clear owner: %v", err)
	}
	state, err = st.ReadOwnershipState(ctx)
	if err != nil {
		t.Fatalf("ReadOwnershipState: %v", err)
	}
	if !state.Stranded || state.People != 1 {
		t.Fatalf("state=%+v, want a store with one person and no owner", state)
	}

	// A MISSING machine row is a different state with a different remedy, and
	// startup refuses outright there - so this must not claim it is survivable.
	if _, err := dbs.Write.ExecContext(ctx, "DELETE FROM server_identity"); err != nil {
		t.Fatalf("drop machine row: %v", err)
	}
	state, err = st.ReadOwnershipState(ctx)
	if err != nil {
		t.Fatalf("ReadOwnershipState: %v", err)
	}
	if state.Stranded {
		t.Fatal("a store with no machine row was reported as merely ownerless")
	}

	// And the warning itself says what to do, without advising a claim Pair refuses.
	loud := &syncBuffer{}
	warnOwnerlessStore(store.OwnershipState{Stranded: true, People: 1}, slog.New(slog.NewTextHandler(loud, nil)))
	if !strings.Contains(loud.String(), "no owner") || strings.Contains(loud.String(), "re-claim") {
		t.Fatalf("warning reads %q", loud.String())
	}
	quiet := &syncBuffer{}
	warnOwnerlessStore(store.OwnershipState{}, slog.New(slog.NewTextHandler(quiet, nil)))
	if quiet.String() != "" {
		t.Fatalf("a healthy store warned: %s", quiet.String())
	}
}

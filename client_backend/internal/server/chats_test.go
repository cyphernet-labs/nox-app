package server

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"testing"
	"time"

	"context"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

type chatsPage struct {
	Chats   []protocol.Chat `json:"chats"`
	HasMore bool            `json:"has_more"`
}

func listChats(t *testing.T, c *wsClient, id int, data string) chatsPage {
	t.Helper()
	reply := c.expectOKAfter(id, fmt.Sprintf(`{"id":%d,"cmd":"chats.list","data":%s}`, id, data))
	var page chatsPage
	mustUnmarshal(t, reply["chats"], &page.Chats)
	mustUnmarshal(t, reply["has_more"], &page.HasMore)
	return page
}

func TestStoryOneChatsListOrderSearchAndGet(t *testing.T) {
	ts, srv := newTestServer(t)

	// Seed through the store with controlled timestamps: wall-clock writes
	// land in the same unix second and would leave the order to the random
	// chat_id tiebreaker.
	kitchenChat, _, _, err := srv.store.CreateChat(t.Context(), "", "Kitchen", "Anna", 100)
	if err != nil {
		t.Fatalf("seed Kitchen: %v", err)
	}
	kitchen := kitchenChat.ChatID
	obshchiyChat, _, _, err := srv.store.CreateChat(t.Context(), "", "Общий", "Anna", 200)
	if err != nil {
		t.Fatalf("seed chat: %v", err)
	}
	// A later message into Kitchen makes it the most recent and sets its
	// preview.
	if _, _, _, err := srv.store.SendMessage(t.Context(), kitchen, "c1", person(t, srv.store, "Anna"),
		[]byte(`{"type":"text","text":"fresh preview"}`), "", 300); err != nil {
		t.Fatalf("seed message: %v", err)
	}

	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)

	page := listChats(t, anna, 10, `{"page":1,"page_size":10}`)
	if page.HasMore || len(page.Chats) != 2 {
		t.Fatalf("page = %d rows hasMore=%v", len(page.Chats), page.HasMore)
	}
	if page.Chats[0].ChatID != kitchen || page.Chats[0].LastMessagePreview != "fresh preview" {
		t.Fatalf("top row = %+v, want Kitchen with the fresh preview", page.Chats[0])
	}

	// Unicode case-insensitive substring search.
	found := listChats(t, anna, 11, `{"page":1,"page_size":10,"query":"оБщ"}`)
	if len(found.Chats) != 1 || found.Chats[0].ChatID != obshchiyChat.ChatID {
		t.Fatalf("search = %+v", found.Chats)
	}

	// Page past the end: empty, has_more false.
	far := listChats(t, anna, 12, `{"page":9,"page_size":10}`)
	if far.HasMore || len(far.Chats) != 0 {
		t.Fatalf("far page = %+v", far)
	}

	// Validation; an attacker-sized page must answer, not panic the handler.
	anna.send(`{"id":13,"cmd":"chats.list","data":{"page":0,"page_size":10}}`)
	anna.expectErr(13, protocol.ErrInvalidRequest)
	huge := listChats(t, anna, 14, `{"page":92233720368547760,"page_size":100}`)
	if huge.HasMore || len(huge.Chats) != 0 {
		t.Fatalf("huge page = %d rows hasMore=%v, want empty reply", len(huge.Chats), huge.HasMore)
	}

	// chat.get: full card equals the created one (plus preview refresh path).
	got := anna.expectOKAfter(15, fmt.Sprintf(`{"id":15,"cmd":"chat.get","data":{"chat_id":%q}}`, obshchiyChat.ChatID))
	var card protocol.Chat
	mustUnmarshal(t, got["chat"], &card)
	if card != obshchiyChat {
		t.Fatalf("chat.get = %+v, want %+v", card, obshchiyChat)
	}
	anna.send(`{"id":16,"cmd":"chat.get","data":{"chat_id":"c_missing"}}`)
	anna.expectErr(16, protocol.ErrNotFound)
}

func TestStoryOneFirstPageLatencyOverLargeList(t *testing.T) {
	ts, srv := newTestServer(t)

	// Seed 250 chats through the store directly - the wire would dominate
	// the measurement with 250 round trips.
	for i := range 250 {
		if _, _, _, err := srv.store.CreateChat(t.Context(), "", fmt.Sprintf("chat-%03d", i), "Seeder", int64(1000+i)); err != nil {
			t.Fatalf("seed chat %d: %v", i, err)
		}
	}

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, ``)
	start := time.Now()
	page := listChats(t, c, 2, `{"page":1,"page_size":100}`)
	if elapsed := time.Since(start); elapsed >= time.Second {
		t.Fatalf("first page over 250 chats took %v, want < 1s (SC-001)", elapsed)
	}
	if !page.HasMore || len(page.Chats) != 100 {
		t.Fatalf("page = %d rows hasMore=%v", len(page.Chats), page.HasMore)
	}

	// The clamp is observable here: 250 rows exist, so a request for 500
	// coming back with exactly 100 rows and has_more proves the cap works.
	clamped := listChats(t, c, 3, `{"page":1,"page_size":500}`)
	if !clamped.HasMore || len(clamped.Chats) != 100 {
		t.Fatalf("clamped page = %d rows hasMore=%v, want exactly 100 + more", len(clamped.Chats), clamped.HasMore)
	}
}

func TestStoryThreeRenameValidationNegatives(t *testing.T) {
	ts, srv := newTestServer(t)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, ``)
	chatID := seedChat(t, c, "valid")

	long := strings.Repeat("я", 65)
	c.send(`{"id":10,"cmd":"chat.rename","data":{"chat_id":"","name":"x"}}`)
	c.expectErr(10, protocol.ErrInvalidRequest)
	c.send(fmt.Sprintf(`{"id":11,"cmd":"chat.rename","data":{"chat_id":%q,"name":"   "}}`, chatID))
	c.expectErr(11, protocol.ErrInvalidRequest)
	c.send(fmt.Sprintf(`{"id":12,"cmd":"chat.rename","data":{"chat_id":%q,"name":%q}}`, chatID, long))
	c.expectErr(12, protocol.ErrInvalidRequest)
	c.send(fmt.Sprintf(`{"id":13,"cmd":"chat.nameAvailable","data":{"name":%q}}`, long))
	c.expectErr(13, protocol.ErrInvalidRequest)
	c.send(`{"id":14,"cmd":"chat.nameAvailable","data":{"name":"  "}}`)
	c.expectErr(14, protocol.ErrInvalidRequest)

	// A 64-rune name is the boundary and stays valid.
	ok := c.expectOKAfter(15, fmt.Sprintf(`{"id":15,"cmd":"chat.rename","data":{"chat_id":%q,"name":%q}}`, chatID, strings.Repeat("я", 64)))
	var card protocol.Chat
	mustUnmarshal(t, ok["chat"], &card)
	if card.ChatID != chatID {
		t.Fatalf("boundary rename card = %+v", card)
	}
}

func TestStoryThreeRenameLiveNoReorderAndReplay(t *testing.T) {
	ts, srv := newTestServer(t)

	// Controlled distinct timestamps make the no-reorder check
	// discriminating: same-second rows would tie-break by chat_id and an
	// accidental activity bump could go unnoticed.
	kitchenChat, _, _, err := srv.store.CreateChat(t.Context(), "", "Kitchen", "Anna", 100)
	if err != nil {
		t.Fatalf("seed Kitchen: %v", err)
	}
	kitchen := kitchenChat.ChatID
	targetChat, _, _, err := srv.store.CreateChat(t.Context(), "", "Старое", "Anna", 200)
	if err != nil {
		t.Fatalf("seed target: %v", err)
	}
	if _, _, _, err := srv.store.SendMessage(t.Context(), kitchen, "m1", person(t, srv.store, "Anna"),
		[]byte(`{"type":"text","text":"keeps kitchen on top"}`), "", 300); err != nil {
		t.Fatalf("seed message: %v", err)
	}

	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	bob := dialWS(t, ts, srv)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	orderBefore := listChats(t, anna, 10, `{"page":1,"page_size":10}`)
	if len(orderBefore.Chats) != 2 || orderBefore.Chats[0].ChatID != kitchen || orderBefore.Chats[1].ChatID != targetChat.ChatID {
		t.Fatalf("baseline order = %+v, want Kitchen(300) then target(200)", orderBefore.Chats)
	}

	// nameAvailable agrees with the upcoming rename outcomes.
	avail := anna.expectOKAfter(11, `{"id":11,"cmd":"chat.nameAvailable","data":{"name":"kitchen"}}`)
	var available bool
	mustUnmarshal(t, avail["available"], &available)
	if available {
		t.Fatal("kitchen must be reported taken (case-insensitive)")
	}
	avail = anna.expectOKAfter(12, fmt.Sprintf(`{"id":12,"cmd":"chat.nameAvailable","data":{"name":"СТАРОЕ","exclude_chat_id":%q}}`, targetChat.ChatID))
	mustUnmarshal(t, avail["available"], &available)
	if !available {
		t.Fatal("own name with exclusion must be available")
	}

	// Rename: live chat.updated with the full card on the second client.
	// The dispatcher flushes the seeded backlog on its first kick, so Bob
	// reads until the chat.updated frame arrives.
	before := time.Now()
	renamed := anna.expectOKAfter(13, fmt.Sprintf(`{"id":13,"cmd":"chat.rename","data":{"chat_id":%q,"name":"Новое"}}`, targetChat.ChatID))
	var renamedChat protocol.Chat
	mustUnmarshal(t, renamed["chat"], &renamedChat)
	if renamedChat.LastActivityAt != 200 {
		t.Fatalf("rename bumped last_activity_at to %d, want untouched 200", renamedChat.LastActivityAt)
	}

	var evData map[string]json.RawMessage
	found := false
	for range 10 {
		_, name, data := bob.expectEvent()
		if name == protocol.EventChatUpdated {
			evData = data
			found = true
			break
		}
	}
	if !found {
		t.Fatal("chat.updated never reached the second client")
	}
	if latency := time.Since(before); latency >= time.Second {
		t.Fatalf("chat.updated latency = %v, want < 1s (SC-002)", latency)
	}
	raw, err := json.Marshal(evData)
	if err != nil {
		t.Fatalf("re-marshal event: %v", err)
	}
	var evChat protocol.Chat
	if err := json.Unmarshal(raw, &evChat); err != nil || evChat != renamedChat {
		t.Fatalf("event card = %+v err=%v, want %+v", evChat, err, renamedChat)
	}

	// The list order did not change: rename is not activity.
	orderAfter := listChats(t, anna, 14, `{"page":1,"page_size":10}`)
	if len(orderAfter.Chats) != len(orderBefore.Chats) {
		t.Fatalf("row count changed: %d -> %d", len(orderBefore.Chats), len(orderAfter.Chats))
	}
	for i := range orderBefore.Chats {
		if orderAfter.Chats[i].ChatID != orderBefore.Chats[i].ChatID {
			t.Fatalf("position %d changed: %s -> %s", i, orderBefore.Chats[i].Name, orderAfter.Chats[i].Name)
		}
	}

	// Cyrillic case-variant of another chat's name is taken.
	anna.send(fmt.Sprintf(`{"id":15,"cmd":"chat.rename","data":{"chat_id":%q,"name":"KITCHEN"}}`, targetChat.ChatID))
	anna.expectErr(15, protocol.ErrNameTaken)

	// No-op rename: ok, and Bob receives no event - proven by the NEXT
	// event Bob sees being the message below, not a chat.updated.
	noop := anna.expectOKAfter(16, fmt.Sprintf(`{"id":16,"cmd":"chat.rename","data":{"chat_id":%q,"name":"Новое"}}`, targetChat.ChatID))
	var noopChat protocol.Chat
	mustUnmarshal(t, noop["chat"], &noopChat)
	if noopChat != renamedChat {
		t.Fatalf("no-op card = %+v, want unchanged %+v", noopChat, renamedChat)
	}
	sendText(t, anna, 17, kitchen, "m2", "probe")
	if _, name, _ := bob.expectEvent(); name != protocol.EventMessageNew {
		t.Fatalf("bob's next event = %s, want message.new (no-op must not emit chat.updated)", name)
	}

	// Replay: a reconnecting client receives chat.updated in log order.
	lateBob := dialWS(t, ts, srv)
	lateBob.expectGreeting()
	lateBob.hello(1, `,"label":"Late","since":0`)
	var seenChatUpdated bool
	for range 8 {
		_, name, _ := lateBob.expectEvent()
		if name == protocol.EventChatUpdated {
			seenChatUpdated = true
			break
		}
	}
	if !seenChatUpdated {
		t.Fatal("replay never delivered chat.updated")
	}
}

func TestStoryThreeConcurrentRenameRace(t *testing.T) {
	ts, srv := newTestServer(t)

	c1 := dialWS(t, ts, srv)
	c1.expectGreeting()
	c1.hello(1, ``)
	c2 := dialWS(t, ts, srv)
	c2.expectGreeting()
	c2.hello(1, ``)

	a := seedChat(t, c1, "Alpha")
	b := seedChat(t, c2, "Beta")

	// Both rename their chat to the same fresh name concurrently.
	c1.send(fmt.Sprintf(`{"id":9,"cmd":"chat.rename","data":{"chat_id":%q,"name":"Gamma"}}`, a))
	c2.send(fmt.Sprintf(`{"id":9,"cmd":"chat.rename","data":{"chat_id":%q,"name":"gamma"}}`, b))

	wins := 0
	for _, c := range []*wsClient{c1, c2} {
		reply := c.expectReply(9)
		var ok bool
		mustUnmarshal(t, reply["ok"], &ok)
		if ok {
			wins++
		}
	}
	if wins != 1 {
		t.Fatalf("concurrent rename wins = %d, want exactly 1", wins)
	}
}

// deviceChatID is a chat_id the way a device mints it (041): c_ and 32
// lowercase hex digits.
const deviceChatID = "c_5f0e9c1d2a3b4c5d6e7f8091a2b3c4d5"

func TestChatCreateWithDeviceChatIDCreatesItOnceAndRepeatsWithoutAnEvent(t *testing.T) {
	ts, srv := newTestServer(t)

	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	bob := dialWS(t, ts, srv)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	create := func(id int) protocol.Chat {
		t.Helper()
		reply := anna.expectOKAfter(id, fmt.Sprintf(
			`{"id":%d,"cmd":"chat.create","data":{"name":"Kitchen","chat_id":%q}}`, id, deviceChatID))
		var chat protocol.Chat
		mustUnmarshal(t, reply["chat"], &chat)
		return chat
	}

	chat := create(2)
	if chat.ChatID != deviceChatID || chat.Name != "Kitchen" {
		t.Fatalf("reply chat = %+v, want Kitchen under the device's id %s", chat, deviceChatID)
	}
	seq, name, evData := bob.expectJournalEvent()
	var evChatID string
	mustUnmarshal(t, evData["chat_id"], &evChatID)
	if name != protocol.EventChatCreated || evChatID != deviceChatID {
		t.Fatalf("bob got %s for %q, want chat.created for %s", name, evChatID, deviceChatID)
	}

	// The reply was lost and the device sends the same command again: the
	// same chat comes back - not name_taken over its own name - and nothing
	// is written.
	if again := create(3); again != chat {
		t.Fatalf("repeat = %+v, want %+v", again, chat)
	}
	cursor, err := srv.store.Cursor(t.Context())
	if err != nil || cursor != seq {
		t.Fatalf("cursor after the repeat = %d err=%v, want %d (a repeat writes no event)", cursor, err, seq)
	}

	// A NEW id under the same name is another chat, and the name is taken.
	anna.send(`{"id":4,"cmd":"chat.create","data":{"name":"kitchen","chat_id":"c_0123456789abcdef0123456789abcdef"}}`)
	anna.expectErr(4, protocol.ErrNameTaken)

	// Bob was sent nothing for either: the next journal event he sees is this
	// message, one seq after the chat.created.
	sendText(t, anna, 5, deviceChatID, "probe-1", "probe")
	probeSeq, probeName, _ := bob.expectJournalEvent()
	if probeName != protocol.EventMessageNew || probeSeq != seq+1 {
		t.Fatalf("bob's next event = %s seq %d, want message.new seq %d (no event for a repeat)", probeName, probeSeq, seq+1)
	}
}

func TestChatCreateRefusesAMalformedChatID(t *testing.T) {
	ts, srv := newTestServer(t)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, ``)

	const hex32 = "5f0e9c1d2a3b4c5d6e7f8091a2b3c4d5"
	cases := []struct {
		name   string
		chatID string // the raw JSON value of chat_id
	}{
		{"wrong prefix", `"x_` + hex32 + `"`},
		{"uppercase hex", `"c_` + strings.ToUpper(hex32) + `"`},
		{"31 hex digits", `"c_` + hex32[:31] + `"`},
		{"33 hex digits", `"c_` + hex32 + `0"`},
		{"the server's own 16 hex digits", `"c_` + hex32[:16] + `"`},
		{"empty string", `""`},
		// Go's $ is the end of the TEXT, not of a line, so the newline is one
		// character too many rather than a line ending.
		{"trailing newline", `"c_` + hex32 + `\n"`},
		{"not a string", `42`},
	}
	for i, tc := range cases {
		id := 10 + i
		c.send(fmt.Sprintf(`{"id":%d,"cmd":"chat.create","data":{"name":"Kitchen","chat_id":%s}}`, id, tc.chatID))
		raw, refused := c.expectReply(id)["error"]
		if !refused {
			t.Fatalf("%s: chat_id %s was accepted, want invalid_request", tc.name, tc.chatID)
		}
		var wireErr protocol.WireError
		mustUnmarshal(t, raw, &wireErr)
		if wireErr.Code != protocol.ErrInvalidRequest {
			t.Fatalf("%s: code = %q, want invalid_request", tc.name, wireErr.Code)
		}
	}

	// The shape is refused before the store is reached: nothing was written.
	if cursor, err := srv.store.Cursor(t.Context()); err != nil || cursor != 0 {
		t.Fatalf("cursor = %d err=%v, want 0", cursor, err)
	}
}

func TestChatCreateWithoutChatIDStillGetsAServerID(t *testing.T) {
	ts, srv := newTestServer(t)

	anna := dialWS(t, ts, srv)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	bob := dialWS(t, ts, srv)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	serverID := regexp.MustCompile(`^c_[0-9a-f]{16}$`)
	// null reads as absent: a serializer that writes every optional field
	// sends it for a device with no id to give.
	for i, data := range []string{`{"name":"Kitchen"}`, `{"name":"Pantry","chat_id":null}`} {
		id := 2 + i
		reply := anna.expectOKAfter(id, fmt.Sprintf(`{"id":%d,"cmd":"chat.create","data":%s}`, id, data))
		var chat protocol.Chat
		mustUnmarshal(t, reply["chat"], &chat)
		if !serverID.MatchString(chat.ChatID) {
			t.Fatalf("%s: chat_id = %q, want the server's c_<16 hex>", data, chat.ChatID)
		}
		_, name, evData := bob.expectJournalEvent()
		var evChatID string
		mustUnmarshal(t, evData["chat_id"], &evChatID)
		if name != protocol.EventChatCreated || evChatID != chat.ChatID {
			t.Fatalf("%s: bob got %s for %q, want chat.created for %s", data, name, evChatID, chat.ChatID)
		}
	}
}

// Principle I: what a chat is called is what people talk about, and the log is
// not where it goes. A creation is logged once, by seq; a repeat created
// nothing and logs nothing.
func TestChatCreateLogsACreationOnceAndNeverTheName(t *testing.T) {
	buf := &syncBuffer{}
	ts, srv := newTestServerLogging(t, slog.New(slog.NewJSONHandler(buf, nil)))

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, ``)

	const name = "Surprise party planning"
	create := fmt.Sprintf(`{"name":%q,"chat_id":%q}`, name, deviceChatID)
	c.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"chat.create","data":%s}`, create))
	c.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"chat.create","data":%s}`, create))
	// Commands on one connection are handled in order, so this reply means the
	// repeat's handler has finished - including anything it logs after replying.
	c.expectOKAfter(4, fmt.Sprintf(`{"id":4,"cmd":"chat.get","data":{"chat_id":%q}}`, deviceChatID))

	created := 0
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if strings.Contains(line, name) {
			t.Fatalf("the chat's name reached the log: %s", line)
		}
		var record map[string]any
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			t.Fatalf("log line is not JSON: %v (%s)", err, line)
		}
		if record["msg"] == "chat created" {
			created++
		}
	}
	if created != 1 {
		t.Fatalf("chat created logged %d times, want once: the repeat created nothing", created)
	}
}

// person pairs one device and names it, the way the first device of a fresh
// install does. Messages carry a foreign key to users, so a test that writes a
// message needs its author to exist - and since feature 032 a person can only
// come into being through pairing. Idempotent: the device key finds the row on
// every later call.
func person(t *testing.T, s *store.Store, name string) store.Identity {
	t.Helper()
	ctx := context.Background()
	deviceKey := "dev-" + name

	if id, err := s.ResolveIdentity(ctx, deviceKey, name, 1); err == nil {
		return id
	}
	if _, err := s.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	link, err := s.IssueMachineLink(ctx, 1)
	if err != nil {
		t.Fatalf("IssueMachineLink: %v", err)
	}
	if _, err := s.Pair(ctx, link.Token, deviceKey, "test", 1); err != nil {
		t.Fatalf("Pair(%s): %v", name, err)
	}
	// State the chosen name the way onboarding does.
	id, err := s.ResolveIdentity(ctx, deviceKey, name, 1)
	if err != nil {
		t.Fatalf("ResolveIdentity(%s): %v", name, err)
	}
	return id
}

package server

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"nox.app/client-backend/internal/protocol"
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
	kitchenChat, _, err := srv.store.CreateChat(t.Context(), "Kitchen", "Anna", 100)
	if err != nil {
		t.Fatalf("seed Kitchen: %v", err)
	}
	kitchen := kitchenChat.ChatID
	obshchiyChat, _, err := srv.store.CreateChat(t.Context(), "Общий", "Anna", 200)
	if err != nil {
		t.Fatalf("seed chat: %v", err)
	}
	// A later message into Kitchen makes it the most recent and sets its
	// preview.
	if _, _, _, err := srv.store.SendMessage(t.Context(), kitchen, "c1", "Anna", "Anna",
		[]byte(`{"type":"text","text":"fresh preview"}`), 300); err != nil {
		t.Fatalf("seed message: %v", err)
	}

	anna := dialWS(t, ts)
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

	// Validation and clamping.
	anna.send(`{"id":13,"cmd":"chats.list","data":{"page":0,"page_size":10}}`)
	anna.expectErr(13, protocol.ErrInvalidRequest)
	clamped := listChats(t, anna, 14, `{"page":1,"page_size":500}`)
	if len(clamped.Chats) > 100 {
		t.Fatalf("clamped page = %d rows, want at most 100", len(clamped.Chats))
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
		if _, _, err := srv.store.CreateChat(t.Context(), fmt.Sprintf("chat-%03d", i), "Seeder", int64(1000+i)); err != nil {
			t.Fatalf("seed chat %d: %v", i, err)
		}
	}

	c := dialWS(t, ts)
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
}

func TestStoryThreeRenameLiveNoReorderAndReplay(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	kitchen := seedChat(t, anna, "Kitchen")
	target := anna.expectOKAfter(3, `{"id":3,"cmd":"chat.create","data":{"name":"Старое"}}`)
	var targetChat protocol.Chat
	mustUnmarshal(t, target["chat"], &targetChat)
	sendText(t, anna, 4, kitchen, "m1", "keeps kitchen on top")

	bob := dialWS(t, ts)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)

	orderBefore := listChats(t, anna, 10, `{"page":1,"page_size":10}`)

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
	before := time.Now()
	renamed := anna.expectOKAfter(13, fmt.Sprintf(`{"id":13,"cmd":"chat.rename","data":{"chat_id":%q,"name":"Новое"}}`, targetChat.ChatID))
	var renamedChat protocol.Chat
	mustUnmarshal(t, renamed["chat"], &renamedChat)

	seq, name, evData := bob.expectEvent()
	if latency := time.Since(before); latency >= time.Second {
		t.Fatalf("chat.updated latency = %v, want < 1s (SC-002)", latency)
	}
	if name != protocol.EventChatUpdated {
		t.Fatalf("event = %s/%d, want chat.updated", name, seq)
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
	lateBob := dialWS(t, ts)
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
	ts, _ := newTestServer(t)

	c1 := dialWS(t, ts)
	c1.expectGreeting()
	c1.hello(1, ``)
	c2 := dialWS(t, ts)
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

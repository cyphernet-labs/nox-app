package server

import (
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

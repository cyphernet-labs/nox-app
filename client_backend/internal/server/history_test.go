package server

import (
	"fmt"
	"testing"
	"time"

	"nox.app/client-backend/internal/protocol"
)

type historyPage struct {
	Messages []protocol.Message `json:"messages"`
	HasMore  bool               `json:"has_more"`
}

func listMessages(t *testing.T, c *wsClient, id int, data string) historyPage {
	t.Helper()
	reply := c.expectOKAfter(id, fmt.Sprintf(`{"id":%d,"cmd":"messages.list","data":%s}`, id, data))
	var page historyPage
	mustUnmarshal(t, reply["messages"], &page.Messages)
	mustUnmarshal(t, reply["has_more"], &page.HasMore)
	return page
}

func TestStoryTwoBackwardWalkIsCompleteAndOrdered(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "walk")
	for i := range 25 {
		sendText(t, anna, 100+i, chatID, fmt.Sprintf("w%d", i), fmt.Sprintf("msg %d", i))
	}
	// A duplicate send must not add a 26th row.
	sendText(t, anna, 200, chatID, "w0", "msg 0")

	seen := make(map[int64]bool)
	var walked []protocol.Message
	before := int64(0)
	for {
		data := `{"chat_id":` + fmt.Sprintf("%q", chatID) + `,"limit":10}`
		if before > 0 {
			data = fmt.Sprintf(`{"chat_id":%q,"before_seq":%d,"limit":10}`, chatID, before)
		}
		page := listMessages(t, anna, 300+len(walked), data)
		for i, msg := range page.Messages {
			if i > 0 && page.Messages[i-1].Seq >= msg.Seq {
				t.Fatalf("page not ascending: %d then %d", page.Messages[i-1].Seq, msg.Seq)
			}
			if seen[msg.Seq] {
				t.Fatalf("duplicate seq %d across pages", msg.Seq)
			}
			seen[msg.Seq] = true
			walked = append(walked, msg)
		}
		if !page.HasMore {
			break
		}
		before = page.Messages[0].Seq
	}
	if len(walked) != 25 {
		t.Fatalf("walked %d messages, want 25 (dup must appear once)", len(walked))
	}
	// The author sees client_message_id on every own message.
	for _, msg := range walked {
		if msg.ClientMessageID == "" {
			t.Fatalf("author's history lost client_message_id at seq %d", msg.Seq)
		}
	}

	// A second client gets the same history WITHOUT client_message_id.
	bob := dialWS(t, ts)
	bob.expectGreeting()
	bob.hello(1, `,"label":"Bob"`)
	bobPage := listMessages(t, bob, 2, fmt.Sprintf(`{"chat_id":%q,"limit":100}`, chatID))
	if len(bobPage.Messages) != 25 {
		t.Fatalf("bob sees %d messages, want 25", len(bobPage.Messages))
	}
	for _, msg := range bobPage.Messages {
		if msg.ClientMessageID != "" {
			t.Fatalf("bob's history leaked client_message_id at seq %d", msg.Seq)
		}
	}
}

func TestStoryTwoHistoryEdges(t *testing.T) {
	ts, _ := newTestServer(t)

	c := dialWS(t, ts)
	c.expectGreeting()
	c.hello(1, ``)
	chatID := seedChat(t, c, "edges")

	// Empty chat: empty page, has_more false.
	empty := listMessages(t, c, 10, fmt.Sprintf(`{"chat_id":%q,"limit":10}`, chatID))
	if empty.HasMore || len(empty.Messages) != 0 {
		t.Fatalf("empty chat page = %+v", empty)
	}

	// Unknown chat and invalid limit.
	c.send(`{"id":11,"cmd":"messages.list","data":{"chat_id":"c_missing","limit":10}}`)
	c.expectErr(11, protocol.ErrNotFound)
	c.send(fmt.Sprintf(`{"id":12,"cmd":"messages.list","data":{"chat_id":%q,"limit":0}}`, chatID))
	c.expectErr(12, protocol.ErrInvalidRequest)
}

func TestStoryTwoTailLatencyOverLargeHistory(t *testing.T) {
	ts, srv := newTestServer(t)

	chat, _, err := srv.store.CreateChat(t.Context(), "big", "Seeder", 100)
	if err != nil {
		t.Fatalf("seed chat: %v", err)
	}
	for i := range 1000 {
		if _, _, _, err := srv.store.SendMessage(t.Context(), chat.ChatID, fmt.Sprintf("b%d", i), "Seeder", "Seeder",
			[]byte(`{"type":"text","text":"bulk"}`), int64(200+i)); err != nil {
			t.Fatalf("seed message %d: %v", i, err)
		}
	}

	c := dialWS(t, ts)
	c.expectGreeting()
	c.hello(1, ``)
	start := time.Now()
	page := listMessages(t, c, 2, fmt.Sprintf(`{"chat_id":%q,"limit":100}`, chat.ChatID))
	if elapsed := time.Since(start); elapsed >= time.Second {
		t.Fatalf("tail over 1000 messages took %v, want < 1s (SC-001)", elapsed)
	}
	if !page.HasMore || len(page.Messages) != 100 {
		t.Fatalf("tail = %d rows hasMore=%v", len(page.Messages), page.HasMore)
	}
}

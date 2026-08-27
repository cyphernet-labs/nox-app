package server

import (
	"encoding/json"
	"fmt"
	"testing"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// seedChat creates a chat and returns its id; the caller's client must have
// completed hello.
func seedChat(t *testing.T, c *wsClient, name string) string {
	t.Helper()
	data := c.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"chat.create","data":{"name":%q}}`, name))
	var chat protocol.Chat
	mustUnmarshal(t, data["chat"], &chat)
	return chat.ChatID
}

func sendText(t *testing.T, c *wsClient, id int, chatID, clientMessageID, text string) {
	t.Helper()
	c.expectOKAfter(id, fmt.Sprintf(
		`{"id":%d,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":%q,"body":{"type":"text","text":%q}}}`,
		id, chatID, clientMessageID, text))
}

// helloCursor performs session.hello with since and returns the reply cursor.
func helloCursor(t *testing.T, c *wsClient, since int64) int64 {
	t.Helper()
	data := c.hello(1, fmt.Sprintf(`,"since":%d`, since))
	var cursor int64
	mustUnmarshal(t, data["cursor"], &cursor)
	return cursor
}

func TestStoryTwoKillReconnectCatchup(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "catchup")
	sendText(t, anna, 3, chatID, "a1", "first")

	// Bob is live, sees seq 1..2, then dies.
	bob := dialWS(t, ts)
	bob.expectGreeting()
	if cursor := helloCursor(t, bob, 0); cursor != 2 {
		t.Fatalf("bob cursor = %d, want 2", cursor)
	}
	var lastSeen int64
	for range 2 {
		seq, _, _ := bob.expectEvent()
		lastSeen = seq
	}
	_ = bob.conn.Close(websocket.StatusNormalClosure, "killed")

	// Bob misses three events.
	sendText(t, anna, 4, chatID, "a2", "second")
	sendText(t, anna, 5, chatID, "a3", "third")
	sendText(t, anna, 6, chatID, "a4", "fourth")

	// Reconnect with the last seen cursor: all missed events, ascending.
	bob2 := dialWS(t, ts)
	bob2.expectGreeting()
	cursor := helloCursor(t, bob2, lastSeen)
	if cursor != 5 {
		t.Fatalf("reconnect cursor = %d, want 5", cursor)
	}
	for wantSeq := lastSeen + 1; wantSeq <= cursor; wantSeq++ {
		seq, name, _ := bob2.expectEvent()
		if seq != wantSeq || name != protocol.EventMessageNew {
			t.Fatalf("replay frame = %s/%d, want message.new/%d", name, seq, wantSeq)
		}
	}

	// Caught up (seq >= cursor reached); the stream continues live.
	sendText(t, anna, 7, chatID, "a5", "fifth")
	if seq, name, _ := bob2.expectEvent(); seq != 6 || name != protocol.EventMessageNew {
		t.Fatalf("live after catchup = %s/%d, want message.new/6", name, seq)
	}
}

func TestStoryTwoSinceEqualsCursorIsImmediatelyCaughtUp(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, ``)
	chatID := seedChat(t, anna, "quiet")
	sendText(t, anna, 3, chatID, "q1", "only")

	bob := dialWS(t, ts)
	bob.expectGreeting()
	cursor := helloCursor(t, bob, 2)
	if cursor != 2 {
		t.Fatalf("cursor = %d, want 2", cursor)
	}
	// Nothing to replay: the very first frame Bob receives is the next live
	// event, not a replayed one.
	sendText(t, anna, 4, chatID, "q2", "wake")
	if seq, _, _ := bob.expectEvent(); seq != 3 {
		t.Fatalf("first frame seq = %d, want live 3 (empty replay)", seq)
	}
}

func TestStoryTwoSinceAheadOfCursorYieldsEmptyReplay(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, ``)
	chatID := seedChat(t, anna, "ahead")

	bob := dialWS(t, ts)
	bob.expectGreeting()
	cursor := helloCursor(t, bob, 99)
	if cursor != 1 {
		t.Fatalf("cursor = %d, want 1", cursor)
	}
	// The connection stays usable, replay is empty and live delivery works:
	// the first frame Bob receives is the fresh event.
	sendText(t, anna, 3, chatID, "h1", "x")
	if seq, _, _ := bob.expectEvent(); seq != 2 {
		t.Fatalf("first frame seq = %d, want live 2 (empty replay)", seq)
	}
}

func TestStoryTwoReplayIsRepeatable(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, ``)
	chatID := seedChat(t, anna, "repeat")
	sendText(t, anna, 3, chatID, "r1", "one")
	sendText(t, anna, 4, chatID, "r2", "two")

	type replayFrame struct {
		Seq   int64
		Event string
		Data  string
	}
	collect := func() []replayFrame {
		c := dialWS(t, ts)
		c.expectGreeting()
		cursor := helloCursor(t, c, 0)
		frames := make([]replayFrame, 0, cursor)
		for range cursor {
			seq, name, data := c.expectEvent()
			raw, err := json.Marshal(data)
			if err != nil {
				t.Fatalf("re-marshal event data: %v", err)
			}
			frames = append(frames, replayFrame{Seq: seq, Event: name, Data: string(raw)})
		}
		return frames
	}

	first := collect()
	second := collect()
	if len(first) != 3 || len(second) != 3 {
		t.Fatalf("replay lengths = %d, %d, want 3 each", len(first), len(second))
	}
	for i := range first {
		if first[i] != second[i] {
			t.Fatalf("replay diverged at %d:\n%v\nvs\n%v", i, first[i], second[i])
		}
	}
}

func TestStoryTwoLiveDuringReplayLosesNothing(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, ``)
	chatID := seedChat(t, anna, "boundary")
	sendText(t, anna, 3, chatID, "b1", "pre")

	// Bob's hello (subscribe + replay) is processed by the server while live
	// traffic keeps flowing: duplicates at the boundary are tolerated, loss
	// is not (invariant 6). Bob deliberately does not read until the end -
	// frames queue up on his connection.
	bob := dialWS(t, ts)
	bob.expectGreeting()
	bob.send(`{"id":1,"cmd":"session.hello","data":{"schema":1,"since":1}}`)
	for i := range 8 {
		sendText(t, anna, 10+i, chatID, fmt.Sprintf("live%d", i), "during")
	}
	bob.expectOK(1)

	// Final log: seq 1 chat.created + 9 messages = 10. Bob asked since 1.
	const finalSeq = 10
	seen := make(map[int64]bool)
	var lastNew int64 = 1
	for len(seen) < finalSeq-1 {
		seq, _, _ := bob.expectEvent()
		if seq <= 1 {
			t.Fatalf("got seq %d, replay must start after since=1", seq)
		}
		if !seen[seq] {
			if seq < lastNew {
				t.Fatalf("first delivery of seq %d arrived after seq %d", seq, lastNew)
			}
			seen[seq] = true
			lastNew = seq
		}
	}
	for seq := int64(2); seq <= finalSeq; seq++ {
		if !seen[seq] {
			t.Fatalf("seq %d was lost across the replay boundary", seq)
		}
	}
}

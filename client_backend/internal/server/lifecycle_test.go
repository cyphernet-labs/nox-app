package server

import (
	"context"
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// TestStoryThreeSlowClientDropped floods a non-reading client until its
// outbound queue overflows: the connection must close with policy violation
// while the healthy client keeps receiving with normal latency (SC-006).
func TestStoryThreeSlowClientDropped(t *testing.T) {
	ts, _ := newTestServer(t)

	anna := dialWS(t, ts)
	anna.expectGreeting()
	anna.hello(1, `,"label":"Anna"`)
	chatID := seedChat(t, anna, "flood")
	if seq, name, _ := anna.expectEvent(); name != protocol.EventChatCreated || seq != 1 {
		t.Fatalf("anna's own chat.created = %s/%d", name, seq)
	}

	observer := dialWS(t, ts)
	observer.expectGreeting()
	observer.hello(1, `,"label":"Watcher"`)

	slow := dialWS(t, ts)
	slow.expectGreeting()
	slow.hello(1, `,"label":"Slow"`)
	// From here on the slow client never reads; large frames fill its
	// outbound path until enqueue overflows and drops it.

	body := strings.Repeat("x", 60000)
	const flood = 120
	for i := range flood {
		sendText(t, anna, 100+i, chatID, fmt.Sprintf("f%d", i), body)
		if seq, name, _ := observer.expectEvent(); name != protocol.EventMessageNew || seq != int64(2+i) {
			t.Fatalf("observer frame %d = %s/%d, want message.new/%d", i, name, seq, 2+i)
		}
	}

	// The healthy client is unaffected: one more message lands in under 1s.
	before := time.Now()
	sendText(t, anna, 900, chatID, "probe", "after flood")
	if seq, name, _ := observer.expectEvent(); name != protocol.EventMessageNew || seq != flood+2 {
		t.Fatalf("probe frame = %s/%d, want message.new/%d", name, seq, flood+2)
	}
	if latency := time.Since(before); latency >= time.Second {
		t.Fatalf("healthy client latency after slow drop = %v, want < 1s (SC-006)", latency)
	}

	// Drain the slow connection: buffered frames, then the policy-violation
	// close the server issued mid-flood.
	rctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	for {
		_, _, err := slow.conn.Read(rctx)
		if err == nil {
			continue
		}
		if status := websocket.CloseStatus(err); status != websocket.StatusPolicyViolation {
			t.Fatalf("slow client close status = %v (%v), want policy violation", status, err)
		}
		break
	}
}

// TestStoryThreeShutdownDeliversGoingAway verifies graceful shutdown: open
// WebSocket connections receive the going-away close and the server exits
// within the SC-005 window.
func TestStoryThreeShutdownDeliversGoingAway(t *testing.T) {
	ts, _ := newTestServer(t)

	c := dialWS(t, ts)
	c.expectGreeting()
	c.hello(1, ``)

	start := time.Now()
	shCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := ts.Config.Shutdown(shCtx); err != nil {
		t.Fatalf("Shutdown: %v", err)
	}
	if elapsed := time.Since(start); elapsed >= 10*time.Second {
		t.Fatalf("shutdown took %v, want < 10s (SC-005)", elapsed)
	}

	rctx, rcancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer rcancel()
	for {
		_, _, err := c.conn.Read(rctx)
		if err == nil {
			continue
		}
		if status := websocket.CloseStatus(err); status != websocket.StatusGoingAway {
			t.Fatalf("close status = %v (%v), want going away", status, err)
		}
		break
	}
}

// TestStoryThreeRestartIntegrity runs repeated full start -> write -> stop
// cycles against one database file (SC-005: 100 restarts, data intact) and
// verifies the complete replay after the final cycle, plus goroutine
// hygiene across cycles.
func TestStoryThreeRestartIntegrity(t *testing.T) {
	cycles := 100
	if testing.Short() {
		cycles = 15
	}
	path := filepath.Join(t.TempDir(), "restart.db")
	baseline := runtime.NumGoroutine()

	var chatID string
	for i := range cycles {
		// The closure guarantees the stack is released even when an
		// assertion fails mid-cycle (Fatalf runs deferred calls via Goexit).
		func() {
			ts, _, closeAll := openStack(t, path)
			defer closeAll()
			c := dialWS(t, ts)
			c.expectGreeting()
			// A stable device key across cycles: client_message_id comes back
			// only to the message's own author, and every nameless greeting is
			// now a different person.
			c.hello(1, `,"device_key":"dev-restart"`)
			if i == 0 {
				chatID = seedChat(t, c, "restart")
			}
			sendText(t, c, 3, chatID, fmt.Sprintf("cycle-%d", i), fmt.Sprintf("message %d", i))
			_ = c.conn.Close(websocket.StatusNormalClosure, "cycle done")
		}()
	}

	// Final cycle: a fresh process replays the whole history in order.
	ts, _, closeAll := openStack(t, path)
	closed := false
	defer func() {
		if !closed {
			closeAll()
		}
	}()
	c := dialWS(t, ts)
	c.expectGreeting()
	cursor := helloCursor(t, c, 0, `,"device_key":"dev-restart"`)
	if want := int64(cycles + 1); cursor != want {
		t.Fatalf("cursor after %d cycles = %d, want %d", cycles, cursor, want)
	}
	if seq, name, _ := c.expectEvent(); name != protocol.EventChatCreated || seq != 1 {
		t.Fatalf("replay[0] = %s/%d, want chat.created/1", name, seq)
	}
	for i := range cycles {
		seq, name, data := c.expectEvent()
		if name != protocol.EventMessageNew || seq != int64(i+2) {
			t.Fatalf("replay[%d] = %s/%d, want message.new/%d", i+1, name, seq, i+2)
		}
		var msg protocol.Message
		mustUnmarshal(t, data["client_message_id"], &msg.ClientMessageID)
		if msg.ClientMessageID != fmt.Sprintf("cycle-%d", i) {
			t.Fatalf("replay[%d] client_message_id = %q", i+1, msg.ClientMessageID)
		}
	}

	// Close the final stack too, then check goroutine hygiene: every cycle
	// must have released its stack.
	_ = c.conn.Close(websocket.StatusNormalClosure, "verified")
	closeAll()
	closed = true
	deadline := time.Now().Add(3 * time.Second)
	for {
		if n := runtime.NumGoroutine(); n <= baseline+8 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("goroutines = %d, baseline %d: cycles are leaking", runtime.NumGoroutine(), baseline)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

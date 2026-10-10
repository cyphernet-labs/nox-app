package server

import (
	"context"
	"fmt"
	"log/slog"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// A /ws connection whose key nobody paired may only pair (contract §1, §8A),
// and what it may hold is bounded: a deadline to pair by, and a cap on how many
// are open at once, the oldest closed for a newcomer. A paired device's
// connection is held to neither.

// unpairedHeld counts the connections srv holds as unpaired.
func unpairedHeld(srv *Server) int {
	srv.mu.Lock()
	defer srv.mu.Unlock()
	return srv.unpaired.Len()
}

// A key made for the occasion passes the channel check like any other, and
// without a deadline the server's own pings would keep its connection alive
// for as long as its holder liked. One that has not paired in time is closed,
// and holds no place after.
func TestAConnectionThatDoesNotPairInTimeIsClosed(t *testing.T) {
	const deadline = 300 * time.Millisecond
	ts, srv := newTestServerWith(t, func(s *Server) { s.unpairedTimeout = deadline })

	stranger := dialWS(t, ts, srv)
	stranger.expectGreeting()
	start := time.Now()
	waitClosed(t, stranger, websocket.StatusPolicyViolation)
	if took := time.Since(start); took < deadline/2 {
		t.Fatalf("closed after %v, well inside its deadline of %v", took, deadline)
	}
	eventually(t, "the stranger holds no place", func() bool { return unpairedHeld(srv) == 0 })
}

// The deadline is a stranger's only. A connection that pairs in time leaves it,
// whether it pairs on that connection or on another one before it greets; and
// a paired device's connection never had one, greeted or not.
func TestAConnectionThatPairsInTimeOrIsPairedStaysOpen(t *testing.T) {
	const deadline = 300 * time.Millisecond
	ts, srv := newTestServerWith(t, func(s *Server) { s.unpairedTimeout = deadline })
	pastIt := func() { time.Sleep(3 * deadline) }

	t.Run("pairs on this connection", func(t *testing.T) {
		d := newDevice(t)
		c := dialAs(t, ts, srv, d)
		c.expectGreeting()
		c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test"}}`, mustClaimToken(t, srv)))
		c.expectOK(1)
		pastIt()
		c.send(`{"id":2,"cmd":"session.hello","data":{"schema":1}}`)
		c.expectOK(2)
	})

	t.Run("pairs on another connection, then greets on this one", func(t *testing.T) {
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		// hello pairs the key on a connection of its own first.
		c.hello(1, "")
		pastIt()
		c.send(`{"id":2,"cmd":"device.list","data":{}}`)
		c.expectOK(2)
	})

	t.Run("a paired device that has not greeted", func(t *testing.T) {
		c := dialAs(t, ts, srv, pairedDevice(t, ts, srv))
		c.expectGreeting()
		pastIt()
		c.hello(1, "")
	})

	if n := unpairedHeld(srv); n != 0 {
		t.Fatalf("%d connections held as unpaired, want none", n)
	}
}

// Connections of keys nobody paired are capped, and a newcomer past the cap is
// taken while the oldest is closed: whoever holds the places cannot keep a
// device from pairing by holding them. A paired device's connection is not one
// of them, and a stranger that pairs leaves them. The closing reaches the log
// as a count, with no key in it.
func TestUnpairedConnectionsAreCappedAndTheOldestMakesRoom(t *testing.T) {
	buf := &syncBuffer{}
	const most = 3
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "unpaired.db"), slog.New(slog.NewTextHandler(buf, nil)),
		func(s *Server) { s.maxUnpaired = most })
	t.Cleanup(closeAll)
	home := pairedDevice(t, ts, srv)

	var strangers []*wsClient
	for range most {
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		strangers = append(strangers, c)
	}
	// The person's own device makes nobody leave.
	mine := dialAs(t, ts, srv, home)
	mine.expectGreeting()
	mine.hello(1, "")
	if n := unpairedHeld(srv); n != most {
		t.Fatalf("%d connections held as unpaired, want the %d strangers", n, most)
	}

	// One stranger more is taken, and the oldest goes.
	newcomer := dialWS(t, ts, srv)
	newcomer.expectGreeting()
	waitClosed(t, strangers[0], websocket.StatusTryAgainLater)
	if n := unpairedHeld(srv); n != most {
		t.Fatalf("%d connections held as unpaired after the newcomer, want the cap of %d", n, most)
	}

	// The newcomer pairs - with an invite the person's device issued - and
	// leaves the count; the others are untouched.
	invite, err := srv.store.IssueDeviceInvite(context.Background(), home.pub, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	newcomer.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test"}}`, invite))
	newcomer.expectOK(1)
	if n := unpairedHeld(srv); n != most-1 {
		t.Fatalf("%d connections held as unpaired after one paired, want %d", n, most-1)
	}
	for _, c := range strangers[1:] {
		c.send(`{"id":1,"cmd":"session.hello","data":{"schema":1}}`)
		c.expectErr(1, protocol.ErrUnauthenticated)
	}

	eventually(t, "the closing is logged", func() bool {
		return strings.Contains(buf.String(), `msg="unpaired connections closed to make room" closed=1`)
	})
	log := buf.String()
	for _, d := range []*device{home, strangers[0].dev, newcomer.dev} {
		if strings.Contains(log, d.pub) {
			t.Fatalf("a device key reached the log:\n%s", log)
		}
	}
}

package server

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// connsBy counts registered connections by where they came in.
func connsBy(srv *Server) (direct, onion int) {
	srv.mu.Lock()
	defer srv.mu.Unlock()
	for c := range srv.conns {
		if c.viaOnion {
			onion++
		} else {
			direct++
		}
	}
	return direct, onion
}

func TestTheOnionEntryMarksItsConnectionsAndTheirTimeouts(t *testing.T) {
	st := newOnionStack(t)
	direct := dialWS(t, st.ts, st.srv)
	direct.expectGreeting()
	onion := dialWS(t, st.onion, st.srv)
	onion.expectGreeting()

	eventually(t, "one of each", func() bool {
		d, o := connsBy(st.srv)
		return d == 1 && o == 1
	})
	st.srv.mu.Lock()
	defer st.srv.mu.Unlock()
	for c := range st.srv.conns {
		want := st.srv.writeTimeout
		if c.viaOnion {
			want = st.srv.onionTimeout
		}
		if c.writeTimeout != want {
			t.Errorf("viaOnion=%v: writeTimeout = %v, want %v", c.viaOnion, c.writeTimeout, want)
		}
	}
}

// SC-009 at test scale: a peer that answers pings slowly - here, not at all -
// is dropped on the direct path after its timeout and kept on the onion path,
// whose timeout is the longer one. A client that never calls Read never
// answers a ping, which is exactly a Tor round trip that takes too long.
func TestASlowPeerIsKeptOnOnionAndDroppedOnTheDirectPath(t *testing.T) {
	st := newOnionStack(t, func(s *Server) {
		s.pingInterval = 20 * time.Millisecond
		s.writeTimeout = 60 * time.Millisecond
		s.onionTimeout = time.Minute
	})
	_ = dialWS(t, st.ts, st.srv)    // never reads
	_ = dialWS(t, st.onion, st.srv) // never reads
	eventually(t, "both registered", func() bool {
		d, o := connsBy(st.srv)
		return d == 1 && o == 1
	})
	// The direct peer's ping times out after 60 ms; leaving the registry then
	// takes the close handshake, which waits ~5 s for a peer that never
	// answers. The onion peer's ping has a minute.
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		if d, _ := connsBy(st.srv); d == 0 {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	d, o := connsBy(st.srv)
	if d != 0 {
		t.Fatal("the direct peer that never answered a ping is still registered")
	}
	if o != 1 {
		t.Fatal("the onion peer was dropped on the direct timeout")
	}
}

// Neither the service page nor /health is on the onion entry: the page has its
// own loopback listener, and /health moved there with 044.
func TestTheStatusPageIsNotOnTheOnionEntry(t *testing.T) {
	st := newOnionStack(t)
	for _, path := range []string{"/", "/health"} {
		resp, err := st.onion.Client().Get(st.onion.URL + path)
		if err != nil {
			t.Fatalf("GET %s: %v", path, err)
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("GET %s on the onion entry = %d, want 404 - it lives on the service page's loopback listener", path, resp.StatusCode)
		}
	}
}

// presentToken presents a token as d through the entry ts serves, and reports
// the answer.
func presentToken(t *testing.T, ts *httptest.Server, token string, d *device) (bool, string) {
	t.Helper()
	c := dialAs(t, ts, nil, d)
	defer func() { _ = c.conn.Close(websocket.StatusNormalClosure, "") }()
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test"}}`, token))
	reply := c.expectReply(1)
	var ok bool
	mustUnmarshal(t, reply["ok"], &ok)
	if ok {
		return true, ""
	}
	var wireErr protocol.WireError
	mustUnmarshal(t, reply["error"], &wireErr)
	return false, wireErr.Code
}

func TestAClaimOverOnionIsRefusedAndTheTokenSurvives(t *testing.T) {
	st := newOnionStack(t)
	token := mustClaimToken(t, st.srv)
	d := newDevice(t)

	if ok, code := presentToken(t, st.onion, token, d); ok || code != protocol.ErrInvalidToken {
		t.Fatalf("claim over onion: ok=%v code=%q, want invalid_token", ok, code)
	}
	// The refusal rolled back: the same token still claims at home.
	if ok, code := presentToken(t, st.ts, token, d); !ok {
		t.Fatalf("the token did not survive the refusal: %q", code)
	}
}

func TestAReplayedClaimOverOnionIsRefused(t *testing.T) {
	st := newOnionStack(t)
	token := mustClaimToken(t, st.srv)
	d := newDevice(t)
	if ok, code := presentToken(t, st.ts, token, d); !ok {
		t.Fatalf("claim at home: %q", code)
	}
	if ok, code := presentToken(t, st.onion, token, d); ok || code != protocol.ErrInvalidToken {
		t.Fatalf("replay over onion: ok=%v code=%q, want invalid_token", ok, code)
	}
}

// readLink parses a link the server issued, failing the test if it does not
// read back.
func readLink(t *testing.T, link string) PairingLink {
	t.Helper()
	parsed, err := ParsePairingLink(link)
	if err != nil {
		t.Fatalf("the link does not read back: %v (%s)", err, link)
	}
	return parsed
}

func TestAnInviteAskedOverOnionCarriesADirectAddressNotTheOnionName(t *testing.T) {
	st := newOnionStack(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8080"
		s.listIPs = ips("fd00::1", "192.168.1.20", "10.0.0.5")
	})
	// Paired at home - a claim never goes over onion - then greeting over it.
	d := pairedDevice(t, st.ts, st.srv)
	owner := dialAs(t, st.onion, st.srv, d)
	owner.expectGreeting()
	owner.hello(1, "")
	owner.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	data := owner.expectOK(2)
	var link string
	mustUnmarshal(t, data["link"], &link)
	direct := readLink(t, link).Direct
	if len(direct) != 1 || direct[0] != "192.168.1.20:8080" {
		t.Fatalf("direct = %v, want the head of the list - the home address - rather than the Host the onion request carried", direct)
	}
}

// A ping waiting for its pong does not hold the writer. Over Tor a round trip
// is seconds; a writer parked on that wait let a burst of live frames fill the
// queue behind it until a healthy connection was dropped as a slow consumer.
// Here the onion device answers no ping at all - it reads nothing during the
// burst - and must still be there, with every frame, when it reads again.
func TestAPingWaitingForItsPongDoesNotStallTheWriter(t *testing.T) {
	st := newOnionStack(t, func(s *Server) {
		s.pingInterval = 20 * time.Millisecond
		s.onionTimeout = time.Minute
	})
	home := dialWS(t, st.ts, st.srv)
	home.expectGreeting()
	home.hello(1, "")
	slow := dialWS(t, st.onion, st.srv)
	slow.expectGreeting()
	slow.hello(1, "")
	_, onionBefore := connsBy(st.srv)
	// Several ticks with nobody reading on the onion side: a ping is now
	// waiting for a pong that will not come for as long as the burst lasts.
	time.Sleep(100 * time.Millisecond)

	const burst = 120 // more than the 64-frame queue and the hub's buffer hold together
	for i := range burst {
		home.send(fmt.Sprintf(`{"id":%d,"cmd":"chat.create","data":{"name":"burst-%d"}}`, 10+i, i))
		home.expectOK(10 + i)
	}
	if _, onion := connsBy(st.srv); onion != onionBefore {
		t.Fatalf("onion connections %d -> %d: the device was dropped while its pong was outstanding", onionBefore, onion)
	}
	for seen := 0; seen < burst; {
		frame := slow.read()
		var event string
		if raw, ok := frame["event"]; ok {
			mustUnmarshal(t, raw, &event)
		}
		if event == protocol.EventChatCreated {
			seen++
		}
	}
}

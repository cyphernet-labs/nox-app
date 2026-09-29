package server

import (
	"context"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"strings"
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

func TestTheStatusPageIsNotOnTheOnionEntry(t *testing.T) {
	st := newOnionStack(t)
	resp, err := pinnedClient(st.onion).Get(st.onion.URL + "/")
	if err != nil {
		t.Fatalf("GET /: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("GET / on the onion entry = %d, want 404 - the status page lives on its own loopback listener", resp.StatusCode)
	}
	health, err := pinnedClient(st.onion).Get(st.onion.URL + "/health")
	if err != nil {
		t.Fatalf("GET /health: %v", err)
	}
	_ = health.Body.Close()
	if health.StatusCode != http.StatusOK {
		t.Fatalf("GET /health on the onion entry = %d, want 200 - everything but claim works there", health.StatusCode)
	}
}

func presentToken(t *testing.T, ts interface {
	Client() *http.Client
}, url string, token string, d *device) (bool, string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, url+"/ws", &websocket.DialOptions{HTTPClient: ts.Client()})
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close(websocket.StatusNormalClosure, "") }()
	c := &wsClient{t: t, conn: conn, ctx: ctx}
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test"}}`, token, d.pub))
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

	if ok, code := presentToken(t, st.onion, st.onion.URL, token, d); ok || code != protocol.ErrInvalidToken {
		t.Fatalf("claim over onion: ok=%v code=%q, want invalid_token", ok, code)
	}
	// The refusal rolled back: the same token still claims at home.
	if ok, code := presentToken(t, st.ts, st.ts.URL, token, d); !ok {
		t.Fatalf("the token did not survive the refusal: %q", code)
	}
}

func TestAReplayedClaimOverOnionIsRefused(t *testing.T) {
	st := newOnionStack(t)
	token := mustClaimToken(t, st.srv)
	d := newDevice(t)
	if ok, code := presentToken(t, st.ts, st.ts.URL, token, d); !ok {
		t.Fatalf("claim at home: %q", code)
	}
	if ok, code := presentToken(t, st.onion, st.onion.URL, token, d); ok || code != protocol.ErrInvalidToken {
		t.Fatalf("replay over onion: ok=%v code=%q, want invalid_token", ok, code)
	}
}

// decodeLink splits a pairing link into its version and the host it names.
func decodeLink(t *testing.T, link string) (version byte, payload []byte, host string) {
	t.Helper()
	raw, err := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(link, pairingLinkPrefix))
	if err != nil {
		t.Fatalf("link payload: %v", err)
	}
	switch raw[1] {
	case hostTypeIPv4:
		host = net.IP(raw[2:6]).String()
	case hostTypeIPv6:
		host = net.IP(raw[2:18]).String()
	case hostTypeDNS:
		host = string(raw[3 : 3+int(raw[2])])
	}
	return raw[0], raw, host
}

func TestAnInviteAskedOverOnionCarriesADirectAddressNotTheOnionName(t *testing.T) {
	st := newOnionStack(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8080"
		s.listIPs = ips("fd00::1", "192.168.1.20", "10.0.0.5")
	})
	// Paired at home - a claim never goes over onion - then greeting over it.
	d := pairedDevice(t, st.ts, st.srv)
	owner := dialWS(t, st.onion, st.srv)
	owner.expectGreeting()
	owner.greet(t, 1, d, "")
	owner.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	data := owner.expectOK(2)
	var link string
	mustUnmarshal(t, data["link"], &link)
	version, _, host := decodeLink(t, link)
	if version != pairingLinkVersion {
		t.Fatalf("version = %d, want 1 without onion", version)
	}
	if host != "192.168.1.20" {
		t.Fatalf("host = %q, want the head of the list - the home address - rather than the Host the onion request carried", host)
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

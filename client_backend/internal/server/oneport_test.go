package server

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// One port for every path (045, FR-009). tor runs as a separate service and
// forwards the onion service to the main port, so a connection through Tor is
// a TCP connection like any other: the same channel, the same rights, the same
// timeouts. All that can still tell it apart is the Host header it carries.

// dialThroughOnion opens a WebSocket as d the way a device reaching the onion
// service does: the same channel to the same port, with the onion name in Host.
func dialThroughOnion(t *testing.T, ts *httptest.Server, srv *Server, d *device, opts ...func(*websocket.DialOptions)) (*wsClient, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	dial := &websocket.DialOptions{HTTPClient: channelOf(t, ts).clientAs(d), Host: testOnionAddr + ":443"}
	for _, opt := range opts {
		opt(dial)
	}
	conn, resp, err := websocket.Dial(ctx, ts.URL+"/ws", dial)
	if resp != nil && resp.Body != nil {
		_ = resp.Body.Close()
	}
	if err != nil {
		return nil, err
	}
	t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "") })
	conn.SetReadLimit(1 << 20)
	return &wsClient{t: t, conn: conn, ctx: ctx, dev: d, srv: srv, ts: ts}, nil
}

// The slow path's budget is everybody's: nothing on the server can pick out a
// connection from tor to give it a longer one, so no connection gets a shorter
// one. A round trip through Tor can take seconds; 30 s covers a 10 s one three
// times over.
func TestEveryConnectionGetsTheSlowPathTimeouts(t *testing.T) {
	srv := New(config.Config{}, nil, nil, nil, slog.New(slog.DiscardHandler))
	// The main port's http.Server the way Run builds it.
	main := &http.Server{}
	srv.configureMain(main)
	for name, got := range map[string]time.Duration{
		"the frame write and pong wait":   srv.writeTimeout,
		"TLS and the channel check":       srv.channelTimeout,
		"the request headers on the port": main.ReadHeaderTimeout,
		// Where nothing of ours reads it (boundRequestBody).
		"a request body": srv.bodyTimeout,
	} {
		if got != 30*time.Second {
			t.Errorf("%s: %v, want 30s", name, got)
		}
	}
	if main.ConnState == nil {
		t.Error("nothing bounds a body nothing of ours reads")
	}
	// Answered by net/http itself, "OPTIONS *" would never reach the door.
	if !main.DisableGeneralOptionsHandler {
		t.Error(`net/http answers "OPTIONS *" itself, past the door`)
	}
	// A ping goes out before its predecessor's budget runs out, or a quiet
	// connection would be cut by its own keepalive.
	if srv.pingInterval >= srv.writeTimeout {
		t.Errorf("ping every %v with a %v wait for the pong", srv.pingInterval, srv.writeTimeout)
	}
	// Between two requests a connection waits two minutes at most - and no
	// less, or the server would close connections the app still means to
	// use (dart:io lets an idle one go after 15 s).
	if main.IdleTimeout != 2*time.Minute {
		t.Errorf("a connection between two requests: %v, want 2m", main.IdleTimeout)
	}
}

// A connection kept for the next request waits for it for the idle timeout
// and no longer. Only a paired device's connection is kept at all - a
// stranger's ends with its answer (unpaired_test.go) - and without the timeout
// one would stay for as long as its peer liked, a revoked device's among them.
func TestAnIdleConnectionIsClosedAfterItsIdleTimeout(t *testing.T) {
	const idle = 300 * time.Millisecond
	ts, srv := newTestServerWith(t, func(s *Server) { s.idleTimeout = idle })
	c := openRawChannel(t, ts, pairedDevice(t, ts, srv))

	// One request - a paired device's with a token that is no token - and
	// then nothing at all.
	resp := c.ask("GET /files/not-a-token HTTP/1.1\r\nHost: nox\r\n\r\n")
	if resp.StatusCode != http.StatusNotFound || resp.Close {
		t.Fatalf("answer %d (close=%v), want a 404 that keeps the connection: anything else proves nothing here",
			resp.StatusCode, resp.Close)
	}
	if took := c.closedWithin(5 * time.Second); took < idle/2 {
		t.Fatalf("closed %v after the answer, well inside its idle timeout of %v", took, idle)
	}
}

// A claim through the onion service is a claim like any other (045, FR-008):
// the very first device may pair through Tor, from anywhere, and then greet
// the same way.
func TestAClaimThroughTheOnionServiceIsAClaimLikeAnyOther(t *testing.T) {
	ts, srv := newTestServer(t)
	token := mustClaimToken(t, srv)
	d := newDevice(t)

	c, err := dialThroughOnion(t, ts, srv, d)
	if err != nil {
		t.Fatalf("dial through the onion service: %v", err)
	}
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test"}}`, token))
	data := c.expectOK(1)
	var id identity
	mustUnmarshal(t, data["identity"], &id)
	if !id.Created {
		t.Fatalf("the claim did not create the person: %+v", id)
	}

	again, err := dialThroughOnion(t, ts, srv, d)
	if err != nil {
		t.Fatalf("dial again: %v", err)
	}
	again.expectGreeting()
	again.send(`{"id":1,"cmd":"session.hello","data":{"schema":1}}`)
	again.expectOK(1)
}

// `pair` still answers an old client that sends an access key - it is skipped
// like any field this server does not know - and device.setAccessKey is now an
// unknown command like any other.
func TestAccessKeysAreGoneFromTheWire(t *testing.T) {
	ts, srv := newTestServer(t)
	token := mustClaimToken(t, srv)
	d := newDevice(t)
	c := dialAs(t, ts, srv, d)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test","access_key":"not even base64!"}}`, token))
	c.expectOK(1)

	g := dialAs(t, ts, srv, d)
	g.expectGreeting()
	g.hello(1, "")
	g.send(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":"AAAA"}}`)
	g.expectErr(2, protocol.ErrInvalidRequest)

	var columns int
	if err := readDB(t, srv).QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pragma_table_info('devices') WHERE name = 'access_key'").Scan(&columns); err != nil {
		t.Fatalf("inspect devices: %v", err)
	}
	if columns != 0 {
		t.Fatal("devices still has an access_key column")
	}
}

// Through the onion service, Host is the onion name - useless to a device at
// home - so an invite asked for that way takes its direct address from the
// head of the list. The onion service rides along at the end as always.
func TestAnInviteAskedThroughTheOnionServiceCarriesADirectAddress(t *testing.T) {
	ts, srv := newTestServerWith(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8080"
		s.listIPs = ips("fd00::1", "192.168.1.20", "10.0.0.5")
	})
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	srv.refreshAddresses(t.Context())
	d := pairedDevice(t, ts, srv)
	c, err := dialThroughOnion(t, ts, srv, d)
	if err != nil {
		t.Fatalf("dial through the onion service: %v", err)
	}
	c.expectGreeting()
	c.hello(1, "")
	link, onion, public := inviteOver(t, c, 2, `{}`)
	got := readLink(t, link)
	if !slices.Equal(got.Direct, []string{"192.168.1.20:8080"}) {
		t.Fatalf("direct = %v, want the head of the list rather than the onion name the request carried", got.Direct)
	}
	if !onion || public || !got.Onion.Equal(onionKeyOf(t, testOnionAddr)) {
		t.Fatalf("onion=%v public=%v key=%x, want the stored onion service", onion, public, got.Onion)
	}
}

// The library's refusal quotes Host, and through the onion service Host is the
// onion name. The line says what happened and masks the name (FR-022).
func TestARefusedUpgradeThroughTheOnionServiceKeepsTheAddressOutOfTheLog(t *testing.T) {
	logs := &syncBuffer{}
	ts, srv := newTestServerLogging(t, slog.New(slog.NewTextHandler(logs, nil)))
	_, err := dialThroughOnion(t, ts, srv, newDevice(t), func(o *websocket.DialOptions) {
		o.HTTPHeader = http.Header{"Origin": {"http://evil.example"}}
	})
	if err == nil {
		t.Fatal("a cross-origin upgrade was accepted")
	}
	eventually(t, "the refusal is logged", func() bool { return strings.Contains(logs.String(), "websocket accept failed") })
	if !strings.Contains(logs.String(), "[onion]") {
		t.Fatalf("the refusal no longer quotes Host, so this test proves nothing:\n%s", logs.String())
	}
	if strings.Contains(logs.String(), strings.TrimSuffix(testOnionAddr, ".onion")) {
		t.Fatalf("the onion address reached the log:\n%s", logs.String())
	}
}

// A ping waiting for its pong does not hold the writer. Through Tor a round
// trip is seconds; a writer parked on that wait let a burst of live frames fill
// the queue behind it until a healthy connection was dropped as a slow
// consumer. Here a device answers no ping at all - it reads nothing during the
// burst - and must still be there, with every frame, when it reads again.
func TestAPingWaitingForItsPongDoesNotStallTheWriter(t *testing.T) {
	ts, srv := newTestServerWith(t, func(s *Server) {
		s.pingInterval = 20 * time.Millisecond
	})
	home := dialWS(t, ts, srv)
	home.expectGreeting()
	home.hello(1, "")
	slow, err := dialThroughOnion(t, ts, srv, newDevice(t))
	if err != nil {
		t.Fatalf("dial through the onion service: %v", err)
	}
	slow.expectGreeting()
	slow.hello(1, "")
	registered := func() int {
		srv.mu.Lock()
		defer srv.mu.Unlock()
		return len(srv.conns)
	}
	before := registered()
	// Several ticks with nobody reading on the slow side: a ping is now
	// waiting for a pong that will not come for as long as the burst lasts.
	time.Sleep(100 * time.Millisecond)

	const burst = 120 // more than the 64-frame queue and the hub's buffer hold together
	for i := range burst {
		home.send(fmt.Sprintf(`{"id":%d,"cmd":"chat.create","data":{"name":"burst-%d"}}`, 10+i, i))
		home.expectOK(10 + i)
	}
	if after := registered(); after != before {
		t.Fatalf("connections %d -> %d: the device was dropped while its pong was outstanding", before, after)
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

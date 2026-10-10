package server

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

// A /ws connection whose key nobody paired may only pair (contract §1, §8A),
// and what it may hold is bounded: a deadline to pair by, and a cap on how many
// are open at once, the oldest closed for a newcomer. On any other path such a
// connection serves one request: every answer but a WebSocket upgrade ends it.
// A paired device's connection is held to none of this.

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
		c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, mustMachineLink(t, srv)))
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

	// The newcomer pairs - with a machine link, which pairs at once - and
	// leaves the count; the others are untouched.
	newcomer.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, mustMachineLink(t, srv)))
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

// rawChannel is one channel connection over which a test speaks HTTP by hand,
// so that it can send what no well-behaved client would: a body it declares
// and never sends, a request no handler of ours serves.
type rawChannel struct {
	t    *testing.T
	conn *tls.Conn
	br   *bufio.Reader
}

// openRawChannel opens a channel as d: TLS and the check, and no byte of HTTP.
func openRawChannel(t *testing.T, ts *httptest.Server, d *device) *rawChannel {
	t.Helper()
	ch := channelOf(t, ts)
	conn, err := dialChannel(t.Context(), ch.addr, ch.serverKey, d.priv)
	if err != nil {
		t.Fatalf("open a channel: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return &rawChannel{t: t, conn: conn, br: bufio.NewReader(conn)}
}

// send writes a request's head, and nothing after it.
func (c *rawChannel) send(head string) {
	c.t.Helper()
	if _, err := io.WriteString(c.conn, head); err != nil {
		c.t.Fatalf("write the request: %v", err)
	}
}

// answer reads the head of the next response within d, leaving its body to
// the caller.
func (c *rawChannel) answer(d time.Duration) *http.Response {
	c.t.Helper()
	if err := c.conn.SetReadDeadline(time.Now().Add(d)); err != nil {
		c.t.Fatalf("set a deadline: %v", err)
	}
	resp, err := http.ReadResponse(c.br, nil)
	if err != nil {
		c.t.Fatalf("no answer within %v: %v", d, err)
	}
	return resp
}

// ask sends a request's head and reads the whole answer.
func (c *rawChannel) ask(head string) *http.Response {
	c.t.Helper()
	c.send(head)
	resp := c.answer(5 * time.Second)
	if _, err := io.Copy(io.Discard, resp.Body); err != nil {
		c.t.Fatalf("read the answer's body: %v", err)
	}
	_ = resp.Body.Close()
	return resp
}

// closedWithin fails unless the server ends the connection within d, having
// sent nothing more, and returns how long that took.
func (c *rawChannel) closedWithin(d time.Duration) time.Duration {
	c.t.Helper()
	start := time.Now()
	if err := c.conn.SetReadDeadline(start.Add(d)); err != nil {
		c.t.Fatalf("set a deadline: %v", err)
	}
	n, err := c.br.Read(make([]byte, 1))
	var ne net.Error
	switch {
	case n > 0:
		c.t.Fatal("the server sent more after its answer")
	case errors.As(err, &ne) && ne.Timeout():
		c.t.Fatalf("the connection was still open %v after the answer", d)
	case err == nil:
		c.t.Fatal("a read returned neither bytes nor an error")
	}
	return time.Since(start)
}

// A key nobody paired gets one request out of a connection: every answer but
// a WebSocket upgrade says "Connection: close", and the connection ends right
// behind it. Kept open, the connection would be the stranger's for as long as
// it asked again within each idle timeout - and a body declared and never
// sent would hold it with no further byte, because net/http reads the rest of
// a body before it lets a connection go. Neither the idle timeout nor the body
// timeout is scaled here: what ends the connection must be the answer.
func TestAStrangersConnectionEndsWithItsAnswer(t *testing.T) {
	ts, _ := newTestServer(t)
	for _, tc := range []struct {
		name, head string
		want       int
	}{
		{"a refused transfer", "GET /files/whatever HTTP/1.1\r\nHost: nox\r\n\r\n", http.StatusUnauthorized},
		{"a path the port does not serve", "GET /health HTTP/1.1\r\nHost: nox\r\n\r\n", http.StatusNotFound},
		{"a method the path does not take", "DELETE /ws HTTP/1.1\r\nHost: nox\r\n\r\n", http.StatusMethodNotAllowed},
		// The library answers this one with a "Connection: Upgrade" of its own.
		{"a request for /ws that asks for no upgrade", "GET /ws HTTP/1.1\r\nHost: nox\r\n\r\n", http.StatusUpgradeRequired},
		{"an upgrade from another origin", "GET /ws HTTP/1.1\r\nHost: nox\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n" +
			"Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nOrigin: http://evil.example\r\n\r\n",
			http.StatusForbidden},
		// net/http answers this one itself unless told not to - a 200 that
		// keeps the connection - and the mux, once it is told, with a 400.
		{"a request for the whole server", "OPTIONS * HTTP/1.1\r\nHost: nox\r\n\r\n", http.StatusBadRequest},
		{"a body declared and never sent", "PUT /files/whatever HTTP/1.1\r\nHost: nox\r\nContent-Length: 1000\r\n\r\n",
			http.StatusUnauthorized},
		{"a chunked body never sent", "PUT /files/whatever HTTP/1.1\r\nHost: nox\r\nTransfer-Encoding: chunked\r\n\r\n",
			http.StatusUnauthorized},
		{"a body for a path the port does not serve", "POST /anything HTTP/1.1\r\nHost: nox\r\nContent-Length: 10\r\n\r\n",
			http.StatusNotFound},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := openRawChannel(t, ts, newDevice(t))
			resp := c.ask(tc.head)
			if resp.StatusCode != tc.want || !resp.Close {
				t.Fatalf("answer %d (close=%v), want a %d that ends the connection", resp.StatusCode, resp.Close, tc.want)
			}
			c.closedWithin(5 * time.Second)
		})
	}
}

// net/http answers some requests itself, before any handler of ours runs - an
// Expect it does not support among them - and then reads what is left of a
// declared body before it lets the connection go. No handler sees such a
// request, so no handler can end it; what does is the read deadline every
// request gets once its headers are in.
func TestARequestNetHTTPAnswersItselfCannotHoldTheConnection(t *testing.T) {
	const bodyTimeout = 300 * time.Millisecond
	ts, srv := newTestServerWith(t, func(s *Server) { s.bodyTimeout = bodyTimeout })
	for name, d := range map[string]*device{"a stranger": newDevice(t), "a paired device": pairedDevice(t, ts, srv)} {
		t.Run(name, func(t *testing.T) {
			c := openRawChannel(t, ts, d)
			resp := c.ask("PUT /files/whatever HTTP/1.1\r\nHost: nox\r\nExpect: the-impossible\r\nContent-Length: 1000\r\n\r\n")
			if resp.StatusCode != http.StatusExpectationFailed {
				t.Fatalf("answer %d, want net/http's own 417: anything else proves nothing here", resp.StatusCode)
			}
			c.closedWithin(10 * bodyTimeout)
		})
	}
}

// A paired device's connection is held to none of this: an answer leaves it
// open for the next request, the way the app reuses one connection for its
// transfers.
func TestAPairedDevicesConnectionOutlivesItsAnswers(t *testing.T) {
	ts, srv := newTestServer(t)
	c := openRawChannel(t, ts, pairedDevice(t, ts, srv))
	for _, head := range []string{
		"GET /files/not-a-token HTTP/1.1\r\nHost: nox\r\n\r\n",
		"GET /health HTTP/1.1\r\nHost: nox\r\n\r\n",
		"GET /files/still-not-a-token HTTP/1.1\r\nHost: nox\r\n\r\n",
	} {
		if resp := c.ask(head); resp.StatusCode != http.StatusNotFound || resp.Close {
			t.Fatalf("%q: answer %d (close=%v), want a 404 that keeps the connection",
				strings.SplitN(head, "\r\n", 2)[0], resp.StatusCode, resp.Close)
		}
	}
}

// A paired device's request leaves its connection usable however long it
// runs. The deadline boundRequestBody sets once the headers are in must never
// reach net/http's own read behind a request with no body left - its watch
// for the peer hanging up, which runs under a download - because a deadline
// firing there ends the connection's context, and every later request on the
// connection fails. net/http lifts the deadline as that read starts; this
// holds the server to never setting one after it.
func TestAPairedDevicesLongDownloadLeavesItsConnectionUsable(t *testing.T) {
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "long.db"), nil, func(s *Server) {
		s.bodyTimeout = 100 * time.Millisecond
	})
	t.Cleanup(closeAll)
	c := greeted(t, ts, srv)
	// More than the socket buffers on both ends hold, read with pauses: the
	// handler is still writing many times the body timeout later.
	payload := randomPayload(t, 8<<20)
	token := downloadBegin(t, c, 3, storeFile(t, srv, payload))

	raw := openRawChannel(t, ts, c.dev)
	raw.send("GET /files/" + token + " HTTP/1.1\r\nHost: nox\r\n\r\n")
	resp := raw.answer(5 * time.Second)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("download = %d, want 200", resp.StatusCode)
	}
	if err := raw.conn.SetReadDeadline(time.Now().Add(30 * time.Second)); err != nil {
		t.Fatalf("set a deadline: %v", err)
	}
	var got bytes.Buffer
	chunk := make([]byte, 512<<10)
	for {
		n, err := io.ReadFull(resp.Body, chunk)
		got.Write(chunk[:n])
		if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
			break
		}
		if err != nil {
			t.Fatalf("read after %d bytes: %v", got.Len(), err)
		}
		time.Sleep(50 * time.Millisecond)
	}
	_ = resp.Body.Close()
	if !bytes.Equal(got.Bytes(), payload) || resp.Close {
		t.Fatalf("got %d of %d bytes (close=%v), want all of them on a connection kept for more", got.Len(), len(payload), resp.Close)
	}

	if next := raw.ask("GET /files/not-a-token HTTP/1.1\r\nHost: nox\r\n\r\n"); next.StatusCode != http.StatusNotFound || next.Close {
		t.Fatalf("the next request on the connection: %d (close=%v), want a 404 that keeps it", next.StatusCode, next.Close)
	}
}

// --- a pairing that waits for Allow (046) ---

// waitsHeld counts the connections srv holds as waiting on a pairing request.
func waitsHeld(srv *Server) int {
	srv.mu.Lock()
	defer srv.mu.Unlock()
	return len(srv.waits)
}

// presentAgain presents token once more on c and returns the answer: the
// request it waits on, for as long as it does.
func presentAgain(t *testing.T, c *wsClient, id int, token string) pendingReply {
	t.Helper()
	var got pendingReply
	data := c.expectOKAfter(id, fmt.Sprintf(`{"id":%d,"cmd":"pair","data":{"token":%q,"platform":"windows"}}`, id, token))
	mustUnmarshal(t, mustRaw(t, data), &got)
	return got
}

// holdBeforeWait stops every `pair` that found its request waiting before the
// connection's wait on it takes hold, until let is called: the window a close
// lands in with nobody waiting on the request yet.
func holdBeforeWait(t *testing.T) (tweak func(*Server), reached <-chan string, let func()) {
	t.Helper()
	at := make(chan string, 1)
	release := make(chan struct{})
	let = sync.OnceFunc(func() { close(release) })
	// Released before the stack closes, or a held command would hold its
	// shutdown too.
	t.Cleanup(let)
	return func(s *Server) {
		s.beforeWait = func(requestID string) {
			at <- requestID
			<-release
		}
	}, at, let
}

// An approval can take the invite's whole ten minutes, and a device waits for
// it on the connection it presented the invite on - a stranger's connection,
// whose key nobody paired yet. While the request waits, a stranger's deadline
// does not apply to it: here the wait runs four deadlines long, eight minutes
// at the real scale, and the device is then allowed, greets on that same
// connection and stays. Beside it, a stranger with no request, and one whose
// pairing was refused at once, are still closed at the deadline.
func TestAPairingThatWaitsForAllowOutlivesAStrangersDeadline(t *testing.T) {
	const deadline = 300 * time.Millisecond
	ts, srv := newTestServerWith(t, func(s *Server) { s.unpairedTimeout = deadline })
	_, issuer, token := issuerSetup(t, ts, srv)

	waiting, pending := presentInvite(t, ts, srv, newDevice(t), token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)
	idle := dialWS(t, ts, srv)
	idle.expectGreeting()
	refused := dialWS(t, ts, srv)
	refused.expectGreeting()
	refused.send(`{"id":1,"cmd":"pair","data":{"token":"not-a-token","platform":"linux"}}`)
	refused.expectErr(1, protocol.ErrInvalidToken)
	if w := waitsHeld(srv); w != 1 {
		t.Fatalf("%d connections held as waiting, want the device that presented the invite", w)
	}

	time.Sleep(4 * deadline)
	waitClosed(t, idle, websocket.StatusPolicyViolation)
	waitClosed(t, refused, websocket.StatusPolicyViolation)
	if again := presentAgain(t, waiting, 2, token); again != pending {
		t.Fatalf("four deadlines on, the waiting device's repeat = %+v, want the same request %+v", again, pending)
	}

	issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	data := expectNamedEvent(t, waiting, protocol.EventPairResolved)
	if string(data["outcome"]) != `"allowed"` {
		t.Fatalf("pair.resolved = %v, want allowed", data)
	}
	waiting.hello(3, "")
	if n, w := unpairedHeld(srv), waitsHeld(srv); n != 0 || w != 0 {
		t.Fatalf("%d held as strangers and %d as waiting after the Allow, want none", n, w)
	}
	// A paired device's connection now: no deadline left to close it.
	time.Sleep(2 * deadline)
	waiting.expectOKAfter(4, `{"id":4,"cmd":"device.list","data":{}}`)
}

// The cap on strangers takes the oldest out for a newcomer, and the device
// waiting for Allow connected before every stranger here - held to the cap, it
// would be the first one out. A wait holds no place: a flood of newcomers
// pushes out only its own, and the waiting device is then allowed.
func TestTheCapNeverPushesOutAPairingThatWaits(t *testing.T) {
	const most = 2
	ts, srv := newTestServerWith(t, func(s *Server) { s.maxUnpaired = most })
	_, issuer, token := issuerSetup(t, ts, srv)
	waiting, pending := presentInvite(t, ts, srv, newDevice(t), token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	var flood []*wsClient
	for range 3 * most {
		c := dialWS(t, ts, srv)
		c.expectGreeting()
		flood = append(flood, c)
	}
	for _, c := range flood[:2*most] {
		waitClosed(t, c, websocket.StatusTryAgainLater)
	}
	if n, w := unpairedHeld(srv), waitsHeld(srv); n != most || w != 1 {
		t.Fatalf("%d held as strangers and %d as waiting, want the cap of %d and the waiting device", n, w, most)
	}
	if again := presentAgain(t, waiting, 2, token); again != pending {
		t.Fatalf("after the flood the waiting device's repeat = %+v, want the same request %+v", again, pending)
	}

	issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	expectNamedEvent(t, waiting, protocol.EventPairResolved)
	waiting.hello(3, "")
}

// A request that closes without a pairing leaves its connection with nothing
// that says it will pair any more: it is a stranger again, with two minutes of
// its own from the close, counted afresh. Each way a request ends without
// Allow: Deny on the issuing device, Cancel on the new one, and its time
// running out with nobody acting - where the sweep must get to the request
// before the wait's own bound, its deadline plus one sweep and a stranger's
// time, and half a second of the latter leaves room for a slow sweep.
func TestAWaitThatEndsWithoutAPairingIsAStrangersAgain(t *testing.T) {
	const deadline = 500 * time.Millisecond
	for _, tc := range []struct {
		name    string
		outcome string
		// end ends the request: by the issuer's answer, or the new device's
		// cancel. Nil leaves it to its deadline.
		end func(t *testing.T, issuer, waiting *wsClient, token string, pending pendingReply)
		// almostGone issues the invite with two seconds of its time left.
		almostGone bool
	}{
		{"denied", "denied", func(t *testing.T, issuer, _ *wsClient, _ string, pending pendingReply) {
			issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":false}}`, pending.RequestID))
		}, false},
		{"cancelled", "cancelled", func(t *testing.T, _, waiting *wsClient, token string, _ pendingReply) {
			waiting.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"pair.cancel","data":{"token":%q}}`, token))
		}, false},
		{"expired", "expired", nil, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ts, srv := newTestServerWith(t, func(s *Server) {
				s.unpairedTimeout = deadline
				s.requestSweep = 50 * time.Millisecond
			})
			issuerKey, issuer, token := issuerSetup(t, ts, srv)
			if tc.almostGone {
				// Issued almost ten minutes ago: two seconds are left.
				var err error
				token, err = srv.store.IssueDeviceInvite(context.Background(), issuerKey.pub, time.Now().Unix()-598)
				if err != nil {
					t.Fatalf("IssueDeviceInvite: %v", err)
				}
			}
			waiting, pending := presentInvite(t, ts, srv, newDevice(t), token)
			// When the request ends at the earliest: its deadline, or the
			// moment before the answer or the cancel goes out.
			ends := time.Unix(pending.ExpiresAt, 0)
			if tc.end != nil {
				// Past the deadline first: the wait, not the clock, is what
				// keeps the connection until the request ends.
				time.Sleep(2 * deadline)
				ends = time.Now()
				tc.end(t, issuer, waiting, token, pending)
			}
			data := expectNamedEvent(t, waiting, protocol.EventPairResolved)
			if string(data["outcome"]) != `"`+tc.outcome+`"` {
				t.Fatalf("pair.resolved = %v, want %s", data, tc.outcome)
			}
			waitClosed(t, waiting, websocket.StatusPolicyViolation)
			if took := time.Since(ends); took < deadline/2 {
				t.Fatalf("closed %v after the request ended, well inside a fresh deadline of %v", took, deadline)
			}
			eventually(t, "the connection holds no place and no wait", func() bool {
				return unpairedHeld(srv) == 0 && waitsHeld(srv) == 0
			})
		})
	}
}

// One connection holds each request's wait: the one that presented it last.
// The app presents its invite again on every new connection, and the one it
// left behind - dead, as a rule, though the server may not know it yet - is
// closed at once, not left to a deadline; the newest waits on, and is
// allowed. So the connections a key nobody paired holds this way are no more
// than the requests that wait.
func TestTheConnectionThatPresentedTheInviteLastHoldsTheWait(t *testing.T) {
	const deadline = 300 * time.Millisecond
	ts, srv := newTestServerWith(t, func(s *Server) { s.unpairedTimeout = deadline })
	_, issuer, token := issuerSetup(t, ts, srv)
	newcomer := newDevice(t)
	first, pending := presentInvite(t, ts, srv, newcomer, token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)

	second, again := presentInvite(t, ts, srv, newcomer, token)
	if again != pending {
		t.Fatalf("the second connection's answer = %+v, want the same request %+v", again, pending)
	}
	waitClosed(t, first, websocket.StatusTryAgainLater)
	if n, w := unpairedHeld(srv), waitsHeld(srv); n != 0 || w != 1 {
		t.Fatalf("%d held as strangers and %d as waiting, want only the second connection's wait", n, w)
	}
	time.Sleep(3 * deadline)
	if still := presentAgain(t, second, 2, token); still != pending {
		t.Fatalf("the second connection's repeat = %+v, want the same request %+v", still, pending)
	}

	issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	expectNamedEvent(t, second, protocol.EventPairResolved)
	second.hello(3, "")
}

// A wait moves to the connection that presented the invite last, and the one
// it leaves is closed - never put back among the strangers. Put back as the
// newest, it would move behind every stranger that dialled after it: a key
// whose request waits - a leaked invite, presented first - could reorder the
// places with `pair` frames alone, presenting on its spare connections one by
// one until a device that dialled later was the oldest, and then push that
// device out with ONE new connection instead of a whole cap's worth.
func TestPresentingAnInviteAgainCannotReorderTheStrangers(t *testing.T) {
	const most = 4
	ts, srv := newTestServerWith(t, func(s *Server) { s.maxUnpaired = most })
	_, issuer, token := issuerSetup(t, ts, srv)
	leaked := newDevice(t)
	holder, pending := presentInvite(t, ts, srv, leaked, token)
	expectNamedEvent(t, issuer, protocol.EventDevicePairRequested)
	var spares []*wsClient
	for range most - 1 {
		c := dialAs(t, ts, srv, leaked)
		c.expectGreeting()
		spares = append(spares, c)
	}
	// A device that dials after all of them, to pair with a link of its own:
	// the places are full now, and it is the newest.
	late := dialWS(t, ts, srv)
	late.expectGreeting()

	for _, c := range spares {
		if again := presentAgain(t, c, 1, token); again != pending {
			t.Fatalf("a spare connection's repeat = %+v, want the same request %+v", again, pending)
		}
	}
	// One new connection of the same key. Had the repeats moved the
	// connections they left behind the late device, it would be the oldest
	// now, and this would push it out.
	extra := dialAs(t, ts, srv, leaked)
	extra.expectGreeting()

	late.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, mustMachineLink(t, srv)))
	if _, paired := late.expectOK(1)["identity"]; !paired {
		t.Fatal("the late device did not pair through its machine link")
	}
	// Each repeat closed the connection the wait left, and the last spare
	// waits; the new connection is the only stranger left in a place.
	for _, left := range append([]*wsClient{holder}, spares[:len(spares)-1]...) {
		waitClosed(t, left, websocket.StatusTryAgainLater)
	}
	if n, w := unpairedHeld(srv), waitsHeld(srv); n != 1 || w != 1 {
		t.Fatalf("%d held as strangers and %d as waiting, want the new connection and the last spare's wait", n, w)
	}
	if still := presentAgain(t, spares[len(spares)-1], 2, token); still != pending {
		t.Fatalf("the last spare's repeat = %+v, want the same request %+v", still, pending)
	}
}

// A request can close between the store's "pending" and the wait taking hold -
// here the issuer answers in exactly that window - and whoever closed it found
// nobody waiting on it. The wait reads the request again once it holds, so a
// Deny puts the connection back under a stranger's deadline at once, and an
// Allow lets it go as a paired device's: neither is left exempt for the rest
// of the request's ten minutes. The deadline is a second here: the stranger's
// own runs while the command is held in the window, and must not end it there.
func TestARequestThatClosesBeforeItsWaitTakesHoldEndsTheWait(t *testing.T) {
	const deadline = time.Second
	for _, allow := range []bool{false, true} {
		t.Run(map[bool]string{false: "denied", true: "allowed"}[allow], func(t *testing.T) {
			hold, reached, let := holdBeforeWait(t)
			ts, srv := newTestServerWith(t, func(s *Server) { s.unpairedTimeout = deadline }, hold)
			_, issuer, token := issuerSetup(t, ts, srv)

			waiting := dialAs(t, ts, srv, newDevice(t))
			waiting.expectGreeting()
			waiting.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"windows"}}`, token))
			var requestID string
			select {
			case requestID = <-reached:
			case <-time.After(5 * time.Second):
				t.Fatal("pair never found its request waiting")
			}
			issuer.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":%t}}`, requestID, allow))
			let()

			var answer pendingReply
			mustUnmarshal(t, mustRaw(t, waiting.expectOK(1)), &answer)
			if answer.Status != "pending" || answer.RequestID != requestID {
				t.Fatalf("pair = %+v, want the pending request %s the store answered before the close", answer, requestID)
			}
			eventually(t, "the wait has ended", func() bool { return waitsHeld(srv) == 0 })
			if !allow {
				waitClosed(t, waiting, websocket.StatusPolicyViolation)
				return
			}
			if n := unpairedHeld(srv); n != 0 {
				t.Fatalf("%d held as strangers after the Allow, want none", n)
			}
			time.Sleep(deadline + deadline/2)
			waiting.hello(2, "")
		})
	}
}

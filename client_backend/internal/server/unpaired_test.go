package server

import (
	"bufio"
	"bytes"
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

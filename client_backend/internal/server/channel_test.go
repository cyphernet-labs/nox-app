package server

import (
	"context"
	"crypto/ed25519"
	"crypto/tls"
	"errors"
	"io"
	"log/slog"
	"net"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"nox.app/client-backend/internal/eidolon"
)

// The channel listener (044): TLS 1.3, then the channel check, then HTTP - and
// a connection that fails either layer is closed without a word.

// stackWith is newTestServer with a logger and tweaks applied before anything
// serves, returning the main entry's address.
func stackWith(t *testing.T, logger *slog.Logger, tweak ...func(*Server)) (*Server, string) {
	t.Helper()
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "channel.db"), logger, tweak...)
	t.Cleanup(closeAll)
	return srv, ts.Listener.Addr().String()
}

// A device that proves its key is served, and the connection is known by that
// key from its first byte - the registry entry carries it before any command.
func TestAChannelThatProvesAKeyIsServedAsThatKey(t *testing.T) {
	ts, srv := newTestServer(t)
	d := newDevice(t)
	c := dialAs(t, ts, srv, d)
	c.expectGreeting()

	eventually(t, "the connection is registered", func() bool {
		srv.mu.Lock()
		defer srv.mu.Unlock()
		for conn := range srv.conns {
			if conn.deviceKey == d.pub {
				return true
			}
		}
		return false
	})
}

// silentAfter reads until the server closes the connection, and reports what
// it said on the way: a refused peer must be told nothing at all.
func silentAfter(t *testing.T, conn net.Conn) []byte {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	got, err := io.ReadAll(conn)
	var ne net.Error
	if errors.As(err, &ne) && ne.Timeout() {
		t.Fatal("the server neither answered nor closed a connection that failed the check")
	}
	return got
}

// A message that does not verify is answered with nothing - not the server's
// own message, not an alert worth reading - and the connection is closed.
func TestAMessageThatDoesNotVerifyIsAnsweredWithNothing(t *testing.T) {
	buf := &syncBuffer{}
	_, addr := stackWith(t, slog.New(slog.NewTextHandler(buf, nil)))
	d := newDevice(t)

	for _, tc := range []struct {
		name   string
		reason string
		msg    func(binding []byte) []byte
	}{
		{"signed over another binding", "binding", func([]byte) []byte {
			return eidolon.Message(d.priv, make([]byte, eidolon.BindingSize))
		}},
		{"a key that does not sign itself", "signature over the key", func(binding []byte) []byte {
			msg := eidolon.Message(d.priv, binding)
			msg[ed25519.PublicKeySize] ^= 0x01
			return msg
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			conn, err := tls.Dial("tcp", addr, testClientTLS())
			if err != nil {
				t.Fatalf("tls.Dial: %v", err)
			}
			defer func() { _ = conn.Close() }()
			state := conn.ConnectionState()
			binding, err := state.ExportKeyingMaterial(eidolon.ExporterLabel, nil, eidolon.BindingSize)
			if err != nil {
				t.Fatalf("exporter: %v", err)
			}
			if _, err := conn.Write(tc.msg(binding)); err != nil {
				t.Fatalf("write: %v", err)
			}
			if got := silentAfter(t, conn); len(got) != 0 {
				t.Fatalf("the server answered a failed check with %d bytes", len(got))
			}
			eventually(t, "the refusal is logged", func() bool {
				return strings.Contains(buf.String(), "channel check refused") && strings.Contains(buf.String(), tc.reason)
			})
		})
	}
}

// A device expecting another machine's key refuses this one - and does so
// before writing anything but its own check message: the answer it got is the
// server's real one, proved over the right binding, and the key is simply not
// the one its link named.
func TestADeviceExpectingAnotherServerRefusesIt(t *testing.T) {
	ts, _ := newTestServer(t)
	other := ed25519.NewKeyFromSeed(make([]byte, 32)).Public().(ed25519.PublicKey)
	_, err := dialChannel(t.Context(), ts.Listener.Addr().String(), other, newDevice(t).priv)
	if !errors.Is(err, eidolon.ErrUnauthorized) {
		t.Fatalf("dialChannel expecting another key = %v, want eidolon.ErrUnauthorized", err)
	}
}

// T029: a relay in the middle. It runs one TLS session with the device and
// another with the server, and forwards the device's check message unchanged.
// The server sees a message signed over the relay's OTHER session, refuses it,
// and answers the relay with nothing - not even its own key - so the device,
// left waiting, gets nothing to accept either.
func TestARelayBetweenTwoTLSSessionsIsRefused(t *testing.T) {
	buf := &syncBuffer{}
	srv, addr := stackWith(t, slog.New(slog.NewTextHandler(buf, nil)))
	relayTLS, err := channelTLSConfig(time.Now())
	if err != nil {
		t.Fatalf("channelTLSConfig: %v", err)
	}
	relay, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { _ = relay.Close() })

	type relayed struct {
		fromServer []byte
		err        error
	}
	result := make(chan relayed, 1)
	go func() {
		raw, err := relay.Accept()
		if err != nil {
			result <- relayed{err: err}
			return
		}
		toDevice := tls.Server(raw, relayTLS)
		defer func() { _ = toDevice.Close() }()
		if err := toDevice.Handshake(); err != nil {
			result <- relayed{err: err}
			return
		}
		toServer, err := tls.Dial("tcp", addr, testClientTLS())
		if err != nil {
			result <- relayed{err: err}
			return
		}
		defer func() { _ = toServer.Close() }()
		msg := make([]byte, eidolon.MessageSize)
		if _, err := io.ReadFull(toDevice, msg); err != nil {
			result <- relayed{err: err}
			return
		}
		if _, err := toServer.Write(msg); err != nil {
			result <- relayed{err: err}
			return
		}
		_ = toServer.SetReadDeadline(time.Now().Add(5 * time.Second))
		back, _ := io.ReadAll(toServer)
		result <- relayed{fromServer: back}
	}()

	_, err = dialChannel(t.Context(), relay.Addr().String(), serverKeyOf(t, srv), newDevice(t).priv)
	if err == nil {
		t.Fatal("the device completed the check through a relay")
	}
	got := <-result
	if got.err != nil {
		t.Fatalf("the relay could not do its part: %v", got.err)
	}
	if len(got.fromServer) != 0 {
		t.Fatalf("the server answered the relay with %d bytes", len(got.fromServer))
	}
	eventually(t, "the server logged a binding mismatch", func() bool {
		return strings.Contains(buf.String(), "channel check refused") && strings.Contains(buf.String(), "binding")
	})
}

// A client that connects and says nothing holds its own goroutine and one
// place among the handshakes under way, and nothing else: a device dialling
// meanwhile is served at once.
func TestASilentClientDoesNotHoldUpTheNextOne(t *testing.T) {
	ts, srv := newTestServer(t)
	for range 3 {
		conn, err := net.Dial("tcp", ts.Listener.Addr().String())
		if err != nil {
			t.Fatalf("dial: %v", err)
		}
		t.Cleanup(func() { _ = conn.Close() })
	}
	start := time.Now()
	conn, err := dialChannel(t.Context(), ts.Listener.Addr().String(), serverKeyOf(t, srv), newDevice(t).priv)
	if err != nil {
		t.Fatalf("a device behind three silent clients was refused: %v", err)
	}
	_ = conn.Close()
	// The silent ones hold the 10 s budget; anything near it means the device
	// waited for them.
	if took := time.Since(start); took > 5*time.Second {
		t.Fatalf("the device waited %v behind silent clients", took)
	}
}

// One deadline, counted from the accept, covers TLS and the check together:
// a client that says nothing is cut, and so is one that finishes TLS and then
// goes quiet before the check.
func TestTheBudgetCoversTLSAndTheCheckTogether(t *testing.T) {
	const budget = 300 * time.Millisecond
	_, addr := stackWith(t, nil, func(s *Server) { s.channelTimeout = budget })

	t.Run("silent from the first byte", func(t *testing.T) {
		conn, err := net.Dial("tcp", addr)
		if err != nil {
			t.Fatalf("dial: %v", err)
		}
		defer func() { _ = conn.Close() }()
		start := time.Now()
		if got := silentAfter(t, conn); len(got) != 0 {
			t.Fatalf("a silent client was sent %d bytes", len(got))
		}
		if took := time.Since(start); took < budget/2 {
			t.Fatalf("cut after %v, well inside the %v budget", took, budget)
		}
	})

	t.Run("silent after TLS", func(t *testing.T) {
		conn, err := tls.Dial("tcp", addr, testClientTLS())
		if err != nil {
			t.Fatalf("tls.Dial: %v", err)
		}
		defer func() { _ = conn.Close() }()
		if got := silentAfter(t, conn); len(got) != 0 {
			t.Fatalf("a client silent after TLS was sent %d bytes", len(got))
		}
	})
}

// The handshakes under way are bounded, and a full entry still never keeps a
// device out. maxPendingChannels silent sockets from loopback - held to no
// share there, so they fill the entry by themselves - with more arriving all
// the while: a device dialling meanwhile is through at once, because every
// newcomer cuts the handshake that has waited longest, and that is a silent
// one.
func TestAFullEntryCutsItsOldestHandshakeToLetADeviceIn(t *testing.T) {
	buf := &syncBuffer{}
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "full.db"), slog.New(slog.NewTextHandler(buf, nil)))
	t.Cleanup(closeAll)
	listener, ok := ts.Listener.(*channelListener)
	if !ok {
		t.Fatalf("the test server's listener is %T", ts.Listener)
	}
	addr := ts.Listener.Addr().String()
	var silent []net.Conn
	t.Cleanup(func() {
		for _, conn := range silent {
			_ = conn.Close()
		}
	})
	for range maxPendingChannels {
		conn, err := net.Dial("tcp", addr)
		if err != nil {
			t.Fatalf("dial: %v", err)
		}
		silent = append(silent, conn)
	}
	eventually(t, "every place is taken", func() bool { return underWay(listener) == maxPendingChannels })

	// More keep arriving while the device dials, each cutting the oldest. One
	// every few milliseconds leaves the device more than a second before its
	// own turn as the oldest could come.
	stop := make(chan struct{})
	flooded := make(chan error, 1)
	go func() {
		var more []net.Conn
		defer func() {
			for _, conn := range more {
				_ = conn.Close()
			}
		}()
		tick := time.NewTicker(5 * time.Millisecond)
		defer tick.Stop()
		for {
			select {
			case <-stop:
				flooded <- nil
				return
			case <-tick.C:
			}
			conn, err := net.Dial("tcp", addr)
			if err != nil {
				flooded <- err
				return
			}
			more = append(more, conn)
		}
	}()

	key, dev := serverKeyOf(t, srv), newDevice(t)
	ctx, cancel := context.WithTimeout(t.Context(), defaultChannelTimeout)
	defer cancel()
	start := time.Now()
	conn, err := dialChannel(ctx, addr, key, dev.priv)
	took := time.Since(start)
	close(stop)
	if ferr := <-flooded; ferr != nil {
		t.Fatalf("the flood could not dial: %v", ferr)
	}
	if err != nil {
		t.Fatalf("a device was refused by a full entry: %v", err)
	}
	_ = conn.Close()
	// Waiting for a place to free up, it would have waited out the silent
	// ones' whole budget.
	if took > 2*time.Second {
		t.Fatalf("the device waited %v for a place", took)
	}
	// Room was made by cutting whoever had waited longest: the first silent
	// socket.
	if got := silentAfter(t, silent[0]); len(got) != 0 {
		t.Fatalf("a connection cut to make room was sent %d bytes", len(got))
	}
	if n := underWay(listener); n > maxPendingChannels {
		t.Fatalf("%d handshakes under way, over the bound of %d", n, maxPendingChannels)
	}
	eventually(t, "the cuts are logged", func() bool {
		for _, line := range shedLines(buf.String()) {
			if line.evicted > 0 {
				return true
			}
		}
		return false
	})
}

// Closing the listener ends the handshakes under way at once and closes their
// connections; it does not wait for their budget to run out.
func TestClosingTheListenerEndsHandshakesUnderWay(t *testing.T) {
	_, srv := newTestServer(t)
	raw, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	cfg, err := channelTLSConfig(time.Now())
	if err != nil {
		t.Fatalf("channelTLSConfig: %v", err)
	}
	key, err := srv.store.ServerKey(t.Context())
	if err != nil {
		t.Fatalf("ServerKey: %v", err)
	}
	l := srv.newChannelListener(raw, cfg, key, time.Hour, "direct")
	conn, err := net.Dial("tcp", raw.Addr().String())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close() }()
	eventually(t, "the handshake is under way", func() bool { return underWay(l) == 1 })

	closed := make(chan error, 1)
	go func() { closed <- l.Close() }()
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("Close waited on a handshake with an hour of budget left")
	}
	if n := underWay(l); n != 0 {
		t.Fatalf("%d handshakes still under way after Close", n)
	}
	if got := silentAfter(t, conn); len(got) != 0 {
		t.Fatalf("a connection cut by Close was sent %d bytes", len(got))
	}
	if _, err := l.Accept(); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("Accept after Close = %v, want net.ErrClosed", err)
	}
}

// One source holds only its share of the handshakes under way, and a newcomer
// from a source at its share is taken all the same: the source's OLDEST
// handshake is cut for it. A device is through in well under a second, so the
// one cut is whoever has been saying nothing longest - and a stranger behind the
// same router as a household, opening one silent connection after another,
// cannot keep the household's devices out, nor touch another source's
// handshakes. The cuts go to the log as counts - the first at once, the rest
// in the next minute's line, which Close sends early - and never with an
// address.
func TestASourceAtItsShareCutsItsOldestHandshakeForANewcomer(t *testing.T) {
	buf := &syncBuffer{}
	srv, _ := stackWith(t, slog.New(slog.NewTextHandler(buf, nil)))
	l, pipes := pipeChannel(t, srv, time.Hour, func(l *channelListener) {
		// Nothing but the share may cut the silent ones here.
		l.firstByte = time.Hour
	})
	const home, neighbour = "203.0.113.7", "198.51.100.9"

	next := pipes.dial(t, neighbour)
	var silent []net.Conn
	for range maxPendingPerSource {
		silent = append(silent, pipes.dial(t, home))
	}
	eventually(t, "the source holds its share", func() bool { return heldBy(l, home) == maxPendingPerSource })

	// The ninth from the source is taken, and the first of its eight goes.
	ninth := pipes.dial(t, home)
	if got := silentAfter(t, silent[0]); len(got) != 0 {
		t.Fatalf("the source's oldest handshake was sent %d bytes", len(got))
	}
	stillOpen(t, ninth, 100*time.Millisecond)
	// Eight still, so the ninth is among them and nothing but the oldest went.
	if n := heldBy(l, home); n != maxPendingPerSource {
		t.Fatalf("the source holds %d handshakes after the ninth, want its share of %d", n, maxPendingPerSource)
	}
	// The first cut is logged at once. Waiting for it keeps the cuts below out
	// of its line, whatever the scheduler does.
	eventually(t, "the first cut is logged", func() bool { return len(shedLines(buf.String())) == 1 })

	// A stranger at home goes on opening silent connections, each cutting the
	// oldest of the source's, while a device dials from the same address. One
	// every 25 ms gives the device 200 ms before eight newer ones could make it
	// the oldest; it needs well under 10 ms, even under the race detector.
	stop := make(chan struct{})
	stopped := make(chan struct{})
	var flooded atomic.Int64
	go func() {
		var ends []net.Conn
		defer func() {
			for _, end := range ends {
				_ = end.Close()
			}
			close(stopped)
		}()
		tick := time.NewTicker(25 * time.Millisecond)
		defer tick.Stop()
		for {
			select {
			case <-stop:
				return
			case <-tick.C:
			}
			// pipes.dial reports through t, which only the test's own goroutine
			// may stop; this is its body without the report.
			client, server := net.Pipe()
			select {
			case pipes.conns <- &fromConn{Conn: server, remote: &net.TCPAddr{IP: net.ParseIP(home), Port: 50000}}:
				ends = append(ends, client)
				flooded.Add(1)
			case <-stop:
				_ = client.Close()
				_ = server.Close()
				return
			}
		}
	}()
	// A few of them first, so the device arrives into a flood under way.
	eventually(t, "the stranger's flood is under way", func() bool { return flooded.Load() >= 3 })
	key, dev := serverKeyOf(t, srv), newDevice(t)
	conn := pipes.dial(t, home)
	opened := make(chan error, 1)
	go func() {
		_, err := channelOver(t.Context(), conn, key, dev.priv)
		opened <- err
	}()
	got := acceptWithin(t, l, 5*time.Second)
	close(stop)
	<-stopped
	flood := int(flooded.Load())
	if err := <-opened; err != nil {
		t.Fatalf("a device from a source a stranger keeps full was refused: %v", err)
	}
	if peer, ok := channelPeerFrom(withChannelPeer(t.Context(), got)); !ok || peer.deviceKey() != dev.pub {
		t.Fatalf("the channel that passed proved %v (ok=%v), want the device's key", peer.key, ok)
	}
	// The device's end first: closing a TLS connection writes to its peer,
	// and nobody reads this pipe's other end any more.
	_ = conn.Close()
	_ = got.Close()
	// The other source's one handshake was never in the way of any of it.
	stillOpen(t, next, 100*time.Millisecond)
	if n := heldBy(l, neighbour); n != 1 {
		t.Fatalf("the other source holds %d handshakes, want its one", n)
	}

	if lines := shedLines(buf.String()); len(lines) != 1 || lines[0] != (shedCounts{inSource: 1}) {
		t.Fatalf("warnings before Close = %+v, want one carrying the first cut", lines)
	}
	_ = l.Close()
	// The second line carries a cut for every connection taken while the source
	// was at its share: the stranger's and the device's, less one if the
	// stranger's next came after the device was through and had left room.
	lines := shedLines(buf.String())
	if len(lines) != 2 || lines[1].evicted != 0 || lines[1].inSource < flood || lines[1].inSource > flood+1 {
		t.Fatalf("warnings after Close = %+v, want a second one carrying %d or %d cuts within the source", lines, flood, flood+1)
	}
	if log := buf.String(); strings.Contains(log, home) || strings.Contains(log, neighbour) {
		t.Fatalf("an address reached the log:\n%s", log)
	}
}

// A source's share comes back as its handshakes leave, whichever way they
// leave: cut at the first-byte deadline, or given up by the peer. The source
// then holds nothing, a device from it is taken and passes, and once through
// it holds nothing either - the share counts handshakes UNDER WAY, never the
// connections a source has made.
func TestASourceGetsItsShareBackAsItsHandshakesLeave(t *testing.T) {
	_, srv := newTestServer(t)
	const home = "203.0.113.7"
	through := func(t *testing.T, l *channelListener, pipes *pipeListener) {
		t.Helper()
		key, dev := serverKeyOf(t, srv), newDevice(t)
		conn := pipes.dial(t, home)
		opened := make(chan error, 1)
		go func() {
			_, err := channelOver(t.Context(), conn, key, dev.priv)
			opened <- err
		}()
		got := acceptWithin(t, l, 5*time.Second)
		if err := <-opened; err != nil {
			t.Fatalf("a device from the source was refused: %v", err)
		}
		if n := heldBy(l, home); n != 0 {
			t.Fatalf("the source holds %d handshakes with its device through, want none", n)
		}
		_ = conn.Close()
		_ = got.Close()
	}

	t.Run("cut at the first-byte deadline", func(t *testing.T) {
		l, pipes := pipeChannel(t, srv, time.Hour, func(l *channelListener) { l.firstByte = 200 * time.Millisecond })
		var silent []net.Conn
		for range maxPendingPerSource {
			silent = append(silent, pipes.dial(t, home))
		}
		for _, conn := range silent {
			if got := silentAfter(t, conn); len(got) != 0 {
				t.Fatalf("a silent peer was sent %d bytes", len(got))
			}
		}
		eventually(t, "the source's share is back", func() bool { return heldBy(l, home) == 0 })
		through(t, l, pipes)
	})

	t.Run("given up by the peer", func(t *testing.T) {
		l, pipes := pipeChannel(t, srv, time.Hour, func(l *channelListener) { l.firstByte = time.Hour })
		var quitting []net.Conn
		for range maxPendingPerSource {
			quitting = append(quitting, pipes.dial(t, home))
		}
		eventually(t, "the source holds its share", func() bool { return heldBy(l, home) == maxPendingPerSource })
		for _, conn := range quitting {
			_ = conn.Close()
		}
		eventually(t, "the source's share is back", func() bool { return heldBy(l, home) == 0 })
		through(t, l, pipes)
	})
}

// A handshake cut to make room in the entry takes its source's count with it.
// With one place in all, a connection from another source cuts the one held,
// and the source it came from is out of the count altogether - not left at
// zero in a map that would otherwise grow with every address that ever
// knocked.
func TestAHandshakeCutToMakeRoomTakesItsCountWithIt(t *testing.T) {
	_, srv := newTestServer(t)
	l, pipes := pipeChannel(t, srv, time.Hour, func(l *channelListener) {
		l.maxPending = 1
		l.firstByte = time.Hour
	})
	const first, second = "203.0.113.7", "198.51.100.9"

	early := pipes.dial(t, first)
	eventually(t, "the first source holds the place", func() bool { return heldBy(l, first) == 1 })
	pipes.dial(t, second)
	if got := silentAfter(t, early); len(got) != 0 {
		t.Fatalf("the handshake cut to make room was sent %d bytes", len(got))
	}
	if n := heldBy(l, second); n != 1 {
		t.Fatalf("the second source holds %d handshakes, want the one place", n)
	}
	if counted := countedSources(l); len(counted) != 1 || counted[0] != second {
		t.Fatalf("the count names %v, want only the source still holding a handshake", counted)
	}
}

// Off loopback, a connection has firstByteTimeout to say anything at all.
// Silent, it is cut long before its budget; once a byte is in, it has the
// whole budget; and a device, which speaks at once, is left with no deadline
// at all once it is through the check. Loopback - tor - is held to none of it.
func TestAPeerThatSaysNothingIsCutAtItsFirstByteDeadline(t *testing.T) {
	_, srv := newTestServer(t)
	const firstByte, budget = 300 * time.Millisecond, 2 * time.Second
	l, pipes := pipeChannel(t, srv, budget, func(l *channelListener) { l.firstByte = firstByte })

	t.Run("silent", func(t *testing.T) {
		t.Parallel()
		conn := pipes.dial(t, "203.0.113.7")
		start := time.Now()
		if got := silentAfter(t, conn); len(got) != 0 {
			t.Fatalf("a silent peer was sent %d bytes", len(got))
		}
		took := time.Since(start)
		if took < firstByte/2 {
			t.Fatalf("cut after %v, before its first-byte deadline of %v", took, firstByte)
		}
		if took > budget/2 {
			t.Fatalf("cut after %v: its budget of %v, not the first-byte deadline", took, budget)
		}
	})

	t.Run("one byte, then silence", func(t *testing.T) {
		t.Parallel()
		conn := pipes.dial(t, "203.0.113.8")
		start := time.Now()
		// The first byte of a TLS record, and nothing after it.
		if _, err := conn.Write([]byte{0x16}); err != nil {
			t.Fatalf("write: %v", err)
		}
		stillOpen(t, conn, 2*firstByte)
		if got := silentAfter(t, conn); len(got) != 0 {
			t.Fatalf("a stalled peer was sent %d bytes", len(got))
		}
		if took := time.Since(start); took < budget/2 {
			t.Fatalf("cut after %v, well inside its budget of %v", took, budget)
		}
	})

	t.Run("silent on loopback", func(t *testing.T) {
		t.Parallel()
		stillOpen(t, pipes.dial(t, "127.0.0.1"), 2*firstByte)
	})

	t.Run("a device", func(t *testing.T) {
		t.Parallel()
		key, dev := serverKeyOf(t, srv), newDevice(t)
		conn := pipes.dial(t, "198.51.100.9")
		var tc *tls.Conn
		opened := make(chan error, 1)
		go func() {
			var err error
			tc, err = channelOver(t.Context(), conn, key, dev.priv)
			opened <- err
		}()
		got := acceptWithin(t, l, 5*time.Second)
		if err := <-opened; err != nil {
			t.Fatalf("the device did not open its channel: %v", err)
		}
		// Past both of its deadlines - the first byte's and the budget - the
		// channel carries one record after another like any connection.
		time.Sleep(budget + firstByte)
		go func() {
			for _, word := range []string{"ping", "pong"} {
				if _, err := tc.Write([]byte(word)); err != nil {
					return
				}
			}
		}()
		read := make(chan error, 1)
		go func() {
			msg := make([]byte, 8)
			_, err := io.ReadFull(got, msg)
			if err == nil && string(msg) != "pingpong" {
				err = errors.New("read " + strconv.Quote(string(msg)))
			}
			read <- err
		}()
		select {
		case err := <-read:
			if err != nil {
				t.Fatalf("the channel failed a read after the check: %v", err)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("the channel did not carry a write after the check")
		}
		_ = conn.Close()
		_ = got.Close()
	})
}

// A source is an IPv4 address or an IPv6 /64, and loopback counts as none.
func TestASourceIsAnAddressOrAnIPv6Slash64(t *testing.T) {
	tcp := func(ip net.IP) net.Addr { return &net.TCPAddr{IP: ip, Port: 443} }
	for _, tc := range []struct {
		name     string
		addr     net.Addr
		source   string
		loopback bool
	}{
		{"an IPv4 address", tcp(net.IPv4(203, 0, 113, 7).To4()), "203.0.113.7", false},
		{"the same address the way a dual-stack socket reports it", tcp(net.ParseIP("::ffff:203.0.113.7")), "203.0.113.7", false},
		{"the address next to it", tcp(net.ParseIP("203.0.113.8")), "203.0.113.8", false},
		{"an IPv6 address counts by its /64", tcp(net.ParseIP("2001:db8:1:2::1")), "2001:db8:1:2::/64", false},
		{"anywhere in that /64", tcp(net.ParseIP("2001:db8:1:2:ffff:ffff:ffff:fffe")), "2001:db8:1:2::/64", false},
		{"the next /64", tcp(net.ParseIP("2001:db8:1:3::1")), "2001:db8:1:3::/64", false},
		{"a zone changes nothing", &net.TCPAddr{IP: net.ParseIP("fe80::1"), Port: 443, Zone: "en0"}, "fe80::/64", false},
		{"IPv4 loopback", tcp(net.ParseIP("127.0.0.1")), "127.0.0.1", true},
		{"anywhere in 127.0.0.0/8", tcp(net.ParseIP("127.1.2.3")), "127.1.2.3", true},
		{"IPv6 loopback", tcp(net.IPv6loopback), "::1", true},
		{"loopback the way a dual-stack socket reports it", tcp(net.ParseIP("::ffff:127.0.0.1")), "127.0.0.1", true},
		{"an address of another type, read from its string", textAddr("198.51.100.9:443"), "198.51.100.9", false},
		{"no IP at all: one shared source, still held to a share", &net.UnixAddr{Name: "/run/nox.sock", Net: "unix"}, "", false},
		{"no address", nil, "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source, loopback := sourceOf(tc.addr)
			if source != tc.source || loopback != tc.loopback {
				t.Fatalf("sourceOf(%v) = %q, %v; want %q, %v", tc.addr, source, loopback, tc.source, tc.loopback)
			}
		})
	}
}

// pair records the key the channel proved, never one a frame names. An older
// client still sends device_key; an attacker would send somebody else's - and
// either way the row that comes into being is the connection's own key.
func TestPairPairsTheKeyTheChannelProved(t *testing.T) {
	ts, srv := newTestServer(t)
	token := mustClaimToken(t, srv)
	proved := newDevice(t)
	named := newDevice(t)

	c := dialAs(t, ts, srv, proved)
	c.expectGreeting()
	c.send(`{"id":1,"cmd":"pair","data":{"token":"` + token + `","device_key":"` + named.pub + `","platform":"test"}}`)
	c.expectOK(1)

	if _, found, err := srv.store.DeviceOwner(t.Context(), proved.pub); err != nil || !found {
		t.Fatalf("the proved key was not paired (found=%v err=%v)", found, err)
	}
	if _, found, err := srv.store.DeviceOwner(t.Context(), named.pub); err != nil || found {
		t.Fatalf("the key the frame named was paired (found=%v err=%v)", found, err)
	}
	// And it greets as the key it proved, on a connection of its own.
	back := dialAs(t, ts, srv, proved)
	back.expectGreeting()
	back.send(`{"id":1,"cmd":"session.hello","data":{"schema":1}}`)
	back.expectOK(1)
}

// pipeListener is a listener a test feeds by hand, which is how one machine
// stands in for hosts all over a network: every connection is one end of an
// in-memory pipe, and says it comes from the address the test gave it.
type pipeListener struct {
	conns  chan net.Conn
	closed chan struct{}
	once   sync.Once
}

func newPipeListener() *pipeListener {
	return &pipeListener{conns: make(chan net.Conn), closed: make(chan struct{})}
}

func (l *pipeListener) Accept() (net.Conn, error) {
	select {
	case c := <-l.conns:
		return c, nil
	case <-l.closed:
		return nil, net.ErrClosed
	}
}

func (l *pipeListener) Close() error {
	l.once.Do(func() { close(l.closed) })
	return nil
}

func (l *pipeListener) Addr() net.Addr {
	return &net.TCPAddr{IP: net.IPv4(192, 0, 2, 1), Port: 443}
}

// dial opens a connection from host and returns its client end once the
// listener has taken the other one - so connections arrive in the order they
// were dialled, each after the one before was admitted or turned away.
func (l *pipeListener) dial(t *testing.T, host string) net.Conn {
	t.Helper()
	client, server := net.Pipe()
	t.Cleanup(func() { _ = client.Close() })
	from := &fromConn{Conn: server, remote: &net.TCPAddr{IP: net.ParseIP(host), Port: 50000}}
	select {
	case l.conns <- from:
	case <-time.After(5 * time.Second):
		_ = server.Close()
		t.Fatal("the listener did not take the connection")
	}
	return client
}

// fromConn is a connection that says it comes from remote.
type fromConn struct {
	net.Conn
	remote net.Addr
}

func (c *fromConn) RemoteAddr() net.Addr { return c.remote }

// pipeChannel puts a channel listener of srv's with the given budget in front
// of a pipeListener, and lets tune shrink its limits before anything arrives.
func pipeChannel(t *testing.T, srv *Server, budget time.Duration, tune func(*channelListener)) (*channelListener, *pipeListener) {
	t.Helper()
	cfg, err := channelTLSConfig(time.Now())
	if err != nil {
		t.Fatalf("channelTLSConfig: %v", err)
	}
	key, err := srv.store.ServerKey(t.Context())
	if err != nil {
		t.Fatalf("ServerKey: %v", err)
	}
	pipes := newPipeListener()
	l := srv.newChannelListener(pipes, cfg, key, budget, "direct")
	t.Cleanup(func() { _ = l.Close() })
	l.mu.Lock()
	tune(l)
	l.mu.Unlock()
	return l, pipes
}

// acceptWithin is l.Accept, failing the test when nothing passes within d.
func acceptWithin(t *testing.T, l *channelListener, d time.Duration) net.Conn {
	t.Helper()
	type accepted struct {
		conn net.Conn
		err  error
	}
	got := make(chan accepted, 1)
	go func() {
		conn, err := l.Accept()
		got <- accepted{conn, err}
	}()
	select {
	case a := <-got:
		if a.err != nil {
			t.Fatalf("Accept: %v", a.err)
		}
		return a.conn
	case <-time.After(d):
		t.Fatalf("no connection passed within %v", d)
		return nil
	}
}

// stillOpen fails the test if the server answers conn or closes it within d.
func stillOpen(t *testing.T, conn net.Conn, d time.Duration) {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(d))
	defer func() { _ = conn.SetReadDeadline(time.Time{}) }()
	n, err := conn.Read(make([]byte, 1))
	var ne net.Error
	if n != 0 || !errors.As(err, &ne) || !ne.Timeout() {
		t.Fatalf("within %v the server sent %d bytes or closed the connection (%v)", d, n, err)
	}
}

// underWay counts the handshakes l has under way.
func underWay(l *channelListener) int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.pending.Len()
}

// heldBy counts the handshakes the source at host has under way on l.
func heldBy(l *channelListener, host string) int {
	source, _ := sourceOf(&net.TCPAddr{IP: net.ParseIP(host)})
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.bySource[source]
}

// countedSources lists the sources l keeps a count for.
func countedSources(l *channelListener) []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	sources := make([]string, 0, len(l.bySource))
	for source := range l.bySource {
		sources = append(sources, source)
	}
	return sources
}

// shedLine is one warning about shed connections in a text log.
var shedLine = regexp.MustCompile(`level=WARN msg="channel entry shedding connections".* evicted_in_source=(\d+) evicted=(\d+)`)

// shedLines reads the counts of every shedding warning out of a text log.
func shedLines(log string) []shedCounts {
	var lines []shedCounts
	for _, m := range shedLine.FindAllStringSubmatch(log, -1) {
		inSource, _ := strconv.Atoi(m[1])
		evicted, _ := strconv.Atoi(m[2])
		lines = append(lines, shedCounts{inSource: inSource, evicted: evicted})
	}
	return lines
}

// textAddr is an address of a type sourceOf does not know, read only through
// its string.
type textAddr string

func (a textAddr) Network() string { return "tcp" }
func (a textAddr) String() string  { return string(a) }

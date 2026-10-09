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
	"strings"
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

// A client that connects and says nothing costs its own goroutine and nothing
// else: a device dialling meanwhile is served at once.
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

// The number of connections proving themselves at once is bounded. With every
// slot held by a silent client, a device waits in the kernel's queue - its
// connection is not dropped - and gets in once the silent ones run out of
// budget.
func TestHandshakesUnderWayAreBounded(t *testing.T) {
	const budget = 2 * time.Second
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "bounded.db"), nil,
		func(s *Server) { s.channelTimeout = budget })
	t.Cleanup(closeAll)
	listener, ok := ts.Listener.(*channelListener)
	if !ok {
		t.Fatalf("the test server's listener is %T", ts.Listener)
	}
	for range maxPendingChannels {
		conn, err := net.Dial("tcp", ts.Listener.Addr().String())
		if err != nil {
			t.Fatalf("dial: %v", err)
		}
		t.Cleanup(func() { _ = conn.Close() })
	}
	// Full: the loop holds a slot before every accept, so a full set means the
	// next connection stays in the kernel's queue.
	eventually(t, "every slot is held", func() bool { return len(listener.slots) == maxPendingChannels })

	done := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 4*budget)
		defer cancel()
		conn, err := dialChannel(ctx, ts.Listener.Addr().String(), serverKeyOf(t, srv), newDevice(t).priv)
		if err == nil {
			_ = conn.Close()
		}
		done <- err
	}()
	select {
	case err := <-done:
		t.Fatalf("a device got through while every slot was held (err %v)", err)
	case <-time.After(200 * time.Millisecond):
	}
	if err := <-done; err != nil {
		t.Fatalf("the device was refused once the slots freed: %v", err)
	}
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
	// Two slots: the handshake's, and the one the loop has already taken for
	// the next connection it accepts.
	eventually(t, "the handshake is under way", func() bool { return len(l.slots) == 2 })

	closed := make(chan error, 1)
	go func() { closed <- l.Close() }()
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("Close waited on a handshake with an hour of budget left")
	}
	if got := silentAfter(t, conn); len(got) != 0 {
		t.Fatalf("a connection cut by Close was sent %d bytes", len(got))
	}
	if _, err := l.Accept(); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("Accept after Close = %v, want net.ErrClosed", err)
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

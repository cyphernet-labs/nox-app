package server

import (
	"bytes"
	"crypto/ed25519"
	"io"
	"log"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"

	"nox.app/client-backend/internal/tor"
)

// fakeTor stands in for the supervisor: the handlers and the watcher talk to
// it exactly as they would to a running tor, and the test decides what it
// says.
type fakeTor struct {
	mu      sync.Mutex
	offered bool
	ready   bool
	kicks   int
	status  tor.Status
	pub     ed25519.PublicKey
	addr    string
}

func newFakeTor(t *testing.T) *fakeTor {
	t.Helper()
	pub, err := tor.PublicKey(bytes.Repeat([]byte{42}, 32))
	if err != nil {
		t.Fatalf("PublicKey: %v", err)
	}
	addr, err := tor.Address(pub)
	if err != nil {
		t.Fatalf("Address: %v", err)
	}
	return &fakeTor{pub: pub, addr: addr, status: tor.Status{Enabled: true, Phase: tor.PhaseRunning, Bootstrap: 100}}
}

func (f *fakeTor) KeysChanged() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.kicks++
}

func (f *fakeTor) ReadyForInvite() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.ready
}

func (f *fakeTor) Offered() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.offered
}

func (f *fakeTor) OnionPublicKey() ed25519.PublicKey { return f.pub }
func (f *fakeTor) Address() string                   { return f.addr }

func (f *fakeTor) Status() tor.Status {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.status
}

func (f *fakeTor) set(offered, ready bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.offered, f.ready = offered, ready
}

func (f *fakeTor) kickCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.kicks
}

// onionStack is the full server with a fake tor and a second TLS entry marked
// as the onion one - the same ConnContext Run gives the real onion listener.
type onionStack struct {
	ts    *httptest.Server // the direct entry
	onion *httptest.Server // the onion entry
	srv   *Server
	tor   *fakeTor
}

func newOnionStack(t *testing.T, tweak ...func(*Server)) *onionStack {
	t.Helper()
	ft := newFakeTor(t)
	all := append([]func(*Server){func(s *Server) { s.tor = ft }}, tweak...)
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "onion.db"), nil, all...)
	t.Cleanup(closeAll)

	tlsCfg, err := srv.serverTLSConfig(t.Context())
	if err != nil {
		t.Fatalf("serverTLSConfig: %v", err)
	}
	onion := httptest.NewUnstartedServer(srv.Handler())
	onion.TLS = tlsCfg
	onion.Config.ConnContext = markOnionConn
	onion.Config.ErrorLog = log.New(io.Discard, "", 0)
	onion.StartTLS()
	onion.Client().Transport = ts.Client().Transport
	t.Cleanup(onion.Close)
	return &onionStack{ts: ts, onion: onion, srv: srv, tor: ft}
}

// discardLogger is a logger nobody reads.
func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// pinnedClient is the transport the app uses: the pin and nothing else.
func pinnedClient(ts *httptest.Server) *http.Client { return ts.Client() }

// devKey gives this client a paired device if it has none and returns its
// public key - for tests that write the greeting by hand.
func (c *wsClient) devKey(t *testing.T) string {
	t.Helper()
	if c.dev == nil {
		c.dev = pairedDevice(t, c.ts, c.srv)
	}
	return c.dev.pub
}

// devSig signs this connection's challenge with the client's device.
func (c *wsClient) devSig(t *testing.T) string {
	t.Helper()
	return c.dev.sign(t, c.challenge)
}

// newTextLogger writes a readable log to w.
func newTextLogger(w io.Writer) *slog.Logger { return slog.New(slog.NewTextHandler(w, nil)) }

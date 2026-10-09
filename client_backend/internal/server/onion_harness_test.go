package server

import (
	"bytes"
	"crypto/ed25519"
	"io"
	"log/slog"
	"net"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"
	"time"

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

// onionStack is the full server with a fake tor and a second entry behind the
// channel, marked as the onion one - the same ConnContext and budget Run gives
// the real onion listener.
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

	raw, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	tlsCfg, err := channelTLSConfig(time.Now())
	if err != nil {
		t.Fatalf("channelTLSConfig: %v", err)
	}
	key, err := srv.store.ServerKey(t.Context())
	if err != nil {
		t.Fatalf("ServerKey: %v", err)
	}
	// The devices the plain client presents are the direct entry's: a device
	// that greeted at home moves bytes over onion as itself.
	onion := serveChannel(t, srv, raw, tlsCfg, key, srv.onionTimeout, "onion", onionConnContext, channelOf(t, ts).devices)
	t.Cleanup(onion.Close)
	return &onionStack{ts: ts, onion: onion, srv: srv, tor: ft}
}

// discardLogger is a logger nobody reads.
func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// newTextLogger writes a readable log to w.
func newTextLogger(w io.Writer) *slog.Logger { return slog.New(slog.NewTextHandler(w, nil)) }

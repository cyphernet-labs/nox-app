package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"database/sql"
	"encoding/base64"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/eidolon"
	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/store"
	"nox.app/client-backend/internal/vault"
)

// testDataKey is the data key every test database and files directory built
// by openStack is encrypted with (047). Fixed, so a test that stops a stack
// and starts another over the same files opens them again.
var testDataKey = bytes.Repeat([]byte{0x47}, 32)

// testKDF are Argon2id costs a test can afford many times over: what is under
// test around the lock is the lock, not Argon2's price. The production costs
// have a test of their own in the vault package.
var testKDF = vault.Params{MemoryKiB: 64, Iterations: 1, Parallelism: 1}

// testPassword is the password tests set and enter.
const testPassword = "correct horse battery"

// newTestServer builds the full stack over a temp database and returns the
// running httptest server plus the Server for direct inspection.
func newTestServer(t *testing.T) (*httptest.Server, *Server) {
	t.Helper()
	return newTestServerLogging(t, nil)
}

// newTestServerWith is newTestServer with tweaks applied to the Server before
// anything serves - fixing the machine's interfaces, moving its bind address,
// scaling a timeout.
func newTestServerWith(t *testing.T, tweak ...func(*Server)) (*httptest.Server, *Server) {
	t.Helper()
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "test.db"), nil, tweak...)
	t.Cleanup(closeAll)
	return ts, srv
}

// newTestServerLogging is newTestServer with somewhere to read the log from.
// The logger is handed in BEFORE the stack starts: assigning srv.logger after
// httptest is serving races the request middleware.
func newTestServerLogging(t *testing.T, logger *slog.Logger) (*httptest.Server, *Server) {
	t.Helper()
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "test.db"), logger)
	t.Cleanup(closeAll)
	return ts, srv
}

// openStack assembles db + hub + server over the given database file and
// returns an explicit close function, so lifecycle tests can stop and restart
// the whole stack against the same file.
//
// tweak runs on the Server after New and before anything serves - where a test
// fixes the machine's interfaces or scales a timeout.
func openStack(t *testing.T, path string, logger *slog.Logger, tweak ...func(*Server)) (*httptest.Server, *Server, func()) {
	t.Helper()

	dbs, err := db.Open(path, testDataKey)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	if _, err := db.Migrate(context.Background(), dbs.Write, os.DirFS("../../migrations")); err != nil {
		_ = dbs.Close()
		t.Fatalf("db.Migrate: %v", err)
	}

	bl, err := blob.Open(path + "-files")
	if err != nil {
		_ = dbs.Close()
		t.Fatalf("blob.Open: %v", err)
	}

	// The main entry's socket first, so the configured address is the real
	// one: links carry it, and a link with port 0 is one no parser reads.
	raw, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		_ = bl.Close()
		_ = dbs.Close()
		t.Fatalf("listen: %v", err)
	}

	h := hub.New()
	hubCtx, stopHub := context.WithCancel(context.Background())
	hubDone := make(chan struct{})
	go func() {
		defer close(hubDone)
		h.Run(hubCtx)
	}()

	if logger == nil {
		logger = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	cfg := config.Config{Addr: raw.Addr().String(), DBPath: path, FilesPath: path + "-files", Limits: config.DefaultLimits()}
	st := store.New(dbs.Read, dbs.Write)
	// Mirror Run: the store identity is minted in Go once the schema exists,
	// and the greeting hands it to clients.
	if err := st.EnsureJournal(t.Context()); err != nil {
		t.Fatalf("EnsureJournal: %v", err)
	}
	// Mirror Run again: the machine's key is settled before anything serves,
	// because the channel proves it on every connection.
	if _, err := st.EnsureServerIdentity(t.Context()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	serverKey, err := st.ServerKey(t.Context())
	if err != nil {
		t.Fatalf("ServerKey: %v", err)
	}
	srv := New(cfg, st, h, bl, logger)
	// The machine "has" no interfaces unless a test says otherwise: the
	// address list must not depend on the network of whoever runs the suite.
	srv.listIPs = func() []net.IP { return nil }
	srv.pingInterval = 50 * time.Millisecond
	// The request sweep at test speed: a request whose time ran out closes
	// within a few tens of milliseconds rather than seconds.
	srv.requestSweep = 20 * time.Millisecond
	// The write timeout stays the slow path's 30 s: slow-consumer tests rely
	// on it, because the overflow drop (policy violation) must win over a
	// ping or write timeout.
	//
	// Mirror Run's startup order: the orphan sweep runs before endpoints open.
	if err := srv.sweepOrphans(context.Background(), time.Now().Add(-24*time.Hour).Unix()); err != nil {
		t.Fatalf("startup sweep: %v", err)
	}
	for _, fn := range tweak {
		fn(srv)
	}
	// Mirror Run again: the first address snapshot exists before anything
	// serves, and the watcher - the only sender of server.addresses - runs.
	srv.refreshAddresses(t.Context())
	watchCtx, stopWatch := context.WithCancel(context.Background())
	watchDone := make(chan struct{})
	go func() {
		defer close(watchDone)
		srv.runAddressWatcher(watchCtx)
	}()
	// And the request sweeper, which Run starts beside the watcher (046).
	sweepCtx, stopSweep := context.WithCancel(context.Background())
	sweepDone := make(chan struct{})
	go func() {
		defer close(sweepDone)
		srv.runRequestSweeper(sweepCtx)
	}()

	dispDone := make(chan struct{})
	go func() {
		defer close(dispDone)
		_ = srv.runDispatcher(hubCtx)
	}()

	// The channel exactly as Run builds it: TLS on a throwaway certificate,
	// then the check, and only then the handler. NOT httptest.NewTLSServer: its
	// stock TLS would put the handler behind something the product never uses,
	// and leave this feature's one real question - who proved which key -
	// untested.
	tlsCfg, err := channelTLSConfig(time.Now())
	if err != nil {
		t.Fatalf("channelTLSConfig: %v", err)
	}
	ts := serveChannel(t, srv, raw, tlsCfg, serverKey, &testDevices{})
	closeAll := func() {
		ts.Close()
		stopWatch()
		<-watchDone
		stopSweep()
		<-sweepDone
		stopHub()
		<-hubDone
		<-dispDone
		_ = bl.Close()
		_ = dbs.Close()
	}
	return ts, srv, closeAll
}

// serveChannel serves srv's handler behind the channel on raw, the way Run
// serves the main port, and returns an httptest.Server whose client dials the
// way the app does. ts.URL is https: it names the TLS the channel carries, and
// the client's transport is the one that knows how to open it.
func serveChannel(t *testing.T, srv *Server, raw net.Listener, cfg *tls.Config, key ed25519.PrivateKey, devices *testDevices) *httptest.Server {
	t.Helper()
	ts := httptest.NewUnstartedServer(srv.Handler())
	_ = ts.Listener.Close()
	ts.Listener = srv.newChannelListener(raw, cfg, key, srv.channelTimeout)
	ts.Config.ConnContext = withChannelPeer
	ts.Config.ReadHeaderTimeout = readHeaderTimeout
	// Transport-level complaints go nowhere: several tests break connections
	// on purpose, and http.Server would print each one to stderr.
	ts.Config.ErrorLog = log.New(io.Discard, "", 0)
	ts.Config.RegisterOnShutdown(srv.CloseConnections)
	ts.Start()
	ts.URL = "https://" + raw.Addr().String()
	ts.Client().Transport = newTestChannel(raw.Addr().String(), key.Public().(ed25519.PublicKey), devices)
	return ts
}

// testChannel is every test server's client transport: TCP, TLS 1.3 that
// checks no certificate, then the channel check as a device against the
// server's key - and only then HTTP. It is what the app's Rust module does,
// and it is why ts.Client() and ts.URL go on working unchanged.
type testChannel struct {
	*http.Transport
	addr      string
	serverKey ed25519.PublicKey
	devices   *testDevices
}

// testDevices remembers which device the plain client presents: the last one
// a helper paired or greeted. /files wants a PAIRED key on the connection, and
// the tests that move bytes do it right after greeting - so the device that
// just greeted is the one to send them as. Before any, it is a stranger.
type testDevices struct {
	mu       sync.Mutex
	last     *device
	stranger *device
}

func (d *testDevices) use(dev *device) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.last = dev
}

func (d *testDevices) current() (*device, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.last != nil {
		return d.last, nil
	}
	if d.stranger == nil {
		_, priv, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			return nil, err
		}
		d.stranger = &device{pub: base64.StdEncoding.EncodeToString(priv.Public().(ed25519.PublicKey)), priv: priv}
	}
	return d.stranger, nil
}

func newTestChannel(addr string, serverKey ed25519.PublicKey, devices *testDevices) *testChannel {
	ch := &testChannel{addr: addr, serverKey: serverKey, devices: devices}
	ch.Transport = ch.transportAs(nil)
	return ch
}

// transportAs dials every connection as d; nil means whichever device
// testDevices names at the moment of the dial.
func (ch *testChannel) transportAs(d *device) *http.Transport {
	return &http.Transport{
		DialTLSContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			dev := d
			if dev == nil {
				var err error
				if dev, err = ch.devices.current(); err != nil {
					return nil, err
				}
			}
			return dialChannel(ctx, ch.addr, ch.serverKey, dev.priv)
		},
	}
}

// clientAs is an HTTP client whose every connection proves d's key.
func (ch *testChannel) clientAs(d *device) *http.Client {
	return &http.Client{Transport: ch.transportAs(d)}
}

// channelOf is the channel transport of a test server.
func channelOf(t *testing.T, ts *httptest.Server) *testChannel {
	t.Helper()
	ch, ok := ts.Client().Transport.(*testChannel)
	if !ok {
		t.Fatal("this test server's client does not dial the channel")
	}
	return ch
}

// dialChannel opens one channel as the device priv belongs to: everything a
// device does before its first byte of HTTP, and nothing else. The returned
// connection is the verified TLS session with no deadline left on it.
func dialChannel(ctx context.Context, addr string, serverKey ed25519.PublicKey, priv ed25519.PrivateKey) (*tls.Conn, error) {
	raw, err := (&net.Dialer{}).DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}
	return channelOver(ctx, raw, serverKey, priv)
}

// channelOver runs the channel on a transport that is already open - a TCP
// connection, or a stream through Tor - and closes it on any failure.
func channelOver(ctx context.Context, raw net.Conn, serverKey ed25519.PublicKey, priv ed25519.PrivateKey) (*tls.Conn, error) {
	tc := tls.Client(raw, testClientTLS())
	if err := tc.HandshakeContext(ctx); err != nil {
		_ = raw.Close()
		return nil, err
	}
	state := tc.ConnectionState()
	binding, err := state.ExportKeyingMaterial(eidolon.ExporterLabel, nil, eidolon.BindingSize)
	if err != nil {
		_ = raw.Close()
		return nil, err
	}
	if err := eidolon.Initiate(ctx, tc, binding, priv, serverKey); err != nil {
		_ = raw.Close()
		return nil, err
	}
	if err := tc.SetDeadline(time.Time{}); err != nil {
		_ = raw.Close()
		return nil, err
	}
	return tc, nil
}

// testClientTLS is the device's TLS: 1.3 only, no certificate check - the
// certificate is technical, the channel check decides - no SNI, since no name
// is set, and no resumption.
func testClientTLS() *tls.Config {
	return &tls.Config{
		InsecureSkipVerify:     true, //nolint:gosec // the channel check is the check; see the doc comment
		MinVersion:             tls.VersionTLS13,
		NextProtos:             []string{"http/1.1"},
		SessionTicketsDisabled: true,
	}
}

// serverKeyOf reads the machine's public key, as a link names it.
func serverKeyOf(t *testing.T, srv *Server) ed25519.PublicKey {
	t.Helper()
	id, err := srv.store.ServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}
	return id.PublicKey
}

// /health answers on the service page's listener and nowhere else (044): the
// main port says nothing to anybody before the channel check, and a liveness
// probe proves no key.
func TestHealthServes200OnTheServicePageMux(t *testing.T) {
	_, srv := newTestServer(t)
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if body := rec.Body.String(); body != `{"status":"ok"}` {
		t.Fatalf("body = %s", body)
	}
}

func TestHealthIsNotOnTheMainPort(t *testing.T) {
	ts, _ := newTestServer(t)
	resp, err := ts.Client().Get(ts.URL + "/health")
	if err != nil {
		t.Fatalf("GET /health: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("GET /health on the main port = %d, want 404", resp.StatusCode)
	}
}

// readDB opens a second read handle over the server's own database file, so a
// test can assert on rows the command surface does not expose. Same process,
// so invariant 1 (one process per file) holds. A harness server's database is
// encrypted with testDataKey.
func readDB(t *testing.T, srv *Server) *sql.DB {
	t.Helper()
	d, err := db.Open(srv.cfg.DBPath, testDataKey)
	if err != nil {
		t.Fatalf("db.Open for reading: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	return d.Read
}

// readWriteDB is readDB's writing twin, for the one thing a test needs it for:
// leaving the database the way a hand edit or a partial restore would.
func readWriteDB(t *testing.T, srv *Server) *sql.DB {
	t.Helper()
	d, err := db.Open(srv.cfg.DBPath, testDataKey)
	if err != nil {
		t.Fatalf("db.Open for writing: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	return d.Write
}

// A startup that is going to abort must not rotate the journal on its way out.
// The journal id is what makes every paired device wipe its chats, messages,
// cursor and read marks - and a partial restore is exactly when the operator
// still has a way back, right up until something destroys it for them.
func TestAnAbortedStartupDoesNotRotateTheJournal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "restore.db")
	dbs, err := db.Open(path, testDataKey)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = dbs.Close() })
	ctx := context.Background()
	if _, err := db.Migrate(ctx, dbs.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	// A restore that brought back people but neither single-row bootstrap table.
	if _, err := dbs.Write.ExecContext(ctx,
		"INSERT INTO users (user_id, label, created_at) VALUES ('u_restored', 'Restored', 1)"); err != nil {
		t.Fatalf("insert person: %v", err)
	}

	st := store.New(dbs.Read, dbs.Write)
	if _, err := st.EnsureServerIdentity(ctx); err == nil {
		t.Fatal("a store with people and no server identity was handed a new key")
	}

	// And nothing minted a journal on the way to that refusal.
	var journals int
	if err := dbs.Read.QueryRowContext(ctx, "SELECT COUNT(1) FROM journal").Scan(&journals); err != nil {
		t.Fatalf("count journal: %v", err)
	}
	if journals != 0 {
		t.Fatal("the journal was rotated before the startup guard could refuse - every paired device would wipe its world")
	}
}

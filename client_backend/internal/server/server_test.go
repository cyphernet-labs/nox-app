package server

import (
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
	"strings"
	"sync"
	"testing"
	"time"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/eidolon"
	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/store"
)

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

	dbs, err := db.Open(path)
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
	srv.configureMain(ts.Config)
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
// so invariant 1 (one process per file) holds.
func readDB(t *testing.T, srv *Server) *sql.DB {
	t.Helper()
	d, err := db.Open(srv.cfg.DBPath)
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
	d, err := db.Open(srv.cfg.DBPath)
	if err != nil {
		t.Fatalf("db.Open for writing: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	return d.Write
}

// announceConfig is the configuration startup hands to announceClaim: a bind
// address for the link it builds, and the service page that shows the link.
var announceConfig = config.Config{Addr: "127.0.0.1:8080", StatusAddr: "127.0.0.1:8081"}

// The startup line says where the claim link is and never what it is: the link
// carries the claim token and, packed, the onion service's key, and a log is
// copied to places neither may go (045, FR-022). With the page turned off it
// says how to turn it on, because nothing else shows the link.
func TestTheStartupLinePointsAtThePageAndNeverCarriesTheLink(t *testing.T) {
	st := startStore(t)
	ctx := context.Background()
	stored := setAddressParams(t, st, testOnionAddr)

	logs := &syncBuffer{}
	token, err := announceClaim(ctx, st, announceConfig, mustOwnership(t, st), mustIdentity(t, st), configured(stored),
		slog.New(ScrubLogs(slog.NewTextHandler(logs, nil))))
	if err != nil {
		t.Fatalf("announceClaim: %v", err)
	}
	out := logs.String()
	if token == "" || strings.Contains(out, token) || strings.Contains(out, "nox://pair/") || strings.Contains(out, "[link]") {
		t.Fatalf("the line carries the link or its token (%q):\n%s", token, out)
	}
	if !strings.Contains(out, "service page") || !strings.Contains(out, "http://127.0.0.1:8081") {
		t.Fatalf("the line does not say where the link is:\n%s", out)
	}

	off := &syncBuffer{}
	cfg := announceConfig
	cfg.StatusAddr = ""
	if _, err := announceClaim(ctx, st, cfg, mustOwnership(t, st), mustIdentity(t, st), configured(stored),
		slog.New(slog.NewTextHandler(off, nil))); err != nil {
		t.Fatalf("announceClaim with the page off: %v", err)
	}
	if !strings.Contains(off.String(), "level=WARN") || !strings.Contains(off.String(), "-status-addr") {
		t.Fatalf("with the page off the line does not say how to see the link:\n%s", off.String())
	}
}

// setAddressParams stores onion the way a start parameter does and returns the
// stored addresses.
func setAddressParams(t *testing.T, st *store.Store, onion string) store.Addresses {
	t.Helper()
	if err := st.ApplyAddressParam(context.Background(), store.AddressOnion, onion, onion); err != nil {
		t.Fatalf("ApplyAddressParam: %v", err)
	}
	got, err := st.Addresses(context.Background())
	if err != nil {
		t.Fatalf("Addresses: %v", err)
	}
	return got
}

// The startup line has to tell the two situations apart, because they ask
// different things of the person reading it: a machine nobody has claimed is
// about to get an owner, while one whose owner lost every device is about to
// let that same owner back in. Before ownership was explicit the two were
// indistinguishable and the message said "no owner yet" for both.
func TestTheStartupLineDistinguishesAnUnclaimedServerFromAnEmptyOne(t *testing.T) {
	path := filepath.Join(t.TempDir(), "announce.db")
	dbs, err := db.Open(path)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = dbs.Close() })
	if _, err := db.Migrate(context.Background(), dbs.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	st := store.New(dbs.Read, dbs.Write)
	ctx := context.Background()

	fresh := &syncBuffer{}
	if _, err := announceClaim(ctx, st, announceConfig, mustOwnership(t, st), mustIdentity(t, st), configuredAddresses{}, slog.New(slog.NewTextHandler(fresh, nil))); err != nil {
		t.Fatalf("announceClaim on a fresh store: %v", err)
	}
	if !strings.Contains(fresh.String(), "no owner yet") {
		t.Fatalf("fresh store announced %q", fresh.String())
	}

	// Claim it, then take the device away - which is what logging out does.
	token, err := st.IssueClaimToken(ctx, 100)
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	if _, err := st.Pair(ctx, token, "dev-a", "test", 100); err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if err := st.RevokeDevice(ctx, "dev-a"); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	owned := &syncBuffer{}
	if _, err := announceClaim(ctx, st, announceConfig, mustOwnership(t, st), mustIdentity(t, st), configuredAddresses{}, slog.New(slog.NewTextHandler(owned, nil))); err != nil {
		t.Fatalf("announceClaim on an owned store: %v", err)
	}
	if strings.Contains(owned.String(), "no owner yet") {
		t.Fatalf("a server that still has an owner claims to have none: %q", owned.String())
	}
	if !strings.Contains(owned.String(), "get back in") {
		t.Fatalf("owned-but-empty store announced %q", owned.String())
	}

	// And the third: a store that holds the person but lost the marker. This is
	// the state feature 037 traded the old refusal for, so it is the one line an
	// operator reads while recovering. Ordering matters here - Owned implies
	// HasPerson, so a switch that tested HasPerson first would swallow the case
	// above and pass every other assertion in this test.
	handle, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open the database again: %v", err)
	}
	if _, err := handle.Exec("UPDATE server_identity SET owner_user_id = NULL WHERE id = 1"); err != nil {
		t.Fatalf("forget the owner: %v", err)
	}
	_ = handle.Close()

	stranded := &syncBuffer{}
	if _, err := announceClaim(ctx, st, announceConfig, mustOwnership(t, st), mustIdentity(t, st), configuredAddresses{}, slog.New(slog.NewTextHandler(stranded, nil))); err != nil {
		t.Fatalf("announceClaim on a store with no marker: %v", err)
	}
	if !strings.Contains(stranded.String(), "sign in as the person it belongs to") {
		t.Fatalf("a store that holds somebody announced %q", stranded.String())
	}
	for _, wrong := range []string{"no owner yet", "get back in"} {
		if strings.Contains(stranded.String(), wrong) {
			t.Fatalf("announced %q, which is the copy for another state: %q", wrong, stranded.String())
		}
	}
}

// mustIdentity mints or reads the machine identity startup settles first.
func mustIdentity(t *testing.T, st *store.Store) store.ServerIdentity {
	t.Helper()
	id, err := st.EnsureServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	return id
}

// mustOwnership reads the snapshot startup would hand to announceClaim.
func mustOwnership(t *testing.T, st *store.Store) store.OwnershipState {
	t.Helper()
	state, err := st.ReadOwnershipState(context.Background())
	if err != nil {
		t.Fatalf("ReadOwnershipState: %v", err)
	}
	return state
}

// A startup that is going to abort must not rotate the journal on its way out.
// The journal id is what makes every paired device wipe its chats, messages,
// cursor and read marks - and a partial restore is exactly when the operator
// still has a way back, right up until something destroys it for them.
func TestAnAbortedStartupDoesNotRotateTheJournal(t *testing.T) {
	path := filepath.Join(t.TempDir(), "restore.db")
	dbs, err := db.Open(path)
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

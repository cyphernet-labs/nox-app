// Package server wires the HTTP surface (contract §1) and the WebSocket
// command channel (contract §2-§6) over the store and the hub, and owns the
// process lifecycle including the ordered shutdown of CLAUDE.md invariant 9.
package server

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
	"golang.org/x/sync/errgroup"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
	"nox.app/client-backend/internal/vault"
)

const (
	// slowPathTimeout is the budget of every wait a round trip through Tor can
	// stretch: one frame write, one ping's wait for its pong, the request
	// headers, and TLS with the channel check (channel.go). It is every
	// connection's budget, not only the onion ones' (045, FR-009): tor
	// forwards the onion service to the main port, and a connection from it
	// looks like any other. A round trip through Tor can take seconds; 30 s
	// covers a 10 s one three times over.
	slowPathTimeout     = 30 * time.Second
	defaultPingInterval = 25 * time.Second
	// defaultWriteTimeout bounds one frame write and one ping's wait for its
	// pong.
	defaultWriteTimeout = slowPathTimeout
	// readHeaderTimeout bounds the request headers that follow the channel
	// check on the main port.
	readHeaderTimeout = slowPathTimeout
	// pageReadHeaderTimeout is the service page's: a browser on this same
	// machine, never a path through Tor.
	pageReadHeaderTimeout = 5 * time.Second
	shutdownTimeout       = 5 * time.Second
	// drainTimeout bounds the wait for connection handlers at shutdown. Longer
	// than one close handshake (the library's 5 s write + 5 s wait for the
	// peer), which a connection through Tor can use whole, so a goodbye still
	// in flight is not cut off by the database closing under it.
	drainTimeout = 15 * time.Second
	// outBuffer is the per-connection outbound queue (replies + replay +
	// forwarded live events). Overflow on the LIVE path means a slow
	// consumer: the connection is closed and heals via replay. The read
	// goroutine's own frames (replies, replay) block instead of dropping.
	outBuffer = 64
)

// Server handles one process's connections.
type Server struct {
	cfg    config.Config
	store  *store.Store
	hub    *hub.Hub
	blob   *blob.Store
	tokens *tokenStore
	logger *slog.Logger

	// The file transfers (043). writers keeps one request writing each part.
	// The rest are fields so tests can scale them: how long a body may go
	// without a byte before the transfer counts as stalled, how often an
	// upload makes what it received durable, how long a PUT waits for the
	// previous writer of its file to let go, and how long a continuation
	// does - a command handler runs on the loop that also reads pongs.
	writers          *uploadWriters
	stallTimeout     time.Duration
	checkpointBytes  int64
	preemptWait      time.Duration
	continuationWait time.Duration

	pingInterval time.Duration
	writeTimeout time.Duration
	// channelTimeout is the budget for TLS and the channel check together
	// (044). A field so tests can scale it.
	channelTimeout time.Duration

	// addrs is the current address snapshot. After startup only the watcher
	// writes it; greetings read it.
	addrs atomic.Pointer[addressSet]
	// addrKick pokes the watcher; capacity 1 coalesces.
	addrKick chan struct{}
	// addressPoll is how often the watcher looks at the interfaces.
	addressPoll time.Duration
	// listIPs enumerates the machine's dialable addresses. A field so tests can
	// fix what the machine "has".
	listIPs func() []net.IP
	// resolveHost resolves a bind host NAME for the address list. A field for
	// the same reason as listIPs.
	resolveHost func(string) ([]net.IP, error)
	// Test seams at the two moments the greeting's ordering rests on: right
	// after the hello handler reads the address snapshot, and right after
	// markGreeted. Nil outside tests; nothing else can put the watcher there
	// on demand.
	afterAddressRead func()
	afterGreeted     func(*client)
	// The same kind of seam in the file chain (043): right after an upload's
	// part became its file and before the database hears of it - the window a
	// client hanging up, a continuation or a crash lands in. Nil outside tests.
	afterFinalize func(fileID string)
	// What the service page shows about the process itself. Set once at
	// startup: the schema version the migrator reported, the moment this
	// process began. A person who closed that terminal has no other way to it.
	schemaVersion int
	startedAt     time.Time
	// addrWarnings are the start parameters that were not applied (045). Set
	// once at startup before anything serves, read by the page after.
	addrWarnings []addressWarning
	// formToken is what the service page's forms carry - Set, the link
	// buttons and the password forms - and what every POST of the page
	// checks: 32 random bytes per process, hex. A page from another site
	// cannot read it, so it cannot forge the form even from this machine's
	// own browser. Run hands in the gate's (047), so one token holds from the
	// lock page to the open one.
	formToken string
	// dataKey is the key the database and the attachments are encrypted with
	// (047), as the password unsealed it. Only a backup needs it here: the
	// snapshot is written under it, and the archive's MAC key comes from it.
	dataKey []byte

	// requestSweep is how often the sweeper closes pairing requests whose time
	// ran out (046). A field so tests can scale it.
	requestSweep time.Duration

	// kick wakes the event dispatcher after a committed mutation; capacity 1
	// coalesces bursts (the dispatcher drains the log until it is current).
	kick chan struct{}

	// mu guards conns; wg tracks connection handlers so shutdown can wait
	// for hijacked connections. Infrastructure-only synchronization
	// (ws-rest-patterns §5); business state stays goroutine-owned.
	mu    sync.Mutex
	conns map[*client]struct{}
	wg    sync.WaitGroup
}

// New builds a Server over an opened store, a running hub and a blob store.
func New(cfg config.Config, st *store.Store, h *hub.Hub, bl *blob.Store, logger *slog.Logger) *Server {
	return &Server{
		cfg:              cfg,
		store:            st,
		hub:              h,
		blob:             bl,
		tokens:           newTokenStore(),
		logger:           logger,
		writers:          newUploadWriters(),
		stallTimeout:     defaultStallTimeout,
		checkpointBytes:  defaultCheckpointBytes,
		preemptWait:      defaultPreemptWait,
		continuationWait: defaultContinuationWait,
		pingInterval:     defaultPingInterval,
		writeTimeout:     defaultWriteTimeout,
		channelTimeout:   defaultChannelTimeout,
		addrKick:         make(chan struct{}, 1),
		addressPoll:      defaultAddressPoll,
		listIPs:          usableIPs,
		resolveHost:      resolveHost,
		startedAt:        time.Now(),
		formToken:        newFormToken(),
		requestSweep:     defaultRequestSweep,
		kick:             make(chan struct{}, 1),
		conns:            make(map[*client]struct{}),
	}
}

// newFormToken mints the service page's form token.
func newFormToken() string {
	var buf [32]byte
	if _, err := rand.Read(buf[:]); err != nil {
		// The platform RNG failing is fatal-grade; mirrors tokenStore.issue. A
		// guessable token would be worse than no page.
		panic("crypto/rand: " + err.Error())
	}
	return hex.EncodeToString(buf[:])
}

// kickDispatcher signals the dispatcher that new events are committed.
func (s *Server) kickDispatcher() {
	select {
	case s.kick <- struct{}{}:
	default:
	}
}

// runDispatcher broadcasts committed events in strict seq order. Handlers
// never broadcast themselves: two connections committing seq N and N+1
// concurrently could otherwise reach the hub out of order, and a client
// whose cursor jumped to N+1 would lose N forever. A single reader of the
// committed log makes the order authoritative. Events committed before
// startup are replay-only.
func (s *Server) runDispatcher(ctx context.Context) error {
	last, err := s.store.Cursor(ctx)
	if err != nil {
		// A shutdown that lands before this first read is a stop, not a
		// failure: the read fails BECAUSE of the cancel, and reporting it made
		// Run return an error for a clean stop.
		if ctx.Err() != nil {
			return nil
		}
		return fmt.Errorf("dispatcher cursor: %w", err)
	}
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-s.kick:
		}
		for {
			events, err := s.store.EventsSince(ctx, last)
			if err != nil {
				// Transient read failure: the next kick retries from last.
				s.logger.Error("dispatcher read failed", "err", err, "after_seq", last)
				break
			}
			if len(events) == 0 {
				break
			}
			for _, ev := range events {
				env, err := eventEnvelope(ev)
				if err != nil {
					s.logger.Error("dispatcher marshal failed", "err", err, "seq", ev.Seq)
					last = ev.Seq
					continue
				}
				s.hub.Broadcast(env)
				last = ev.Seq
			}
		}
	}
}

// Handler returns the HTTP surface the main port serves behind the channel:
// the WebSocket and the file bytes, and nothing else. /health lives on the
// service page's loopback listener (044): the main port answers nobody who has
// not proved a key, and a probe that has not cannot ask it anything.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /ws", s.handleWS)
	mux.HandleFunc("PUT /files/{token}", s.handlePutFile)
	mux.HandleFunc("GET /files/{token}", s.handleGetFile)
	return s.logRequests(mux)
}

// CloseConnections force-closes every live WebSocket with the going-away
// status. Wire it via http.Server.RegisterOnShutdown: Shutdown itself never
// waits for hijacked connections.
//
// In PARALLEL (039). One close handshake waits up to 5 s to write and 5 s for
// the peer's answer, and a connection through Tor can use both; one after
// another, a few devices away from home would push the rest of the shutdown
// past every deadline.
func (s *Server) CloseConnections() {
	s.mu.Lock()
	clients := make([]*client, 0, len(s.conns))
	for c := range s.conns {
		clients = append(clients, c)
	}
	s.mu.Unlock()
	var wg sync.WaitGroup
	for _, c := range clients {
		wg.Go(func() { c.close(websocket.StatusGoingAway, "server shutting down") })
	}
	wg.Wait()
}

// WaitConnections blocks until every connection handler has returned or ctx
// expires. http.Server.Shutdown never waits for hijacked connections, so the
// shutdown path calls this between Shutdown and stopping the hub.
func (s *Server) WaitConnections(ctx context.Context) error {
	done := make(chan struct{})
	go func() {
		s.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// dropDevice cuts off every live connection authenticated with a revoked key,
// and tells each one why before the socket closes.
//
// Immediately, not on the device's next attempt: a sold tablet would otherwise
// keep reading the conversation for as long as it stays online, which is the
// whole thing revocation exists to stop.
func (s *Server) dropDevice(deviceKey string) {
	s.mu.Lock()
	doomed := make([]*client, 0, 1)
	for c := range s.conns {
		if c.deviceKey == deviceKey {
			doomed = append(doomed, c)
		}
	}
	s.mu.Unlock()
	payload, err := json.Marshal(map[string]string{"device_key": deviceKey})
	if err != nil {
		// Cannot fail for a map of strings, but the connections still have to
		// go: the row is already deleted either way.
		payload = json.RawMessage(`{}`)
	}
	for _, c := range doomed {
		c.sendFrame(protocol.Event{Seq: 0, Event: protocol.EventDeviceRevoked, Data: payload})
		go c.closeAfterFlush("device revoked")
	}
}

// refreshLabel updates the cached identity of every live connection of a
// person after a rename.
//
// Under the same lock as the writes it touches. Without it the renaming device
// is the only one that knows: another live socket keeps the identity it cached
// at greeting time and stamps the old name into `messages.author_label`, which
// is frozen at send time and never follows a rename.
func (s *Server) refreshLabel(userID, label string, origin *client) {
	s.mu.Lock()
	notify := make([]*client, 0, 1)
	for c := range s.conns {
		if c.identity.UserID == userID {
			c.identity.Label = label
			if c != origin {
				notify = append(notify, c)
			}
		}
	}
	s.mu.Unlock()

	if len(notify) == 0 {
		return
	}
	payload, err := json.Marshal(map[string]string{"label": label})
	if err != nil {
		// Cannot fail for a map of strings; the in-memory state above is
		// already correct either way, and a missed frame costs a stale name
		// until the next greeting rather than anything unrecoverable.
		return
	}
	// Outside the lock: sendFrame writes to a bounded queue, and a full one
	// under s.mu would hold up every other connection of every other person.
	for _, c := range notify {
		c.sendFrame(protocol.Event{Seq: 0, Event: protocol.EventIdentityUpdated, Data: payload})
	}
}

// announcePaired tells a person's OTHER live connections that a device has just
// been added through `pair`, so an open device list refreshes itself instead of
// showing a stale one until somebody leaves the screen and comes back.
//
// The connection it came from is the RECEIVER, not a parameter, and that is
// deliberate: excluding the wrong one is then unrepresentable. It cannot be
// asked through a socket - a device that is pairing has not greeted and so has
// no identity to match on - and it is still live: a greeting that fails on the
// journal id or the cursor leaves identity.UserID written and helloDone false,
// dispatch still admits `pair` on that connection, and without the exclusion
// the device would be told about its own pairing.
func (origin *client) announcePaired(userID string) {
	origin.srv.announceDevicesChanged(userID, origin)
}

// announceDevicesChanged sends device.paired to every live connection of one
// person but except (nil for none): the set of devices changed, and the
// receiver re-reads device.list.
//
// Shaped after refreshLabel and NOT after dropDevice: the two answer different
// questions. dropDevice looks for the connections holding ONE KEY and closes
// them; this needs every connection of ONE PERSON, left running. Only the frame
// shape is shared with the revocation.
//
// Collected under s.mu and sent outside it, for refreshLabel's reason:
// sendFrame writes to a bounded queue, and a full one under the registry lock
// would hold up every other connection on the server.
//
// The loop is sequential and send blocks, so a recipient whose queue is full
// holds up the recipients AFTER it, in an order map iteration does not fix. It
// is a delay rather than a loss: the wait ends when that connection's context
// is cancelled, which the slow-consumer drop is already on its way to doing.
// Dropping the frame on a full queue instead is defensible for events that do
// not survive a disconnect anyway - and is deliberately not done here, because
// it would change delivery for device.revoked too, which deserves its own
// decision rather than arriving as a side effect of this one.
//
// Inherited with the shape: a connection in the MIDDLE of greeting has an
// empty identity.UserID, because the greeting reads the person from the store
// and writes it to the connection a few lines later. Such a connection misses
// this event - and reads the list when its screen opens, which is where every
// device that was offline ends up anyway. It is the same window the rename
// carries (see client_backend/CLAUDE.md), and it closes here when it closes
// there.
func (s *Server) announceDevicesChanged(userID string, except *client) {
	notify := s.connectionsWhere(func(c *client) bool { return c.identity.UserID == userID && c != except })
	// Empty on purpose (contract §8A): the event says the set of devices
	// changed, not how, and the receiver re-reads device.list. A device key here
	// would be a public key on a frame nobody reads it from, and a spent token
	// would be a credential.
	for _, c := range notify {
		c.sendFrame(protocol.Event{Seq: 0, Event: protocol.EventDevicePaired, Data: json.RawMessage(`{}`)})
	}
}

// setIdentity records who a connection speaks as, under the same lock the
// other goroutines touch it through.
//
// A connection joins s.conns when it is accepted, long before it greets, so
// refreshLabel and announcePaired walk it while this write is still to
// come. Writing it bare made the greeting race every one of them. (The
// ten-second sweeper that once widened this window went with the person invite
// in 037; the race it exposed is the same one either way.)
func (s *Server) setIdentity(c *client, id store.Identity) {
	s.mu.Lock()
	c.identity = id
	s.mu.Unlock()
}

// currentIdentity reads back the person this connection speaks as.
//
// Needed only where the LABEL is consumed: refreshLabel rewrites it from
// another goroutine, while user_id is written once by the read goroutine itself
// and never changes. The name matters because it is frozen into message history
// at send time.
func (s *Server) currentIdentity(c *client) store.Identity {
	s.mu.Lock()
	defer s.mu.Unlock()
	return c.identity
}

func (s *Server) track(c *client) {
	s.mu.Lock()
	s.conns[c] = struct{}{}
	s.mu.Unlock()
}

func (s *Server) untrack(c *client) {
	s.mu.Lock()
	delete(s.conns, c)
	s.mu.Unlock()
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		// Transfer tokens are one-shot capabilities - they never reach
		// logs. Contains, not HasPrefix: uncleaned request paths like
		// "//files/<token>" reach this middleware before the mux's
		// canonicalization redirect.
		path := r.URL.Path
		if strings.Contains(path, "/files/") {
			path = "/files/*"
		}
		s.logger.Info("http request",
			"method", r.Method,
			"path", path,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

// Run owns the whole process: it waits for the password that opens the data
// (047), then opens the database, migrates, starts the hub and the HTTP
// server, and shuts everything down in order on ctx cancellation. It returns
// when the process is fully stopped.
func Run(ctx context.Context, cfg config.Config, migrations fs.FS, logger *slog.Logger) error {
	return run(ctx, cfg, migrations, logger, vault.DefaultParams())
}

// run is Run with the Argon2id costs new keys are sealed with: the real ones
// in production, small ones in tests, which seal and unseal a key many times.
func run(ctx context.Context, cfg config.Config, migrations fs.FS, logger *slog.Logger, kdf vault.Params) error {
	// What is on disk decides the state before anything listens: nothing - a
	// first password; a database with its key - locked; one without the other
	// - no start at all, rather than a new database beside a lost one.
	state, err := detectLock(cfg.DBPath, cfg.KeyPath())
	if err != nil {
		return err
	}
	if cfg.StatusAddr == "" {
		return errors.New("the service page is off (-status-addr is empty), and the password that opens this " +
			"server's data is entered there or with noxd unlock through it")
	}

	// The service page gets its OWN listener, on loopback, and the main one
	// never serves it. That is the whole protection: a check on RemoteAddr
	// inside a handler is a check somebody eventually routes around with a
	// header, and the main server is ordinarily bound to every interface -
	// otherwise no phone could reach it.
	//
	// It stays PLAIN HTTP while the main listener is TLS, and that is a
	// decision rather than an oversight: the socket carries no network traffic
	// by construction, so there is nothing in transit to protect, and a
	// certificate there would only teach an operator's browser to expect a
	// warning - on the one page whose whole job is to hand out the right to
	// own this machine.
	//
	// And it comes up FIRST, before the data is open, because the password is
	// entered on it (047). A port somebody else holds is therefore a server
	// that cannot start, where it used to be a page skipped: nothing else can
	// unlock it.
	statusListener, err := net.Listen("tcp", cfg.StatusAddr)
	if err != nil {
		return fmt.Errorf("service page on %s - the password is entered there, so the server cannot start without it: %w",
			cfg.StatusAddr, err)
	}
	if err := assertLoopback(statusListener); err != nil {
		// The config check catches the mistake when it is made; this is the
		// guarantee. A name can resolve to loopback at parse time and
		// somewhere else at bind time, and the difference between those two
		// moments is a machine link on a network.
		_ = statusListener.Close()
		return err
	}
	g := newGate(cfg, state, kdf, logger)
	page := startPage(statusListener, g.handler(), logger)
	// On every way out. The open server stops it itself, earlier, in the
	// order invariant 9 sets; this is for the ways out before that.
	defer func() { _ = page.stop() }()

	// Printed, or nobody learns it exists: the password goes in there, and
	// later the link for a new device comes out of it. The scheme is stated on
	// purpose: the main listener is TLS, and an operator who assumes the page
	// followed it gets a browser error instead of a password field.
	pageURL := "http://" + page.addr
	if state == stateSetup {
		logger.Info("no password is set yet - set one on the service page, or with noxd unlock; "+
			"devices cannot reach this server until then", "url", pageURL, "tls", false)
	} else {
		logger.Info("this server is locked - enter its password on the service page, or with noxd unlock; "+
			"devices cannot reach it until then", "url", pageURL, "tls", false)
	}

	key, opener, ok := g.awaitKey(ctx)
	if !ok {
		logger.Info("stopped while locked")
		return nil
	}
	err = serve(ctx, cfg, migrations, logger, key, g, page, opener)
	if err != nil && g.current() != stateOpen {
		// The password was right and the data still did not open: whoever
		// typed it hears so, and the process goes down with the reason in the
		// log - the same as a database that failed to open always did.
		opener.answer(codeInternal, "the password is right, but the server could not open its data - see its log")
	}
	return err
}

// serve opens the data with key and runs the server until ctx ends: what Run
// did before 047, from the database on. The request that brought the key is
// answered once the main port listens.
func serve(ctx context.Context, cfg config.Config, migrations fs.FS, logger *slog.Logger, key []byte, g *gate,
	page *servicePage, opener gateRequest) error {
	opened := time.Now()
	dbs, err := db.Open(cfg.DBPath, key)
	if err != nil {
		return fmt.Errorf("open database: %w", err)
	}
	defer func() { _ = dbs.Close() }()
	// Registered after the database's close, so it runs before it: whatever
	// way serve ends, the page stops before the database it reads closes
	// (invariant 9).
	defer func() { _ = page.stop() }()

	version, err := db.Migrate(ctx, dbs.Write, migrations)
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	// The runner skips migrations it has already applied, so an edited
	// 001_init.sql never reaches a database that predates this feature (the
	// pre-release rule edits it in place). Without this assertion the mismatch
	// would degrade into an internal error on every greeting - a silent
	// failure where a loud one is needed.
	if err := assertIdentitySchema(ctx, dbs.Read, migrations, cfg.DBPath); err != nil {
		return err
	}
	logger.Info("database ready", "path", cfg.DBPath, "schema_version", version)

	bl, err := blob.Open(cfg.FilesPath, key)
	if err != nil {
		return fmt.Errorf("open files dir: %w", err)
	}
	defer func() { _ = bl.Close() }()

	h := hub.New()
	st := store.New(dbs.Read, dbs.Write)
	// The machine's own identity is settled BEFORE the journal is touched.
	//
	// EnsureServerIdentity refuses to mint a key for a store that already holds
	// people - a partial restore - and that refusal has to happen while nothing
	// destructive has run yet. EnsureJournal MINTS A NEW JOURNAL ID on a store
	// that has none, and a changed journal id is what makes every paired device
	// wipe its chats, messages, cursor and read marks. Running it first meant an
	// aborted startup still destroyed every client's local world, silently and
	// before the error that stopped it was even printed.
	machine, err := st.EnsureServerIdentity(ctx)
	if err != nil {
		return fmt.Errorf("ensure server identity: %w", err)
	}
	if err := st.EnsureJournal(ctx); err != nil {
		return fmt.Errorf("ensure journal: %w", err)
	}
	// The machine's private key, read once: the channel listener proves it on
	// every connection, and nothing else ever asks for it.
	serverKey, err := st.ServerKey(ctx)
	if err != nil {
		return fmt.Errorf("read the server key: %w", err)
	}
	// The address parameters land before any listener opens, so the first
	// greeting and the first link already name them (045, FR-003). A malformed
	// one is a warning, never a reason to stay down.
	addrWarnings, err := applyAddressParams(ctx, st, cfg, logger)
	if err != nil {
		return err
	}
	if err := sayHowToPair(ctx, st, cfg, logger); err != nil {
		return err
	}
	srv := New(cfg, st, h, bl, logger)
	srv.schemaVersion = version
	srv.addrWarnings = addrWarnings
	srv.dataKey = key
	// One form token for the life of the process: a form the lock page
	// rendered is still the page's own once the server has opened.
	srv.formToken = g.formToken

	// Startup sweep before endpoints open (research R10): abandoned uploads
	// older than a day are the only garbage under indefinite retention.
	if err := srv.sweepOrphans(ctx, time.Now().Add(-24*time.Hour).Unix()); err != nil {
		return fmt.Errorf("sweep orphans: %w", err)
	}

	// The TLS side of the channel, built here, once, around a throwaway key.
	// There is no flag to serve without it, and none to serve without the check
	// after it: a channel that can be asked to downgrade is a channel somebody
	// downgrades.
	tlsConfig, err := channelTLSConfig(time.Now())
	if err != nil {
		return err
	}
	// The HTTP server does no TLS of its own: its listener hands it connections
	// that already passed both layers (channel.go), each carrying the device
	// key it proved. HTTP/2 cannot happen - the only TLS here offers
	// http/1.1, and nothing serves h2 in the clear.
	//
	// ONE port for every path (045): tor runs as a separate service and
	// forwards the onion service here, so a connection through Tor arrives
	// like one from the next room and is held to the same rules - and to the
	// same slow-path timeouts.
	httpServer := &http.Server{
		Handler:           srv.Handler(),
		ReadHeaderTimeout: readHeaderTimeout,
		ConnContext:       withChannelPeer,
	}
	httpServer.RegisterOnShutdown(srv.CloseConnections)

	// The first address snapshot is taken before any listener opens, so the
	// very first greeting already carries a list (contract §3: `direct` is
	// always there).
	srv.refreshAddresses(ctx)

	// The main port opens only now (047): until the data is open there is
	// nothing a device could be served, and a port that answers nothing would
	// still say a server is there. Bound here rather than in its goroutine, so
	// a port somebody else holds is said to the person who just unlocked.
	raw, err := net.Listen("tcp", cfg.Addr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", cfg.Addr, err)
	}
	// The machine's PUBLIC key, which is what an operator compares with the
	// one in a link; the private half and every token stay out of this line.
	logger.Info("listening", "addr", cfg.Addr, "tls", "1.3",
		"server_key", base64.StdEncoding.EncodeToString(machine.PublicKey))
	g.opened(srv)
	opener.answer("", "")
	logger.Info("server unlocked", "took_ms", time.Since(opened).Milliseconds())

	hubCtx, stopHub := context.WithCancel(context.Background())
	defer stopHub()
	// The watcher gets a context of its OWN, like the hub: it sends to the
	// connections that are still being told goodbye, and it reads the
	// database, so it stops after the drain and before the database closes
	// (invariant 9) rather than the moment shutdown begins. The request sweeper
	// (046) does both as well, and stops beside it - and so does the gate's
	// keeper (047), which may be writing a backup out of the database.
	watchCtx, stopWatch := context.WithCancel(context.Background())
	defer stopWatch()
	sweepCtx, stopSweep := context.WithCancel(context.Background())
	defer stopSweep()
	keepCtx, stopKeeper := context.WithCancel(context.Background())
	defer stopKeeper()

	eg, gctx := errgroup.WithContext(ctx)
	eg.Go(func() error {
		h.Run(hubCtx)
		return nil
	})
	eg.Go(func() error {
		return srv.runDispatcher(gctx)
	})
	eg.Go(func() error {
		srv.runAddressWatcher(watchCtx)
		return nil
	})
	eg.Go(func() error {
		srv.runRequestSweeper(sweepCtx)
		return nil
	})
	eg.Go(func() error {
		g.serveOpen(keepCtx)
		return nil
	})
	eg.Go(func() error {
		channel := srv.newChannelListener(raw, tlsConfig, serverKey, srv.channelTimeout)
		if err := httpServer.Serve(channel); !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("listen on %s: %w", cfg.Addr, err)
		}
		return nil
	})
	eg.Go(func() error {
		<-gctx.Done()
		shCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		err := httpServer.Shutdown(shCtx)
		cancel()
		// Down with the main one and BEFORE the database closes: a request
		// arriving mid-shutdown would otherwise read a store being closed
		// underneath it (invariant 9). The page ends every request's context
		// first, so a backup being written stops rather than outliving the
		// database; and it waits on its OWN deadline, not the leftovers of the
		// main one - sharing an expired context closes the listener and
		// returns immediately, leaving a page request in flight to race the
		// database close, the exact thing the ordering is for.
		if pageErr := page.stop(); pageErr != nil && err == nil {
			err = pageErr
		}
		// Shutdown ignores hijacked connections; wait for their handlers so
		// the going-away close frames flush and nothing touches the store
		// after the database closes (invariant 9). Its own budget: a close
		// handshake through Tor alone can take ten seconds.
		drainCtx, cancelDrain := context.WithTimeout(context.Background(), drainTimeout)
		if waitErr := srv.WaitConnections(drainCtx); waitErr != nil {
			logger.Warn("connections still draining at shutdown deadline", "err", waitErr)
		}
		cancelDrain()
		// Then the keeper, the watcher, the request sweeper and the hub; serve
		// returns - the errgroup waits for all of them before the database
		// closes.
		stopKeeper()
		stopWatch()
		stopSweep()
		stopHub()
		if err != nil {
			return fmt.Errorf("shutdown: %w", err)
		}
		return nil
	})
	return eg.Wait()
}

// assertIdentitySchema refuses to start on a database written before the
// pairing tables existed. See the call site for why the migration runner
// cannot repair such a database on its own.
//
// It names every table the current 001 creates that a pre-release database may
// be missing: a guard that checks only some of them starts happily and then
// fails deeper in with an error nobody can act on.
//
// Tables are not enough on their own. Editing 001 in place also ADDS COLUMNS to
// tables that already exist, and a missing column sails past a table check to
// die later as a raw "no such column" - the exact unactionable error this guard
// exists to replace.
//
// So the check is a FINGERPRINT, not a list. A hand-maintained catalogue of
// columns only covers what somebody remembered to add to it, and its own
// comment said as much; the hash of the migration text covers every column,
// index, CHECK and rename that any later phase writes, and cannot be forgotten.
//
// A zero stored fingerprint means a database from before this existed, which is
// by definition older than the current schema.
func assertIdentitySchema(ctx context.Context, read *sql.DB, migrations fs.FS, dbPath string) error {
	var present int
	err := read.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM sqlite_master WHERE type = 'table' AND name IN "+
			"('users', 'devices', 'journal', 'server_identity', 'pair_tokens', 'pair_requests')").Scan(&present)
	if err != nil {
		return fmt.Errorf("inspect schema: %w", err)
	}
	if present != 6 {
		return staleSchemaError(dbPath)
	}
	want, err := db.Fingerprint(migrations)
	if err != nil {
		return err
	}
	stored, err := db.ReadFingerprint(ctx, read)
	if err != nil {
		return err
	}
	if stored != want {
		return staleSchemaError(dbPath)
	}
	return nil
}

func staleSchemaError(dbPath string) error {
	return fmt.Errorf(
		"database schema predates this build: the pre-release rule edits 001_init.sql in place, "+
			"so delete %s together with its -wal and -shm siblings and the %s-files directory, then start again",
		dbPath, dbPath)
}

// sayHowToPair tells the operator, when no device can reach this machine, where
// a link for one is - and never the link itself (046, FR-005).
//
// The log is the one place a pairing link must not go: it is kept, copied,
// shipped to collectors and read by whoever reads logs, while the link is a way
// in for ten minutes. The service page and `noxd link` hand it out on this
// machine instead, and both are named here. The page always listens: since 047
// a server cannot start without it, because its password is entered there.
func sayHowToPair(ctx context.Context, st *store.Store, cfg config.Config, logger *slog.Logger) error {
	counts, err := st.CountEverything(ctx)
	if err != nil {
		return fmt.Errorf("count devices: %w", err)
	}
	if counts.Devices > 0 {
		return nil
	}
	logger.Info("no device can reach this server yet - the service page shows a link to pair one, and `noxd link` prints it",
		"page", "http://"+cfg.StatusAddr)
	return nil
}

// assertLoopback refuses a service-page listener that ended up anywhere else.
//
// Checked on the socket rather than on the string, because the string is what
// somebody typed and the socket is what happened. A hostname resolving one way
// at parse time and another at bind time is the whole gap this closes.
func assertLoopback(ln net.Listener) error {
	tcp, ok := ln.Addr().(*net.TCPAddr)
	if !ok {
		return fmt.Errorf("service page listener is not TCP: %s", ln.Addr())
	}
	if !tcp.IP.IsLoopback() {
		return fmt.Errorf("service page bound to %s, which is not loopback", tcp.IP)
	}
	return nil
}

// Package server wires the HTTP surface (contract §1) and the WebSocket
// command channel (contract §2-§6) over the store and the hub, and owns the
// process lifecycle including the ordered shutdown of CLAUDE.md invariant 9.
package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"golang.org/x/sync/errgroup"

	"nox.app/client-backend/internal/blob"
	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

const (
	defaultPingInterval = 25 * time.Second
	defaultWriteTimeout = 5 * time.Second
	shutdownTimeout     = 5 * time.Second
	readHeaderTimeout   = 5 * time.Second
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

	pingInterval time.Duration
	writeTimeout time.Duration
	// What the service page shows about the process itself. Set once at
	// startup: the schema version the migrator reported, the moment this
	// process began. A person who closed that terminal has no other way to it.
	schemaVersion int
	startedAt     time.Time

	// claim guards the one claim link this process ever hands out.
	claim      sync.Mutex
	claimToken string

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
		cfg:          cfg,
		store:        st,
		hub:          h,
		blob:         bl,
		tokens:       newTokenStore(),
		logger:       logger,
		pingInterval: defaultPingInterval,
		writeTimeout: defaultWriteTimeout,
		startedAt:    time.Now(),
		kick:         make(chan struct{}, 1),
		conns:        make(map[*client]struct{}),
	}
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

// Handler returns the full HTTP surface of stage 1.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /ws", s.handleWS)
	mux.HandleFunc("PUT /files/{token}", s.handlePutFile)
	mux.HandleFunc("GET /files/{token}", s.handleGetFile)
	return s.logRequests(mux)
}

// CloseConnections force-closes every live WebSocket with the going-away
// status. Wire it via http.Server.RegisterOnShutdown: Shutdown itself never
// waits for hijacked connections.
func (s *Server) CloseConnections() {
	s.mu.Lock()
	clients := make([]*client, 0, len(s.conns))
	for c := range s.conns {
		clients = append(clients, c)
	}
	s.mu.Unlock()
	for _, c := range clients {
		c.close(websocket.StatusGoingAway, "server shutting down")
	}
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
// been added, so an open device list refreshes itself instead of showing a
// stale one until somebody leaves the screen and comes back.
//
// Shaped after refreshLabel and NOT after dropDevice: the two answer different
// questions. dropDevice looks for the connections holding ONE KEY and closes
// them; this needs every connection of ONE PERSON, left running. Only the frame
// shape is shared with the revocation.
//
// Collected under s.mu and sent outside it, for refreshLabel's reason:
// sendFrame writes to a bounded queue, and a full one under the registry lock
// would hold up every other connection of every other person.
//
// origin never matches today, and the parameter is still not dead. The
// connection that just paired has NOT greeted - handlePair refuses an
// already-greeted one - so its identity.UserID is empty and it falls outside
// the filter by itself. The exclusion states the intent, and is the safety net
// for the day `pair` learns to run on a greeted connection.
//
// Inherited with the shape: a connection in the MIDDLE of greeting also has an
// empty identity.UserID, because the greeting reads the person from the store
// and writes it to the connection a few lines later. Such a connection misses
// this event - and reads the list when its screen opens, which is where every
// device that was offline ends up anyway. It is the same window the rename
// carries (see client_backend/CLAUDE.md), and it closes here when it closes
// there.
func (s *Server) announcePaired(userID string, origin *client) {
	s.mu.Lock()
	notify := make([]*client, 0, 1)
	for c := range s.conns {
		if c.identity.UserID == userID && c != origin {
			notify = append(notify, c)
		}
	}
	s.mu.Unlock()

	if len(notify) == 0 {
		return
	}
	// Empty on purpose (contract §8A): the event says the set of devices
	// changed, not how, and the receiver re-reads device.list. A device key here
	// would be a public key on a frame nobody reads it from, and a spent token
	// would be a credential.
	for _, c := range notify {
		c.sendFrame(protocol.Event{Seq: 0, Event: protocol.EventDevicePaired, Data: json.RawMessage(`{}`)})
	}
}

// setDeviceKey records which key a connection authenticated with, under the
// same lock dropDevice reads it through.
func (s *Server) setDeviceKey(c *client, key string) {
	s.mu.Lock()
	c.deviceKey = key
	s.mu.Unlock()
}

// setIdentity records who a connection speaks as, under the same lock the
// other goroutines touch it through.
//
// A connection joins s.conns when it is accepted, long before it greets, so
// refreshLabel and the two notify helpers walk it while this write is still to
// come. Writing it bare made the greeting race every one of them - and the pair
// sweeper turned that from a rename-only window into something a tick hits
// every ten seconds.
func (s *Server) setIdentity(c *client, id store.Identity) {
	s.mu.Lock()
	c.identity = id
	s.mu.Unlock()
}

// currentIdentity reads back the person this connection speaks as.
//
// Needed only where the LABEL is consumed: refreshLabel rewrites it from
// another goroutine, while user_id and the ownership flag are written once by
// the read goroutine itself and never change. The name matters because it is
// frozen into message history at send time.
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

// Run owns the whole process: opens the database, migrates, starts the hub
// and the HTTP server, and shuts everything down in order on ctx
// cancellation. It returns when the process is fully stopped.
func Run(ctx context.Context, cfg config.Config, migrations fs.FS, logger *slog.Logger) error {
	dbs, err := db.Open(cfg.DBPath)
	if err != nil {
		return fmt.Errorf("open database: %w", err)
	}
	defer func() { _ = dbs.Close() }()

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

	bl, err := blob.Open(cfg.FilesPath)
	if err != nil {
		return fmt.Errorf("open files dir: %w", err)
	}
	defer func() { _ = bl.Close() }()

	h := hub.New()
	st := store.New(dbs.Read, dbs.Write)
	// One read, one snapshot. The warning and the decision about printing a
	// claim link are the same fact, and asking for it twice is how the two
	// start disagreeing - an operator getting a link with no warning, or a
	// warning with no link.
	ownership, err := st.ReadOwnershipState(ctx)
	if err != nil {
		return fmt.Errorf("read ownership state: %w", err)
	}
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
	claimToken, err := announceClaim(ctx, st, cfg.Addr, ownership, machine, logger)
	if err != nil {
		return err
	}
	srv := New(cfg, st, h, bl, logger)
	srv.schemaVersion = version
	// The page hands out the SAME right the terminal just printed. A second
	// token would be a second unrevocable door, and the claim token has no
	// expiry to close it.
	srv.seedClaimToken(claimToken)

	// Startup sweep before endpoints open (research R10): abandoned uploads
	// older than a day are the only garbage under indefinite retention.
	if err := srv.sweepOrphans(ctx, time.Now().Add(-24*time.Hour).Unix()); err != nil {
		return fmt.Errorf("sweep orphans: %w", err)
	}

	httpServer := &http.Server{Addr: cfg.Addr, Handler: srv.Handler(), ReadHeaderTimeout: readHeaderTimeout}
	httpServer.RegisterOnShutdown(srv.CloseConnections)

	// The service page gets its OWN listener, on loopback, and the main one
	// never serves it. That is the whole protection: a check on RemoteAddr
	// inside a handler is a check somebody eventually routes around with a
	// header, and the main server is ordinarily bound to every interface -
	// otherwise no phone could reach it. An empty address removes the listener
	// rather than the handler, so the port is not even held.
	var statusServer *http.Server
	var statusListener net.Listener
	if cfg.StatusAddr != "" {
		// Its OWN error variable. Assigning to the function's would leave it
		// non-nil on the "logged it and carried on" path, and the next `if err
		// != nil` anybody adds below would turn a busy port back into a server
		// that refuses to start.
		listener, listenErr := net.Listen("tcp", cfg.StatusAddr)
		statusListener = listener
		if listenErr != nil {
			logger.Error("service page unavailable, continuing without it", "addr", cfg.StatusAddr, "err", listenErr)
		} else if err := assertLoopback(statusListener); err != nil {
			// The config check catches the mistake when it is made; this is the
			// guarantee. A name can resolve to loopback at parse time and
			// somewhere else at bind time, and the difference between those two
			// moments is a claim link on a network.
			_ = statusListener.Close()
			statusListener = nil
			return err
		}
		if statusListener != nil {
			statusServer = &http.Server{Handler: srv.StatusHandler(), ReadHeaderTimeout: readHeaderTimeout}
		}
	}

	hubCtx, stopHub := context.WithCancel(context.Background())
	defer stopHub()

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		h.Run(hubCtx)
		return nil
	})
	g.Go(func() error {
		return srv.runDispatcher(gctx)
	})
	g.Go(func() error {
		logger.Info("listening", "addr", cfg.Addr)
		if err := httpServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("listen on %s: %w", cfg.Addr, err)
		}
		return nil
	})
	if statusServer != nil {
		g.Go(func() error {
			// Printed, or nobody learns it exists. Next to the claim link,
			// because the two are read at the same moment.
			logger.Info("service page for this machine only", "url", "http://"+statusListener.Addr().String())
			if err := statusServer.Serve(statusListener); !errors.Is(err, http.ErrServerClosed) {
				// Logged, NOT returned. Returning it cancels the group and
				// takes the whole messenger down: a port somebody else already
				// holds - 8081 is not rare, and a second noxd with its own -db
				// would collide by default - would stop people talking to each
				// other over a page nobody had opened yet.
				logger.Error("service page unavailable, continuing without it", "addr", cfg.StatusAddr, "err", err)
			}
			return nil
		})
	}
	g.Go(func() error {
		<-gctx.Done()
		shCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		err := httpServer.Shutdown(shCtx)
		if statusServer != nil {
			// Down with the main one and BEFORE the database closes: a request
			// arriving mid-shutdown would otherwise read a store being closed
			// underneath it (invariant 9).
			//
			// Its OWN deadline, not the leftovers of the main one: sharing an
			// expired context closes the listener and returns immediately,
			// leaving a page request in flight to race the database close -
			// the exact thing the ordering is for.
			statusCtx, cancelStatus := context.WithTimeout(context.Background(), shutdownTimeout)
			statusErr := statusServer.Shutdown(statusCtx)
			cancelStatus()
			if statusErr != nil && err == nil {
				err = statusErr
			}
		}
		// Shutdown ignores hijacked connections; wait for their handlers so
		// the going-away close frames flush and nothing touches the store
		// after the database closes (invariant 9).
		if waitErr := srv.WaitConnections(shCtx); waitErr != nil {
			logger.Warn("connections still draining at shutdown deadline", "err", waitErr)
		}
		stopHub()
		if err != nil {
			return fmt.Errorf("shutdown: %w", err)
		}
		return nil
	})
	return g.Wait()
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
			"('users', 'devices', 'journal', 'server_identity', 'pair_tokens')").Scan(&present)
	if err != nil {
		return fmt.Errorf("inspect schema: %w", err)
	}
	if present != 5 {
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

// announceClaim mints the server's own key on first start and, while nobody
// owns this server yet, prints the pairing link.
//
// The link goes to the log, and since 035 to the service page as well - which
// is why that page binds to loopback and refuses to start anywhere else. What
// the pre-035 rule guarded against (a page serving the QR to everyone on the
// network while the transport is not TLS) is answered by the bind, checked on
// the socket rather than on the address somebody typed. It is reprinted on
// every start until somebody claims the server, because a terminal scrolls and
// an unclaimed server has to stay claimable.
//
// This is a place a token is deliberately written to output. It is the claim
// mechanism itself, and it is only visible to whoever can already read
// the machine's logs - which is whoever could take the database anyway.
func announceClaim(
	ctx context.Context,
	st *store.Store,
	addr string,
	ownership store.OwnershipState,
	machine store.ServerIdentity,
	logger *slog.Logger,
) (string, error) {
	// Silent while a device can still reach this server. Not "while an owner is
	// recorded": a store that lost its ownership marker still has a person who
	// can get in, and printing a claim link there offers their machine to
	// whoever reads the log.
	//
	// The answer comes from the snapshot startup already took: re-deriving it
	// here would evaluate the same rule twice against a store another
	// connection could have changed in between.
	if ownership.OwnerCanGetIn {
		return "", nil
	}
	token, err := st.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		return "", fmt.Errorf("issue claim token: %w", err)
	}
	link, err := BuildPairingLink(listenAddress(addr), machine.PublicKey, token)
	if err != nil {
		return "", fmt.Errorf("build pairing link: %w", err)
	}
	// Three situations, and saying the wrong one tells the operator the wrong
	// story about what is about to happen. The machine may never have been
	// claimed; its owner may have run out of devices; or the ownership marker
	// may be missing from a store that still holds a person and their whole
	// conversation - in which case presenting this link signs the device in AS
	// that person rather than making it the owner of an empty machine.
	switch {
	case ownership.Owned:
		logger.Info("this server has an owner but no devices left - present this link in the app to get back in", "link", link)
	case ownership.HasPerson:
		logger.Info("this server holds a conversation but records no owner - present this link to sign in as the person it belongs to", "link", link)
	default:
		logger.Info("this server has no owner yet - present this link in the app to claim it", "link", link)
	}
	return token, nil
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

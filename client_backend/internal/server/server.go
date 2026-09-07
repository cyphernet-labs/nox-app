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

	// pairSweepInterval is how often waiting person invites are checked
	// against their deadline. Ten seconds against a five-minute window is 3%
	// of slack, and it errs towards waiting slightly longer - which is the
	// harmless direction. A shorter tick buys nothing; a longer one makes the
	// gap between "time is up" and "the screen says so" visible.
	pairSweepInterval = 10 * time.Second
)

// pairRequestedPayload is the body of person.pairRequested (contract §8B).
// Nothing about the invitee: before joining, the server knows nothing about
// them, and the platform their unauthenticated device claimed is not a fact.
type pairRequestedPayload struct {
	RequestID string `json:"request_id"`
	InvitedAt int64  `json:"invited_at"`
	ExpiresAt int64  `json:"expires_at"`
}

// pairResolvedPayload is the body of person.pairResolved (contract §8B).
// Identity rides along only when the answer was yes.
type pairResolvedPayload struct {
	RequestID string    `json:"request_id"`
	Outcome   string    `json:"outcome"`
	Identity  *identity `json:"identity,omitempty"`
}

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
	// pairSweep is how often waiting person invites are checked against their
	// deadline, and now is the clock the check reads. Both are fields for the
	// same reason pingInterval is one and tokenStore.now is: a test cannot sit
	// through a five-minute window to watch it close.
	pairSweep time.Duration
	now       func() int64

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
		pairSweep:    pairSweepInterval,
		now:          func() int64 { return time.Now().Unix() },
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
			c.label = label
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

// markPendingRequest records which person invite this connection is waiting on,
// or clears the mark when the wait is over. Under the same lock
// notifyPairResolved reads it through.
func (s *Server) markPendingRequest(c *client, requestID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c.pendingRequestID = requestID
}

// notifyPairRequested asks every live device of the owner to decide about one
// waiting invite.
//
// Every device, not just one: the owner may be holding any of them, and a
// question shown on the wrong screen is a question nobody answers. The frame
// carries nothing about who is knocking, because before joining there is
// nothing the server knows about them.
func (s *Server) notifyPairRequested(owner string, req store.PendingRequest) {
	s.sendToOwnerDevices(owner, pairRequestedFrame(req))
}

// pairRequestedFrame builds the question. One builder for both deliveries - the
// push when a link is presented and the re-send after a greeting - so the two
// cannot come to disagree about what a question looks like.
func pairRequestedFrame(req store.PendingRequest) protocol.Event {
	data, err := json.Marshal(pairRequestedPayload{RequestID: req.RequestID, InvitedAt: req.InvitedAt, ExpiresAt: req.ExpiresAt})
	if err != nil {
		// Cannot fail for a struct of a string and two ints. An empty body is
		// still a frame the receiver will ignore, which beats a nil Data.
		data = json.RawMessage(`{}`)
	}
	return protocol.Event{Seq: 0, Event: protocol.EventPairRequested, Data: data}
}

// notifyPairResolved tells the waiting device what was decided, and the owner's
// devices that the question is closed.
//
// Both, not one: the person at the door needs the outcome, and every other
// device of the owner needs the question to leave its screen rather than only
// the one that answered it.
func (s *Server) notifyPairResolved(owner, requestID, outcome string, id store.Identity) {
	payload := pairResolvedPayload{RequestID: requestID, Outcome: outcome}
	if outcome == store.OutcomeApproved {
		payload.Identity = &identity{
			greetingIdentity: greetingIdentity{ID: id.UserID, Label: id.Label, Owner: id.Owner},
			Created:          id.Created,
		}
	}
	data, err := json.Marshal(payload)
	if err != nil {
		s.logger.Error("marshal pair outcome", "err", err)
		return
	}
	event := protocol.Event{Seq: 0, Event: protocol.EventPairResolved, Data: data}

	s.mu.Lock()
	waiting := make([]*client, 0, 1)
	for c := range s.conns {
		if c.pendingRequestID == requestID {
			c.pendingRequestID = ""
			waiting = append(waiting, c)
		}
	}
	s.mu.Unlock()
	// Outside the lock: sendFrame writes to a bounded queue, and a full one
	// under s.mu would hold up every other connection of every other person.
	for _, c := range waiting {
		c.sendFrame(event)
	}
	s.sendToOwnerDevices(owner, event)
}

// sendToOwnerDevices delivers a frame to every live connection of one person.
func (s *Server) sendToOwnerDevices(owner string, event protocol.Event) {
	if owner == "" {
		return
	}
	s.mu.Lock()
	targets := make([]*client, 0, 2)
	for c := range s.conns {
		if c.identity.UserID == owner {
			targets = append(targets, c)
		}
	}
	s.mu.Unlock()
	for _, c := range targets {
		c.sendFrame(event)
	}
}

// runPairSweeper settles person invites whose owner never answered.
//
// A ticker over the STORE rather than a timer per request: a timer lives in
// this process and a waiting request lives in the database, so a request that
// outlived a restart would never expire at all. Lazily expiring on the next
// touch is not enough either - the owner's devices would keep showing a
// question that is already dead, and nobody would ever touch it again.
func (s *Server) runPairSweeper(ctx context.Context) error {
	ticker := time.NewTicker(s.pairSweep)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
		// The owner is read FIRST, and a failure skips the tick entirely.
		// Expiring writes the outcome, which takes the row out of both the
		// sweeper's predicate and the greeting re-send - so a batch marked
		// without anybody to tell would leave the question on the owner's
		// screen with nothing left that could ever close it.
		//
		// One read for the batch: the owner is a property of the machine, not
		// of a request, and it cannot change while one is waiting.
		owner, err := s.store.OwnerUserID(ctx)
		if err != nil {
			s.logger.Error("read owner for expired pairs", "err", err)
			continue
		}
		expired, err := s.store.ExpirePendingPairs(ctx, s.now())
		if err != nil {
			// Transient: the next tick tries again, and pendingOutcome settles
			// the same request if the device asks first.
			s.logger.Error("expire pending pairs failed", "err", err)
			continue
		}
		if len(expired) == 0 {
			continue
		}
		for _, req := range expired {
			s.notifyPairResolved(owner, req.RequestID, store.OutcomeExpired, store.Identity{})
		}
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
	c.label = id.Label
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
	warnOwnerlessStore(ownership, logger)
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
	if err := announceClaim(ctx, st, cfg.Addr, ownership, machine, logger); err != nil {
		return err
	}
	srv := New(cfg, st, h, bl, logger)

	// Startup sweep before endpoints open (research R10): abandoned uploads
	// older than a day are the only garbage under indefinite retention.
	if err := srv.sweepOrphans(ctx, time.Now().Add(-24*time.Hour).Unix()); err != nil {
		return fmt.Errorf("sweep orphans: %w", err)
	}

	httpServer := &http.Server{Addr: cfg.Addr, Handler: srv.Handler(), ReadHeaderTimeout: readHeaderTimeout}
	httpServer.RegisterOnShutdown(srv.CloseConnections)

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
		return srv.runPairSweeper(gctx)
	})
	g.Go(func() error {
		logger.Info("listening", "addr", cfg.Addr)
		if err := httpServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("listen on %s: %w", cfg.Addr, err)
		}
		return nil
	})
	g.Go(func() error {
		<-gctx.Done()
		shCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		err := httpServer.Shutdown(shCtx)
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

// warnOwnerlessStore says out loud that this store has people but no owner.
//
// Unreachable by any code path: a person is created only by pairing, and the
// claim path records ownership in the same transaction. It takes a hand-edited
// database to get here. The server still STARTS - the conversation is intact
// and only owner-gated rules are affected, so refusing to boot would punish
// the operator harder than the anomaly does - but it must not pick an owner
// by row order, which is precisely the guess this feature exists to remove.
//
// No user id in the message (Principle I): the count is what an operator needs.
func warnOwnerlessStore(ownership store.OwnershipState, logger *slog.Logger) {
	if !ownership.Stranded {
		return
	}
	// Deliberately not "re-claim it": Pair refuses a claim in this state, so
	// that advice would be impossible to follow. The store needs a human -
	// restore a backup, or write the owner back by hand - and no claim link is
	// printed while it is like this.
	logger.Warn("this server holds people but records no owner: it cannot be claimed and no owner will be guessed - restore it from a backup or set the owner by hand",
		"people", ownership.People)
}

// announceClaim mints the server's own key on first start and, while nobody
// owns this server yet, prints the pairing link.
//
// The link goes to the log and nowhere else: a local HTTP page serving the QR
// would hand ownership to everyone on the network as long as the transport is
// not TLS. It is reprinted on every start until somebody claims the server,
// because a terminal scrolls and an unclaimed server has to stay claimable.
//
// This is the ONE place a token is deliberately written to output. It is the
// claim mechanism itself, and it is only visible to whoever can already read
// the machine's logs - which is whoever could take the database anyway.
func announceClaim(
	ctx context.Context,
	st *store.Store,
	addr string,
	ownership store.OwnershipState,
	machine store.ServerIdentity,
	logger *slog.Logger,
) error {
	// Silent while THE OWNER can still reach this server, and while the store is
	// stranded - Pair refuses a claim there, so a link would be an instruction
	// that cannot be followed, printed once per restart for ever.
	//
	// Both come from the snapshot startup already took: re-deriving them here
	// would evaluate the same rule twice against a store another connection
	// could have changed in between.
	if ownership.OwnerCanGetIn || ownership.Stranded {
		return nil
	}
	token, err := st.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		return fmt.Errorf("issue claim token: %w", err)
	}
	link, err := BuildPairingLink(listenAddress(addr), machine.PublicKey, token)
	if err != nil {
		return fmt.Errorf("build pairing link: %w", err)
	}
	// Two different situations, and until this feature they were indistinguishable:
	// nobody has ever claimed the machine, or its owner has no device left to get
	// back in with. Saying "no owner yet" in the second case is simply false, and
	// it tells the person the wrong story about what is about to happen.
	if ownership.Owned {
		logger.Info("this server has an owner but no devices left - present this link in the app to get back in", "link", link)
	} else {
		logger.Info("this server has no owner yet - present this link in the app to claim it", "link", link)
	}
	return nil
}

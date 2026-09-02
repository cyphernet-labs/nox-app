// Package server wires the HTTP surface (contract §1) and the WebSocket
// command channel (contract §2-§6) over the store and the hub, and owns the
// process lifecycle including the ordered shutdown of CLAUDE.md invariant 9.
package server

import (
	"context"
	"database/sql"
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
	if err := assertIdentitySchema(ctx, dbs.Read); err != nil {
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
	if err := st.EnsureJournal(ctx); err != nil {
		return fmt.Errorf("ensure journal: %w", err)
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
// identity tables existed. See the call site for why the migration runner
// cannot repair such a database on its own.
func assertIdentitySchema(ctx context.Context, read *sql.DB) error {
	var present int
	err := read.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM sqlite_master WHERE type = 'table' AND name IN ('users', 'devices', 'journal')").Scan(&present)
	if err != nil {
		return fmt.Errorf("inspect schema: %w", err)
	}
	if present != 3 {
		return fmt.Errorf(
			"database schema predates the identity tables: the pre-release rule edits 001_init.sql in place, "+
				"so delete the database file %s together with its -wal and -shm siblings and the files directory, then start again",
			"(-db path)")
	}
	return nil
}

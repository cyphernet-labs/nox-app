// Package server wires the HTTP surface (contract §1) and the WebSocket
// command channel (contract §2-§6) over the store and the hub, and owns the
// process lifecycle including the ordered shutdown of CLAUDE.md invariant 9.
package server

import (
	"container/list"
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
	// defaultIdleTimeout bounds how long a connection kept for its next HTTP
	// request may wait for it. Only a paired device's connection is kept - a
	// stranger's ends with its answer (limitStrangers) - but a device can be
	// revoked while its connection sits idle, and without a limit that
	// connection would stay for as long as its holder liked. Well above the
	// 15 s after which dart:io's client lets an idle connection go by default,
	// so the server never closes one the app still means to use.
	defaultIdleTimeout = 2 * time.Minute
	// defaultBodyTimeout bounds a request's body where nothing of ours reads
	// it (boundRequestBody): the slow path's budget, like the headers before
	// it.
	defaultBodyTimeout = slowPathTimeout
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
	// idleTimeout is the main port's http.Server.IdleTimeout. A field so tests
	// can scale it.
	idleTimeout time.Duration
	// bodyTimeout bounds a request's body where nothing of ours reads it
	// (boundRequestBody). A field so tests can scale it.
	bodyTimeout time.Duration
	// maxUnpaired and unpairedTimeout bound the /ws connections of keys
	// nobody paired (unpaired.go). Fields so tests can scale them.
	maxUnpaired     int
	unpairedTimeout time.Duration

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
	// formToken is what the service page's Set forms carry and POST
	// /addresses checks: 32 random bytes per process, hex. A page from another
	// site cannot read it, so it cannot forge the form even from this
	// machine's own browser.
	formToken string

	// claim guards the one claim link this process ever hands out.
	claim      sync.Mutex
	claimToken string

	// kick wakes the event dispatcher after a committed mutation; capacity 1
	// coalesces bursts (the dispatcher drains the log until it is current).
	kick chan struct{}

	// mu guards conns, transfers and unpaired; wg tracks connection handlers
	// so shutdown can wait for hijacked connections. Infrastructure-only
	// synchronization (ws-rest-patterns §5); business state stays
	// goroutine-owned.
	mu    sync.Mutex
	conns map[*client]struct{}
	// transfers holds the file transfers under way. Each runs on a connection
	// of its own since 044, which closing a device's socket does not touch, so
	// a revocation walks this set beside conns (dropDevice).
	transfers map[*transfer]struct{}
	// unpaired holds the connections in conns whose key no device row named
	// when they connected - strangers, who may only pair - oldest first
	// (unpaired.go). Under mu with conns: a newcomer's handler takes the
	// oldest out to make room, and each one's deadline, on a timer's
	// goroutine, takes it out if it is still there. unpairedCut and
	// unpairedWarned space the warning about the ones taken out to make room.
	unpaired       *list.List
	unpairedCut    int
	unpairedWarned time.Time
	wg             sync.WaitGroup
}

// transfer is one /files request under way: the device key its connection
// proved, and that connection.
type transfer struct {
	deviceKey string
	conn      *channelConn
}

// New builds a Server over an opened store, a running hub and a blob store.
// Its log goes through the scrubbing handler whatever logger it is handed
// (logscrub.go).
func New(cfg config.Config, st *store.Store, h *hub.Hub, bl *blob.Store, logger *slog.Logger) *Server {
	return &Server{
		cfg:              cfg,
		store:            st,
		hub:              h,
		blob:             bl,
		tokens:           newTokenStore(),
		logger:           scrubbedLogger(logger),
		writers:          newUploadWriters(),
		stallTimeout:     defaultStallTimeout,
		checkpointBytes:  defaultCheckpointBytes,
		preemptWait:      defaultPreemptWait,
		continuationWait: defaultContinuationWait,
		pingInterval:     defaultPingInterval,
		writeTimeout:     defaultWriteTimeout,
		channelTimeout:   defaultChannelTimeout,
		idleTimeout:      defaultIdleTimeout,
		bodyTimeout:      defaultBodyTimeout,
		maxUnpaired:      defaultMaxUnpaired,
		unpairedTimeout:  defaultUnpairedTimeout,
		addrKick:         make(chan struct{}, 1),
		addressPoll:      defaultAddressPoll,
		listIPs:          usableIPs,
		resolveHost:      resolveHost,
		startedAt:        time.Now(),
		formToken:        newFormToken(),
		kick:             make(chan struct{}, 1),
		conns:            make(map[*client]struct{}),
		transfers:        make(map[*transfer]struct{}),
		unpaired:         list.New(),
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
//
// Every request passes the door first (limitStrangers), unmatched ones
// included: the 404 and 405 the mux writes end a stranger's connection like
// any other answer.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /ws", s.handleWS)
	mux.HandleFunc("PUT /files/{token}", s.handlePutFile)
	mux.HandleFunc("GET /files/{token}", s.handleGetFile)
	return s.logRequests(s.limitStrangers(mux))
}

// configureMain sets what the main port's http.Server holds a connection to
// once it passed the channel: the connection - and the key it proved - in
// every request's context; the slow path's 30 s for a request's headers, since
// a connection from tor looks like any other (045), and bodyTimeout - the same
// 30 s - for a body nothing of ours reads (boundRequestBody); and idleTimeout
// between two requests. One place, so the test stack serves exactly what Run
// serves.
//
// "OPTIONS *" goes to the handler like any other request. Answered by net/http
// itself it would never reach the door, and a stranger could keep its
// connection by asking it again within each idle timeout.
func (s *Server) configureMain(hs *http.Server) {
	hs.ConnContext = withChannelPeer
	hs.ConnState = s.boundRequestBody
	hs.ReadHeaderTimeout = readHeaderTimeout
	hs.IdleTimeout = s.idleTimeout
	hs.DisableGeneralOptionsHandler = true
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

// dropDevice cuts off every live connection authenticated with a revoked key:
// its sockets, each told why before it closes, and its file transfers under
// way, cut without a word - a transfer has no frame to carry a reason on, and
// the socket carries it.
//
// Immediately, not on the device's next attempt: a sold tablet would otherwise
// keep reading the conversation for as long as it stays online, which is the
// whole thing revocation exists to stop. For a transfer that is no figure of
// speech: nothing but silence ends one (043), so a download already under way
// would go on for as long as the tablet kept reading it.
//
// The transfers go first. Cutting one only closes a socket and never waits,
// while telling a socket why can wait on that connection's full queue.
func (s *Server) dropDevice(deviceKey string) {
	s.mu.Lock()
	doomed := make([]*client, 0, 1)
	for c := range s.conns {
		if c.deviceKey == deviceKey {
			doomed = append(doomed, c)
		}
	}
	var cut []*channelConn
	for tr := range s.transfers {
		if tr.deviceKey == deviceKey {
			cut = append(cut, tr.conn)
		}
	}
	s.mu.Unlock()
	for _, conn := range cut {
		conn.cut()
	}
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
// would hold up every other connection on the server. (refreshLabel says "of
// every other person", which this server has not had since 037 - one machine,
// one person - but the lock is shared by every connection all the same.)
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
// The connection it came from is the RECEIVER, not a parameter, and that is
// deliberate: excluding the wrong one is then unrepresentable. refreshLabel
// takes an origin because its caller could legitimately pass a different one;
// this caller never can - and no test could catch it passing nil, because the
// pairing connection has no identity to match on in the ordinary case, so the
// mistake would look correct through every socket in the suite.
//
// The exclusion is live, not a statement of intent. It is easy to read
// the code as one - handlePair refuses an already-greeted connection, so the
// pairing device usually has no identity to match on - but "greeted" and "has
// an identity" are two different marks, and handleSessionHello sets the second
// several steps before the first: a greeting that fails on the journal id or
// the cursor leaves identity.UserID written and helloDone false, and dispatch
// still admits `pair` on that connection. Then it DOES match, and without this
// the device would be told about its own pairing.
//
// Inherited with the shape: a connection in the MIDDLE of greeting also has an
// empty identity.UserID, because the greeting reads the person from the store
// and writes it to the connection a few lines later. Such a connection misses
// this event - and reads the list when its screen opens, which is where every
// device that was offline ends up anyway. It is the same window the rename
// carries (see client_backend/CLAUDE.md), and it closes here when it closes
// there.
func (origin *client) announcePaired(userID string) {
	s := origin.srv
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

// untrack takes c out of the registry, and out of the unpaired connections if
// it was still one: a connection that is gone holds no place.
func (s *Server) untrack(c *client) {
	s.mu.Lock()
	delete(s.conns, c)
	s.forgetUnpairedLocked(c)
	s.mu.Unlock()
}

// trackTransfer registers a transfer under the device key its connection
// proved, until the returned func takes it out again.
func (s *Server) trackTransfer(deviceKey string, conn *channelConn) (untrack func()) {
	tr := &transfer{deviceKey: deviceKey, conn: conn}
	s.mu.Lock()
	s.transfers[tr] = struct{}{}
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		delete(s.transfers, tr)
		s.mu.Unlock()
	}
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
	// Every line of the process goes through the scrubbing handler, from the
	// first one on: the address parameters are applied below, before anything
	// listens (FR-022).
	logger = scrubbedLogger(logger)
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
	// The machine's private key, read once: the channel listener proves it on
	// every connection, and nothing else ever asks for it.
	serverKey, err := st.ServerKey(ctx)
	if err != nil {
		return fmt.Errorf("read the server key: %w", err)
	}
	// The address parameters land before anything is announced, so the claim
	// link the page shows already names them, and before any listener opens,
	// so the first greeting does too (045, FR-003). A malformed one is a
	// warning, never a reason to stay down.
	addrWarnings, err := applyAddressParams(ctx, st, cfg, logger)
	if err != nil {
		return err
	}
	stored, err := st.Addresses(ctx)
	if err != nil {
		return fmt.Errorf("read addresses: %w", err)
	}
	claimToken, err := announceClaim(ctx, st, cfg, ownership, machine, configured(stored), logger)
	if err != nil {
		return err
	}
	srv := New(cfg, st, h, bl, logger)
	srv.schemaVersion = version
	srv.addrWarnings = addrWarnings
	// The page hands out the token startup just minted. A second token would
	// be a second unrevocable door, and the claim token has no expiry to close
	// it.
	srv.seedClaimToken(claimToken)

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
		Handler: srv.Handler(),
		// net/http's own complaints - a handler's panic value above all - go
		// through the same handler as every other line, scrubbed, instead of
		// straight to stderr.
		ErrorLog: slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
	srv.configureMain(httpServer)
	httpServer.RegisterOnShutdown(srv.CloseConnections)

	// The first address snapshot is taken before any listener opens, so the
	// very first greeting already carries a list (contract §3: `direct` is
	// always there).
	srv.refreshAddresses(ctx)

	// The service page gets its OWN listener, on loopback, and the main one
	// never serves it. That is the whole protection: a check on RemoteAddr
	// inside a handler is a check somebody eventually routes around with a
	// header, and the main server is ordinarily bound to every interface -
	// otherwise no phone could reach it. An empty address removes the listener
	// rather than the handler, so the port is not even held.
	//
	// It stays PLAIN HTTP while the main listener is TLS, and that is a
	// decision rather than an oversight: the socket carries no network traffic
	// by construction, so there is nothing in transit to protect, and a
	// certificate there would only teach an operator's browser to expect a
	// warning - on the one page whose whole job is to hand out the right to
	// own this machine.
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
			return err
		}
		if statusListener != nil {
			statusServer = &http.Server{
				Handler:           srv.StatusHandler(),
				ReadHeaderTimeout: pageReadHeaderTimeout,
				ErrorLog:          slog.NewLogLogger(logger.Handler(), slog.LevelError),
			}
		}
	}

	hubCtx, stopHub := context.WithCancel(context.Background())
	defer stopHub()
	// The watcher gets a context of its OWN, like the hub: it sends to the
	// connections that are still being told goodbye, and it reads the
	// database, so it stops after the drain and before the database closes
	// (invariant 9) rather than the moment shutdown begins.
	watchCtx, stopWatch := context.WithCancel(context.Background())
	defer stopWatch()

	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		h.Run(hubCtx)
		return nil
	})
	g.Go(func() error {
		return srv.runDispatcher(gctx)
	})
	g.Go(func() error {
		srv.runAddressWatcher(watchCtx)
		return nil
	})
	g.Go(func() error {
		raw, err := net.Listen("tcp", cfg.Addr)
		if err != nil {
			return fmt.Errorf("listen on %s: %w", cfg.Addr, err)
		}
		// The machine's PUBLIC key, which is what an operator compares with the
		// one in a link; the private half and every token stay out of this line.
		logger.Info("listening", "addr", cfg.Addr, "tls", "1.3",
			"server_key", base64.StdEncoding.EncodeToString(machine.PublicKey))
		channel := srv.newChannelListener(raw, tlsConfig, serverKey, srv.channelTimeout)
		if err := httpServer.Serve(channel); !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("listen on %s: %w", cfg.Addr, err)
		}
		return nil
	})
	if statusServer != nil {
		g.Go(func() error {
			// Printed, or nobody learns it exists. Next to the claim link,
			// because the two are read at the same moment.
			// The scheme is stated on purpose: the main listener is https now,
			// and an operator who assumes the page followed it gets a browser
			// error instead of a claim link.
			logger.Info("service page for this machine only, plain HTTP by design",
				"url", "http://"+statusListener.Addr().String(), "tls", false)
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
		err := httpServer.Shutdown(shCtx)
		cancel()
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
		// after the database closes (invariant 9). Its own budget: a close
		// handshake through Tor alone can take ten seconds.
		drainCtx, cancelDrain := context.WithTimeout(context.Background(), drainTimeout)
		if waitErr := srv.WaitConnections(drainCtx); waitErr != nil {
			logger.Warn("connections still draining at shutdown deadline", "err", waitErr)
		}
		cancelDrain()
		// Then the watcher, and the hub; Run returns - the errgroup waits for
		// both before the database closes.
		stopWatch()
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

// announceClaim mints the claim token while nobody can get in, and says where
// the link that carries it is: on the service page of this machine.
//
// Where, and never the link itself (045, FR-022). The link carries the token -
// the right to own this machine, from anywhere now that a claim through Tor is
// a claim like any other - and, packed, the onion service's key; a log is
// copied to places neither may go. The page shows the link, which is why it
// binds to loopback and refuses to start anywhere else. The line is repeated
// on every start until somebody claims the server, because a terminal scrolls
// and an unclaimed server has to stay claimable.
//
// The link is still BUILT here, once: a bind address no link can carry stops
// the start, rather than surfacing later as a page with no link on it.
func announceClaim(
	ctx context.Context,
	st *store.Store,
	cfg config.Config,
	ownership store.OwnershipState,
	machine store.ServerIdentity,
	conf configuredAddresses,
	logger *slog.Logger,
) (string, error) {
	// Silent while a device can still reach this server, and no token is
	// minted: the page decides on the same predicate and shows no link. Not
	// "while an owner is recorded": a store that lost its ownership marker
	// still has a person who can get in, and a claim offered there offers
	// their machine to whoever opens the page.
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
	// The same addresses every link carries (045): the public one first when
	// it is set, the bind address, then the onion service when it is set - a
	// claim through Tor is a claim like any other.
	if _, _, err := buildLink(machine.PublicKey, token, listenAddress(cfg.Addr), conf); err != nil {
		return "", fmt.Errorf("build pairing link: %w", err)
	}
	// Three situations, and saying the wrong one tells the operator the wrong
	// story about what is about to happen. The machine may never have been
	// claimed; its owner may have run out of devices; or the ownership marker
	// may be missing from a store that still holds a person and their whole
	// conversation - in which case presenting the link signs the device in AS
	// that person rather than making it the owner of an empty machine.
	msg := "this server has no owner yet - present the link from the service page in the app to claim it"
	switch {
	case ownership.Owned:
		msg = "this server has an owner but no devices left - present the link from the service page in the app to get back in"
	case ownership.HasPerson:
		msg = "this server holds a conversation but records no owner - present the link from the service page to sign in as the person it belongs to"
	}
	if cfg.StatusAddr == "" {
		// Nothing shows the link, and the log will not: say what would.
		logger.Warn(msg, "service_page", "off - start the server with -status-addr to see the link")
		return token, nil
	}
	logger.Info(msg, "service_page", "http://"+cfg.StatusAddr)
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

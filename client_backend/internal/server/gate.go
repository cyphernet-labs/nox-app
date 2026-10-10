package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"sync"
	"sync/atomic"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/vault"
)

// The locked start (047). The server's data on disk is encrypted with a data
// key that only the owner's password unseals, and the password is stored
// nowhere - so after every start the server waits for it. Until it comes the
// main port is not even bound: a device dialling the server sees exactly what
// it sees when the server is off. Only the service page listens, and shows
// nothing but a password field.
//
// The gate is that waiting, and it stays after it: it owns the lock state and
// the key file for the life of the process. Every request that touches the
// key file - setting the first password, entering it, changing it - is served
// by ONE goroutine at a time, in the order they came: the goroutine of Run
// while the server is locked, the keeper after it opened. So two changes
// cannot both read the old file and both write a new one, and nothing about
// the key needs a lock.

// lockState is where the server stands between its start and its data being
// open.
type lockState int32

const (
	// stateSetup: neither a database nor a key file - the owner sets the
	// first password.
	stateSetup lockState = iota + 1
	// stateLocked: both are there and the password has not been entered.
	stateLocked
	// stateOpening: a password opened the key, and the data is being opened.
	stateOpening
	// stateOpen: the data is open and devices are served.
	stateOpen
)

// name is the state as the control surface says it (contracts/control-and-
// page.md). Opening is a second or two of locked, as far as anybody outside
// can tell.
func (s lockState) name() string {
	switch s {
	case stateSetup:
		return "setup"
	case stateOpen:
		return "open"
	default:
		return "locked"
	}
}

// The answers the page and the commands get, beside success
// (contracts/control-and-page.md). The first three are about the password; a
// request the state does not take is "state".
const (
	codeWrong    = "wrong"
	codeShort    = "short"
	codeMismatch = "mismatch"
	codeState    = "state"
	codeInternal = "internal"
)

type requestKind int

const (
	// reqSetup is the page's first password: only while there is nothing.
	reqSetup requestKind = iota + 1
	// reqUnlock is the page's password field: only while locked.
	reqUnlock
	// reqOpen is `noxd unlock`: a first password or the password, whichever
	// the state asks for.
	reqOpen
	// reqChange is a new password: only while open.
	reqChange
)

// gateRequest is one request for the goroutine serving the gate.
type gateRequest struct {
	kind     requestKind
	password string
	repeat   string
	current  string
	// ctx is the HTTP request's, handed over with it.
	ctx   context.Context //nolint:containedctx // one request's lifetime, handed over with it
	reply chan gateReply
}

// gateReply is the answer: an empty code is success.
type gateReply struct {
	code string
	// message is what to tell the person when the code alone does not say it
	// - an open that failed. Never a secret: the server's own words.
	message string
}

func (req gateRequest) answer(code, message string) {
	// Buffered by one, and answered once: never blocks on a handler gone.
	req.reply <- gateReply{code: code, message: message}
}

// gate is the server's lock and its key file, for the life of the process.
type gate struct {
	dbPath  string
	keyPath string
	kdf     vault.Params
	logger  *slog.Logger
	// formToken is what every form on the service page carries, whichever
	// state rendered it (see Server.formToken).
	formToken string

	state atomic.Int32
	// requests is served by one goroutine at a time; see the comment above.
	requests chan gateRequest
	// srv is the open server, once there is one: the page goes to it.
	srv atomic.Pointer[Server]
	// openPage is srv's own page handler, built once.
	openPage atomic.Pointer[http.Handler]
}

func newGate(cfg config.Config, state lockState, kdf vault.Params, logger *slog.Logger) *gate {
	g := &gate{
		dbPath:    cfg.DBPath,
		keyPath:   cfg.KeyPath(),
		kdf:       kdf,
		logger:    logger,
		formToken: newFormToken(),
		requests:  make(chan gateRequest),
	}
	g.state.Store(int32(state))
	return g
}

func (g *gate) current() lockState {
	return lockState(g.state.Load())
}

// detectLock reads the state the files on disk put a starting server in:
// nothing - set a password; a database and its key file - locked. One
// without the other is a start that must not go on, and the error says what
// to do: the server never creates a database over an existing one, nor
// guesses which of the two is the mistake.
func detectLock(dbPath, keyPath string) (lockState, error) {
	hasDB, err := present(dbPath)
	if err != nil {
		return 0, err
	}
	hasKey, err := present(keyPath)
	if err != nil {
		return 0, err
	}
	switch {
	case !hasDB && !hasKey:
		return stateSetup, nil
	case hasDB && hasKey:
		return stateLocked, nil
	case hasDB:
		return 0, fmt.Errorf("the database %s has no key file beside it (%s). A database from before encryption cannot be "+
			"opened: delete it with its -wal and -shm siblings and its -files directory, then start again and set a password. "+
			"If its key file was lost, only a backup brings this server back: move the database aside and run noxd restore", dbPath, keyPath)
	default:
		return 0, fmt.Errorf("the key file %s is here, but the database %s is not. If this server never held anything, delete "+
			"the key file and start again; if the database was lost, move the key file aside and restore the server from a "+
			"backup with noxd restore", keyPath, dbPath)
	}
}

// present says whether a file is at path, and fails on anything but "no".
func present(path string) (bool, error) {
	_, err := os.Lstat(path)
	switch {
	case err == nil:
		return true, nil
	case errors.Is(err, os.ErrNotExist):
		return false, nil
	default:
		return false, fmt.Errorf("look for %s: %w", path, err)
	}
}

// awaitKey serves the gate on the calling goroutine until a password opens
// the data - set for the first time, or entered - and returns the data key
// with the request that brought it. That request is answered by the caller,
// once the server is open or could not be. ok is false when ctx ended first.
func (g *gate) awaitKey(ctx context.Context) (key []byte, opener gateRequest, ok bool) {
	for {
		select {
		case <-ctx.Done():
			return nil, gateRequest{}, false
		case req := <-g.requests:
			if key := g.handle(req); key != nil {
				return key, req, true
			}
		}
	}
}

// serveOpen is the keeper: it serves the gate once the server is open, until
// ctx ends.
func (g *gate) serveOpen(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case req := <-g.requests:
			g.handle(req)
		}
	}
}

// opened marks the server open: the page goes to srv from here.
func (g *gate) opened(srv *Server) {
	h := srv.StatusHandler()
	g.openPage.Store(&h)
	g.srv.Store(srv)
	g.state.Store(int32(stateOpen))
}

// handle answers one request in the state the gate is in. A request that
// opens the data is not answered here: its key is returned, and whoever opens
// the data answers it.
func (g *gate) handle(req gateRequest) []byte {
	state := g.current()
	kind := req.kind
	if kind == reqOpen {
		kind = reqUnlock
		if state == stateSetup {
			kind = reqSetup
		}
	}
	switch kind {
	case reqSetup:
		if state != stateSetup {
			req.answer(codeState, "")
			return nil
		}
		return g.setup(req)
	case reqUnlock:
		if state != stateLocked {
			req.answer(codeState, "")
			return nil
		}
		return g.unlock(req)
	case reqChange:
		if state != stateOpen {
			req.answer(codeState, "")
			return nil
		}
		g.change(req)
	default:
		req.answer(codeState, "")
	}
	return nil
}

// setup takes the first password: twice the same, at least twelve
// characters. Then a new data key is made and sealed with it - and only if
// there is still nothing on disk: a database that appeared since the start (a
// restore, say) is never covered by a new one.
func (g *gate) setup(req gateRequest) []byte {
	if err := vault.CheckPassword(req.password); err != nil {
		req.answer(codeShort, "")
		return nil
	}
	if req.repeat != req.password {
		req.answer(codeMismatch, "")
		return nil
	}
	state, err := detectLock(g.dbPath, g.keyPath)
	if err != nil || state != stateSetup {
		if err == nil {
			// Both are there now; the page says so on its next load.
			g.state.Store(int32(state))
		}
		g.logger.Warn("a first password came for a server that has data on disk now; nothing was created")
		req.answer(codeState, "")
		return nil
	}
	key, err := vault.Create(g.keyPath, req.password, g.kdf)
	if errors.Is(err, vault.ErrExists) {
		req.answer(codeState, "")
		return nil
	}
	if err != nil {
		g.logger.Error("create the key file", "err", err)
		req.answer(codeInternal, "the server could not write its key file - see its log")
		return nil
	}
	g.state.Store(int32(stateOpening))
	g.logger.Info("password set; opening the data")
	return key
}

// unlock opens the key file with the password. A wrong one changes nothing
// anywhere and says so; the server stays locked.
func (g *gate) unlock(req gateRequest) []byte {
	key, err := vault.Open(g.keyPath, req.password)
	if errors.Is(err, vault.ErrWrongPassword) {
		g.logger.Info("unlock refused: wrong password")
		req.answer(codeWrong, "")
		return nil
	}
	if err != nil {
		g.logger.Error("open the key file", "err", err)
		req.answer(codeInternal, "the server could not read its key file - see its log")
		return nil
	}
	g.state.Store(int32(stateOpening))
	g.logger.Info("password accepted; opening the data")
	return key
}

// change re-seals the data key under a new password. The repeat is the page's
// business and the command's; what arrives here has passed it.
func (g *gate) change(req gateRequest) {
	err := vault.Change(g.keyPath, req.current, req.password, g.kdf)
	switch {
	case errors.Is(err, vault.ErrShortPassword):
		req.answer(codeShort, "")
	case errors.Is(err, vault.ErrWrongPassword):
		g.logger.Info("password change refused: wrong current password")
		req.answer(codeWrong, "")
	case err != nil:
		g.logger.Error("change the password", "err", err)
		req.answer(codeInternal, "the server could not change its password - see its log")
	default:
		g.logger.Info("password changed")
		req.answer("", "")
	}
}

// ask hands req to the goroutine serving the gate and waits for the answer.
// ok is false when the request went away first - its client hung up, or the
// server is stopping.
func (g *gate) ask(ctx context.Context, req gateRequest) (gateReply, bool) {
	req.ctx = ctx
	req.reply = make(chan gateReply, 1)
	select {
	case g.requests <- req:
	case <-ctx.Done():
		return gateReply{}, false
	}
	select {
	case rep := <-req.reply:
		return rep, true
	case <-ctx.Done():
		return gateReply{}, false
	}
}

// --- the service page's own listener ---

// servicePage is the service page's listener and server, up from the first
// moment of the process to its last: the password is entered there.
type servicePage struct {
	srv  *http.Server
	addr string
	// cancel ends every request's context: nothing a page request does
	// outlives the database it reads.
	cancel context.CancelFunc
	done   chan struct{}
	once   sync.Once
}

func startPage(ln net.Listener, h http.Handler, logger *slog.Logger) *servicePage {
	ctx, cancel := context.WithCancel(context.Background())
	p := &servicePage{
		srv: &http.Server{
			Handler:           h,
			ReadHeaderTimeout: pageReadHeaderTimeout,
			BaseContext:       func(net.Listener) context.Context { return ctx },
		},
		addr:   ln.Addr().String(),
		cancel: cancel,
		done:   make(chan struct{}),
	}
	go func() {
		defer close(p.done)
		if err := p.srv.Serve(ln); !errors.Is(err, http.ErrServerClosed) {
			logger.Error("service page stopped", "err", err)
		}
	}()
	return p
}

// stop takes the page down, on its OWN deadline, and waits until it is. Safe
// to call more than once: the first call does it.
func (p *servicePage) stop() error {
	var err error
	p.once.Do(func() {
		p.cancel()
		ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		err = p.srv.Shutdown(ctx)
		cancel()
		<-p.done
	})
	return err
}

// --- the handlers ---

// handler is the service page's mux for the life of the process. What the
// lock touches is answered here in every state; everything else is the open
// server's page, and before it opens there is nothing else to answer.
func (g *gate) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", g.handleHealth)
	mux.HandleFunc("GET "+controlStatePath, g.handleControlState)
	mux.HandleFunc("POST "+controlUnlockPath, g.handleControlUnlock)
	mux.HandleFunc("POST "+controlPasswordPath, g.handleControlPassword)
	mux.HandleFunc("POST /password/setup", g.handlePasswordForm(reqSetup))
	mux.HandleFunc("POST /password/unlock", g.handlePasswordForm(reqUnlock))
	mux.HandleFunc("POST /password/change", g.handlePasswordForm(reqChange))
	mux.HandleFunc("/", g.handleRest)
	return mux
}

// handleHealth is GET /health: alive either way, and which way (contract §1).
// No Host check, like before: it says nothing a rebound page could use.
func (g *gate) handleHealth(w http.ResponseWriter, _ *http.Request) {
	status := `{"status":"locked"}`
	if g.current() == stateOpen {
		status = `{"status":"ok"}`
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(status))
}

// handleRest is the open server's page once there is one. Before that, the
// lock page at / and nothing else: no address form, no link, no figure.
func (g *gate) handleRest(w http.ResponseWriter, r *http.Request) {
	if h := g.openPage.Load(); h != nil && g.current() == stateOpen {
		(*h).ServeHTTP(w, r)
		return
	}
	if !localHost(r.Host) {
		http.Error(w, "this page is only served to this machine", http.StatusForbidden)
		return
	}
	switch {
	case r.URL.Path == "/" && r.Method == http.MethodGet:
		g.handleLockPage(w, r)
	case r.Method == http.MethodPost:
		pageHeaders(w)
		http.Error(w, "the server is locked: enter its password first", http.StatusConflict)
	default:
		http.NotFound(w, r)
	}
}

// handlePasswordForm is one of the page's three password forms. Only the
// page's own form is believed (formAllowed, as for Set and the link buttons);
// the answer is a redirect to the page, naming what went wrong and never what
// was typed.
func (g *gate) handlePasswordForm(kind requestKind) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		pageHeaders(w)
		if !formAllowed(w, r, g.formToken) {
			return
		}
		req := gateRequest{kind: kind, password: r.PostForm.Get("password")}
		switch kind {
		case reqSetup:
			req.repeat = r.PostForm.Get("repeat")
		case reqChange:
			req.current = r.PostForm.Get("current")
			// The rules first, so the person learns what is wrong with what
			// they typed without waiting for the current password to be tried.
			if err := vault.CheckPassword(req.password); err != nil {
				http.Redirect(w, r, "/?error="+codeShort, http.StatusSeeOther)
				return
			}
			if r.PostForm.Get("repeat") != req.password {
				http.Redirect(w, r, "/?error="+codeMismatch, http.StatusSeeOther)
				return
			}
		}
		rep, ok := g.ask(r.Context(), req)
		switch {
		case !ok:
			http.Error(w, "the server is stopping", http.StatusServiceUnavailable)
		case rep.code == "" || rep.code == codeState:
			// Done - or the state moved on under the form: either way the page
			// shows where the server stands now.
			http.Redirect(w, r, "/", http.StatusSeeOther)
		case rep.code == codeWrong || rep.code == codeShort || rep.code == codeMismatch:
			http.Redirect(w, r, "/?error="+rep.code, http.StatusSeeOther)
		default:
			http.Error(w, rep.message, http.StatusInternalServerError)
		}
	}
}

// --- the control surface: noxd unlock, noxd password ---

const (
	controlStatePath    = "/control/state"
	controlUnlockPath   = "/control/unlock"
	controlPasswordPath = "/control/password"
	// maxControlBodyBytes bounds a command's request: two passwords fit many
	// times over.
	maxControlBodyBytes = 16 << 10
)

// ControlState is GET /control/state: where the server stands, so `noxd
// unlock` knows whether to ask for a first password twice or for the
// password once.
type ControlState struct {
	State string `json:"state"`
}

// ControlError is what a refused command request carries.
type ControlError struct {
	Error   string `json:"error"`
	Message string `json:"message,omitempty"`
}

func (g *gate) handleControlState(w http.ResponseWriter, r *http.Request) {
	if !controlAllowed(w, r) {
		return
	}
	writeControlJSON(w, http.StatusOK, ControlState{State: g.current().name()})
}

func (g *gate) handleControlUnlock(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Password string `json:"password"`
		Repeat   string `json:"repeat"`
	}
	if !controlAllowed(w, r) || !readControlBody(w, r, &body) {
		return
	}
	rep, ok := g.ask(r.Context(), gateRequest{kind: reqOpen, password: body.Password, repeat: body.Repeat})
	answerControl(w, rep, ok)
}

func (g *gate) handleControlPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Current  string `json:"current"`
		Password string `json:"password"`
	}
	if !controlAllowed(w, r) || !readControlBody(w, r, &body) {
		return
	}
	rep, ok := g.ask(r.Context(), gateRequest{kind: reqChange, current: body.Current, password: body.Password})
	answerControl(w, rep, ok)
}

// controlAllowed admits a request from a program on this machine and refuses
// anything a browser can send, with a 403 and nothing done - the rule `noxd
// link` set (046): Host names this machine, X-Nox-Control: 1 is present - a
// custom header a page from another site cannot send without a preflight
// nothing here answers - and there is no Origin, which every browser sets on
// a cross-origin request and on a same-origin POST.
func controlAllowed(w http.ResponseWriter, r *http.Request) bool {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if !localHost(r.Host) || r.Header.Get(controlHeader) != "1" || len(r.Header.Values("Origin")) > 0 {
		http.Error(w, "this answers the noxd commands on this machine, and nothing else", http.StatusForbidden)
		return false
	}
	return true
}

// readControlBody decodes a command's JSON body into v, or answers 400.
func readControlBody(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxControlBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		http.Error(w, "the body is not the JSON this command sends", http.StatusBadRequest)
		return false
	}
	return true
}

// answerControl turns the gate's answer into the command's.
func answerControl(w http.ResponseWriter, rep gateReply, ok bool) {
	if !ok {
		writeControlJSON(w, http.StatusServiceUnavailable, ControlError{Error: codeInternal, Message: "the server is stopping"})
		return
	}
	switch rep.code {
	case "":
		writeControlJSON(w, http.StatusOK, struct{}{})
	case codeWrong:
		writeControlJSON(w, http.StatusForbidden, ControlError{Error: rep.code})
	case codeShort, codeMismatch:
		writeControlJSON(w, http.StatusBadRequest, ControlError{Error: rep.code})
	case codeState:
		writeControlJSON(w, http.StatusConflict, ControlError{Error: rep.code})
	default:
		writeControlJSON(w, http.StatusInternalServerError, ControlError{Error: codeInternal, Message: rep.message})
	}
}

func writeControlJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

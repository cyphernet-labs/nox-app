package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/vault"
)

// The locked start (047): the lock state on disk, the page in its three
// states, the password forms and commands, and the main port that stays shut
// until the password is in.

func TestTheDiskDecidesTheStateAServerStartsIn(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "nox.db")
	keyPath := dbPath + ".key"
	touch := func(path string) {
		t.Helper()
		if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
	}

	if state, err := detectLock(dbPath, keyPath); err != nil || state != stateSetup {
		t.Fatalf("nothing on disk = %v, %v; want setup", state, err)
	}
	touch(dbPath)
	if _, err := detectLock(dbPath, keyPath); err == nil || !strings.Contains(err.Error(), "no key file") {
		t.Fatalf("a database without its key = %v, want a refusal that says so", err)
	}
	touch(keyPath)
	if state, err := detectLock(dbPath, keyPath); err != nil || state != stateLocked {
		t.Fatalf("a database and its key = %v, %v; want locked", state, err)
	}
	if err := os.Remove(dbPath); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if _, err := detectLock(dbPath, keyPath); err == nil || !strings.Contains(err.Error(), "noxd restore") {
		t.Fatalf("a key without its database = %v, want a refusal that names the way back", err)
	}
}

// A start on a database from before 047, or one whose key went missing, stops
// before anything listens - it never creates a new database beside a lost one.
func TestAStartWithADatabaseAndNoKeyStopsAtOnce(t *testing.T) {
	cfg := testRunConfig(t)
	if err := os.WriteFile(cfg.DBPath, []byte("SQLite format 3\x00"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	err := run(t.Context(), cfg, os.DirFS("../../migrations"), slog.New(slog.NewTextHandler(io.Discard, nil)), testKDF)
	if err == nil || !strings.Contains(err.Error(), "no key file") {
		t.Fatalf("run over a database with no key = %v, want the refusal", err)
	}
	if _, err := os.Stat(cfg.KeyPath()); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("the refused start wrote a key file (stat err %v)", err)
	}
	if conn, err := net.DialTimeout("tcp", cfg.StatusAddr, time.Second); err == nil {
		_ = conn.Close()
		t.Fatal("the refused start left its page listening")
	}
}

// mainPortShut says whether nothing at all listens on addr: a device dialling
// a locked server sees what it sees when the server is off.
func mainPortShut(addr string) bool {
	conn, err := net.DialTimeout("tcp", addr, time.Second)
	if err != nil {
		return true
	}
	_ = conn.Close()
	return false
}

// pageForm posts a form to a server Run started, the way its own page posts
// it, and returns the status and where it redirects.
func pageForm(t *testing.T, statusAddr, path string, values url.Values) (int, string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, "http://"+statusAddr+path, strings.NewReader(values.Encode()))
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", "http://"+statusAddr)
	noFollow := &http.Client{Timeout: 30 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
	resp, err := noFollow.Do(req)
	if err != nil {
		t.Fatalf("POST %s: %v", path, err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode, resp.Header.Get("Location")
}

// formTokenOn reads the form token off a page.
func formTokenOn(t *testing.T, page string) string {
	t.Helper()
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{64})"`).FindStringSubmatch(page)
	if m == nil {
		t.Fatalf("the page carries no form token:\n%s", page)
	}
	return m[1]
}

// dirState is every file under dir with a digest of its bytes and its
// modification time: what a refused password must leave exactly as it was.
func dirState(t *testing.T, dir string) map[string]string {
	t.Helper()
	state := map[string]string{}
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if d.IsDir() {
			state[path] = "dir " + info.ModTime().String()
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		state[path] = fmt.Sprintf("%x %d %s", sha256.Sum256(data), len(data), info.ModTime())
		return nil
	})
	if err != nil {
		t.Fatalf("walk %s: %v", dir, err)
	}
	return state
}

func sameState(t *testing.T, before, after map[string]string) {
	t.Helper()
	if len(before) != len(after) {
		t.Fatalf("the files on disk changed: %d entries before, %d after", len(before), len(after))
	}
	for path, was := range before {
		if after[path] != was {
			t.Fatalf("%s changed on disk", path)
		}
	}
}

func TestAFreshServerWaitsForItsFirstPasswordWithItsMainPortShut(t *testing.T) {
	cfg := testRunConfig(t)
	logs, _ := startRun(t, cfg)
	ctx := t.Context()

	if got := health(t, cfg.StatusAddr); got != `{"status":"locked"}` {
		t.Fatalf("/health of a server with no password = %s, want locked", got)
	}
	if !mainPortShut(cfg.Addr) {
		t.Fatal("the main port answers before the server has a password")
	}
	if state, err := RequestState(ctx, cfg.StatusAddr); err != nil || state != "setup" {
		t.Fatalf("state = %q, %v; want setup", state, err)
	}
	page := getPage(t, cfg.StatusAddr)
	for _, want := range []string{"Set a password for this server", `name="repeat"`, "Set password",
		"If you forget this password, the server's data can't be opened by anyone, including you."} {
		if !strings.Contains(page, want) {
			t.Fatalf("the setup page lacks %q:\n%s", want, page)
		}
	}
	for _, never := range []string{"nox://", "Addresses", "Storage id", "<script"} {
		if strings.Contains(page, never) {
			t.Fatalf("the setup page shows %q:\n%s", never, page)
		}
	}

	// The rules hold, and a refusal writes nothing.
	for _, c := range []struct{ pw, repeat, code string }{
		{"short", "short", "short"},
		{strings.Repeat(" ", 14), strings.Repeat(" ", 14), "short"},
		{testPassword, testPassword + "!", "mismatch"},
		{testPassword, "", "mismatch"},
	} {
		var refused *CommandError
		if err := RequestUnlock(ctx, cfg.StatusAddr, c.pw, c.repeat); !errors.As(err, &refused) || refused.Code != c.code {
			t.Fatalf("setting %q/%q = %v, want %s", c.pw, c.repeat, err, c.code)
		}
	}
	if _, err := os.Stat(cfg.KeyPath()); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a refused first password left a key file (stat err %v)", err)
	}
	if _, err := os.Stat(cfg.DBPath); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a refused first password left a database (stat err %v)", err)
	}

	if err := RequestUnlock(ctx, cfg.StatusAddr, testPassword, testPassword); err != nil {
		t.Fatalf("set the first password: %v", err)
	}
	if got := health(t, cfg.StatusAddr); got != `{"status":"ok"}` {
		t.Fatalf("/health after the first password = %s, want ok", got)
	}
	if mainPortShut(cfg.Addr) {
		t.Fatal("the main port is still shut after the first password")
	}
	if state, err := RequestState(ctx, cfg.StatusAddr); err != nil || state != "open" {
		t.Fatalf("state = %q, %v; want open", state, err)
	}
	// FR-005: nothing sets a new password over an existing one.
	var refused *CommandError
	if err := RequestUnlock(ctx, cfg.StatusAddr, "another password here", "another password here"); !errors.As(err, &refused) ||
		refused.Code != codeState {
		t.Fatalf("a first password for an open server = %v, want state", err)
	}
	if _, err := vault.Open(cfg.KeyPath(), testPassword); err != nil {
		t.Fatalf("the key file does not open with the password that was set: %v", err)
	}
	if out := logs.String(); strings.Contains(out, testPassword) {
		t.Fatalf("the password reached the log:\n%s", out)
	}
}

// firstRun sets up a server, pairs a device on it and stops it: what a
// restart then finds on disk.
func firstRun(t *testing.T, cfg config.Config) (*device, ed25519.PublicKey) {
	t.Helper()
	logs, stop := runServer(t, cfg)
	raw, err := base64.StdEncoding.DecodeString(loggedServerKey(logs.String()))
	if err != nil {
		t.Fatalf("server key: %v", err)
	}
	serverKey := ed25519.PublicKey(raw)
	link, err := RequestMachineLink(t.Context(), cfg.StatusAddr)
	if err != nil {
		t.Fatalf("RequestMachineLink: %v", err)
	}
	d := newDevice(t)
	c := dialRun(t, cfg.Addr, serverKey, d)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"macos"}}`, readLink(t, link.Link).Token))
	c.expectOK(1)
	c.hello(2, "")
	_ = c.conn.Close(websocket.StatusNormalClosure, "")
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	return d, serverKey
}

func TestARestartedServerIsLockedUntilItsPasswordComes(t *testing.T) {
	cfg := testRunConfig(t)
	d, serverKey := firstRun(t, cfg)

	_, _ = startRun(t, cfg)
	if got := health(t, cfg.StatusAddr); got != `{"status":"locked"}` {
		t.Fatalf("/health after a restart = %s, want locked", got)
	}
	if !mainPortShut(cfg.Addr) {
		t.Fatal("the main port of a locked server answers")
	}
	page := getPage(t, cfg.StatusAddr)
	if !strings.Contains(page, "This server is locked") || !strings.Contains(page, `type="password"`) {
		t.Fatalf("the locked page has no password field:\n%s", page)
	}
	// Only the password field: no link, no address, no figure, no second field.
	for _, never := range []string{"nox://", "Addresses", "Storage id", "Devices", "Messages", `name="repeat"`, "<script"} {
		if strings.Contains(page, never) {
			t.Fatalf("the locked page shows %q:\n%s", never, page)
		}
	}
	if n := strings.Count(page, "<input"); n != 2 {
		t.Fatalf("the locked page has %d inputs, want the password and its form token", n)
	}
	token := formTokenOn(t, page)

	// SC-003: a wrong password, on the page or from the terminal, changes not a
	// byte on disk and leaves the server locked.
	dir := filepath.Dir(cfg.DBPath)
	before := dirState(t, dir)
	code, where := pageForm(t, cfg.StatusAddr, "/password/unlock", url.Values{"token": {token}, "password": {"not the password"}})
	if code != http.StatusSeeOther || where != "/?error=wrong" {
		t.Fatalf("a wrong password on the page = %d to %q, want 303 to /?error=wrong", code, where)
	}
	if page := getPageAt(t, cfg.StatusAddr, where); !strings.Contains(page, "Wrong password.") {
		t.Fatalf("the page does not say the password was wrong:\n%s", page)
	}
	var refused *CommandError
	if err := RequestUnlock(t.Context(), cfg.StatusAddr, "still not it at all", ""); !errors.As(err, &refused) || refused.Code != codeWrong {
		t.Fatalf("a wrong password from the terminal = %v, want wrong", err)
	}
	sameState(t, before, dirState(t, dir))
	if got := health(t, cfg.StatusAddr); got != `{"status":"locked"}` || !mainPortShut(cfg.Addr) {
		t.Fatal("a wrong password opened the server")
	}

	// SC-002: the right one opens it within two seconds, and the device paired
	// before the restart goes on without pairing again.
	start := time.Now()
	code, where = pageForm(t, cfg.StatusAddr, "/password/unlock", url.Values{"token": {token}, "password": {testPassword}})
	if code != http.StatusSeeOther || where != "/" {
		t.Fatalf("the password on the page = %d to %q, want 303 to /", code, where)
	}
	if took := time.Since(start); took > 2*time.Second {
		t.Fatalf("the server took %v to open after its password, want at most 2 s", took)
	}
	if got := health(t, cfg.StatusAddr); got != `{"status":"ok"}` {
		t.Fatalf("/health after the password = %s, want ok", got)
	}
	c := dialRun(t, cfg.Addr, serverKey, d)
	c.expectGreeting()
	c.hello(1, "")
	// The open page is the full one, Change password included, with the form
	// token the lock page handed out still good.
	open := getPage(t, cfg.StatusAddr)
	if !strings.Contains(open, "Change password") || formTokenOn(t, open) != token {
		t.Fatalf("the open page has no password change or another form token:\n%s", open)
	}
}

// getPageAt fetches one address of the page, query included.
func getPageAt(t *testing.T, statusAddr, path string) string {
	t.Helper()
	resp, err := (&http.Client{Timeout: 5 * time.Second}).Get("http://" + statusAddr + path)
	if err != nil {
		t.Fatalf("GET %s: %v", path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(body)
}

func TestALockedServerHandsOutNoLinkAndTakesNoAddress(t *testing.T) {
	cfg := testRunConfig(t)
	_, _ = startRun(t, cfg)
	_, err := RequestMachineLink(t.Context(), cfg.StatusAddr)
	if err == nil || !strings.Contains(err.Error(), "locked") {
		t.Fatalf("noxd link on a locked server = %v, want a refusal that says it is locked", err)
	}
	page := getPage(t, cfg.StatusAddr)
	token := formTokenOn(t, page)
	for _, path := range []string{"/link", "/addresses"} {
		if code, _ := pageForm(t, cfg.StatusAddr, path, url.Values{"token": {token}, "kind": {"public"}, "value": {"x.org:1"}}); code != http.StatusConflict {
			t.Fatalf("POST %s on a locked server = %d, want 409", path, code)
		}
	}
	var refused *CommandError
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, testPassword, "another long password"); !errors.As(err, &refused) ||
		refused.Code != codeState {
		t.Fatalf("a password change on a server with no password = %v, want state", err)
	}
	if err := RequestBackup(t.Context(), cfg.StatusAddr, filepath.Join(t.TempDir(), "b.tar")); !errors.As(err, &refused) ||
		refused.Code != codeState {
		t.Fatalf("a backup of a locked server = %v, want state", err)
	}
}

func TestThePasswordChangesOnThePageAndFromTheTerminal(t *testing.T) {
	cfg := testRunConfig(t)
	_, _ = runServer(t, cfg)
	token := formTokenOn(t, getPage(t, cfg.StatusAddr))
	change := func(current, next, repeat string) (int, string) {
		return pageForm(t, cfg.StatusAddr, "/password/change", url.Values{
			"token": {token}, "current": {current}, "password": {next}, "repeat": {repeat},
		})
	}
	const second = "staple orbit lantern"
	for _, c := range []struct{ current, next, repeat, code string }{
		{"not the password", second, second, "wrong"},
		{testPassword, "short", "short", "short"},
		{testPassword, second, second + "?", "mismatch"},
	} {
		code, where := change(c.current, c.next, c.repeat)
		if code != http.StatusSeeOther || where != "/?error="+c.code {
			t.Fatalf("change %+v = %d to %q, want /?error=%s", c, code, where, c.code)
		}
	}
	if page := getPageAt(t, cfg.StatusAddr, "/?error=mismatch"); !strings.Contains(page, "The passwords don&#39;t match.") {
		t.Fatalf("the open page does not say the passwords differ:\n%s", page)
	}
	if _, err := vault.Open(cfg.KeyPath(), testPassword); err != nil {
		t.Fatalf("a refused change changed the password: %v", err)
	}

	if code, where := change(testPassword, second, second); code != http.StatusSeeOther || where != "/" {
		t.Fatalf("a good change = %d to %q, want 303 to /", code, where)
	}
	if _, err := vault.Open(cfg.KeyPath(), testPassword); !errors.Is(err, vault.ErrWrongPassword) {
		t.Fatalf("the old password after a change = %v, want wrong", err)
	}
	if _, err := vault.Open(cfg.KeyPath(), second); err != nil {
		t.Fatalf("the new password does not open the key: %v", err)
	}

	// From the terminal, the same.
	const third = "violet harbour engine"
	var refused *CommandError
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, testPassword, third); !errors.As(err, &refused) || refused.Code != codeWrong {
		t.Fatalf("noxd password with the old password = %v, want wrong", err)
	}
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, second, "short"); !errors.As(err, &refused) || refused.Code != codeShort {
		t.Fatalf("noxd password to a short one = %v, want short", err)
	}
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, second, third); err != nil {
		t.Fatalf("noxd password: %v", err)
	}
	if _, err := vault.Open(cfg.KeyPath(), third); err != nil {
		t.Fatalf("the password set from the terminal does not open the key: %v", err)
	}
}

// The forms and the commands keep every check `Set` and `noxd link` have:
// whatever a browser can send is refused, whatever the page is showing.
func TestTheLockRefusesWhatABrowserCanSend(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nox.db")
	g := newGate(config.Config{DBPath: path}, stateSetup, testKDF, slog.New(slog.NewTextHandler(io.Discard, nil)))
	h := g.handler()
	serve := func(req *http.Request) int {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec.Code
	}
	body := `{"password":"` + testPassword + `","repeat":"` + testPassword + `","path":"/tmp/x.tar","current":"x"}`
	for _, p := range []string{controlStatePath, controlUnlockPath, controlPasswordPath, controlBackupPath, controlLinkPath} {
		method := http.MethodPost
		if p == controlStatePath {
			method = http.MethodGet
		}
		for name, tweak := range map[string]func(*http.Request){
			"with an Origin":     func(r *http.Request) { r.Header.Set("Origin", pageOrigin) },
			"without its header": func(r *http.Request) { r.Header.Del(controlHeader) },
			"for another host":   func(r *http.Request) { r.Host = "evil.example:8081" },
		} {
			req := httptest.NewRequest(method, p, strings.NewReader(body))
			req.Host = pageHost
			req.Header.Set(controlHeader, "1")
			tweak(req)
			if code := serve(req); code != http.StatusForbidden {
				t.Errorf("%s %s %s = %d, want 403", method, p, name, code)
			}
		}
	}
	form := url.Values{"token": {g.formToken}, "password": {testPassword}, "repeat": {testPassword}}
	for _, p := range []string{"/password/setup", "/password/unlock", "/password/change"} {
		for name, tweak := range map[string]func(*http.Request){
			"without an Origin":      func(r *http.Request) { r.Header.Del("Origin") },
			"from another site":      func(r *http.Request) { r.Header.Set("Origin", "http://evil.example") },
			"for another host":       func(r *http.Request) { r.Host = "evil.example:8081" },
			"without the form token": func(r *http.Request) { r.Body = io.NopCloser(strings.NewReader("password=x")) },
		} {
			req := httptest.NewRequest(http.MethodPost, p, strings.NewReader(form.Encode()))
			req.Host = pageHost
			req.Header.Set("Origin", pageOrigin)
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			tweak(req)
			if code := serve(req); code != http.StatusForbidden {
				t.Errorf("POST %s %s = %d, want 403", p, name, code)
			}
		}
	}
	// Nothing of it reached the gate: no key file.
	if _, err := os.Stat(path + ".key"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a refused request wrote a key file (stat err %v)", err)
	}
	// The lock page itself is only for this machine, and carries no script.
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "evil.example:8081"
	if code := serve(req); code != http.StatusForbidden {
		t.Fatalf("the lock page for another host = %d, want 403", code)
	}
	req = httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = pageHost
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if csp := rec.Header().Get("Content-Security-Policy"); strings.Contains(csp, "script-src") || !strings.Contains(csp, "default-src 'none'") {
		t.Fatalf("the lock page's policy = %q, want no script admitted", csp)
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("the lock page may be kept by a cache")
	}
}

// /health says locked for a server waiting on its first password, as for a
// locked one, and ok only once it is open - always with 200 (contract §1).
func TestHealthSaysLockedUntilTheServerIsOpen(t *testing.T) {
	g := newGate(config.Config{DBPath: filepath.Join(t.TempDir(), "nox.db")}, stateSetup, testKDF,
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	for _, c := range []struct {
		state lockState
		want  string
	}{
		{stateSetup, `{"status":"locked"}`},
		{stateLocked, `{"status":"locked"}`},
		{stateOpening, `{"status":"locked"}`},
		{stateOpen, `{"status":"ok"}`},
	} {
		g.state.Store(int32(c.state))
		rec := httptest.NewRecorder()
		g.handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rec.Code != http.StatusOK || rec.Body.String() != c.want {
			t.Fatalf("/health in state %d = %d %s, want 200 %s", c.state, rec.Code, rec.Body.String(), c.want)
		}
	}
}

// Two passwords at once - the page and the terminal, say - are taken in turn:
// one opens the server, and the other finds it open.
func TestTwoPasswordsAtOnceOpenTheServerOnce(t *testing.T) {
	cfg := testRunConfig(t)
	_, _ = firstRun(t, cfg)
	logs, _ := startRun(t, cfg)
	results := make(chan error, 2)
	for range 2 {
		go func() { results <- RequestUnlock(context.Background(), cfg.StatusAddr, testPassword, "") }()
	}
	var opened, refused int
	for range 2 {
		err := <-results
		var ce *CommandError
		switch {
		case err == nil:
			opened++
		case errors.As(err, &ce) && ce.Code == codeState:
			refused++
		default:
			t.Fatalf("unlock = %v", err)
		}
	}
	if opened != 1 || refused != 1 {
		t.Fatalf("%d opened and %d found it open, want one of each", opened, refused)
	}
	if n := strings.Count(logs.String(), "server unlocked"); n != 1 {
		t.Fatalf("the server opened %d times", n)
	}
}

// A server stopped while it waits for its password stops cleanly, and leaves
// nothing behind it.
func TestALockedServerStopsCleanly(t *testing.T) {
	cfg := testRunConfig(t)
	_, stop := startRun(t, cfg)
	if err := stop(); err != nil {
		t.Fatalf("stopping a server waiting for its password = %v", err)
	}
	entries, err := os.ReadDir(filepath.Dir(cfg.DBPath))
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("a server that never got a password left %d files behind", len(entries))
	}
	if conn, err := net.DialTimeout("tcp", cfg.StatusAddr, time.Second); err == nil {
		_ = conn.Close()
		t.Fatal("the page still listens after the stop")
	}
}

// The password is accepted - here a first one - and the server still cannot
// start, because its main port is somebody else's: the trap a stand falls into
// most. Whoever typed the password hears that, with the port named, from the
// command and from the page alike - not "the server is stopping", which is
// what stopping the page made of every such answer. And the server does stop,
// with the same reason.
func TestAServerThatCannotStartAfterItsPasswordSaysWhy(t *testing.T) {
	for _, via := range []string{"noxd unlock", "the page"} {
		t.Run(via, func(t *testing.T) {
			cfg := testRunConfig(t)
			holder, err := net.Listen("tcp", cfg.Addr)
			if err != nil {
				t.Fatalf("hold the main port: %v", err)
			}
			defer func() { _ = holder.Close() }()
			_, stop := startRun(t, cfg)

			var status int
			var message string
			if via == "noxd unlock" {
				var refused *CommandError
				if err := RequestUnlock(t.Context(), cfg.StatusAddr, testPassword, testPassword); !errors.As(err, &refused) {
					t.Fatalf("noxd unlock on a server whose port is taken = %v, want a refusal", err)
				} else if refused.Code != codeInternal {
					t.Fatalf("the refusal's code = %q, want %s", refused.Code, codeInternal)
				} else {
					status, message = refused.Status, refused.Message
				}
			} else {
				token := formTokenOn(t, getPage(t, cfg.StatusAddr))
				form := url.Values{"token": {token}, "password": {testPassword}, "repeat": {testPassword}}
				req, err := http.NewRequest(http.MethodPost, "http://"+cfg.StatusAddr+"/password/setup", strings.NewReader(form.Encode()))
				if err != nil {
					t.Fatalf("NewRequest: %v", err)
				}
				req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
				req.Header.Set("Origin", "http://"+cfg.StatusAddr)
				resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(req)
				if err != nil {
					t.Fatalf("POST the first password: %v", err)
				}
				body, err := io.ReadAll(resp.Body)
				_ = resp.Body.Close()
				if err != nil {
					t.Fatalf("read the answer: %v", err)
				}
				status, message = resp.StatusCode, string(body)
			}
			if status != http.StatusInternalServerError || !strings.Contains(message, "main port "+cfg.Addr) ||
				!strings.Contains(message, "password was accepted") {
				t.Fatalf("the answer = %d %q, want 500 saying the password was accepted and the main port %s is the trouble",
					status, message, cfg.Addr)
			}
			if err := stop(); err == nil || !strings.Contains(err.Error(), cfg.Addr) {
				t.Fatalf("Run returned %v, want the reason it could not start", err)
			}
		})
	}
}

// An answer the gate gave before the request's context ended is the answer,
// even when both are ready by the time the request looks: the server answers
// why it cannot start and THEN stops its page, and a select between the two
// would otherwise report "stopping" about half the time. Many rounds, because
// the two arrive together only now and then.
func TestAnAnswerGivenBeforeTheStopIsTheAnswer(t *testing.T) {
	g := newGate(config.Config{DBPath: filepath.Join(t.TempDir(), "nox.db")}, stateSetup, testKDF,
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	for i := range 500 {
		ctx, cancel := context.WithCancel(context.Background())
		go func() {
			req := <-g.requests
			req.answer(codeInternal, "why")
			cancel()
		}()
		rep, ok := g.ask(ctx, gateRequest{kind: reqOpen})
		cancel()
		if !ok || rep.code != codeInternal || rep.message != "why" {
			t.Fatalf("round %d: the answer = %+v, %v; want the one given before the stop", i, rep, ok)
		}
	}
}

// randomBytes is n bytes nobody could guess, for markers.
func randomBytes(t *testing.T, n int) []byte {
	t.Helper()
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		t.Fatalf("rand: %v", err)
	}
	return b
}

// containsAny says which of needles data holds, if any.
func containsAny(data []byte, needles map[string][]byte) string {
	for name, n := range needles {
		if len(n) > 0 && bytes.Contains(data, n) {
			return name
		}
	}
	return ""
}

// The page is where the password goes, so a page that cannot listen is a
// server that cannot start - said at once, with nothing created on disk. It
// used to be skipped with a line in the log; that was right only while the
// page held nothing a server needed.
func TestABusyServicePortStopsTheStart(t *testing.T) {
	cfg := testRunConfig(t)
	holder, err := net.Listen("tcp", cfg.StatusAddr)
	if err != nil {
		t.Fatalf("hold the page's port: %v", err)
	}
	defer func() { _ = holder.Close() }()
	err = run(t.Context(), cfg, os.DirFS("../../migrations"), slog.New(slog.NewTextHandler(io.Discard, nil)), testKDF)
	if err == nil || !strings.Contains(err.Error(), "the password is entered there") {
		t.Fatalf("run with its page's port taken = %v, want a refusal naming why", err)
	}
	if entries, _ := os.ReadDir(filepath.Dir(cfg.DBPath)); len(entries) != 0 {
		t.Fatalf("the refused start left %d files", len(entries))
	}
}

// A server with no page cannot be unlocked: refused before anything listens.
func TestAServerWithoutItsPageIsRefused(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.StatusAddr = ""
	err := run(t.Context(), cfg, os.DirFS("../../migrations"), slog.New(slog.NewTextHandler(io.Discard, nil)), testKDF)
	if err == nil || !strings.Contains(err.Error(), "-status-addr is empty") {
		t.Fatalf("run with no page = %v, want a refusal", err)
	}
}

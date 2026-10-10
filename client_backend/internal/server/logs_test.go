package server

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/vault"
)

// dialRun opens a WebSocket as d on a server Run started: the channel to its
// main port, proving d's key against the machine's, then the upgrade.
func dialRun(t *testing.T, addr string, serverKey ed25519.PublicKey, d *device) *wsClient {
	t.Helper()
	c, err := dialRunVia(t, addr, serverKey, d, "", nil)
	if err != nil {
		t.Fatalf("websocket.Dial: %v", err)
	}
	return c
}

// getPage fetches the service page of a server Run started, as the browser on
// that machine does.
func getPage(t *testing.T, statusAddr string) string {
	t.Helper()
	resp, err := (&http.Client{Timeout: 5 * time.Second}).Get("http://" + statusAddr + "/")
	if err != nil {
		t.Fatalf("GET the service page: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("the service page = %d (%v)", resp.StatusCode, err)
	}
	return string(body)
}

// T017, SC-005, FR-005: no link and no token reaches the server's log - not at
// startup, not when the page mints one, not for `noxd link` or the page's
// button, not while a device pairs through one, and not through an invite, its
// request and its Allow. The log is the one place a link must never be: it is
// kept, copied and shipped, while the link is a way in.
//
// Driven through Run itself, with the log it writes captured whole, because
// what is being asked is everything the process says - including what the
// harness, which copies Run's steps by hand, would never say.
func TestNoLinkAndNoTokenEverReachesTheLog(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.OnionAddr = testOnionAddr
	logs, stop := runServer(t, cfg)
	stopped := false
	defer func() {
		if !stopped {
			_ = stop()
		}
	}()
	rawKey, err := base64.StdEncoding.DecodeString(loggedServerKey(logs.String()))
	if err != nil {
		t.Fatalf("server key: %v", err)
	}
	serverKey := ed25519.PublicKey(rawKey)
	var links, tokens []string
	remember := func(link string) string {
		links = append(links, strings.TrimPrefix(link, "nox://pair/"))
		token := readLink(t, link).Token
		tokens = append(tokens, token)
		return token
	}

	// The page mints the first link of a machine nobody can reach.
	page := getPage(t, cfg.StatusAddr)
	remember(linkOf(t, page))

	// `noxd link`.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	fromTerminal, err := RequestMachineLink(ctx, cfg.StatusAddr)
	if err != nil {
		t.Fatalf("RequestMachineLink: %v", err)
	}
	remember(fromTerminal.Link)

	// The page's button, posted the way the page's own form posts it.
	formToken := regexp.MustCompile(`name="token" value="([0-9a-f]{64})"`).FindStringSubmatch(page)
	if formToken == nil {
		t.Fatal("the page carries no form token")
	}
	req, err := http.NewRequest(http.MethodPost, "http://"+cfg.StatusAddr+"/link",
		strings.NewReader(url.Values{"token": {formToken[1]}}.Encode()))
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", "http://"+cfg.StatusAddr)
	noFollow := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := noFollow.Do(req)
	if err != nil {
		t.Fatalf("POST /link: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusSeeOther {
		t.Fatalf("POST /link = %d", resp.StatusCode)
	}
	machine := remember(linkOf(t, getPage(t, cfg.StatusAddr)))

	// A device pairs through it and greets.
	first := newDevice(t)
	c := dialRun(t, cfg.Addr, serverKey, first)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"macos"}}`, machine))
	c.expectOK(1)
	c.hello(2, "")

	// It invites a second; the second waits; the first allows it.
	invite := c.expectOKAfter(3, `{"id":3,"cmd":"device.invite","data":{}}`)
	var issued struct {
		Token string `json:"token"`
		Link  string `json:"link"`
	}
	mustUnmarshal(t, mustRaw(t, invite), &issued)
	remember(issued.Link)
	second := dialRun(t, cfg.Addr, serverKey, newDevice(t))
	second.expectGreeting()
	second.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"android"}}`, issued.Token))
	var pending pendingReply
	mustUnmarshal(t, mustRaw(t, second.expectOK(1)), &pending)
	expectNamedEvent(t, c, "device.pairRequested")
	c.expectOKAfter(4, fmt.Sprintf(`{"id":4,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	expectNamedEvent(t, second, "pair.resolved")

	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	stopped = true

	out := logs.String()
	// The log was exercised, so silence below means something.
	for _, said := range []string{"machine link issued", "command handled", "pairing request opened", "pairing request closed"} {
		if !strings.Contains(out, said) {
			t.Fatalf("the log never says %q, so the run did not go where the test meant:\n%s", said, out)
		}
	}
	if strings.Contains(out, "nox://pair/") {
		t.Fatalf("a link reached the log:\n%s", out)
	}
	for _, secret := range append(tokens, links...) {
		if strings.Contains(out, secret) {
			t.Fatalf("a token or link payload %q reached the log:\n%s", secret, out)
		}
	}
}

// FR-018 (047): neither a password - right, wrong, old or new - nor the data
// key, in any spelling, nor where a backup went reaches the server's log, at
// any step of the lock: the first password, wrong attempts, a restart and its
// unlock, a change, a backup.
func TestNoPasswordAndNoKeyEverReachesTheLog(t *testing.T) {
	cfg := testRunConfig(t)
	logs1, stop := runServer(t, cfg)
	var refused *CommandError
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, "a wrong current one", "never set at all"); !errors.As(err, &refused) {
		t.Fatalf("a change with a wrong password = %v", err)
	}
	const next = "staple orbit lantern"
	if err := RequestPasswordChange(t.Context(), cfg.StatusAddr, testPassword, next); err != nil {
		t.Fatalf("noxd password: %v", err)
	}
	dst := filepath.Join(t.TempDir(), "secret-place-backup.tar")
	if err := RequestBackup(t.Context(), cfg.StatusAddr, dst); err != nil {
		t.Fatalf("noxd backup: %v", err)
	}
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	logs2, stop2 := startRun(t, cfg)
	if err := RequestUnlock(t.Context(), cfg.StatusAddr, "guess number one", ""); !errors.As(err, &refused) {
		t.Fatalf("a wrong unlock = %v", err)
	}
	if err := RequestUnlock(t.Context(), cfg.StatusAddr, next, ""); err != nil {
		t.Fatalf("unlock: %v", err)
	}
	if err := stop2(); err != nil {
		t.Fatalf("Run returned %v", err)
	}

	key, err := vault.Open(cfg.KeyPath(), next)
	if err != nil {
		t.Fatalf("open the key: %v", err)
	}
	out := logs1.String() + logs2.String()
	for name, secret := range map[string]string{
		"the first password":     testPassword,
		"the new password":       next,
		"a wrong password":       "guess number one",
		"a wrong current one":    "a wrong current one",
		"a refused new password": "never set at all",
		"the data key in hex":    fmt.Sprintf("%x", key),
		"the data key in base64": base64.StdEncoding.EncodeToString(key),
		"the backup's place":     "secret-place-backup",
	} {
		if strings.Contains(out, secret) {
			t.Fatalf("%s reached the log:\n%s", name, out)
		}
	}
	// The log was exercised, so the silence above means something.
	for _, said := range []string{"password changed", "backup written", "unlock refused: wrong password", "server unlocked"} {
		if !strings.Contains(out, said) {
			t.Fatalf("the log never says %q:\n%s", said, out)
		}
	}
}

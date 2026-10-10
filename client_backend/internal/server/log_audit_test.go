package server

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/db"
)

// The whole log of a server's life, read for what it must never carry (045,
// FR-022): a start with both address parameters, the service page's Set as a
// browser sends it - and refused as a forgery - a claim, an invite and a second
// device paired by it, an upgrade through the onion service refused, and a
// second start with a broken parameter. Run itself, on real sockets, with the
// logger a test hands it: the scrubbing is Run's, not the test's.

// pageForm is what a browser takes off the service page before a Set: the
// form token and the claim link.
func pageForm(t *testing.T, statusAddr string) (token, link string) {
	t.Helper()
	resp, err := (&http.Client{Timeout: 5 * time.Second}).Get("http://" + statusAddr + "/")
	if err != nil {
		t.Fatalf("GET the service page: %v", err)
	}
	body, err := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if err != nil {
		t.Fatalf("read the service page: %v", err)
	}
	m := regexp.MustCompile(`name="token" value="([0-9a-f]+)"`).FindStringSubmatch(string(body))
	if m == nil {
		t.Fatalf("no form token on the page: %s", body)
	}
	return m[1], regexp.MustCompile(`nox://pair/[A-Za-z0-9_-]+`).FindString(string(body))
}

// postSet posts the Set form over the page's own listener, with the Host a
// browser sends and the Origin given, and returns the status - redirects not
// followed.
func postSet(t *testing.T, statusAddr, origin string, form url.Values) int {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, "http://"+statusAddr+"/addresses", strings.NewReader(form.Encode()))
	if err != nil {
		t.Fatalf("build the form: %v", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	client := &http.Client{
		Timeout:       5 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("POST /addresses: %v", err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

// dialRun opens a WebSocket to a server started by Run, as d, through the
// channel - with the Host and headers a device going through the onion service
// would send, when given.
func dialRun(t *testing.T, addr string, key ed25519.PublicKey, d *device, host string, header http.Header) (*wsClient, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	client := newTestChannel(addr, key, &testDevices{}).clientAs(d)
	conn, resp, err := websocket.Dial(ctx, "https://"+addr+"/ws", &websocket.DialOptions{HTTPClient: client, Host: host, HTTPHeader: header})
	if resp != nil && resp.Body != nil {
		_ = resp.Body.Close()
	}
	if err != nil {
		return nil, err
	}
	t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "") })
	conn.SetReadLimit(1 << 20)
	return &wsClient{t: t, conn: conn, ctx: ctx, dev: d}, nil
}

// pairOverRun presents token as d and returns once the server answered.
func pairOverRun(t *testing.T, addr string, key ed25519.PublicKey, d *device, token string) {
	t.Helper()
	c, err := dialRun(t, addr, key, d, "", nil)
	if err != nil {
		t.Fatalf("dial to pair: %v", err)
	}
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test"}}`, token))
	c.expectOK(1)
	_ = c.conn.Close(websocket.StatusNormalClosure, "")
}

func TestTheLogNeverCarriesAnOnionAddressALinkATokenOrAKey(t *testing.T) {
	typo := []byte(strings.TrimSuffix(contractOnion, ".onion"))
	typo[10] = 'a'
	cfg := testRunConfig(t)
	cfg.OnionAddr = testOnionAddr + ":443"
	// An onion name pasted into the wrong parameter: refused, and named in the
	// refusal - masked.
	cfg.PublicAddr = contractOnion + ":443"
	logs, stop := runServer(t, cfg)
	key, err := base64.StdEncoding.DecodeString(loggedServerKey(logs.String()))
	if err != nil {
		t.Fatalf("the server key: %v", err)
	}
	page := "http://" + cfg.StatusAddr

	// --- The service page, as a browser on this machine uses it. ---
	formToken, claimLink := pageForm(t, cfg.StatusAddr)
	if claimLink == "" {
		t.Fatal("no claim link on the page of an unclaimed server")
	}
	set := func(kind, value, token string) url.Values {
		return url.Values{"kind": {kind}, "value": {value}, "token": {token}}
	}
	for _, step := range []struct {
		name   string
		origin string
		form   url.Values
		want   int
	}{
		{"a new onion address", page, set("onion", contractOnion, formToken), http.StatusSeeOther},
		{"a broken one", page, set("onion", string(typo)+".onion", formToken), http.StatusSeeOther},
		{"a public address", page, set("public", "nox.example.org:8443", formToken), http.StatusSeeOther},
		{"a forged Origin", "http://evil.example", set("onion", testOnionAddr, formToken), http.StatusForbidden},
		{"no form token", page, set("onion", testOnionAddr, ""), http.StatusForbidden},
	} {
		if got := postSet(t, cfg.StatusAddr, step.origin, step.form); got != step.want {
			t.Fatalf("Set, %s: %d, want %d", step.name, got, step.want)
		}
	}
	_, claimLink = pageForm(t, cfg.StatusAddr)
	claim := readLink(t, claimLink)
	if claim.Onion == nil {
		t.Fatalf("the claim link names no onion service after the Set: %+v", claim)
	}

	// --- A claim, an invite, and a second device paired by it. ---
	owner := newDevice(t)
	pairOverRun(t, cfg.Addr, key, owner, claim.Token)
	c, err := dialRun(t, cfg.Addr, key, owner, "", nil)
	if err != nil {
		t.Fatalf("dial as the owner: %v", err)
	}
	c.expectGreeting()
	c.hello(1, "")
	inviteLink, onion, _ := inviteOver(t, c, 2, `{}`)
	if !onion {
		t.Fatal("the invite does not carry the onion service")
	}
	invite := readLink(t, inviteLink)
	second := newDevice(t)
	pairOverRun(t, cfg.Addr, key, second, invite.Token)

	// --- An upgrade through the onion service, refused: the library's error
	// quotes the Host it carried, which is the onion name. ---
	if _, err := dialRun(t, cfg.Addr, key, second, contractOnion+":443", http.Header{"Origin": {"http://evil.example"}}); err == nil {
		t.Fatal("a cross-origin upgrade was accepted")
	}
	eventually(t, "the refused upgrade is logged", func() bool { return strings.Contains(logs.String(), "websocket accept failed") })
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}

	// --- A second start over the same database, with a broken parameter. ---
	cfg.OnionAddr = string(typo) + ".onion"
	cfg.PublicAddr = ""
	again, stopAgain := runServer(t, cfg)
	if err := stopAgain(); err != nil {
		t.Fatalf("Run returned %v the second time", err)
	}

	dbs, err := db.Open(cfg.DBPath)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	defer func() { _ = dbs.Close() }()
	var seed string
	if err := dbs.Read.QueryRow("SELECT private_key FROM server_identity WHERE id = 1").Scan(&seed); err != nil {
		t.Fatalf("read the server key: %v", err)
	}

	out := logs.String() + again.String()
	for _, step := range []string{"address set on the service page", "start parameter not applied", "websocket accept failed", "command handled"} {
		if !strings.Contains(out, step) {
			t.Fatalf("the log has no %q, so this test proves less than it says:\n%s", step, out)
		}
	}
	lower := strings.ToLower(out)
	for what, secret := range map[string]string{
		"the onion address given at the start": strings.TrimSuffix(testOnionAddr, ".onion"),
		"the onion address set on the page":    strings.TrimSuffix(contractOnion, ".onion"),
		"the broken onion address":             string(typo),
	} {
		if strings.Contains(lower, secret) {
			t.Errorf("%s reached the log", what)
		}
	}
	for what, secret := range map[string]string{
		"a pairing link":            "nox://pair/",
		"the claim token":           claim.Token,
		"the invite token":          invite.Token,
		"the form token":            formToken,
		"the server's private key":  seed,
		"the owner's device key":    base64.StdEncoding.EncodeToString(owner.priv),
		"the second device's key":   base64.StdEncoding.EncodeToString(second.priv),
		"the onion service's key":   base64.RawURLEncoding.EncodeToString(claim.Onion),
		"the claim link's payload":  strings.TrimPrefix(claimLink, "nox://pair/")[:40],
		"the invite link's payload": strings.TrimPrefix(inviteLink, "nox://pair/")[:40],
	} {
		if strings.Contains(out, secret) {
			t.Errorf("%s reached the log", what)
		}
	}
	// Masked, not merely absent: the refused public parameter and the refused
	// upgrade both named an onion address.
	if strings.Count(out, "[onion]") < 2 {
		t.Errorf("fewer masked addresses than lines that named one")
	}
	if t.Failed() {
		t.Logf("the log:\n%s", out)
	}
}

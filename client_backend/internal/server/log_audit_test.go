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
// FR-022; 046, FR-005): a start with both address parameters, the service
// page's Set as a browser sends it - and refused as a forgery - a first device
// paired by the machine link, an invite and a second device asking with it and
// allowed, an upgrade through the onion service refused, and a second start
// with a broken parameter. Run itself, on real sockets, with the logger a test
// hands it: the scrubbing is Run's, not the test's.

// pageTokenAndLink is what a browser takes off the service page before a Set:
// the form token and the machine link the page shows while no device is
// paired.
func pageTokenAndLink(t *testing.T, statusAddr string) (token, link string) {
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

// dialRunVia opens a WebSocket to a server started by Run, as d, through the
// channel - with the Host and headers a device going through the onion service
// would send, when given.
func dialRunVia(t *testing.T, addr string, key ed25519.PublicKey, d *device, host string, header http.Header) (*wsClient, error) {
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

// pairOverRun presents a machine link's token as d and returns once the
// device is paired.
func pairOverRun(t *testing.T, addr string, key ed25519.PublicKey, d *device, token string) {
	t.Helper()
	c := dialRun(t, addr, key, d)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, token))
	if _, paired := c.expectOK(1)["identity"]; !paired {
		t.Fatal("the machine link did not pair the device")
	}
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
	formToken, machineLink := pageTokenAndLink(t, cfg.StatusAddr)
	if machineLink == "" {
		t.Fatal("no machine link on the page of a machine no device can reach")
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
	// The page still shows the link it minted - a reload never mints - rebuilt
	// with the addresses the Set left.
	_, machineLink = pageTokenAndLink(t, cfg.StatusAddr)
	machine := readLink(t, machineLink)
	if machine.Onion == nil {
		t.Fatalf("the machine link names no onion service after the Set: %+v", machine)
	}

	// --- A first device by the machine link, an invite, and a second device
	// asking with it and allowed. ---
	first := newDevice(t)
	pairOverRun(t, cfg.Addr, key, first, machine.Token)
	c := dialRun(t, cfg.Addr, key, first)
	c.expectGreeting()
	c.hello(1, "")
	inviteLink, onion, _ := inviteOver(t, c, 2, `{}`)
	if !onion {
		t.Fatal("the invite does not carry the onion service")
	}
	invite := readLink(t, inviteLink)
	second := newDevice(t)
	asking := dialRun(t, cfg.Addr, key, second)
	asking.expectGreeting()
	asking.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"android"}}`, invite.Token))
	var pending pendingReply
	mustUnmarshal(t, mustRaw(t, asking.expectOK(1)), &pending)
	expectNamedEvent(t, c, "device.pairRequested")
	c.expectOKAfter(3, fmt.Sprintf(`{"id":3,"cmd":"device.approve","data":{"request_id":%q,"allow":true}}`, pending.RequestID))
	expectNamedEvent(t, asking, "pair.resolved")
	_ = asking.conn.Close(websocket.StatusNormalClosure, "")

	// --- An upgrade through the onion service, refused: the library's error
	// quotes the Host it carried, which is the onion name. ---
	if _, err := dialRunVia(t, cfg.Addr, key, second, contractOnion+":443", http.Header{"Origin": {"http://evil.example"}}); err == nil {
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

	dbs, err := db.Open(cfg.DBPath, runDataKey(t, cfg))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	defer func() { _ = dbs.Close() }()
	var seed string
	if err := dbs.Read.QueryRow("SELECT private_key FROM server_identity WHERE id = 1").Scan(&seed); err != nil {
		t.Fatalf("read the server key: %v", err)
	}

	out := logs.String() + again.String()
	for _, step := range []string{
		"address set on the service page", "start parameter not applied", "websocket accept failed", "command handled",
		"pairing request closed",
	} {
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
		"a pairing link":             "nox://pair/",
		"the machine link's token":   machine.Token,
		"the invite token":           invite.Token,
		"the form token":             formToken,
		"the server's private key":   seed,
		"the first device's key":     base64.StdEncoding.EncodeToString(first.priv),
		"the second device's key":    base64.StdEncoding.EncodeToString(second.priv),
		"the onion service's key":    base64.RawURLEncoding.EncodeToString(machine.Onion),
		"the machine link's payload": strings.TrimPrefix(machineLink, "nox://pair/")[:40],
		"the invite link's payload":  strings.TrimPrefix(inviteLink, "nox://pair/")[:40],
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

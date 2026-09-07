package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// statusBody fetches the service page through its own mux.
func statusBody(t *testing.T, srv *Server) string {
	t.Helper()
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status page = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	return rec.Body.String()
}

func TestAnUnclaimedServerOffersTheLinkAndACodeToScan(t *testing.T) {
	_, srv := newTestServer(t)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	body := statusBody(t, srv)
	if !strings.Contains(body, "https://nox.app/p/#") {
		t.Fatalf("no claim link on an unclaimed server's page: %s", body)
	}
	if !strings.Contains(body, "<svg") {
		t.Fatalf("no QR on an unclaimed server's page: %s", body)
	}
	// The one screen that must NOT redraw itself: a camera is reading it.
	if strings.Contains(body, "http-equiv=\"refresh\"") {
		t.Fatal("the QR page refreshes itself, which breaks the scan it exists for")
	}
}

// The page hands out the SAME right the terminal printed. A second token would
// be a second unrevocable door - a claim token has no expiry to close it.
func TestThePageAndTheStartupLineShareOneClaimToken(t *testing.T) {
	_, srv := newTestServer(t)
	ctx := context.Background()
	if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := srv.store.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	srv.seedClaimToken(token)

	first := statusBody(t, srv)
	second := statusBody(t, srv)
	if linkOf(t, first) != linkOf(t, second) {
		t.Fatal("two page loads handed out two different links")
	}
	// The token is packed into the link's binary payload rather than spelled
	// out, so the property is asserted where it lives: exactly one unspent
	// claim token exists, the one the startup announcement minted.
	if got := countLiveClaimTokens(t, srv); got != 1 {
		t.Fatalf("unspent claim tokens = %d, want 1: the page minted its own", got)
	}
}

// listenAddress falls back to loopback under a wildcard bind - right for the
// terminal line, useless for the phone this page exists to serve.
func TestTheCodeCarriesAnAddressAPhoneCanDial(t *testing.T) {
	t.Run("a concrete bind is used as it stands", func(t *testing.T) {
		if got := dialableHost("192.168.1.10:8080"); got != "192.168.1.10:8080" {
			t.Fatalf("dialableHost = %q, want the operator's own address", got)
		}
	})

	t.Run("a wildcard bind resolves to something reachable", func(t *testing.T) {
		got := dialableHost("0.0.0.0:8080")
		if got == "" {
			t.Skip("this machine has no non-loopback address")
		}
		if strings.HasPrefix(got, "127.") || strings.HasPrefix(got, "[::1]") {
			t.Fatalf("dialableHost = %q, which no phone can dial", got)
		}
	})

	t.Run("a machine with no reachable address says so rather than drawing a dead code", func(t *testing.T) {
		if got := dialableHost("nonsense"); got != "" {
			t.Fatalf("dialableHost = %q, want empty", got)
		}
	})
}

func TestAClaimedServerShowsTheMachineAndNoLink(t *testing.T) {
	ts, srv := newTestServer(t)
	claimDevice(t, ts, srv)

	body := statusBody(t, srv)
	if strings.Contains(body, "https://nox.app/p/#") {
		t.Fatalf("a claimed server still offers a claim link: %s", body)
	}
	if strings.Contains(body, "<svg") {
		t.Fatalf("a claimed server still draws a QR: %s", body)
	}
	for _, want := range []string{"Version", "Uptime", "Schema", "Storage id", "Database", "People", "Devices", "Chats", "Messages"} {
		if !strings.Contains(body, want) {
			t.Fatalf("the claimed page does not show %q: %s", want, body)
		}
	}
	// This one refreshes: uptime and counters shown without one read as now.
	if !strings.Contains(body, `http-equiv="refresh"`) {
		t.Fatal("the status page does not refresh, so it shows stale numbers as current")
	}
}

// "Claimed" means the owner can still get in - the SAME predicate the startup
// announcement uses. A second definition here would show a status page to
// somebody locked out of their own machine.
func TestAnOwnerWithNoDevicesLeftIsOfferedTheLinkAgain(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, _ := claimDevice(t, ts, srv)
	if strings.Contains(statusBody(t, srv), "https://nox.app/p/#") {
		t.Fatal("a claimed server offered a link before the device was revoked")
	}

	if err := srv.store.RevokeDevice(context.Background(), dev.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	if !strings.Contains(statusBody(t, srv), "https://nox.app/p/#") {
		t.Fatal("an owner who lost every device is not offered a way back in")
	}
}

// The anomaly of phase 033: people, no owner. Pair refuses a claim there, so a
// link would be an instruction nobody can follow.
func TestAStoreWithPeopleAndNoOwnerOffersNothingToScan(t *testing.T) {
	ts, srv := newTestServer(t)
	claimDevice(t, ts, srv)
	orphanStore(t, srv)

	body := statusBody(t, srv)
	if strings.Contains(body, "https://nox.app/p/#") || strings.Contains(body, "<svg") {
		t.Fatalf("an ownerless store offers a claim it would refuse: %s", body)
	}
	if !strings.Contains(body, "no owner") {
		t.Fatalf("an ownerless store does not say so: %s", body)
	}
}

// Principle I, and stricter here than for a log: a log is read by somebody who
// went to read it, a page is seen by whoever is standing near the monitor.
func TestThePageNamesNobodyAndShowsNoKeys(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, data := claimDevice(t, ts, srv)
	var id identity
	mustUnmarshal(t, data["identity"], &id)

	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.greet(t, 1, dev, "")
	c.send(`{"id":2,"cmd":"identity.setLabel","data":{"label":"Anastasia"}}`)
	c.expectOK(2)
	c.send(`{"id":3,"cmd":"chat.create","data":{"name":"Kitchen renovation"}}`)
	c.expectOK(3)
	c.send(`{"id":4,"cmd":"chat.create","data":{"name":"Second"}}`)
	chat := c.expectOK(4)
	var created struct {
		ChatID string `json:"chat_id"`
	}
	mustUnmarshal(t, chat["chat"], &created)
	c.send(`{"id":5,"cmd":"message.send","data":{"chat_id":"` + created.ChatID +
		`","client_message_id":"m1","body":{"type":"text","text":"the boiler is leaking"}}}`)
	c.expectOK(5)

	body := statusBody(t, srv)
	for _, secret := range []string{"Anastasia", "Kitchen renovation", "the boiler is leaking", dev.pub, id.ID} {
		if strings.Contains(body, secret) {
			t.Fatalf("the service page shows %q", secret)
		}
	}
	// The counters are the point, and they must still be there.
	if !strings.Contains(body, "Chats") {
		t.Fatalf("the page stopped counting: %s", body)
	}
}

// The main listener is bound to every interface in an ordinary install. The
// page must live nowhere on it.
func TestTheMainListenerNeverServesTheServicePage(t *testing.T) {
	ts, srv := newTestServer(t)
	claimDevice(t, ts, srv)

	for _, path := range []string{"/", "/status", "/index.html"} {
		rec := httptest.NewRecorder()
		srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code == http.StatusOK && strings.Contains(rec.Body.String(), "<html") {
			t.Fatalf("the main listener serves the service page at %q", path)
		}
	}
}

// A page for people must not change a machine's answer: OS services and the
// tunnel read this one.
func TestHealthAnswersExactlyWhatItAnswered(t *testing.T) {
	_, srv := newTestServer(t)
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/health = %d, want 200", rec.Code)
	}
	var got map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("/health is not the JSON it was: %v (%s)", err, rec.Body.String())
	}
	if len(got) != 1 || got["status"] != "ok" {
		t.Fatalf("/health = %v, want exactly {\"status\":\"ok\"}", got)
	}
}

// orphanStore removes the owner from a store that has people, reaching the
// anomaly of phase 033 that no code path produces. A second handle on the same
// file, in the same process: the invariant is one PROCESS, and a test that
// cannot reach the state cannot check what the page says about it.
func orphanStore(t *testing.T, srv *Server) {
	t.Helper()
	handle, err := sql.Open("sqlite", srv.cfg.DBPath)
	if err != nil {
		t.Fatalf("open the database again: %v", err)
	}
	defer func() { _ = handle.Close() }()
	if _, err := handle.Exec("UPDATE server_identity SET owner_user_id = NULL WHERE id = 1"); err != nil {
		t.Fatalf("orphan the store: %v", err)
	}
}

// linkOf pulls the claim link out of the rendered page.
func linkOf(t *testing.T, body string) string {
	t.Helper()
	const open = `<code class="link">`
	i := strings.Index(body, open)
	if i < 0 {
		t.Fatal("no link on the page")
	}
	rest := body[i+len(open):]
	j := strings.Index(rest, "</code>")
	if j < 0 {
		t.Fatal("unterminated link on the page")
	}
	return rest[:j]
}

// countLiveClaimTokens counts the doors into this server that are still open.
func countLiveClaimTokens(t *testing.T, srv *Server) int {
	t.Helper()
	handle, err := sql.Open("sqlite", srv.cfg.DBPath)
	if err != nil {
		t.Fatalf("open the database again: %v", err)
	}
	defer func() { _ = handle.Close() }()
	var n int
	if err := handle.QueryRow("SELECT COUNT(1) FROM pair_tokens WHERE kind = 'claim' AND used_at IS NULL").Scan(&n); err != nil {
		t.Fatalf("count claim tokens: %v", err)
	}
	return n
}

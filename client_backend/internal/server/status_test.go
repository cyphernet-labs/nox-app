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
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "127.0.0.1:8081"
	srv.StatusHandler().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status page = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	return rec.Body.String()
}

func TestAnUnclaimedServerOffersTheLinkAndACodeToScan(t *testing.T) {
	_, srv := newTestServer(t)
	dialable(srv)
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
	dialable(srv)
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
	dialable(srv)
	claimDevice(t, ts, srv)

	body := statusBody(t, srv)
	if strings.Contains(body, "https://nox.app/p/#") {
		t.Fatalf("a claimed server still offers a claim link: %s", body)
	}
	if strings.Contains(body, "<svg") {
		t.Fatalf("a claimed server still draws a QR: %s", body)
	}
	for _, want := range []string{"Version", "Uptime", "Schema", "Storage id", "Database", "Devices", "Chats", "Messages"} {
		if !strings.Contains(body, want) {
			t.Fatalf("the claimed page does not show %q: %s", want, body)
		}
	}
	// Nothing counts people any more: this machine holds exactly one, so the
	// number would say the same thing on every server that ever runs.
	if strings.Contains(body, "People") {
		t.Fatalf("the page still counts people: %s", body)
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
	dialable(srv)
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

// A token spent between two page loads must not come back. The owner claims,
// then logs out; the page is the only recovery tool there is, and offering the
// burnt link would point it at a door that no longer opens.
func TestThePageStopsOfferingATokenThatHasBeenSpent(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	ctx := context.Background()
	if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := srv.store.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	// The production path: the startup announcement's token is what the page
	// holds. Without seeding it, the page mints its own and the bug is unreachable.
	srv.seedClaimToken(token)
	first := linkOf(t, statusBody(t, srv))

	dev, _ := pairDevice(t, ts, token)
	if err := srv.store.RevokeDevice(ctx, dev.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	second := linkOf(t, statusBody(t, srv))
	if second == first {
		t.Fatal("the page still offers the token the claim already burned")
	}
	if got := countLiveClaimTokens(t, srv); got != 1 {
		t.Fatalf("unspent claim tokens = %d, want exactly the replacement", got)
	}
}

// The default bind is loopback, and a phone cannot dial it. Drawing a code
// confidently there is worse than drawing none: the person scans it and gets a
// network error instead of being told to bind an address.
func TestALoopbackBindDrawsNoCodeAndSaysWhy(t *testing.T) {
	if got := dialableHost("127.0.0.1:8080"); got != "" {
		t.Fatalf("dialableHost = %q, want empty: no phone can dial loopback", got)
	}
	if got := dialableHost("localhost:8080"); got != "" {
		t.Fatalf("dialableHost = %q, want empty", got)
	}
	if got := dialableHost("[::1]:8080"); got != "" {
		t.Fatalf("dialableHost = %q, want empty", got)
	}

	_, srv := newTestServer(t)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	body := statusBody(t, srv)
	if strings.Contains(body, "<svg") {
		t.Fatalf("a loopback-bound server drew a code no phone can use: %s", body)
	}
	if !strings.Contains(body, "reachable from this machine only") {
		t.Fatalf("the page does not explain why there is no code: %s", body)
	}
	// And the LINK is still there. Conflating "no phone can dial this" with
	// "there is no link" left an owner on the default bind - which is loopback
	// - unable to claim their own server from the app running right there.
	if !strings.Contains(body, "https://nox.app/p/#") {
		t.Fatalf("a loopback-bound server offers no link at all: %s", body)
	}
	if got := countLiveClaimTokens(t, srv); got != 1 {
		t.Fatalf("unspent claim tokens = %d, want 1: a loopback bind must still issue one", got)
	}
}

// The recovery path on the DEFAULT configuration: claim, log out, and the page
// must offer a fresh usable link - not nothing, and not the burnt one.
func TestALoopbackServerCanBeReclaimedAfterALogout(t *testing.T) {
	ts, srv := newTestServer(t)
	ctx := context.Background()
	if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	token, err := srv.store.IssueClaimToken(ctx, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueClaimToken: %v", err)
	}
	srv.seedClaimToken(token)
	first := linkOf(t, statusBody(t, srv))

	dev, _ := pairDevice(t, ts, token)
	if err := srv.store.RevokeDevice(ctx, dev.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	second := linkOf(t, statusBody(t, srv))
	if second == first {
		t.Fatal("the page offers the token the claim already burned")
	}
	if got := countLiveClaimTokens(t, srv); got != 1 {
		t.Fatalf("unspent claim tokens = %d, want exactly the replacement", got)
	}
}

// A separate socket keeps the network out; it does not keep the operator's own
// browser out. Any site can be rebound to 127.0.0.1 by DNS and read this page
// as same-origin - and the claim link with it.
func TestThePageRefusesAHostThatIsNotThisMachine(t *testing.T) {
	_, srv := newTestServer(t)
	for _, host := range []string{"evil.example:8081", "nox.local:8081", "192.168.1.10:8081"} {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Host = host
		rec := httptest.NewRecorder()
		srv.StatusHandler().ServeHTTP(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("Host %q = %d, want 403: a rebound name must not read this page", host, rec.Code)
		}
	}
	for _, host := range []string{"127.0.0.1:8081", "localhost:8081", "[::1]:8081"} {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.Host = host
		rec := httptest.NewRecorder()
		srv.StatusHandler().ServeHTTP(rec, req)
		if rec.Code == http.StatusForbidden {
			t.Fatalf("Host %q was refused, but it is this machine", host)
		}
	}
}

// dialable gives the test server an address a phone could reach.
//
// The harness binds 127.0.0.1:0, which the page now correctly treats as "no
// phone can get here" - right in production, and it would leave every
// link-related test asserting about a page that deliberately shows none.
func dialable(srv *Server) {
	srv.cfg.Addr = "192.168.1.10:8080"
}

// The link follows the address; only the token is held.
//
// Caching the built link froze an address for the life of the process while
// "can a phone reach us" went on being recomputed — so a laptop whose network
// came up after the server did drew a QR over a link that still said
// 127.0.0.1, which is precisely the code this page refuses to draw.
func TestTheLinkFollowsTheAddressWhileTheTokenStaysPut(t *testing.T) {
	_, srv := newTestServer(t)
	ctx := context.Background()
	if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	// Started with no network: loopback, no code, but a link.
	first := statusBody(t, srv)
	if strings.Contains(first, "<svg") {
		t.Fatalf("a loopback bind drew a code: %s", first)
	}
	loopbackLink := linkOf(t, first)

	// The network comes up.
	dialable(srv)
	second := statusBody(t, srv)
	if !strings.Contains(second, "<svg") {
		t.Fatalf("a reachable address drew no code: %s", second)
	}
	lanLink := linkOf(t, second)
	if lanLink == loopbackLink {
		t.Fatal("the link kept the address it was built with, so the code points at loopback")
	}
	// And it is the same right, not a second one.
	if got := countLiveClaimTokens(t, srv); got != 1 {
		t.Fatalf("unspent claim tokens = %d, want 1: the address changed, the token must not", got)
	}
}

// The two situations behind one page state. A store that lost its ownership
// marker still holds a person and their whole conversation, and presenting the
// link there signs the device in AS them - so the page must not say "the first
// device to use it becomes the owner", which is the copy for an empty machine.
func TestAStoreThatHoldsSomebodySaysSoOnTheClaimPage(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	d, _ := claimDevice(t, ts, srv)
	ctx := context.Background()
	if err := srv.store.RevokeDevice(ctx, d.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	forgetOwnerOnDisk(t, srv)

	body := statusBody(t, srv)
	if !strings.Contains(body, "This server holds a conversation") {
		t.Fatalf("the page offers an empty machine's copy over a store that holds somebody: %s", body)
	}
	if strings.Contains(body, "becomes the owner of this server") {
		t.Fatalf("the page still promises ownership of an empty machine: %s", body)
	}
	// The link is still offered: this state is recoverable, not fatal.
	if !strings.Contains(body, "https://nox.app/p/#") {
		t.Fatalf("no way back in is offered: %s", body)
	}
}

// forgetOwnerOnDisk drops the ownership marker through a second handle on the
// same file - what a partial restore or a hand edit leaves behind.
func forgetOwnerOnDisk(t *testing.T, srv *Server) {
	t.Helper()
	handle, err := sql.Open("sqlite", srv.cfg.DBPath)
	if err != nil {
		t.Fatalf("open the database again: %v", err)
	}
	defer func() { _ = handle.Close() }()
	if _, err := handle.Exec("UPDATE server_identity SET owner_user_id = NULL WHERE id = 1"); err != nil {
		t.Fatalf("forget the owner: %v", err)
	}
}

// An owner who signed out on their last device is getting back in, not looking
// at a hand-edited database. The page and the startup line have to split the
// same three ways, or one of them tells the person the wrong story at the one
// moment they are reading it.
func TestAnOwnerWithNoDevicesIsNotToldTheirDatabaseWasEdited(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	d, _ := claimDevice(t, ts, srv)
	if err := srv.store.RevokeDevice(context.Background(), d.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}

	body := statusBody(t, srv)
	if !strings.Contains(body, "Your server is waiting for you") {
		t.Fatalf("the page does not recognise an owner getting back in: %s", body)
	}
	for _, wrong := range []string{"no normal sequence of events produces", "becomes the owner of this server"} {
		if strings.Contains(body, wrong) {
			t.Fatalf("the page tells the owner %q: %s", wrong, body)
		}
	}
}

// "Claimed" and "reachable" stopped being the same question. A store whose
// ownership marker is missing but whose devices still work is running normally,
// and the page must say so without claiming an owner it does not record.
func TestAReachableServerWithNoOwnerMarkerSaysWhatIsActuallyTrue(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	claimDevice(t, ts, srv)
	forgetOwnerOnDisk(t, srv)

	body := statusBody(t, srv)
	if strings.Contains(body, "Running and claimed") {
		t.Fatalf("the page claims an owner the store does not record: %s", body)
	}
	if !strings.Contains(body, "records no owner") {
		t.Fatalf("the page says nothing about the missing marker: %s", body)
	}
	// And no claim link: a device is paired, so Pair would refuse one anyway.
	if strings.Contains(body, "https://nox.app/p/#") {
		t.Fatalf("a link is offered that Pair would refuse: %s", body)
	}
}

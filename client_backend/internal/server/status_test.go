package server

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
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

// linkOf pulls the machine link out of the rendered page.
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

// linkTokenOnPage opens the page and returns the token of the link it shows.
func linkTokenOnPage(t *testing.T, srv *Server) string {
	t.Helper()
	return readLink(t, linkOf(t, statusBody(t, srv))).Token
}

// countLiveMachineLinks counts the machine links that could still be shown or
// presented - SC-004's "at most one".
func countLiveMachineLinks(t *testing.T, srv *Server) int {
	t.Helper()
	var n int
	if err := readDB(t, srv).QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pair_tokens WHERE kind = 'machine' AND used_at IS NULL").Scan(&n); err != nil {
		t.Fatalf("count machine links: %v", err)
	}
	return n
}

// postLink posts the page's link button as a browser on this machine would.
func postLink(t *testing.T, srv *Server, host, origin string, form url.Values) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/link", strings.NewReader(form.Encode()))
	req.Host = host
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, req)
	return rec
}

// expireLinks puts every unspent machine link's deadline in the past, the way
// ten minutes would.
func expireLinks(t *testing.T, srv *Server) {
	t.Helper()
	if _, err := readWriteDB(t, srv).ExecContext(context.Background(),
		"UPDATE pair_tokens SET expires_at = ? WHERE kind = 'machine' AND used_at IS NULL", time.Now().Unix()-1); err != nil {
		t.Fatalf("expire the machine links: %v", err)
	}
}

// dialable gives the test server an address a phone could reach.
//
// The harness binds 127.0.0.1:0, which the page correctly treats as "no phone
// can get here" - right in production, and it would leave every code-related
// test asserting about a page that deliberately draws none.
func dialable(srv *Server) {
	srv.cfg.Addr = "192.168.1.10:8080"
}

// FR-003, US2 scenario 1: a machine nobody can reach shows a link at once - the
// QR code, the link and its ten minutes - with no button to press first.
func TestAMachineWithNoDeviceShowsALinkAtOnce(t *testing.T) {
	_, srv := newTestServer(t)
	dialable(srv)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	body := statusBody(t, srv)
	// The page and the code beside it are how the first device learns which
	// key to expect in the channel. A link carrying anything else hands out a
	// server nobody can reach.
	got := readLink(t, linkOf(t, body))
	if !got.ServerKey.Equal(serverKeyOf(t, srv)) {
		t.Fatalf("the page's link carries %x, want this machine's key %x", got.ServerKey, serverKeyOf(t, srv))
	}
	if len(got.Direct) != 1 || got.Direct[0] != "192.168.1.10:8080" {
		t.Fatalf("the page's link names %v, want the address a phone can dial", got.Direct)
	}
	for _, want := range []string{"<svg", "Expires in 10 minutes", "Pair your first device"} {
		if !strings.Contains(body, want) {
			t.Fatalf("the page does not show %q: %s", want, body)
		}
	}
	if strings.Contains(body, "Add a device") {
		t.Fatal("a machine nobody can reach asks for a button press before showing a link")
	}
	// The one screen that must NOT redraw itself: a camera is reading it.
	if strings.Contains(body, `http-equiv="refresh"`) {
		t.Fatal("the QR page refreshes itself, which breaks the scan it exists for")
	}
}

// A reload shows the link the page already showed: the page mints once for a
// machine nobody can reach, never once per view (SC-004).
func TestAReloadShowsTheSameLink(t *testing.T) {
	_, srv := newTestServer(t)
	dialable(srv)
	first := linkOf(t, statusBody(t, srv))
	second := linkOf(t, statusBody(t, srv))
	if first != second {
		t.Fatal("two page loads handed out two different links")
	}
	if got := countLiveMachineLinks(t, srv); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1: the page minted another", got)
	}
}

// The service page's states, every one, from contracts/service-page-link.md:
// what each shows and - the load-bearing column - whether it hands out a live
// link at all.
func TestTheServicePageShowsEveryStateOfTheMachineLink(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		name    string
		arrange func(t *testing.T, ts *httptest.Server, srv *Server)
		want    []string
		notWant []string
		live    bool
	}{
		{
			name:    "no devices, the link is live",
			arrange: func(*testing.T, *httptest.Server, *Server) {},
			want:    []string{"Pair your first device", `class="link"`, "<svg", "Expires in 10 minutes", `class="copy"`},
			notWant: []string{"Add a device", "Running."},
			live:    true,
		},
		{
			name: "no devices, the link ran out",
			arrange: func(t *testing.T, _ *httptest.Server, srv *Server) {
				statusBody(t, srv) // the page mints the link on its first view
				expireLinks(t, srv)
			},
			want:    []string{"Pair your first device", "Link expired", "New link"},
			notWant: []string{`class="link"`, "<svg", "Expires in", "Add a device"},
			live:    false,
		},
		{
			name: "devices, no link asked for",
			arrange: func(t *testing.T, ts *httptest.Server, srv *Server) {
				firstDevice(t, ts, srv)
			},
			want:    []string{"NOX server", "Add a device", "Devices"},
			notWant: []string{`class="link"`, "<svg", "Link expired", "Expires in"},
			live:    false,
		},
		{
			name: "devices, the link is live",
			arrange: func(t *testing.T, ts *httptest.Server, srv *Server) {
				firstDevice(t, ts, srv)
				if _, err := srv.store.IssueMachineLink(ctx, time.Now().Unix()); err != nil {
					t.Fatalf("IssueMachineLink: %v", err)
				}
			},
			want:    []string{"NOX server", `class="link"`, "<svg", "Expires in 10 minutes"},
			notWant: []string{"Add a device"},
			live:    true,
		},
		{
			name: "devices, the link ran out",
			arrange: func(t *testing.T, ts *httptest.Server, srv *Server) {
				firstDevice(t, ts, srv)
				if _, err := srv.store.IssueMachineLink(ctx, time.Now().Unix()); err != nil {
					t.Fatalf("IssueMachineLink: %v", err)
				}
				expireLinks(t, srv)
			},
			want:    []string{"NOX server", "Link expired", "New link"},
			notWant: []string{`class="link"`, "<svg", "Add a device", "Expires in"},
			live:    false,
		},
		{
			name: "the person signed out of their last device",
			arrange: func(t *testing.T, ts *httptest.Server, srv *Server) {
				d, _ := firstDevice(t, ts, srv)
				if _, err := srv.store.RevokeDevice(ctx, d.pub, time.Now().Unix()); err != nil {
					t.Fatalf("RevokeDevice: %v", err)
				}
			},
			want:    []string{"No device can reach this server", "chats and messages", `class="link"`, "<svg", "Expires in 10 minutes"},
			notWant: []string{"Pair your first device", "Add a device"},
			live:    true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ts, srv := newTestServer(t)
			dialable(srv)
			// Startup mints the machine key before it ever draws a page.
			if _, err := srv.store.EnsureServerIdentity(ctx); err != nil {
				t.Fatalf("EnsureServerIdentity: %v", err)
			}
			tc.arrange(t, ts, srv)

			rec := statusResponse(t, srv)
			body := rec.Body.String()
			for _, want := range tc.want {
				if !strings.Contains(body, want) {
					t.Fatalf("the page does not show %q: %s", want, body)
				}
			}
			for _, wrong := range tc.notWant {
				if strings.Contains(body, wrong) {
					t.Fatalf("the page also shows %q, which belongs to another state: %s", wrong, body)
				}
			}
			// The script counts the live link down and is there for nothing
			// else, so it comes - and is admitted - with a live link only.
			if got := strings.Contains(body, "<script>"); got != tc.live {
				t.Fatalf("script on the page = %v, want %v", got, tc.live)
			}
			if got := strings.Contains(rec.Header().Get("Content-Security-Policy"), "script-src"); got != tc.live {
				t.Fatalf("the policy admits a script = %v, want %v", got, tc.live)
			}
		})
	}
}

// A live link carries its deadline for the countdown, and the expired state
// ships hidden beside it, so a page left open turns into `Link expired` with
// `New link` when the minutes run out - without minting anything (FR-002).
func TestALiveLinkCarriesItsDeadlineAndTheExpiredStateBesideIt(t *testing.T) {
	_, srv := newTestServer(t)
	page, err := srv.store.PageMachineLink(context.Background(), time.Now().Unix())
	if err != nil || !page.Found {
		t.Fatalf("PageMachineLink = %+v (%v)", page, err)
	}
	body := statusBody(t, srv)
	if !strings.Contains(body, fmt.Sprintf(`data-expires="%d"`, page.Link.ExpiresAt)) {
		t.Fatalf("the countdown does not carry the link's deadline %d: %s", page.Link.ExpiresAt, body)
	}
	if !strings.Contains(body, `<div class="expired" hidden>`) || !strings.Contains(body, `<div class="live">`) {
		t.Fatalf("the live link is not paired with a hidden expired state: %s", body)
	}
}

// ExpiresIn rounds up to the minute, the way the page and the terminal say it.
func TestExpiresInWordsTheMinutesLeft(t *testing.T) {
	for _, tc := range []struct {
		left int64
		want string
	}{
		{600, "Expires in 10 minutes"},
		{599, "Expires in 10 minutes"},
		{540, "Expires in 9 minutes"},
		{61, "Expires in 2 minutes"},
		{60, "Expires in 1 minute"},
		{1, "Expires in 1 minute"},
		{0, "Link expired"},
		{-5, "Link expired"},
	} {
		if got := ExpiresIn(1000+tc.left, 1000); got != tc.want {
			t.Errorf("ExpiresIn with %d s left = %q, want %q", tc.left, got, tc.want)
		}
	}
}

// listenAddress falls back to loopback under a wildcard bind - right for a link
// pasted on this machine, useless for the phone the code exists for.
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

// With devices the page shows the machine, and a link only once somebody asks
// for one: an open page does not hold a live link nobody wanted (decision 3).
func TestAMachineWithDevicesShowsAddADeviceAndNoLink(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	firstDevice(t, ts, srv)

	body := statusBody(t, srv)
	if strings.Contains(body, "nox://pair/") || strings.Contains(body, "<svg") {
		t.Fatalf("a machine with devices offers a link nobody asked for: %s", body)
	}
	if !strings.Contains(body, `action="/link"`) || !strings.Contains(body, "Add a device") {
		t.Fatalf("no Add a device on a machine with devices: %s", body)
	}
	for _, want := range []string{"Version", "Uptime", "Schema", "Storage id", "Database", "Devices", "Chats", "Messages"} {
		if !strings.Contains(body, want) {
			t.Fatalf("the page does not show %q: %s", want, body)
		}
	}
	// Nothing counts people: this machine holds exactly one, so the number
	// would say the same thing on every server that ever runs.
	if strings.Contains(body, "People") {
		t.Fatalf("the page counts people: %s", body)
	}
	if got := countLiveMachineLinks(t, srv); got != 0 {
		t.Fatalf("the page minted %d links over a machine with devices", got)
	}
}

// FR-015 through the wire: signing out of the last device puts the machine back
// to "no devices", and the page shows a link at once - even when the link the
// person asked for earlier ran out unused in the meantime.
func TestTheLastDeviceGoneShowsALinkAgain(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	dev, _ := firstDevice(t, ts, srv)
	if rec := postLink(t, srv, pageHost, pageOrigin, url.Values{"token": {srv.formToken}}); rec.Code != http.StatusSeeOther {
		t.Fatalf("Add a device = %d", rec.Code)
	}
	expireLinks(t, srv) // asked for, never used
	if body := statusBody(t, srv); !strings.Contains(body, "Link expired") {
		t.Fatalf("precondition: the page shows the link that ran out: %s", body)
	}

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
	c.expectOKAfter(2, fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, dev.pub))

	body := statusBody(t, srv)
	if !strings.Contains(body, "No device can reach this server") || !strings.Contains(body, "Expires in 10 minutes") {
		t.Fatalf("after the last device left the page does not show a live link at once: %s", body)
	}
	if strings.Contains(body, `<div class="expired">`) {
		t.Fatalf("the run-out link stands between the person and a fresh one: %s", body)
	}
}

// Principle I, and stricter here than for a log: a log is read by somebody who
// went to read it, a page is seen by whoever is standing near the monitor.
func TestThePageNamesNobodyAndShowsNoKeys(t *testing.T) {
	ts, srv := newTestServer(t)
	dev, data := firstDevice(t, ts, srv)
	var id identity
	mustUnmarshal(t, data["identity"], &id)

	c := dialAs(t, ts, srv, dev)
	c.expectGreeting()
	c.hello(1, "")
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

// FR-016: a lost device is revoked from a device the person holds, never from
// the page - so the page offers no way to, in any state.
func TestThePageHasNoRevocation(t *testing.T) {
	ts, srv := newTestServer(t)
	firstDevice(t, ts, srv)
	for _, body := range []string{statusBody(t, srv), pageAt(t, srv, "/?saved=onion")} {
		if strings.Contains(strings.ToLower(body), "revoke") {
			t.Fatalf("the page offers revocation: %s", body)
		}
	}
	for _, path := range []string{"/revoke", "/devices"} {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, path, nil)
		req.Host = pageHost
		srv.StatusHandler().ServeHTTP(rec, req)
		if rec.Code == http.StatusOK || rec.Code == http.StatusSeeOther {
			t.Fatalf("POST %s = %d, want no such route", path, rec.Code)
		}
	}
}

// The main listener is bound to every interface in an ordinary install. The
// page must live nowhere on it.
func TestTheMainListenerNeverServesTheServicePage(t *testing.T) {
	ts, srv := newTestServer(t)
	firstDevice(t, ts, srv)

	for _, path := range []string{"/", "/status", "/index.html"} {
		rec := httptest.NewRecorder()
		srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code == http.StatusOK && strings.Contains(rec.Body.String(), "<html") {
			t.Fatalf("the main listener serves the service page at %q", path)
		}
	}
	for _, path := range []string{"/link", controlLinkPath} {
		rec := httptest.NewRecorder()
		srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodPost, path, nil))
		if rec.Code == http.StatusOK || rec.Code == http.StatusSeeOther {
			t.Fatalf("the main listener answers POST %s with %d", path, rec.Code)
		}
	}
}

// A page for people must not change a machine's answer: OS services and the
// tunnel read this one. It moved to the page's listener with 044 - the main
// port answers nobody who has not proved a key - and its answer did not move.
func TestHealthAnswersExactlyWhatItAnswered(t *testing.T) {
	_, srv := newTestServer(t)
	main := httptest.NewRecorder()
	srv.Handler().ServeHTTP(main, httptest.NewRequest(http.MethodGet, "/health", nil))
	if main.Code != http.StatusNotFound {
		t.Fatalf("/health on the main mux = %d, want 404: it lives beside the service page", main.Code)
	}
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
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

// A link spent between two page loads must not come back: the device it paired
// is there, so the page offers Add a device - and after that device signs out,
// a fresh link rather than the burnt one.
func TestThePageStopsOfferingALinkThatHasBeenSpent(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	first := linkOf(t, statusBody(t, srv))

	dev, _ := pairDevice(t, ts, readLink(t, first).Token)
	if body := statusBody(t, srv); strings.Contains(body, "nox://pair/") {
		t.Fatalf("the page still offers the link the pairing spent: %s", body)
	}
	if _, err := srv.store.RevokeDevice(context.Background(), dev.pub, time.Now().Unix()); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	second := linkOf(t, statusBody(t, srv))
	if second == first {
		t.Fatal("the page offers the link the pairing already spent")
	}
	if got := countLiveMachineLinks(t, srv); got != 1 {
		t.Fatalf("unspent machine links = %d, want exactly the replacement", got)
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
	// And the LINK is still there: the app running on this machine pairs by
	// pasting it, and a loopback bind is the default.
	if !strings.Contains(body, "nox://pair/") {
		t.Fatalf("a loopback-bound server offers no link at all: %s", body)
	}
	if got := countLiveMachineLinks(t, srv); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1: a loopback bind must still issue one", got)
	}
}

// A separate socket keeps the network out; it does not keep the operator's own
// browser out. Any site can be rebound to 127.0.0.1 by DNS and read this page
// as same-origin - and the machine link with it.
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
	if got := countLiveMachineLinks(t, srv); got != 0 {
		t.Fatal("a refused request still minted a link")
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

// The link follows the address; only the token is kept.
//
// Caching the built link froze an address for the life of the process while
// "can a phone reach us" went on being recomputed — so a laptop whose network
// came up after the server did drew a QR over a link that still said
// 127.0.0.1, which is precisely the code this page refuses to draw.
func TestTheLinkFollowsTheAddressWhileTheTokenStaysPut(t *testing.T) {
	_, srv := newTestServer(t)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
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
	// And it is the same link, not a second one.
	if readLink(t, lanLink).Token != readLink(t, loopbackLink).Token {
		t.Fatal("the address changed, and so did the token")
	}
	if got := countLiveMachineLinks(t, srv); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1: the address changed, the token must not", got)
	}
}

// Add a device and New link (FR-003, SC-004): a new link, the one before it
// dead, back to the page - which shows the new one.
func TestTheLinkButtonIssuesANewLinkAndVoidsThePrevious(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	previous := linkTokenOnPage(t, srv)

	rec := postLink(t, srv, pageHost, pageOrigin, url.Values{"token": {srv.formToken}})
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/" {
		t.Fatalf("POST /link = %d to %q, want 303 to /", rec.Code, rec.Header().Get("Location"))
	}
	current := linkTokenOnPage(t, srv)
	if current == previous {
		t.Fatal("the button left the same link on the page")
	}
	if got := countLiveMachineLinks(t, srv); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1", got)
	}
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"linux"}}`, previous))
	if code := expectErrCode(t, c, 1); code != "invalid_token" {
		t.Fatalf("the link the button replaced = %q, want invalid_token", code)
	}
	pairDevice(t, ts, current)
}

// The button is a write through the page, held to the three checks Set is: a
// rebound name, another site's form, or a request that never saw the page gets
// 403, and nothing is minted - a link minted by another site's form would void
// the one somebody is scanning.
func TestTheLinkButtonRefusesAFormThatIsNotThePagesOwn(t *testing.T) {
	_, srv := newTestServer(t)
	good := url.Values{"token": {srv.formToken}}
	for _, tc := range []struct {
		name, host, origin string
		form               url.Values
	}{
		{"a host that is not this machine", "evil.example:8081", "http://evil.example:8081", good},
		{"no origin", pageHost, "", good},
		{"another site's origin", pageHost, "http://evil.example", good},
		{"a null origin", pageHost, "null", good},
		{"no token", pageHost, pageOrigin, url.Values{}},
		{"a wrong token", pageHost, pageOrigin, url.Values{"token": {strings.Repeat("0", 64)}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if rec := postLink(t, srv, tc.host, tc.origin, tc.form); rec.Code != http.StatusForbidden {
				t.Fatalf("POST /link = %d, want 403", rec.Code)
			}
			if got := countLiveMachineLinks(t, srv); got != 0 {
				t.Fatalf("a refused form minted %d links", got)
			}
		})
	}
}

// The page stays on plain HTTP while everything else moved to TLS.
//
// Not an oversight: its socket carries no network traffic by construction, so
// there is nothing in transit to protect - and a self-signed certificate there
// would teach an operator's browser to expect a warning on the one page whose
// job is to hand out a way in.
func TestTheServicePageIsStillPlainHTTPOnLoopback(t *testing.T) {
	_, srv := newTestServer(t)
	dialable(srv)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	// Its own listener, dialled without a certificate of any kind.
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	page := &http.Server{Handler: srv.StatusHandler(), ReadHeaderTimeout: pageReadHeaderTimeout}
	go func() { _ = page.Serve(listener) }()
	t.Cleanup(func() { _ = page.Close() })

	resp, err := http.Get("http://" + listener.Addr().String() + "/") //nolint:noctx // a page fetch
	if err != nil {
		t.Fatalf("the service page refused a plain request: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("service page = %d, want 200", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read the page: %v", err)
	}
	if !strings.Contains(string(body), "nox://pair/") {
		t.Fatalf("the page came back without its link: %s", body)
	}
}

// statusResponse fetches the page and hands back the recorder, so a test can
// read the headers as well as the body.
func statusResponse(t *testing.T, srv *Server) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Host = "127.0.0.1:8081"
	srv.StatusHandler().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status page = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	return rec
}

// The machine link is two lines of base64 nobody should have to select by hand.
func TestTheMachineLinkCanBeCopied(t *testing.T) {
	_, srv := newTestServer(t)
	dialable(srv)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	body := statusResponse(t, srv).Body.String()
	if !strings.Contains(body, `<button type="button" class="copy" hidden>`) {
		t.Fatalf("no copy button beside the link: %s", body)
	}
	// HIDDEN in the markup, revealed by the script. A control that does nothing
	// when pressed is worse than no control, and that is exactly what a page
	// whose script did not run would otherwise show.
	if !strings.Contains(body, `<script>`) {
		t.Fatal("the button is there but the script that reveals it is not")
	}
	// The feedback has to reach a screen reader, not only the eye.
	if !strings.Contains(body, `class="copied" role="status"`) {
		t.Fatal("the copy feedback is not announced")
	}
}

// The policy admits the script by HASH. This is the test that keeps the two
// from drifting: it hashes the script the page actually served and demands the
// header names that hash - so editing one without the other fails here rather
// than in a browser, silently, as a button that stopped working.
func TestThePolicyAdmitsExactlyTheScriptThePageServed(t *testing.T) {
	_, srv := newTestServer(t)
	dialable(srv)
	if _, err := srv.store.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	rec := statusResponse(t, srv)
	body := rec.Body.String()

	open := strings.Index(body, "<script>")
	closing := strings.Index(body, "</script>")
	if open < 0 || closing < open {
		t.Fatalf("no script on a page that carries a live link: %s", body)
	}
	served := body[open+len("<script>") : closing]

	sum := sha256.Sum256([]byte(served))
	want := "'sha256-" + base64.StdEncoding.EncodeToString(sum[:]) + "'"

	policy := rec.Header().Get("Content-Security-Policy")
	if !strings.Contains(policy, "script-src "+want) {
		t.Fatalf("the policy does not admit the script the page served.\n  served hash: %s\n  policy:      %s", want, policy)
	}
	// And nothing weaker. 'unsafe-inline' would admit an injected script too,
	// on the one page that hands out a way into this machine.
	if strings.Contains(policy, "unsafe-inline'; script") || strings.Contains(policy, "script-src 'unsafe-inline'") {
		t.Fatalf("the policy admits inline scripts wholesale: %s", policy)
	}
	// The script may read the link. It must have nowhere to send it.
	if !strings.HasPrefix(policy, "default-src 'none'") {
		t.Fatalf("default-src is no longer none, so the script has somewhere to send the link: %s", policy)
	}
}

// A page with no live link carries no script, and the policy says so rather
// than leaving a permission standing for something that is not there.
func TestAPageWithNoLinkCarriesNoScriptAndAdmitsNone(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	// A machine with a device and no link asked for: nothing to copy, nothing
	// to count down.
	firstDevice(t, ts, srv)

	rec := statusResponse(t, srv)
	if strings.Contains(rec.Body.String(), "<script>") {
		t.Fatal("a page with no link is carrying a script anyway")
	}
	if policy := rec.Header().Get("Content-Security-Policy"); strings.Contains(policy, "script-src") {
		t.Fatalf("no script on the page, but the policy still admits one: %s", policy)
	}
}

// The token travels in the page as the link and nowhere else: the page never
// writes it into a URL a browser keeps, and the forms name the process's form
// token, not the link's.
func TestTheLinkTokenAppearsOnlyInsideTheLink(t *testing.T) {
	_, srv := newTestServer(t)
	page, err := srv.store.PageMachineLink(context.Background(), time.Now().Unix())
	if err != nil || !page.Found {
		t.Fatalf("PageMachineLink = %+v (%v)", page, err)
	}
	body := statusBody(t, srv)
	// The link itself is taken out first: the token sits at a byte offset that
	// is a multiple of three inside it, so its base64 can show through the
	// link's own.
	rest := strings.Replace(body, linkOf(t, body), "", 1)
	if strings.Contains(rest, page.Link.Token) {
		t.Fatalf("the raw token is on the page outside the link: %s", rest)
	}
}

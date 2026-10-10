package server

import (
	"encoding/json"
	"html"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"regexp"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/store"
)

// The service page's Set (045, contracts/service-page-addresses.md).

const (
	pageHost   = "127.0.0.1:8081"
	pageOrigin = "http://" + pageHost
)

// postAddress posts the Set form as a browser on this machine would, with the
// Host and Origin given.
func postAddress(t *testing.T, srv *Server, host, origin string, form url.Values) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/addresses", strings.NewReader(form.Encode()))
	req.Host = host
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, req)
	return rec
}

// setForm is the form the page itself renders for kind.
func setForm(srv *Server, kind, value string) url.Values {
	return url.Values{"kind": {kind}, "value": {value}, "token": {srv.formToken}}
}

// pageAt fetches the page at a path that may carry the redirect's query.
func pageAt(t *testing.T, srv *Server, target string) string {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, target, nil)
	req.Host = pageHost
	srv.StatusHandler().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET %s = %d: %s", target, rec.Code, rec.Body.String())
	}
	return rec.Body.String()
}

func storedAddresses(t *testing.T, srv *Server) store.Addresses {
	t.Helper()
	got, err := srv.store.Addresses(t.Context())
	if err != nil {
		t.Fatalf("Addresses: %v", err)
	}
	return got
}

// The whole road, through a real listener and a real HTTP client: the page
// hands out its form, the form posts back with the page's own origin and
// token, and the next page - the code on it included - already names the new
// address (SC-003: "in the new QR code at once").
func TestSetFromThePageReachesTheNextCodeAtOnce(t *testing.T) {
	_, srv := newTestServerWith(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	page := httptest.NewServer(srv.StatusHandler())
	t.Cleanup(page.Close)
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

	resp, err := client.Get(page.URL + "/")
	if err != nil {
		t.Fatalf("GET the page: %v", err)
	}
	body, err := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if err != nil {
		t.Fatalf("read the page: %v", err)
	}
	m := regexp.MustCompile(`name="token" value="([0-9a-f]{64})"`).FindStringSubmatch(string(body))
	if m == nil {
		t.Fatalf("the page carries no form token: %s", body)
	}
	if n := strings.Count(string(body), `name="token"`); n < 2 || strings.Count(string(body), m[1]) != n {
		t.Fatalf("want the one process token in every form: %s", body)
	}

	form := url.Values{"kind": {"onion"}, "value": {testOnionAddr}, "token": {m[1]}}
	req, err := http.NewRequest(http.MethodPost, page.URL+"/addresses", strings.NewReader(form.Encode()))
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", page.URL)
	resp, err = client.Do(req)
	if err != nil {
		t.Fatalf("POST /addresses: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusSeeOther || resp.Header.Get("Location") != "/?saved=onion" {
		t.Fatalf("POST = %d to %q, want 303 to /?saved=onion", resp.StatusCode, resp.Header.Get("Location"))
	}

	after := pageAt(t, srv, "/?saved=onion")
	if !strings.Contains(after, "Saved. New links carry it, and connected devices get it now.") {
		t.Fatalf("the page does not confirm the save: %s", after)
	}
	if !strings.Contains(after, `value="`+testOnionAddr+`"`) {
		t.Fatalf("the onion field does not show the stored address: %s", after)
	}
	if got := readLink(t, linkOf(t, after)); !got.Onion.Equal(onionKeyOf(t, testOnionAddr)) {
		t.Fatalf("the next link names onion key %x, want the address just set", got.Onion)
	}
}

// SC-003, the other half: a device already greeted hears of the new address
// within five seconds, without reconnecting - and of its removal the same way.
func TestSetReachesAGreetedDeviceWithinFiveSeconds(t *testing.T) {
	ts, srv := newTestServerWith(t, func(s *Server) { s.addressPoll = time.Hour }) // the poll must not be what delivers it
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, "")

	waitFor := func(want addressSet) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			_, name, data := c.expectEvent()
			if name != "server.addresses" {
				continue
			}
			var got addressSet
			raw, err := json.Marshal(data)
			if err != nil {
				t.Fatalf("event payload: %v", err)
			}
			mustUnmarshal(t, raw, &got)
			if got.Onion == want.Onion && got.Public == want.Public {
				return
			}
		}
		t.Fatalf("no server.addresses with public=%q onion=%q within five seconds", want.Public, want.Onion)
	}

	start := time.Now()
	if rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, "onion", testOnionAddr+":443")); rec.Code != http.StatusSeeOther {
		t.Fatalf("Set = %d: %s", rec.Code, rec.Body.String())
	}
	waitFor(addressSet{Onion: testOnionAddr + ":443"})
	if rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, "public", "nox.example.org:8443")); rec.Code != http.StatusSeeOther {
		t.Fatalf("Set = %d: %s", rec.Code, rec.Body.String())
	}
	waitFor(addressSet{Onion: testOnionAddr + ":443", Public: "nox.example.org:8443"})
	if rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, "onion", "")); rec.Code != http.StatusSeeOther {
		t.Fatalf("Set empty = %d: %s", rec.Code, rec.Body.String())
	}
	waitFor(addressSet{Public: "nox.example.org:8443"})
	if took := time.Since(start); took > 5*time.Second {
		t.Fatalf("three changes took %v to arrive", took)
	}
}

// The three checks that decide whether the form is the page's own, each one a
// 403 with nothing written: a name rebound to this machine by DNS, a form on
// another site opened in this machine's browser, and a request that never saw
// the page.
func TestSetRefusesAFormThatIsNotThePagesOwn(t *testing.T) {
	_, srv := newTestServer(t)
	good := setForm(srv, "onion", testOnionAddr)
	noToken := url.Values{"kind": {"onion"}, "value": {testOnionAddr}}
	wrongToken := url.Values{"kind": {"onion"}, "value": {testOnionAddr}, "token": {strings.Repeat("0", 64)}}
	for _, tc := range []struct {
		name, host, origin string
		form               url.Values
	}{
		{"a host that is not this machine", "evil.example:8081", "http://evil.example:8081", good},
		{"a host that merely resolves here", "nox.local:8081", "http://nox.local:8081", good},
		{"no origin", pageHost, "", good},
		{"another site's origin", pageHost, "http://evil.example", good},
		{"the right host over another scheme", pageHost, "https://" + pageHost, good},
		{"another port on this machine", pageHost, "http://127.0.0.1:9999", good},
		{"a null origin", pageHost, "null", good},
		{"no token", pageHost, pageOrigin, noToken},
		{"a wrong token", pageHost, pageOrigin, wrongToken},
		{"an empty token", pageHost, pageOrigin, url.Values{"kind": {"onion"}, "value": {testOnionAddr}, "token": {""}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if rec := postAddress(t, srv, tc.host, tc.origin, tc.form); rec.Code != http.StatusForbidden {
				t.Fatalf("Set = %d, want 403", rec.Code)
			}
			if got := storedAddresses(t, srv); got != (store.Addresses{}) {
				t.Fatalf("a refused form wrote %+v", got)
			}
		})
	}

	// The token counts only in the body: a link can carry a query string.
	req := httptest.NewRequest(http.MethodPost, "/addresses?token="+srv.formToken,
		strings.NewReader(url.Values{"kind": {"onion"}, "value": {testOnionAddr}}.Encode()))
	req.Host = pageHost
	req.Header.Set("Origin", pageOrigin)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden || storedAddresses(t, srv) != (store.Addresses{}) {
		t.Fatalf("a token in the URL was believed: %d", rec.Code)
	}
}

// Past the three checks, the form itself: a kind that is neither address is a
// 400, and an address that does not check out sends the person back with
// nothing written - the redirect naming the kind, never the value.
func TestSetRefusesAnUnknownKindAndAMalformedAddress(t *testing.T) {
	_, srv := newTestServer(t)
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	before := storedAddresses(t, srv)

	if rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, "direct", "192.168.1.20:8443")); rec.Code != http.StatusBadRequest {
		t.Fatalf("an unknown kind = %d, want 400", rec.Code)
	}
	name := []byte(strings.TrimSuffix(testOnionAddr, ".onion"))
	name[10] = 'a'
	for _, tc := range []struct{ kind, value, notice string }{
		{"onion", string(name) + ".onion", "That isn't a valid onion address. Nothing was changed."},
		{"onion", testOnionAddr + ":80", "That isn't a valid onion address. Nothing was changed."},
		{"public", "nox.example.org", "That isn't a valid address. Use host:port, like nox.example.org:8443. Nothing was changed."},
	} {
		rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, tc.kind, tc.value))
		if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/?invalid="+tc.kind {
			t.Fatalf("%s %q = %d to %q, want 303 to /?invalid=%s", tc.kind, tc.value, rec.Code, rec.Header().Get("Location"), tc.kind)
		}
		if got := storedAddresses(t, srv); got != before {
			t.Fatalf("%s %q moved %+v to %+v", tc.kind, tc.value, before, got)
		}
		// The page escapes the apostrophe; the words are what is asserted.
		if body := html.UnescapeString(pageAt(t, srv, rec.Header().Get("Location"))); !strings.Contains(body, tc.notice) {
			t.Fatalf("the page after %s %q does not say %q", tc.kind, tc.value, tc.notice)
		}
	}
}

// An empty field and Set delete the address, and the page says so in words
// that fit a deletion.
func TestAnEmptySetDeletesTheAddress(t *testing.T) {
	_, srv := newTestServer(t)
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	setStored(t, srv, store.AddressPublic, "nox.example.org:8443")

	rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, "onion", "  "))
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "/?saved=onion" {
		t.Fatalf("Set empty = %d to %q", rec.Code, rec.Header().Get("Location"))
	}
	if got := storedAddresses(t, srv); got.Onion != "" || got.Public != "nox.example.org:8443" {
		t.Fatalf("after deleting the onion address: %+v", got)
	}
	if body := pageAt(t, srv, "/?saved=onion"); !strings.Contains(body, "Removed. New links no longer carry it") {
		t.Fatalf("the page does not confirm the removal: %s", body)
	}
}

// A Set never puts the onion address in the log (FR-022).
func TestSetKeepsTheOnionAddressOutOfTheLog(t *testing.T) {
	logs := &syncBuffer{}
	_, srv := newTestServerLogging(t, slog.New(slog.NewTextHandler(logs, nil)))
	if rec := postAddress(t, srv, pageHost, pageOrigin, setForm(srv, "onion", testOnionAddr)); rec.Code != http.StatusSeeOther {
		t.Fatalf("Set = %d", rec.Code)
	}
	if !strings.Contains(logs.String(), "address set on the service page") {
		t.Fatalf("the Set left no line in the log:\n%s", logs.String())
	}
	if strings.Contains(logs.String(), strings.TrimSuffix(testOnionAddr, ".onion")) {
		t.Fatalf("the onion address reached the log:\n%s", logs.String())
	}
}

// What the page shows: the addresses found on the machine's networks, read
// only; the two stored ones in their fields; one form token for both; and the
// headers the forms depend on.
func TestThePageShowsTheAddressesAndItsForms(t *testing.T) {
	_, srv := newTestServerWith(t, func(s *Server) {
		s.cfg.Addr = "0.0.0.0:8443"
		s.listIPs = ips("192.168.1.20", "10.0.0.5")
	})
	setStored(t, srv, store.AddressPublic, "nox.example.org:8443")
	srv.refreshAddresses(t.Context())

	rec := statusResponse(t, srv)
	body := rec.Body.String()
	for _, want := range []string{
		"Found on this machine's networks", "<code>192.168.1.20:8443</code>", "<code>10.0.0.5:8443</code>",
		"Public address", "Onion address", `value="nox.example.org:8443"`,
		`action="/addresses"`, `name="kind" value="public"`, `name="kind" value="onion"`,
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("the page does not show %q: %s", want, body)
		}
	}
	if n := strings.Count(body, `name="token"`); n < 2 || strings.Count(body, `name="token" value="`+srv.formToken+`"`) != n {
		t.Fatalf("every form must carry the process's token: %s", body)
	}
	if policy := rec.Header().Get("Content-Security-Policy"); !strings.Contains(policy, "form-action 'self'") {
		t.Fatalf("the policy lets the forms post elsewhere: %s", policy)
	}
	// Under no-referrer a browser posts the form with Origin: null, and the
	// Origin check would refuse every honest Set.
	if got := rec.Header().Get("Referrer-Policy"); got != "same-origin" {
		t.Fatalf("Referrer-Policy = %q, want same-origin", got)
	}
}

// A start parameter that was not applied is named on the page, with what the
// server runs on instead - the address it holds NOW.
func TestThePageNamesAStartParameterThatWasNotApplied(t *testing.T) {
	_, srv := newTestServer(t)
	srv.addrWarnings = []addressWarning{{Kind: store.AddressOnion}}

	if body := statusBody(t, srv); !strings.Contains(body,
		"-onion-addr is not a valid onion address. The server keeps no onion address.") {
		t.Fatalf("no warning for the refused parameter: %s", body)
	}
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	body := statusBody(t, srv)
	if !strings.Contains(body, "-onion-addr is not a valid onion address. The server keeps "+testOnionAddr+".") {
		t.Fatalf("the warning does not name the address the server keeps: %s", body)
	}
	if strings.Contains(body, "-public-addr is not") {
		t.Fatal("the page warns about a parameter nobody refused")
	}
}

// The Set lives on the page's loopback listener and nowhere else: the main
// port, bound to every interface in an ordinary install, has no form to post
// to - not even for a device that proved its key.
func TestTheMainPortHasNoSetForm(t *testing.T) {
	ts, srv := newTestServer(t)
	firstDevice(t, ts, srv)
	resp, err := ts.Client().PostForm(ts.URL+"/addresses", setForm(srv, "onion", testOnionAddr))
	if err != nil {
		t.Fatalf("POST /addresses on the main port: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound && resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("POST /addresses on the main port = %d, want no such route", resp.StatusCode)
	}
	if got := storedAddresses(t, srv); got != (store.Addresses{}) {
		t.Fatalf("the main port wrote %+v", got)
	}
}

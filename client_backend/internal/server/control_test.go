package server

import (
	"context"
	"crypto/ed25519"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"rsc.io/qr"
)

// `noxd link` (046, FR-001): POST /control/link on the service page's
// listener, and the command's side of it.

// controlRequest is POST /control/link as a program on this machine sends it,
// with tweak applied first.
func controlRequest(t *testing.T, srv *Server, tweak func(*http.Request)) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, controlLinkPath, nil)
	req.Host = pageHost
	req.Header.Set(controlHeader, "1")
	if tweak != nil {
		tweak(req)
	}
	rec := httptest.NewRecorder()
	srv.StatusHandler().ServeHTTP(rec, req)
	return rec
}

// The command's request gets the link and its deadline - a version-3 link
// carrying this machine's key, ten minutes to live - and the live link before
// it stops working: at most one at a time (SC-004).
func TestTheControlEndpointHandsTheTerminalANewLink(t *testing.T) {
	ts, srv := newTestServer(t)
	dialable(srv)
	previous := linkTokenOnPage(t, srv)

	rec := controlRequest(t, srv, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST %s = %d: %s", controlLinkPath, rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q: the answer is a link, and nothing on the way may keep it", got)
	}
	var reply MachineLinkReply
	if err := json.Unmarshal(rec.Body.Bytes(), &reply); err != nil {
		t.Fatalf("the answer is not JSON: %v (%s)", err, rec.Body.String())
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &keys); err != nil || len(keys) != 2 {
		t.Fatalf("the answer carries %v, want exactly link and expires_at", keys)
	}
	link := readLink(t, reply.Link)
	if !link.ServerKey.Equal(serverKeyOf(t, srv)) {
		t.Fatal("the link names another machine's key")
	}
	if left := reply.ExpiresAt - time.Now().Unix(); left < 595 || left > 600 {
		t.Fatalf("expires_at is %d s away, want ten minutes", left)
	}
	if got := countLiveMachineLinks(t, srv); got != 1 {
		t.Fatalf("unspent machine links = %d, want 1", got)
	}
	// The page shows the terminal's link now, and the one it showed is dead.
	if linkTokenOnPage(t, srv) != link.Token {
		t.Fatal("the page still shows the link the terminal replaced")
	}
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.send(`{"id":1,"cmd":"pair","data":{"token":"` + previous + `","platform":"linux"}}`)
	if code := expectErrCode(t, c, 1); code != "invalid_token" {
		t.Fatalf("the replaced link = %q, want invalid_token", code)
	}
	pairDevice(t, ts, link.Token)
}

// What a page on another site can make a browser on this machine send is
// refused, and nothing is minted: a request with an Origin - any Origin - one
// without the header (a plain form or fetch), and one naming another host (a
// site rebound to 127.0.0.1 by DNS). A GET finds no such page.
func TestTheControlEndpointRefusesWhatABrowserCanSend(t *testing.T) {
	_, srv := newTestServer(t)
	for _, tc := range []struct {
		name  string
		tweak func(*http.Request)
		want  int
	}{
		{"another site's origin", func(r *http.Request) { r.Header.Set("Origin", "http://evil.example") }, http.StatusForbidden},
		{"this page's own origin", func(r *http.Request) { r.Header.Set("Origin", pageOrigin) }, http.StatusForbidden},
		{"a null origin", func(r *http.Request) { r.Header.Set("Origin", "null") }, http.StatusForbidden},
		{"an empty origin", func(r *http.Request) { r.Header["Origin"] = []string{""} }, http.StatusForbidden},
		{"no control header", func(r *http.Request) { r.Header.Del(controlHeader) }, http.StatusForbidden},
		{"the header saying something else", func(r *http.Request) { r.Header.Set(controlHeader, "true") }, http.StatusForbidden},
		{"a host that is not this machine", func(r *http.Request) { r.Host = "evil.example:8081" }, http.StatusForbidden},
		{"a name that merely resolves here", func(r *http.Request) { r.Host = "nox.local:8081" }, http.StatusForbidden},
		// The page's own GET / catches every other GET, and answers a path it
		// does not know with a 404 before it reads anything.
		{"a GET", func(r *http.Request) { r.Method = http.MethodGet }, http.StatusNotFound},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rec := controlRequest(t, srv, tc.tweak)
			if rec.Code != tc.want {
				t.Fatalf("status = %d, want %d", rec.Code, tc.want)
			}
			if strings.Contains(rec.Body.String(), "nox://pair/") {
				t.Fatalf("a refused request was handed a link: %s", rec.Body.String())
			}
			if got := countLiveMachineLinks(t, srv); got != 0 {
				t.Fatalf("a refused request minted %d links", got)
			}
		})
	}
}

// The command end to end against the page's real listener: it gets a link the
// server will accept, and says where it looked when nobody answers.
func TestTheLinkCommandTalksToTheRunningServer(t *testing.T) {
	ts, srv := newTestServer(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	page := &http.Server{Handler: srv.StatusHandler(), ReadHeaderTimeout: pageReadHeaderTimeout}
	go func() { _ = page.Serve(listener) }()
	t.Cleanup(func() { _ = page.Close() })

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	got, err := RequestMachineLink(ctx, listener.Addr().String())
	if err != nil {
		t.Fatalf("RequestMachineLink: %v", err)
	}
	if _, paired := pairDevice(t, ts, readLink(t, got.Link).Token); paired["identity"] == nil {
		t.Fatal("the terminal's link did not pair")
	}

	closed := freeAddr(t)
	if _, err := RequestMachineLink(ctx, closed); err == nil || !strings.Contains(err.Error(), "is noxd running") {
		t.Fatalf("with nobody listening = %v, want the question of whether noxd is running", err)
	}
}

// -qr draws no code for a link only the app on this machine can follow - the
// page draws none either - and draws one whenever the link names anything
// another device could reach.
func TestOnlyALinkToThisMachineGoesWithoutACode(t *testing.T) {
	key := make(ed25519.PublicKey, ed25519.PublicKeySize)
	token := strings.Repeat("A", 22)
	build := func(direct []string, onion ed25519.PublicKey) string {
		t.Helper()
		link, err := BuildPairingLink(key, token, direct, onion)
		if err != nil {
			t.Fatalf("BuildPairingLink: %v", err)
		}
		return link
	}
	onion := onionKeyOf(t, testOnionAddr)
	for _, tc := range []struct {
		name string
		link string
		only bool
	}{
		{"IPv4 loopback", build([]string{"127.0.0.1:8080"}, nil), true},
		{"IPv6 loopback", build([]string{"[::1]:8080"}, nil), true},
		{"localhost", build([]string{"localhost:8080"}, nil), true},
		{"a home address", build([]string{"192.168.1.10:8080"}, nil), false},
		{"a public name before loopback", build([]string{"nox.example.org:8443", "127.0.0.1:8080"}, nil), false},
		{"loopback and an onion service", build([]string{"127.0.0.1:8080"}, onion), false},
		{"not a link at all", "nox://pair/garbage", false},
	} {
		if got := LinkReachesOnlyThisMachine(tc.link); got != tc.only {
			t.Errorf("%s: LinkReachesOnlyThisMachine = %v, want %v", tc.name, got, tc.only)
		}
	}
}

// The terminal code (049 T001): two rows of modules per line in ▀ ▄ █ and
// blank, the light modules drawn, a quiet zone of four modules all round - and
// it reads back as exactly the code the library encodes.
func TestTheTerminalCodeReadsBackAsTheCode(t *testing.T) {
	link := "nox://pair/" + strings.Repeat("Ab0_-", 24)
	text, err := QRText(link)
	if err != nil {
		t.Fatalf("QRText: %v", err)
	}
	code, err := qr.Encode(link, qr.M)
	if err != nil {
		t.Fatalf("qr.Encode: %v", err)
	}
	side := code.Size + 2*qrQuietZone
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	if want := (side + 1) / 2; len(lines) != want {
		t.Fatalf("%d lines, want %d: two module rows per line", len(lines), want)
	}
	if side > 80 {
		t.Fatalf("the code is %d characters wide, more than a terminal shows", side)
	}
	light := func(x, y int) bool {
		x, y = x-qrQuietZone, y-qrQuietZone
		if x < 0 || y < 0 || x >= code.Size || y >= code.Size {
			return true
		}
		return !code.Black(x, y)
	}
	for i, line := range lines {
		if n := utf8.RuneCountInString(line); n != side {
			t.Fatalf("line %d is %d characters, want %d", i, n, side)
		}
		for x, r := range []rune(line) {
			var top, bottom bool
			switch r {
			case '█':
				top, bottom = true, true
			case '▀':
				top = true
			case '▄':
				bottom = true
			case ' ':
			default:
				t.Fatalf("line %d holds %q, which is not a block or a blank", i, r)
			}
			y := 2 * i
			if top != light(x, y) || bottom != light(x, y+1) {
				t.Fatalf("line %d column %d = %q does not match the code's modules", i, x, r)
			}
		}
	}
	// The quiet zone, said outright: four light modules on every side - two
	// whole lines at the top and at the bottom, four cells at each end of every
	// line. It is how a scanner finds the code.
	full := strings.Repeat("█", side)
	for _, i := range []int{0, 1, len(lines) - 2, len(lines) - 1} {
		if lines[i] != full {
			t.Fatalf("line %d is not quiet zone: %q", i, lines[i])
		}
	}
	edge := strings.Repeat("█", qrQuietZone)
	for i, line := range lines {
		if !strings.HasPrefix(line, edge) || !strings.HasSuffix(line, edge) {
			t.Fatalf("line %d lacks the quiet zone at its ends: %q", i, line)
		}
	}
}

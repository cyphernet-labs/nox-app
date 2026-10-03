package server

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/tor"
)

// The tests in this file go through the REAL Tor network: a real supervisor
// publishes the onion service and a second tor plays the device. They run
// only when NOX_TOR_TEST_BIN names a tor (0.4.9+), and take minutes - the
// network has to be joined and the descriptor published.
//
// What they cannot reach is said where it applies: claim over onion is
// impossible by construction on a real network (an unclaimed server has no
// key, so no service), and is covered on the onion entry in
// onion_entry_test.go - the same code path without the minutes.

func torTestBin(t *testing.T) string {
	t.Helper()
	bin := os.Getenv("NOX_TOR_TEST_BIN")
	if bin == "" {
		t.Skip("NOX_TOR_TEST_BIN is not set: these tests need a tor binary and the Tor network")
	}
	return bin
}

// liveStack is the server with a real supervisor behind its onion entry.
type liveStack struct {
	ts   *httptest.Server
	srv  *Server
	sup  *tor.Supervisor
	logs *syncLog
	fp   string
	stop func()
}

func startLive(t *testing.T, dbPath string) *liveStack {
	t.Helper()
	bin := torTestBin(t)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	logs := &syncLog{}
	logger := newTextLogger(logs)
	var sup *tor.Supervisor
	ts, srv, closeAll := openStack(t, dbPath, logger, func(s *Server) {
		seed, err := s.store.OnionSeed(context.Background())
		if err != nil {
			t.Fatalf("OnionSeed: %v", err)
		}
		sup, err = tor.New(tor.Config{
			Bin:       bin,
			DataDir:   filepath.Join(t.TempDir(), "tor"),
			Seed:      seed,
			Target:    ln.Addr().String(),
			Keys:      s.activeKeys,
			OnOffered: s.pokeAddresses,
			Logger:    logger.With("component", "tor"),
		})
		if err != nil {
			t.Fatalf("tor.New: %v", err)
		}
		s.tor = sup
	})
	tlsCfg, err := srv.serverTLSConfig(context.Background())
	if err != nil {
		t.Fatalf("serverTLSConfig: %v", err)
	}
	onion := httptest.NewUnstartedServer(srv.Handler())
	_ = onion.Listener.Close()
	onion.Listener = ln
	onion.TLS = tlsCfg
	onion.Config.ConnContext = markOnionConn
	onion.Config.ErrorLog = log.New(io.Discard, "", 0)
	onion.StartTLS()

	torCtx, stopTor := context.WithCancel(context.Background())
	torDone := make(chan struct{})
	go func() {
		defer close(torDone)
		sup.Run(torCtx)
	}()
	identity, err := srv.store.ServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}
	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		onion.Close()
		closeAll()
		stopTor()
		<-torDone
	}
	t.Cleanup(stop)
	return &liveStack{ts: ts, srv: srv, sup: sup, logs: logs, fp: identity.Fingerprint, stop: stop}
}

func (l *liveStack) waitPublished(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(4 * time.Minute)
	for time.Now().Before(deadline) {
		st := l.sup.Status()
		if st.Phase == tor.PhaseRunning && st.Publication == tor.PublicationPublished && l.sup.ReadyForInvite() {
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
	t.Fatalf("the onion service was not published in time: %+v", l.sup.Status())
}

// clientTor is a second tor, playing the device.
type clientTor struct {
	t     *testing.T
	ctl   *tor.Conn
	socks string
	cmd   *exec.Cmd
}

func startClientTor(t *testing.T) *clientTor {
	t.Helper()
	bin := torTestBin(t)
	dir := filepath.Join(t.TempDir(), "client-tor")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	torrc := filepath.Join(dir, "torrc")
	if err := os.WriteFile(torrc, nil, 0o600); err != nil {
		t.Fatalf("torrc: %v", err)
	}
	portFile := filepath.Join(dir, "control.port")
	cmd := exec.Command(bin, "-f", torrc, "--defaults-torrc", torrc, "--DataDirectory", dir,
		"--SocksPort", "auto", "--ControlPort", "auto", "--ControlPortWriteToFile", portFile,
		"--CookieAuthentication", "1", "--ClientOnly", "1",
		"--__OwningControllerProcess", strconv.Itoa(os.Getpid()), "--Log", "notice file "+filepath.Join(dir, "tor.log"))
	if err := cmd.Start(); err != nil {
		t.Fatalf("start client tor: %v", err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	})
	var addr string
	for range 600 {
		if raw, err := os.ReadFile(portFile); err == nil && strings.HasPrefix(string(raw), "PORT=") {
			addr = strings.TrimSpace(strings.TrimPrefix(string(raw), "PORT="))
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if addr == "" {
		t.Fatal("the client tor opened no control port")
	}
	ctx := context.Background()
	ctl, err := tor.Dial(ctx, addr)
	if err != nil {
		t.Fatalf("dial client control: %v", err)
	}
	t.Cleanup(func() { _ = ctl.Close() })
	cookie, err := os.ReadFile(filepath.Join(dir, "control_auth_cookie"))
	if err != nil {
		t.Fatalf("cookie: %v", err)
	}
	if err := ctl.Authenticate(ctx, cookie); err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	deadline := time.Now().Add(4 * time.Minute)
	for {
		v, err := ctl.GetInfo(ctx, "status/bootstrap-phase")
		if err == nil && strings.Contains(v, "PROGRESS=100") {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the client tor did not bootstrap: %q %v", v, err)
		}
		time.Sleep(time.Second)
	}
	listeners, err := ctl.GetInfo(ctx, "net/listeners/socks")
	if err != nil {
		t.Fatalf("socks listener: %v", err)
	}
	return &clientTor{t: t, ctl: ctl, socks: strings.Trim(strings.Fields(listeners)[0], `"`), cmd: cmd}
}

// authorize makes the client present privB64 for the onion address.
func (c *clientTor) authorize(addr, privB64 string) {
	c.t.Helper()
	if _, err := c.ctl.Command(context.Background(), "ONION_CLIENT_AUTH_ADD "+addr+" x25519:"+privB64); err != nil {
		c.t.Fatalf("ONION_CLIENT_AUTH_ADD: %v", err)
	}
}

func (c *clientTor) forget(addr string) {
	c.t.Helper()
	_, _ = c.ctl.Command(context.Background(), "ONION_CLIENT_AUTH_REMOVE "+addr)
}

// httpClient goes through the client tor with the server's pin.
func (c *clientTor) httpClient(fingerprint string) *http.Client {
	proxy, _ := url.Parse("socks5://" + c.socks)
	return &http.Client{Timeout: 2 * time.Minute, Transport: &http.Transport{
		Proxy:           http.ProxyURL(proxy),
		TLSClientConfig: PinnedTLSConfig(fingerprint),
	}}
}

func newAccessKey(t *testing.T) (*ecdh.PrivateKey, string, string) {
	t.Helper()
	k, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("x25519: %v", err)
	}
	return k, base64.StdEncoding.EncodeToString(k.PublicKey().Bytes()), base64.StdEncoding.EncodeToString(k.Bytes())
}

// dialOnion opens the WebSocket through the client tor, retrying while the
// descriptor propagates.
func dialOnion(t *testing.T, c *clientTor, l *liveStack, within time.Duration) *wsClient {
	t.Helper()
	target := "https://" + l.sup.Address() + ".onion:443/ws"
	deadline := time.Now().Add(within)
	var lastErr error
	for time.Now().Before(deadline) {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		conn, _, err := websocket.Dial(ctx, target, &websocket.DialOptions{HTTPClient: c.httpClient(l.fp)})
		if err == nil {
			conn.SetReadLimit(1 << 20)
			t.Cleanup(cancel)
			t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "") })
			return &wsClient{t: t, conn: conn, ctx: ctx, srv: l.srv}
		}
		cancel()
		lastErr = err
		time.Sleep(3 * time.Second)
	}
	t.Fatalf("no onion connection within %v: %v", within, lastErr)
	return nil
}

// onionRefused reports whether a fresh connection through the client tor is
// refused - every attempt up to n, each from a new circuit.
func onionRefused(c *clientTor, l *liveStack, n int) bool {
	client := c.httpClient(l.fp)
	client.Timeout = 90 * time.Second
	for range n {
		resp, err := client.Get("https://" + l.sup.Address() + ".onion:443/health")
		if err == nil {
			_ = resp.Body.Close()
			return false
		}
	}
	return true
}

func claimWithKey(t *testing.T, l *liveStack, accessPub string) *device {
	t.Helper()
	d := newDevice(t)
	c := dialWS(t, l.ts, l.srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test","access_key":%q}}`,
		mustClaimToken(t, l.srv), d.pub, accessPub))
	c.expectOK(1)
	return d
}

func TestOnionReach(t *testing.T) {
	l := startLive(t, filepath.Join(t.TempDir(), "reach.db"))
	_, k1Pub, k1Priv := newAccessKey(t)
	d := claimWithKey(t, l, k1Pub)
	l.waitPublished(t)

	client := startClientTor(t)
	client.authorize(l.sup.Address(), k1Priv)
	c := dialOnion(t, client, l, 3*time.Minute)
	c.expectGreeting()
	hello := c.greet(t, 1, d, "")
	var addrs addressSet
	mustUnmarshal(t, hello["addresses"], &addrs)
	if addrs.Onion != l.sup.Address()+".onion:443" {
		t.Fatalf("addresses.onion = %q", addrs.Onion)
	}

	// A message and a file, both through Tor (SC-001).
	c.send(`{"id":2,"cmd":"chat.create","data":{"name":"over tor"}}`)
	chat := c.expectOK(2)
	var created struct {
		ChatID string `json:"chat_id"`
	}
	mustUnmarshal(t, chat["chat"], &created)
	chatID := created.ChatID
	c.send(fmt.Sprintf(`{"id":3,"cmd":"message.send","data":{"chat_id":%q,"client_message_id":"m1","body":{"type":"text","text":"hello through tor"}}}`, chatID))
	c.expectOK(3)

	payload := bytes.Repeat([]byte("onion-bytes-"), 4096)
	c.send(fmt.Sprintf(`{"id":4,"cmd":"file.uploadBegin","data":{"name":"t.bin","size":%d,"mime":"application/octet-stream"}}`, len(payload)))
	up := c.expectOK(4)
	var upURL, fileID string
	mustUnmarshal(t, up["upload_url"], &upURL)
	mustUnmarshal(t, up["file_id"], &fileID)
	httpc := client.httpClient(l.fp)
	base := "https://" + l.sup.Address() + ".onion:443"
	req, _ := http.NewRequest(http.MethodPut, base+upURL, bytes.NewReader(payload))
	resp, err := httpc.Do(req)
	if err != nil {
		t.Fatalf("PUT over tor: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		t.Fatalf("PUT over tor = %d", resp.StatusCode)
	}
	c.send(fmt.Sprintf(`{"id":5,"cmd":"file.downloadBegin","data":{"file_id":%q}}`, fileID))
	down := c.expectOK(5)
	var downURL string
	mustUnmarshal(t, down["download_url"], &downURL)
	got, err := httpc.Get(base + downURL)
	if err != nil {
		t.Fatalf("GET over tor: %v", err)
	}
	body, _ := io.ReadAll(got.Body)
	_ = got.Body.Close()
	if !bytes.Equal(body, payload) {
		t.Fatalf("downloaded %d bytes that differ from the %d uploaded", len(body), len(payload))
	}

	// The log knows nothing it must not (SC-012).
	logs := l.logs.String()
	for _, secret := range []string{l.sup.Address(), k1Pub, k1Priv} {
		if strings.Contains(logs, secret) {
			t.Fatalf("the log carries %q", secret[:12])
		}
	}

	// Same database, new process: same address (SC-003).
	before := l.sup.Address()
	dbPath := l.srv.cfg.DBPath
	l.stop()
	again := startLive(t, dbPath)
	if again.sup.Address() != before {
		t.Fatalf("the onion address changed across a restart: %s -> %s", before, again.sup.Address())
	}
}

func TestOnionAccess(t *testing.T) {
	l := startLive(t, filepath.Join(t.TempDir(), "access.db"))
	_, k1Pub, _ := newAccessKey(t)
	owner := claimWithKey(t, l, k1Pub)
	l.waitPublished(t)

	// No key: twenty fresh attempts, not one connection (SC-002).
	stranger := startClientTor(t)
	if !onionRefused(stranger, l, 20) {
		t.Fatal("a client without a key reached the onion service")
	}

	// A second device with its own key gets in, and loses its way the moment
	// it is revoked (SC-004).
	ownerConn := dialWS(t, l.ts, l.srv)
	ownerConn.expectGreeting()
	ownerConn.greet(t, 1, owner, "")
	_, k2Pub, k2Priv := newAccessKey(t)
	ownerConn.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	inv := ownerConn.expectOK(2)
	var token string
	mustUnmarshal(t, inv["token"], &token)
	second := newDevice(t)
	pc := dialWS(t, l.ts, l.srv)
	pc.expectGreeting()
	pc.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test","access_key":%q}}`, token, second.pub, k2Pub))
	pc.expectOK(1)

	device := startClientTor(t)
	device.authorize(l.sup.Address(), k2Priv)
	oc := dialOnion(t, device, l, 3*time.Minute)
	oc.expectGreeting()
	oc.greet(t, 1, second, "")

	ownerConn.send(fmt.Sprintf(`{"id":3,"cmd":"device.revoke","data":{"device_key":%q}}`, second.pub))
	ownerConn.expectOK(3)
	deadline := time.Now().Add(time.Minute)
	for !onionRefused(device, l, 1) {
		if time.Now().After(deadline) {
			t.Fatal("the revoked device still opens onion connections a minute after its revocation")
		}
		time.Sleep(2 * time.Second)
	}
}

func TestOnionInvite(t *testing.T) {
	l := startLive(t, filepath.Join(t.TempDir(), "invite.db"))
	_, k1Pub, _ := newAccessKey(t)
	owner := claimWithKey(t, l, k1Pub)
	l.waitPublished(t)

	ownerConn := dialWS(t, l.ts, l.srv)
	ownerConn.expectGreeting()
	ownerConn.greet(t, 1, owner, "")
	ownerConn.send(`{"id":2,"cmd":"device.invite","data":{"onion":true}}`)
	inv := ownerConn.expectOK(2)
	var link, token string
	var onion bool
	mustUnmarshal(t, inv["link"], &link)
	mustUnmarshal(t, inv["token"], &token)
	mustUnmarshal(t, inv["onion"], &onion)
	if !onion {
		t.Fatal("an onion invite was refused while tor is ready")
	}
	_, raw, _ := decodeLink(t, link)
	tail := raw[len(raw)-66:]
	addr, err := tor.Address(tail[:32])
	if err != nil || addr != l.sup.Address() {
		t.Fatalf("the link names %q, the service is %q (%v)", addr, l.sup.Address(), err)
	}
	oneTimePriv := base64.StdEncoding.EncodeToString(tail[34:])

	// The new device, somewhere else: in by the one-time key, pairs with its own.
	newcomer := startClientTor(t)
	newcomer.authorize(addr, oneTimePriv)
	pc := dialOnion(t, newcomer, l, 3*time.Minute)
	pc.expectGreeting()
	_, k3Pub, k3Priv := newAccessKey(t)
	d := newDevice(t)
	pc.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test","access_key":%q}}`, token, d.pub, k3Pub))
	pc.expectOK(1)

	// Back in with its own key (SC-010)...
	newcomer.forget(addr)
	newcomer.authorize(addr, k3Priv)
	c := dialOnion(t, newcomer, l, 3*time.Minute)
	c.expectGreeting()
	c.greet(t, 1, d, "")

	// ...and the one-time key opens nothing any more.
	late := startClientTor(t)
	late.authorize(addr, oneTimePriv)
	deadline := time.Now().Add(time.Minute)
	for !onionRefused(late, l, 1) {
		if time.Now().After(deadline) {
			t.Fatal("the spent one-time key still opens the onion service")
		}
		time.Sleep(2 * time.Second)
	}
}

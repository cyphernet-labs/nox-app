package server

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
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
// onion_entry_test.go - the same code path without the minutes. Pairing a new
// device through the onion service waits for 045: the one-time key an onion
// invite used to lend is gone, so the service opens only to devices already
// paired at home - which is what TestOnionAccess holds.

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
	// key is the machine's key, which every channel - onion ones too - proves.
	key  ed25519.PublicKey
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
	tlsCfg, err := channelTLSConfig(time.Now())
	if err != nil {
		t.Fatalf("channelTLSConfig: %v", err)
	}
	key, err := srv.store.ServerKey(context.Background())
	if err != nil {
		t.Fatalf("ServerKey: %v", err)
	}
	onion := serveChannel(t, srv, ln, tlsCfg, key, srv.onionTimeout, "onion", onionConnContext, channelOf(t, ts).devices)

	torCtx, stopTor := context.WithCancel(context.Background())
	torDone := make(chan struct{})
	go func() {
		defer close(torDone)
		sup.Run(torCtx)
	}()
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
	return &liveStack{ts: ts, srv: srv, sup: sup, logs: logs, key: serverKeyOf(t, srv), stop: stop}
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

// dialOnionChannel opens the channel through the client tor: a SOCKS5 stream
// to the onion service, then the same TLS and check as at home, as d.
func (c *clientTor) dialOnionChannel(ctx context.Context, l *liveStack, d *device) (net.Conn, error) {
	stream, err := socksConnect(ctx, c.socks, l.sup.Address()+".onion", tor.OnionPort)
	if err != nil {
		return nil, err
	}
	return channelOver(ctx, stream, l.key, d.priv)
}

// httpClientAs is an HTTP client whose every connection is a channel through
// the client tor, as d.
func (c *clientTor) httpClientAs(l *liveStack, d *device) *http.Client {
	return &http.Client{Timeout: 2 * time.Minute, Transport: &http.Transport{
		DialTLSContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return c.dialOnionChannel(ctx, l, d)
		},
	}}
}

// socksConnect asks a SOCKS5 proxy - tor - for a stream to host:port, with
// no authentication and the name resolved by the proxy (RFC 1928). The
// channel goes on top of it exactly as it goes on top of TCP.
func socksConnect(ctx context.Context, proxy, host string, port int) (net.Conn, error) {
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp", proxy)
	if err != nil {
		return nil, err
	}
	fail := func(err error) (net.Conn, error) {
		_ = conn.Close()
		return nil, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	if _, err := conn.Write([]byte{5, 1, 0}); err != nil {
		return fail(err)
	}
	var choice [2]byte
	if _, err := io.ReadFull(conn, choice[:]); err != nil {
		return fail(err)
	}
	if choice != [2]byte{5, 0} {
		return fail(fmt.Errorf("socks: the proxy chose method %x", choice))
	}
	req := append([]byte{5, 1, 0, 3, byte(len(host))}, host...)
	req = binary.BigEndian.AppendUint16(req, uint16(port))
	if _, err := conn.Write(req); err != nil {
		return fail(err)
	}
	var head [4]byte
	if _, err := io.ReadFull(conn, head[:]); err != nil {
		return fail(err)
	}
	if head[1] != 0 {
		return fail(fmt.Errorf("socks: connect refused with code %d", head[1]))
	}
	var skip int
	switch head[3] {
	case 1:
		skip = 4 + 2
	case 4:
		skip = 16 + 2
	case 3:
		var n [1]byte
		if _, err := io.ReadFull(conn, n[:]); err != nil {
			return fail(err)
		}
		skip = int(n[0]) + 2
	default:
		return fail(fmt.Errorf("socks: unknown address type %d", head[3]))
	}
	if _, err := io.ReadFull(conn, make([]byte, skip)); err != nil {
		return fail(err)
	}
	_ = conn.SetDeadline(time.Time{})
	return conn, nil
}

func newAccessKey(t *testing.T) (*ecdh.PrivateKey, string, string) {
	t.Helper()
	k, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("x25519: %v", err)
	}
	return k, base64.StdEncoding.EncodeToString(k.PublicKey().Bytes()), base64.StdEncoding.EncodeToString(k.Bytes())
}

// dialOnionAs opens the WebSocket through the client tor as d, retrying while
// the descriptor propagates.
func dialOnionAs(t *testing.T, c *clientTor, l *liveStack, d *device, within time.Duration) *wsClient {
	t.Helper()
	target := "https://" + l.sup.Address() + ".onion:443/ws"
	deadline := time.Now().Add(within)
	var lastErr error
	for time.Now().Before(deadline) {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		conn, _, err := websocket.Dial(ctx, target, &websocket.DialOptions{HTTPClient: c.httpClientAs(l, d)})
		if err == nil {
			conn.SetReadLimit(1 << 20)
			t.Cleanup(cancel)
			t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "") })
			return &wsClient{t: t, conn: conn, ctx: ctx, dev: d, srv: l.srv}
		}
		cancel()
		lastErr = err
		time.Sleep(3 * time.Second)
	}
	t.Fatalf("no onion connection within %v: %v", within, lastErr)
	return nil
}

// onionRefused reports whether a fresh channel through the client tor is
// refused - every attempt up to n, each from a new circuit. Any key opens the
// channel itself, so a failure here is the onion service's: no stream at all.
func onionRefused(c *clientTor, l *liveStack, n int) bool {
	for range n {
		ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
		conn, err := c.dialOnionChannel(ctx, l, &device{priv: ed25519.NewKeyFromSeed(make([]byte, 32))})
		cancel()
		if err == nil {
			_ = conn.Close()
			return false
		}
	}
	return true
}

func claimWithKey(t *testing.T, l *liveStack, accessPub string) *device {
	t.Helper()
	d := newDevice(t)
	c := dialAs(t, l.ts, l.srv, d)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test","access_key":%q}}`,
		mustClaimToken(t, l.srv), accessPub))
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
	c := dialOnionAs(t, client, l, d, 3*time.Minute)
	c.expectGreeting()
	hello := c.hello(1, "")
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
	httpc := client.httpClientAs(l, d)
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
	ownerConn := dialAs(t, l.ts, l.srv, owner)
	ownerConn.expectGreeting()
	ownerConn.hello(1, "")
	_, k2Pub, k2Priv := newAccessKey(t)
	ownerConn.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	inv := ownerConn.expectOK(2)
	var token string
	mustUnmarshal(t, inv["token"], &token)
	second := newDevice(t)
	pc := dialAs(t, l.ts, l.srv, second)
	pc.expectGreeting()
	pc.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test","access_key":%q}}`, token, k2Pub))
	pc.expectOK(1)

	device := startClientTor(t)
	device.authorize(l.sup.Address(), k2Priv)
	oc := dialOnionAs(t, device, l, second, 3*time.Minute)
	oc.expectGreeting()
	oc.hello(1, "")

	// A connection of its own for the revocation: the onion dial above can
	// take minutes on a slow network, longer than a test connection lives.
	revoker := dialAs(t, l.ts, l.srv, owner)
	revoker.expectGreeting()
	revoker.hello(1, "")
	revoker.send(fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, second.pub))
	revoker.expectOK(2)
	deadline := time.Now().Add(time.Minute)
	for !onionRefused(device, l, 1) {
		if time.Now().After(deadline) {
			t.Fatal("the revoked device still opens onion connections a minute after its revocation")
		}
		time.Sleep(2 * time.Second)
	}
}

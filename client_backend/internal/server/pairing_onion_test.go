package server

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/protocol"
)

func access(b byte) string { return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{b}, 32)) }

func storedAccessKey(t *testing.T, srv *Server, deviceKey string) string {
	t.Helper()
	var k *string
	if err := readDB(t, srv).QueryRowContext(context.Background(),
		"SELECT access_key FROM devices WHERE device_key = ?", deviceKey).Scan(&k); err != nil {
		t.Fatalf("read access key: %v", err)
	}
	if k == nil {
		return ""
	}
	return *k
}

func pairWithKey(t *testing.T, st *onionStack, token, accessKey string) (*device, bool, string) {
	t.Helper()
	d := newDevice(t)
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"device_key":%q,"platform":"test","access_key":%q}}`,
		token, d.pub, accessKey))
	reply := c.expectReply(1)
	var ok bool
	mustUnmarshal(t, reply["ok"], &ok)
	if ok {
		return d, true, ""
	}
	var wireErr protocol.WireError
	mustUnmarshal(t, reply["error"], &wireErr)
	return d, false, wireErr.Code
}

func TestPairingWithAnAccessKeyStoresItAndTellsTor(t *testing.T) {
	st := newOnionStack(t)
	before := st.tor.kickCount()
	d, ok, code := pairWithKey(t, st, mustClaimToken(t, st.srv), access(1))
	if !ok {
		t.Fatalf("pair: %s", code)
	}
	if got := storedAccessKey(t, st.srv, d.pub); got != access(1) {
		t.Fatalf("stored access key = %q", got)
	}
	eventually(t, "the supervisor told", func() bool { return st.tor.kickCount() > before })
}

func TestAMalformedAccessKeyRefusesThePairing(t *testing.T) {
	st := newOnionStack(t)
	token := mustClaimToken(t, st.srv)
	for _, bad := range []string{"not base64!", base64.StdEncoding.EncodeToString(make([]byte, 31))} {
		if _, ok, code := pairWithKey(t, st, token, bad); ok || code != protocol.ErrInvalidRequest {
			t.Fatalf("access_key %q: ok=%v code=%q, want invalid_request", bad, ok, code)
		}
	}
	// Nothing happened: the claim is still there to be made.
	if _, ok, code := pairWithKey(t, st, token, access(2)); !ok {
		t.Fatalf("the refused attempts spent the token: %s", code)
	}
}

func TestSetAccessKeyWantsAGreetingAndAProperKey(t *testing.T) {
	st := newOnionStack(t)
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(1)))
	c.expectErr(1, protocol.ErrInvalidRequest)

	c.hello(2, "")
	for i, bad := range []string{`{}`, `{"access_key":""}`, `{"access_key":"@@@"}`} {
		c.send(fmt.Sprintf(`{"id":%d,"cmd":"device.setAccessKey","data":%s}`, 10+i, bad))
		c.expectErr(10+i, protocol.ErrInvalidRequest)
	}
}

func TestSetAccessKeyReplacesAndTellsTorOnlyWhenItChanged(t *testing.T) {
	st := newOnionStack(t)
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.hello(1, "")

	before := st.tor.kickCount()
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(3)))
	c.expectOK(2)
	if got := storedAccessKey(t, st.srv, c.dev.pub); got != access(3) {
		t.Fatalf("stored = %q", got)
	}
	eventually(t, "kicked", func() bool { return st.tor.kickCount() == before+1 })

	// The same key again: success, and nothing for tor to do.
	c.send(fmt.Sprintf(`{"id":3,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(3)))
	c.expectOK(3)
	time.Sleep(50 * time.Millisecond)
	if st.tor.kickCount() != before+1 {
		t.Fatal("re-registering the same key woke the supervisor")
	}

	c.send(fmt.Sprintf(`{"id":4,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(4)))
	c.expectOK(4)
	if got := storedAccessKey(t, st.srv, c.dev.pub); got != access(4) {
		t.Fatalf("replaced = %q", got)
	}
}

func TestSetAccessKeyForADeviceRevokedMidSessionIsUnauthenticated(t *testing.T) {
	st := newOnionStack(t)
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.hello(1, "")
	// Revoked underneath the live session, without the drop.
	if err := st.srv.store.RevokeDevice(context.Background(), c.dev.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(1)))
	c.expectErr(2, protocol.ErrUnauthenticated)
}

func TestAKeyIsAcceptedWithTorOff(t *testing.T) {
	ts, srv := newTestServer(t) // tor.Disabled()
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, "")
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(7)))
	c.expectOK(2)
	if got := storedAccessKey(t, srv, c.dev.pub); got != access(7) {
		t.Fatalf("with Tor off the key was not kept: %q", got)
	}
}

func TestRevokingADeviceTellsTor(t *testing.T) {
	st := newOnionStack(t)
	owner := dialWS(t, st.ts, st.srv)
	owner.expectGreeting()
	owner.hello(1, "")
	other := pairedDevice(t, st.ts, st.srv)

	before := st.tor.kickCount()
	owner.send(fmt.Sprintf(`{"id":2,"cmd":"device.revoke","data":{"device_key":%q}}`, other.pub))
	owner.expectOK(2)
	eventually(t, "kicked", func() bool { return st.tor.kickCount() > before })
}

func inviteOver(t *testing.T, c *wsClient, id int, data string) (string, bool) {
	t.Helper()
	c.send(fmt.Sprintf(`{"id":%d,"cmd":"device.invite","data":%s}`, id, data))
	reply := c.expectOK(id)
	var link string
	var onion bool
	mustUnmarshal(t, reply["link"], &link)
	mustUnmarshal(t, reply["onion"], &onion)
	return link, onion
}

func TestAnInviteCarriesTheOnionAddressOnlyWhenAskedAndReady(t *testing.T) {
	st := newOnionStack(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.hello(1, "")

	for i, data := range []string{`{}`, `{"onion":false}`, `{"onion":"yes"}`, `{"onion":null}`, `{"onion":true}`} {
		link, onion := inviteOver(t, c, 10+i, data)
		if v, _, _ := decodeLink(t, link); v != pairingLinkVersion || onion {
			t.Fatalf("%s while tor is not ready: version %d onion=%v, want 1 and false", data, v, onion)
		}
	}

	st.tor.set(true, true)
	before := st.tor.kickCount()
	link, onion := inviteOver(t, c, 20, `{"onion":true}`)
	if !onion {
		t.Fatal("onion = false for an onion invite")
	}
	version, raw, host := decodeLink(t, link)
	if version != pairingLinkVersionOnion || host != "192.168.1.10" {
		t.Fatalf("version %d host %q", version, host)
	}
	if len(raw) != 122 {
		t.Fatalf("an IPv4 onion invite is %d bytes, want 122", len(raw))
	}
	tail := raw[len(raw)-66:]
	if !bytes.Equal(tail[:32], st.tor.pub) {
		t.Fatal("onion_pub is not the service's public key")
	}
	if port := binary.BigEndian.Uint16(tail[32:34]); port != 443 {
		t.Fatalf("onion_port = %d, want 443", port)
	}
	priv, err := ecdh.X25519().NewPrivateKey(tail[34:])
	if err != nil {
		t.Fatalf("one_time_priv is not an x25519 key: %v", err)
	}
	pubB64 := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())
	privB64 := base64.StdEncoding.EncodeToString(tail[34:])

	// The store keeps the PUBLIC half - and nowhere the private one.
	var stored string
	if err := readDB(t, st.srv).QueryRowContext(context.Background(),
		"SELECT access_key FROM pair_tokens WHERE access_key IS NOT NULL").Scan(&stored); err != nil {
		t.Fatalf("read one-time key: %v", err)
	}
	if stored != pubB64 {
		t.Fatalf("stored one-time key = %q, want the public half %q", stored, pubB64)
	}
	rows, err := readDB(t, st.srv).QueryContext(context.Background(), "SELECT * FROM pair_tokens")
	if err != nil {
		t.Fatalf("scan tokens: %v", err)
	}
	defer func() { _ = rows.Close() }()
	cols, _ := rows.Columns()
	for rows.Next() {
		vals := make([]any, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			t.Fatalf("scan: %v", err)
		}
		if strings.Contains(fmt.Sprint(vals...), privB64) {
			t.Fatal("the private half of the one-time key is in the database")
		}
	}
	eventually(t, "the one-time key reached tor", func() bool { return st.tor.kickCount() > before })
}

func TestTheLinkLayoutPerHostType(t *testing.T) {
	fp := base64.StdEncoding.EncodeToString(make([]byte, 32))
	tok := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	pub := ed25519.PublicKey(make([]byte, 32))
	priv := make([]byte, 32)
	for addr, want := range map[string]int{
		"192.168.1.10:8080":  122,
		"[fd00::1]:8080":     134,
		"home.example:8080":  119 + len("home.example"),
		"nox.example.com:80": 119 + len("nox.example.com"),
	} {
		link, err := BuildPairingLinkV2(addr, fp, tok, pub, 443, priv)
		if err != nil {
			t.Fatalf("%s: %v", addr, err)
		}
		raw, _ := base64.RawURLEncoding.DecodeString(strings.TrimPrefix(link, pairingLinkPrefix))
		if len(raw) != want {
			t.Errorf("%s: %d bytes, want %d", addr, len(raw), want)
		}
	}
	if _, err := BuildPairingLinkV2("1.2.3.4:1", fp, tok, pub[:31], 443, priv); err == nil {
		t.Error("a 31-byte onion key was accepted")
	}
	if _, err := BuildPairingLinkV2("1.2.3.4:1", fp, tok, pub, 443, priv[:16]); err == nil {
		t.Error("a 16-byte one-time key was accepted")
	}
	if _, err := BuildPairingLinkV2("1.2.3.4:1", fp, tok, pub, 0, priv); err == nil {
		t.Error("port 0 was accepted")
	}
}

// The same three links are pinned byte for byte in the app's parser test
// (test/general/pairing/pairing_link_test.dart). Lengths alone do not catch two
// fields swapped, and a link the two sides read differently would pair nothing.
// Every field is a different run of bytes for the same reason.
func TestTheOnionLinkVectorsTheAppPins(t *testing.T) {
	run := func(from byte, n int) []byte {
		out := make([]byte, n)
		for i := range out {
			out[i] = from + byte(i)
		}
		return out
	}
	fp := base64.StdEncoding.EncodeToString(run(0x00, 32))
	tok := base64.RawURLEncoding.EncodeToString(run(0xa0, 16))
	pub := ed25519.PublicKey(run(0x20, 32))
	priv := run(0x40, 32)
	for _, tc := range []struct{ addr, want string }{
		{"192.168.1.10:8080", "https://nox.app/p/#AgHAqAEKH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8"},
		{"[fd00::1]:8080", "https://nox.app/p/#AgL9AAAAAAAAAAAAAAAAAAABH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8"},
		{"home.example:8080", "https://nox.app/p/#AgMMaG9tZS5leGFtcGxlH5AAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6ChoqOkpaanqKmqq6ytrq8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-PwG7QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8"},
	} {
		link, err := BuildPairingLinkV2(tc.addr, fp, tok, pub, 443, priv)
		if err != nil {
			t.Fatalf("%s: %v", tc.addr, err)
		}
		if link != tc.want {
			t.Errorf("%s:\n got %s\nwant %s", tc.addr, link, tc.want)
		}
	}
}

// The claim link stays version 1 whatever Tor is doing: a claim never goes
// over onion.
func TestTheClaimLinkStaysVersionOneWithTorReady(t *testing.T) {
	st := newOnionStack(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	st.tor.set(true, true)
	link, _, err := st.srv.claimLink(context.Background())
	if err != nil {
		t.Fatalf("claimLink: %v", err)
	}
	if v, _, _ := decodeLink(t, link); v != pairingLinkVersion {
		t.Fatalf("claim link version = %d, want 1", v)
	}
}

// A small-order point - the all-zero key among them - is refused at both
// doors: tor asserts on the zero key, and every such point leaves a
// descriptor entry keyed by the onion address alone.
func TestAnAccessKeyOfSmallOrderIsRefused(t *testing.T) {
	st := newOnionStack(t)
	zero := base64.StdEncoding.EncodeToString(make([]byte, 32))
	token := mustClaimToken(t, st.srv)
	if _, ok, code := pairWithKey(t, st, token, zero); ok || code != protocol.ErrInvalidRequest {
		t.Fatalf("pair with the zero key: ok=%v code=%q, want invalid_request", ok, code)
	}
	d, ok, code := pairWithKey(t, st, token, access(1))
	if !ok {
		t.Fatalf("the refusal spent the claim: %s", code)
	}
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.dev = d
	c.hello(1, "")
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, zero))
	c.expectErr(2, protocol.ErrInvalidRequest)
	if got := storedAccessKey(t, st.srv, d.pub); got != access(1) {
		t.Fatalf("stored access key = %q, want the one it had", got)
	}
}

// A key another device holds is refused at both doors - a shared key would
// survive the revocation of either device - and a refused pairing spends
// nothing.
func TestAnAccessKeyAnotherDeviceHoldsIsRefused(t *testing.T) {
	st := newOnionStack(t)
	first, ok, code := pairWithKey(t, st, mustClaimToken(t, st.srv), access(1))
	if !ok {
		t.Fatalf("claim: %s", code)
	}
	invite, err := st.srv.store.IssueDeviceInvite(context.Background(), first.pub, time.Now().Unix())
	if err != nil {
		t.Fatalf("IssueDeviceInvite: %v", err)
	}
	if _, ok, code := pairWithKey(t, st, invite, access(1)); ok || code != protocol.ErrInvalidRequest {
		t.Fatalf("pair with the first device's key: ok=%v code=%q, want invalid_request", ok, code)
	}
	second, ok, code := pairWithKey(t, st, invite, access(2))
	if !ok {
		t.Fatalf("the refusal spent the invite: %s", code)
	}

	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.dev = second
	c.hello(1, "")
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(1)))
	c.expectErr(2, protocol.ErrInvalidRequest)
	if got := storedAccessKey(t, st.srv, second.pub); got != access(2) {
		t.Fatalf("stored access key = %q, want its own", got)
	}
}

// A device revoked while its connection is still open cannot mint an invite:
// the command gets the answer its next greeting would get, and no token - and
// so no one-time onion key - comes into being.
func TestADeviceRevokedMidSessionCannotIssueAnInvite(t *testing.T) {
	st := newOnionStack(t)
	st.tor.set(true, true)
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.hello(1, "")
	// Revoked from elsewhere: straight in the store, so this socket stays open
	// the way it does between a revocation's commit and the server's close.
	if err := st.srv.store.RevokeDevice(context.Background(), c.dev.pub); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	c.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	c.expectErr(2, protocol.ErrUnauthenticated)
	c.send(`{"id":3,"cmd":"device.invite","data":{"onion":true}}`)
	c.expectErr(3, protocol.ErrUnauthenticated)

	var live int
	if err := readDB(t, st.srv).QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pair_tokens WHERE kind = 'invite_device'").Scan(&live); err != nil {
		t.Fatalf("count invites: %v", err)
	}
	if live != 0 {
		t.Fatalf("%d invites written for a revoked device, want none", live)
	}
}

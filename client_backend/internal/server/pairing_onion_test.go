package server

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"slices"
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
	c := dialAs(t, st.ts, st.srv, d)
	c.expectGreeting()
	c.send(fmt.Sprintf(`{"id":1,"cmd":"pair","data":{"token":%q,"platform":"test","access_key":%q}}`, token, accessKey))
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

// Every invite is the same version-3 link, and every reply says "onion":
// false - whatever the request asked and whatever tor is doing. Pairing through
// the onion service waits for 045; until then an invite that claimed it would
// be a promise the service cannot keep.
//
// The link names the onion service whenever the server offers it - for the
// device to use AFTER pairing - and never otherwise.
func TestEveryInviteIsVersionThreeAndSaysOnionFalse(t *testing.T) {
	st := newOnionStack(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	c := dialWS(t, st.ts, st.srv)
	c.expectGreeting()
	c.hello(1, "")
	key := serverKeyOf(t, st.srv)

	requests := []string{`{}`, `{"onion":false}`, `{"onion":"yes"}`, `{"onion":null}`, `{"onion":true}`, `[]`}
	for i, data := range requests {
		link, onion := inviteOver(t, c, 10+i, data)
		got := readLink(t, link)
		if onion || got.Onion != nil || !got.ServerKey.Equal(key) || !slices.Equal(got.Direct, []string{"192.168.1.10:8080"}) {
			t.Fatalf("%s with tor not offered: onion=%v link=%+v", data, onion, got)
		}
	}

	st.tor.set(true, true)
	before := st.tor.kickCount()
	for i, data := range requests {
		link, onion := inviteOver(t, c, 20+i, data)
		if onion {
			t.Fatalf("%s: the reply says onion=true; pairing over onion waits for 045", data)
		}
		got := readLink(t, link)
		if !bytes.Equal(got.Onion, st.tor.pub) {
			t.Fatalf("%s: the link names onion key %x, want the service's %x", data, got.Onion, st.tor.pub)
		}
		if !slices.Equal(got.Direct, []string{"192.168.1.10:8080"}) {
			t.Fatalf("%s: direct %v, want the address the server listens on, first", data, got.Direct)
		}
	}
	// No invite touches the set of keys tor publishes: there is no one-time
	// key to add any more.
	time.Sleep(50 * time.Millisecond)
	if st.tor.kickCount() != before {
		t.Fatal("an invite woke the supervisor; invites carry no access key since 044")
	}
	// And nothing is left in the store for one: the column went with them.
	var columns int
	if err := readDB(t, st.srv).QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pragma_table_info('pair_tokens') WHERE name = 'access_key'").Scan(&columns); err != nil {
		t.Fatalf("inspect pair_tokens: %v", err)
	}
	if columns != 0 {
		t.Fatal("pair_tokens still has an access_key column")
	}
}

// The claim link is version 3 too, and follows the same rule for the onion
// address: named while the service is offered. A claim still never goes over
// onion - the store refuses it there - but the address is for after pairing.
func TestTheClaimLinkIsVersionThreeAndFollowsTheOnionOffer(t *testing.T) {
	st := newOnionStack(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	link, _, err := st.srv.claimLink(context.Background())
	if err != nil {
		t.Fatalf("claimLink: %v", err)
	}
	if got := readLink(t, link); got.Onion != nil || !slices.Equal(got.Direct, []string{"192.168.1.10:8080"}) {
		t.Fatalf("claim link with tor not offered = %+v", got)
	}

	st.tor.set(true, true)
	link, _, err = st.srv.claimLink(context.Background())
	if err != nil {
		t.Fatalf("claimLink: %v", err)
	}
	got := readLink(t, link)
	if !bytes.Equal(got.Onion, st.tor.pub) || !got.ServerKey.Equal(serverKeyOf(t, st.srv)) {
		t.Fatalf("claim link with tor offered = %+v", got)
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
	c := dialAs(t, st.ts, st.srv, d)
	c.expectGreeting()
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

	c := dialAs(t, st.ts, st.srv, second)
	c.expectGreeting()
	c.hello(1, "")
	c.send(fmt.Sprintf(`{"id":2,"cmd":"device.setAccessKey","data":{"access_key":%q}}`, access(1)))
	c.expectErr(2, protocol.ErrInvalidRequest)
	if got := storedAccessKey(t, st.srv, second.pub); got != access(2) {
		t.Fatalf("stored access key = %q, want its own", got)
	}
}

// A device revoked while its connection is still open cannot mint an invite:
// the command gets the answer its next greeting would get, and no token comes
// into being.
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

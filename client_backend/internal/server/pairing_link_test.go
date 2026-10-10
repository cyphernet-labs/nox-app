package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// linkVectors is testdata/link-vectors.json - a copy of the contract's shared
// vectors, the same file the app's parser tests read.
type linkVectors struct {
	Full struct {
		Link            string       `json:"link"`
		ServerPublicKey string       `json:"server_public_key"`
		Token           string       `json:"token"`
		Addresses       []vectorAddr `json:"addresses"`
	} `json:"full"`
	Minimal struct {
		Link      string       `json:"link"`
		Addresses []vectorAddr `json:"addresses"`
	} `json:"minimal"`
	UnknownTypeSkipped struct {
		Link      string       `json:"link"`
		Addresses []vectorAddr `json:"addresses"`
	} `json:"unknown_type_skipped"`
	Refusals struct {
		Malformed    []string `json:"malformed"`
		NewerVersion string   `json:"newer_version"`
	} `json:"refusals"`
}

type vectorAddr struct {
	Type      string `json:"type"`
	Host      string `json:"host"`
	Port      int    `json:"port"`
	PublicKey string `json:"public_key"`
}

func loadLinkVectors(t *testing.T) linkVectors {
	t.Helper()
	raw, err := os.ReadFile("testdata/link-vectors.json")
	if err != nil {
		t.Fatalf("read the link vectors: %v", err)
	}
	var v linkVectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("parse the link vectors: %v", err)
	}
	return v
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("hex %q: %v", s, err)
	}
	return b
}

// split turns the vectors' address list into what the builder takes and the
// parser gives back: direct addresses as host:port in order, and the onion
// service's key.
func split(t *testing.T, addrs []vectorAddr) (direct []string, onion ed25519.PublicKey) {
	t.Helper()
	for _, a := range addrs {
		switch a.Type {
		case "onion":
			if a.Port != 443 {
				t.Fatalf("an onion address on port %d; the format fixes 443", a.Port)
			}
			onion = mustHex(t, a.PublicKey)
		default:
			direct = append(direct, net.JoinHostPort(a.Host, strconv.Itoa(a.Port)))
		}
	}
	return direct, onion
}

// The server's links, byte for byte the shared vectors. The app parses those
// same strings; a builder that drifted from them would print links no device
// reads.
func TestTheLinkBuilderReproducesTheSharedVectors(t *testing.T) {
	v := loadLinkVectors(t)
	key := ed25519.PublicKey(mustHex(t, v.Full.ServerPublicKey))
	token := base64.RawURLEncoding.EncodeToString(mustHex(t, v.Full.Token))

	for _, tc := range []struct {
		name  string
		addrs []vectorAddr
		want  string
	}{
		{"full", v.Full.Addresses, v.Full.Link},
		{"minimal", v.Minimal.Addresses, v.Minimal.Link},
	} {
		t.Run(tc.name, func(t *testing.T) {
			direct, onion := split(t, tc.addrs)
			got, err := BuildPairingLink(key, token, direct, onion)
			if err != nil {
				t.Fatalf("BuildPairingLink: %v", err)
			}
			if got != tc.want {
				t.Fatalf("link\n got %s\nwant %s", got, tc.want)
			}
		})
	}
}

// The parse rules, case by case from the same file: what reads, what is
// skipped, and the two refusals a person must be able to tell apart.
func TestTheLinkParserFollowsTheSharedVectors(t *testing.T) {
	v := loadLinkVectors(t)
	key := mustHex(t, v.Full.ServerPublicKey)

	for _, tc := range []struct {
		name  string
		link  string
		addrs []vectorAddr
	}{
		{"full", v.Full.Link, v.Full.Addresses},
		{"minimal", v.Minimal.Link, v.Minimal.Addresses},
		{"an unknown address type is skipped by its length", v.UnknownTypeSkipped.Link, v.UnknownTypeSkipped.Addresses},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParsePairingLink(tc.link)
			if err != nil {
				t.Fatalf("ParsePairingLink: %v", err)
			}
			if !bytes.Equal(got.ServerKey, key) {
				t.Fatalf("server key %x, want %x", got.ServerKey, key)
			}
			if want := base64.RawURLEncoding.EncodeToString(mustHex(t, v.Full.Token)); got.Token != want {
				t.Fatalf("token %q, want %q", got.Token, want)
			}
			direct, onion := split(t, tc.addrs)
			if !slices.Equal(got.Direct, direct) {
				t.Fatalf("direct %v, want %v", got.Direct, direct)
			}
			if !bytes.Equal(got.Onion, onion) {
				t.Fatalf("onion %x, want %x", got.Onion, onion)
			}
		})
	}

	for _, link := range v.Refusals.Malformed {
		t.Run("malformed "+link, func(t *testing.T) {
			if _, err := ParsePairingLink(link); !errors.Is(err, ErrLinkMalformed) {
				t.Fatalf("ParsePairingLink = %v, want ErrLinkMalformed", err)
			}
		})
	}
	t.Run("newer version", func(t *testing.T) {
		if _, err := ParsePairingLink(v.Refusals.NewerVersion); !errors.Is(err, ErrLinkNewerVersion) {
			t.Fatalf("ParsePairingLink = %v, want ErrLinkNewerVersion", err)
		}
	})
}

// The parse rules the vectors do not spell out, one each: a known type whose
// length is wrong, a port of 0, an empty name, a name that is not UTF-8, and a
// version below 3.
func TestTheLinkParserRefusesWhatTheRulesRefuse(t *testing.T) {
	head := append([]byte{pairingLinkVersion}, bytes.Repeat([]byte{0xab}, ed25519.PublicKeySize+16)...)
	for _, tc := range []struct {
		name    string
		payload []byte
	}{
		{"an IPv4 address one byte short", append(bytes.Clone(head), addrTypeIPv4, 5, 1, 2, 3, 4, 0)},
		{"port 0", append(bytes.Clone(head), addrTypeIPv4, 6, 1, 2, 3, 4, 0, 0)},
		{"an empty name", append(bytes.Clone(head), addrTypeName, 2, 0x20, 0xfb)},
		{"a name that is not UTF-8", append(bytes.Clone(head), addrTypeName, 4, 0xff, 0xfe, 0x20, 0xfb)},
		{"an onion key one byte short", append(bytes.Clone(head), addrTypeOnion, 31)},
		{"a header cut in half", append(bytes.Clone(head), addrTypeIPv4)},
		{"only unknown addresses", append(bytes.Clone(head), 9, 1, 0)},
		{"version 2", append([]byte{2}, head[1:]...)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			link := pairingLinkPrefix + base64.RawURLEncoding.EncodeToString(tc.payload)
			if _, err := ParsePairingLink(link); !errors.Is(err, ErrLinkMalformed) {
				t.Fatalf("ParsePairingLink = %v, want ErrLinkMalformed", err)
			}
		})
	}
}

// The builder refuses to print what the parser would refuse to read. A link
// that cannot be read is worse than no link: the person carries it to a device
// and only learns there that it was never any good.
func TestTheLinkBuilderRefusesWhatNoDeviceCouldRead(t *testing.T) {
	key := ed25519.PublicKey(bytes.Repeat([]byte{1}, ed25519.PublicKeySize))
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	for _, tc := range []struct {
		name   string
		key    ed25519.PublicKey
		token  string
		direct []string
	}{
		{"port 0", key, token, []string{"127.0.0.1:0"}},
		{"no port at all", key, token, []string{"127.0.0.1"}},
		{"an empty host", key, token, []string{":8080"}},
		{"a name longer than 253 bytes", key, token, []string{strings.Repeat("a", 254) + ":8080"}},
		{"an IPv6 address with a zone", key, token, []string{"[fe80::1%en0]:8080"}},
		{"no address at all", key, token, nil},
		{"a server key of the wrong size", key[:31], token, []string{"127.0.0.1:8080"}},
		{"a token of the wrong size", key, base64.RawURLEncoding.EncodeToString(make([]byte, 15)), []string{"127.0.0.1:8080"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if link, err := BuildPairingLink(tc.key, tc.token, tc.direct, nil); err == nil {
				t.Fatalf("built %s", link)
			}
		})
	}
	if _, err := BuildPairingLink(key, token, []string{"127.0.0.1:8080"}, make([]byte, 31)); err == nil {
		t.Fatal("built a link around an onion key of the wrong size")
	}
}

// An IPv6 bind used to produce "[[::1]]:8080" - JoinHostPort brackets the
// literal, and bracketing it here too made a link this file's own parser
// rejects, so such a server printed no link at all.
func TestListenAddressHandlesEveryBindShape(t *testing.T) {
	key := ed25519.PublicKey(bytes.Repeat([]byte{1}, ed25519.PublicKeySize))
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	for _, tc := range []struct{ in, want string }{
		{"127.0.0.1:8080", "127.0.0.1:8080"},
		{"[::1]:8080", "[::1]:8080"},
		{"0.0.0.0:8080", "127.0.0.1:8080"},
		{"[::]:8080", "127.0.0.1:8080"},
	} {
		if got := listenAddress(tc.in); got != tc.want {
			t.Fatalf("listenAddress(%q) = %q, want %q", tc.in, got, tc.want)
		}
		link, err := BuildPairingLink(key, token, []string{listenAddress(tc.in)}, nil)
		if err != nil {
			t.Fatalf("a %s bind produced no link at all: %v", tc.in, err)
		}
		if got := readLink(t, link).Direct; !slices.Equal(got, []string{tc.want}) {
			t.Fatalf("a %s bind's link names %v, want %s", tc.in, got, tc.want)
		}
	}
}

// The invite goes to a device that is NOT this machine, so loopback is never a
// useful answer for it. Every household server binds a wildcard, so this was
// every invite.
func TestInviteLinkUsesTheAddressTheDeviceActuallyReached(t *testing.T) {
	cases := []struct {
		name        string
		cfgAddr     string
		requestHost string
		want        string
	}{
		{"wildcard bind takes the reached address", "0.0.0.0:8080", "192.168.1.10:8080", "192.168.1.10:8080"},
		{"IPv6 wildcard too", "[::]:8080", "192.168.1.10:8080", "192.168.1.10:8080"},
		{"a header with no port borrows the listening one", "0.0.0.0:8080", "nox.local", "nox.local:8080"},
		{"an explicit bind is a decision and wins", "10.0.0.7:8080", "192.168.1.10:8080", "10.0.0.7:8080"},
		{"no header at all falls back to loopback", "0.0.0.0:8080", "", "127.0.0.1:8080"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := inviteAddress(tc.cfgAddr, tc.requestHost); got != tc.want {
				t.Fatalf("inviteAddress(%q, %q) = %q, want %q", tc.cfgAddr, tc.requestHost, got, tc.want)
			}
		})
	}
}

// And the whole way through: what a device is handed must parse back to the
// address it reached, or the next device dials nowhere.
func TestInviteLinkRoundTripsTheReachedAddress(t *testing.T) {
	key := ed25519.PublicKey(bytes.Repeat([]byte{1}, ed25519.PublicKeySize))
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	for _, reached := range []string{"192.168.1.10:8080", "[fd00::1]:8080", "nox.local:8080"} {
		link, err := BuildPairingLink(key, token, []string{inviteAddress("0.0.0.0:8080", reached)}, nil)
		if err != nil {
			t.Fatalf("BuildPairingLink: %v", err)
		}
		if got := readLink(t, link).Direct; !slices.Equal(got, []string{reached}) {
			t.Fatalf("the link names %v, want %s", got, reached)
		}
	}
}

// The link carries the machine's KEY, whole: thirty-two bytes of Ed25519 that
// the device checks the channel against. Not a hash of it, and not the
// throwaway certificate's - that one changes on every start.
func TestThePairingLinkCarriesTheStoredServerKey(t *testing.T) {
	ts, srv := newTestServer(t)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, "")
	link, _, _ := inviteOver(t, c, 2, `{}`)
	if got := readLink(t, link).ServerKey; !got.Equal(serverKeyOf(t, srv)) {
		t.Fatalf("the link carries %x, want the stored key %x", got, serverKeyOf(t, srv))
	}
	// And the key the channel proves is that same key: a device dialling with
	// it as the only acceptable answer gets in.
	if _, err := dialChannel(t.Context(), ts.Listener.Addr().String(), readLink(t, link).ServerKey, newDevice(t).priv); err != nil {
		t.Fatalf("a channel expecting the link's key was refused: %v", err)
	}
}

// readLink parses a link the server issued, failing the test if it does not
// read back.
func readLink(t *testing.T, link string) PairingLink {
	t.Helper()
	parsed, err := ParsePairingLink(link)
	if err != nil {
		t.Fatalf("the link does not read back: %v (%s)", err, link)
	}
	return parsed
}

// inviteOver asks for a device invite on a greeted connection and returns the
// link and the reply's two flags.
func inviteOver(t *testing.T, c *wsClient, id int, data string) (link string, onion, public bool) {
	t.Helper()
	c.send(fmt.Sprintf(`{"id":%d,"cmd":"device.invite","data":%s}`, id, data))
	reply := c.expectOK(id)
	mustUnmarshal(t, reply["link"], &link)
	mustUnmarshal(t, reply["onion"], &onion)
	mustUnmarshal(t, reply["public"], &public)
	return link, onion, public
}

// onionKeyOf is the service key a valid onion address names - what a link
// carries for it.
func onionKeyOf(t *testing.T, addr string) ed25519.PublicKey {
	t.Helper()
	_, key, err := parseOnionAddress(addr)
	if err != nil {
		t.Fatalf("parseOnionAddress(%q): %v", addr, err)
	}
	return key
}

// The order every link follows (045, contract §8A): the public address first,
// because the app shows the link's first direct address as "server address";
// then the one direct address, left out when it IS the public one; then the
// onion service. Nothing set, nothing added.
func TestLinksNameThePublicAddressThenTheDirectOneThenTheOnion(t *testing.T) {
	key := ed25519.PublicKey(bytes.Repeat([]byte{1}, ed25519.PublicKeySize))
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	onionKey := onionKeyOf(t, testOnionAddr)
	both := configuredAddresses{Public: "nox.example.org:8443", Onion: testOnionAddr, OnionKey: onionKey}
	for _, tc := range []struct {
		name       string
		direct     string
		conf       configuredAddresses
		wantDirect []string
		wantOnion  bool
	}{
		{"nothing stored", "192.168.1.20:8443", configuredAddresses{}, []string{"192.168.1.20:8443"}, false},
		{"public and onion", "192.168.1.20:8443", both, []string{"nox.example.org:8443", "192.168.1.20:8443"}, true},
		{"onion only", "192.168.1.20:8443", configuredAddresses{Onion: testOnionAddr, OnionKey: onionKey}, []string{"192.168.1.20:8443"}, true},
		{"public only", "192.168.1.20:8443", configuredAddresses{Public: "203.0.113.7:8443"}, []string{"203.0.113.7:8443", "192.168.1.20:8443"}, false},
		{"the direct address is the public one", "nox.example.org:8443", both, []string{"nox.example.org:8443"}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			link, carries, err := buildLink(key, token, tc.direct, tc.conf)
			if err != nil {
				t.Fatalf("buildLink: %v", err)
			}
			got := readLink(t, link)
			if !slices.Equal(got.Direct, tc.wantDirect) {
				t.Fatalf("direct = %v, want %v", got.Direct, tc.wantDirect)
			}
			if tc.wantOnion != (got.Onion != nil) || (tc.wantOnion && !got.Onion.Equal(onionKey)) {
				t.Fatalf("onion key = %x, want present=%v", got.Onion, tc.wantOnion)
			}
			if carries.Onion != tc.wantOnion || carries.Public != (tc.conf.Public != "") {
				t.Fatalf("carries = %+v for %+v", carries, tc.conf)
			}
		})
	}
}

// The invite names every address the machine stores, and the reply says which
// of the two it carries: with both false the app labels the invite "home
// only". Whatever the request's own `onion` says, nothing changes - it is read
// softly and ignored (contract §8A).
func TestAnInviteNamesTheStoredAddressesAndSaysWhichItCarries(t *testing.T) {
	ts, srv := newTestServerWith(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, "")
	key := serverKeyOf(t, srv)

	requests := []string{`{}`, `{"onion":false}`, `{"onion":"yes"}`, `{"onion":null}`, `{"onion":true}`, `[]`}
	for i, data := range requests {
		link, onion, public := inviteOver(t, c, 10+i, data)
		got := readLink(t, link)
		if onion || public || got.Onion != nil || !got.ServerKey.Equal(key) || !slices.Equal(got.Direct, []string{"192.168.1.10:8080"}) {
			t.Fatalf("%s with nothing stored: onion=%v public=%v link=%+v", data, onion, public, got)
		}
	}

	setStored(t, srv, store.AddressOnion, testOnionAddr)
	link, onion, public := inviteOver(t, c, 20, `{}`)
	if got := readLink(t, link); !onion || public || !got.Onion.Equal(onionKeyOf(t, testOnionAddr)) ||
		!slices.Equal(got.Direct, []string{"192.168.1.10:8080"}) {
		t.Fatalf("onion stored: onion=%v public=%v link=%+v", onion, public, got)
	}

	setStored(t, srv, store.AddressPublic, "nox.example.org:8443")
	for i, data := range requests {
		link, onion, public := inviteOver(t, c, 30+i, data)
		got := readLink(t, link)
		if !onion || !public {
			t.Fatalf("%s: onion=%v public=%v, want both", data, onion, public)
		}
		if !slices.Equal(got.Direct, []string{"nox.example.org:8443", "192.168.1.10:8080"}) {
			t.Fatalf("%s: direct %v, want the public address first, then the bind", data, got.Direct)
		}
		if !got.Onion.Equal(onionKeyOf(t, testOnionAddr)) {
			t.Fatalf("%s: onion key %x, want the stored address's", data, got.Onion)
		}
	}
}

// machineLinkNow builds a machine link the way the page and `noxd link` do,
// for a freshly minted token, and says whether a phone could follow it.
func machineLinkNow(t *testing.T, srv *Server) (string, bool) {
	t.Helper()
	b, err := srv.machineLinkBuilder(context.Background())
	if err != nil {
		t.Fatalf("machineLinkBuilder: %v", err)
	}
	link, scannable, err := b.build(mustMachineLink(t, srv))
	if err != nil {
		t.Fatalf("build: %v", err)
	}
	return link, scannable
}

// The machine link follows the same rule, and is built from the database on
// every use: an address set a moment ago is already in it.
func TestTheMachineLinkCarriesTheStoredAddresses(t *testing.T) {
	_, srv := newTestServerWith(t, func(s *Server) { s.cfg.Addr = "192.168.1.10:8080" })
	link, scannable := machineLinkNow(t, srv)
	if got := readLink(t, link); got.Onion != nil || !slices.Equal(got.Direct, []string{"192.168.1.10:8080"}) || !scannable {
		t.Fatalf("machine link with nothing stored = %+v (scannable %v)", got, scannable)
	}

	setStored(t, srv, store.AddressPublic, "nox.example.org:8443")
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	link, _ = machineLinkNow(t, srv)
	got := readLink(t, link)
	if !got.Onion.Equal(onionKeyOf(t, testOnionAddr)) || !got.ServerKey.Equal(serverKeyOf(t, srv)) ||
		!slices.Equal(got.Direct, []string{"nox.example.org:8443", "192.168.1.10:8080"}) {
		t.Fatalf("machine link with both stored = %+v", got)
	}
}

// A machine on loopback behind tor has nothing a phone can dial directly - and
// a phone can still pair with it through Tor (045, FR-008). The code is drawn
// whenever the link names an address another device can reach.
func TestALoopbackServerWithAnOnionAddressDrawsTheCode(t *testing.T) {
	_, srv := newTestServer(t) // bound to 127.0.0.1
	if _, scannable := machineLinkNow(t, srv); scannable {
		t.Fatal("loopback with nothing stored is scannable, want no code")
	}
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	if _, scannable := machineLinkNow(t, srv); !scannable {
		t.Fatal("loopback with an onion address is not scannable, want a code")
	}
	if !strings.Contains(statusBody(t, srv), "<svg") {
		t.Fatal("the page drew no code for a link a phone can follow through Tor")
	}
}

// A device revoked while its connection is still open cannot mint an invite:
// the command gets the answer its next greeting would get, and no token comes
// into being.
func TestADeviceRevokedMidSessionCannotIssueAnInvite(t *testing.T) {
	ts, srv := newTestServer(t)
	setStored(t, srv, store.AddressOnion, testOnionAddr)
	c := dialWS(t, ts, srv)
	c.expectGreeting()
	c.hello(1, "")
	// Revoked from elsewhere: straight in the store, so this socket stays open
	// the way it does between a revocation's commit and the server's close.
	if _, err := srv.store.RevokeDevice(context.Background(), c.dev.pub, time.Now().Unix()); err != nil {
		t.Fatalf("RevokeDevice: %v", err)
	}
	c.send(`{"id":2,"cmd":"device.invite","data":{}}`)
	c.expectErr(2, protocol.ErrUnauthenticated)
	c.send(`{"id":3,"cmd":"device.invite","data":{"onion":true}}`)
	c.expectErr(3, protocol.ErrUnauthenticated)

	var live int
	if err := readDB(t, srv).QueryRowContext(context.Background(),
		"SELECT COUNT(1) FROM pair_tokens WHERE kind = 'invite_device'").Scan(&live); err != nil {
		t.Fatalf("count invites: %v", err)
	}
	if live != 0 {
		t.Fatalf("%d invites written for a revoked device, want none", live)
	}
}

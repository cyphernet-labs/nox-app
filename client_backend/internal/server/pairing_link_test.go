package server

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"net"
	"testing"
)

// An IPv6 bind used to produce "[[::1]]:8080" - JoinHostPort brackets the
// literal, and bracketing it here too made a link this file's own parser
// rejects, so such a server printed no link at all.
func TestListenAddressHandlesEveryBindShape(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"127.0.0.1:8080", "127.0.0.1:8080"},
		{"[::1]:8080", "[::1]:8080"},
		{"0.0.0.0:8080", "127.0.0.1:8080"},
		{"[::]:8080", "127.0.0.1:8080"},
	} {
		if got := listenAddress(tc.in); got != tc.want {
			t.Fatalf("listenAddress(%q) = %q, want %q", tc.in, got, tc.want)
		}
		if _, err := BuildPairingLink(listenAddress(tc.in), "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=", "AAECAwQFBgcICQoLDA0ODw"); err != nil {
			t.Fatalf("a %s bind produced no link at all: %v", tc.in, err)
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
	fingerprint := base64.StdEncoding.EncodeToString(make([]byte, 32))
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))

	link, err := BuildPairingLink(inviteAddress("0.0.0.0:8080", "192.168.1.10:8080"), fingerprint, token)
	if err != nil {
		t.Fatalf("BuildPairingLink: %v", err)
	}
	payload, err := base64.RawURLEncoding.DecodeString(link[len(pairingLinkPrefix):])
	if err != nil {
		t.Fatalf("decode link: %v", err)
	}
	if payload[1] != hostTypeIPv4 {
		t.Fatalf("host type = %d, want IPv4", payload[1])
	}
	if got := net.IP(payload[2:6]).String(); got != "192.168.1.10" {
		t.Fatalf("host = %q, want 192.168.1.10", got)
	}
}

// fingerprintInLink digs the thirty-two bytes back out of a rendered link.
//
// Counted from the END rather than parsed forwards: the host field is variable
// length, and the trailing three fields - port, fingerprint, token - are fixed.
func fingerprintInLink(t *testing.T, link string) []byte {
	t.Helper()
	payload, err := base64.RawURLEncoding.DecodeString(link[len(pairingLinkPrefix):])
	if err != nil {
		t.Fatalf("decode link: %v", err)
	}
	if len(payload) < 1+1+2+32+16 {
		t.Fatalf("link payload is %d bytes, too short to hold a fingerprint", len(payload))
	}
	return payload[len(payload)-48 : len(payload)-16]
}

// The link carries the FINGERPRINT, not the key. The two are different objects
// and the field was called the wrong one until feature 036: a raw P-256 point
// is 65 bytes and never fitted in the thirty-two the format has, so anything
// that did fit was necessarily not the key.
func TestThePairingLinkCarriesTheFingerprintOfTheStoredKey(t *testing.T) {
	_, srv := newTestServer(t)
	id, err := srv.store.EnsureServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	spki, err := base64.StdEncoding.DecodeString(id.PublicKey)
	if err != nil {
		t.Fatalf("decode the public half: %v", err)
	}

	link, err := BuildPairingLink("127.0.0.1:8080", id.Fingerprint, base64.RawURLEncoding.EncodeToString(make([]byte, 16)))
	if err != nil {
		t.Fatalf("BuildPairingLink: %v", err)
	}

	sum := sha256.Sum256(spki)
	if got := fingerprintInLink(t, link); !bytes.Equal(got, sum[:]) {
		t.Fatalf("the link carries %x, want sha256 of the SPKI %x", got, sum)
	}
	// And not a truncation of the key, which is how somebody "fixes" a field
	// that no longer fits.
	if bytes.Equal(sum[:], spki[:32]) {
		t.Fatal("the fingerprint equals the head of the key, which means it was not hashed")
	}
}

// The server refuses to render a link it cannot fill honestly. Every one of the
// three call sites returns this error, so a wrong-sized field takes the claim
// link off the terminal rather than shipping thirty-two bytes of something else.
func TestAFingerprintOfTheWrongSizeProducesNoLinkAtAll(t *testing.T) {
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))
	for _, tc := range []struct {
		name        string
		fingerprint string
	}{
		{"a raw P-256 point", base64.StdEncoding.EncodeToString(make([]byte, 65))},
		{"a whole SPKI", base64.StdEncoding.EncodeToString(make([]byte, 91))},
		{"not base64 at all", "this is not base64!"},
		{"empty", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := BuildPairingLink("127.0.0.1:8080", tc.fingerprint, token); err == nil {
				t.Fatal("a link was rendered from a fingerprint that is not 32 bytes")
			}
		})
	}
}

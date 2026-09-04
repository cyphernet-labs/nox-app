package server

import (
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
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	token := base64.RawURLEncoding.EncodeToString(make([]byte, 16))

	link, err := BuildPairingLink(inviteAddress("0.0.0.0:8080", "192.168.1.10:8080"), key, token)
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

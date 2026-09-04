package server

import "testing"

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

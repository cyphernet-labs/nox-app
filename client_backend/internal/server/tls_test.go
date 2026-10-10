package server

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/tls"
	"io"
	"net"
	"path/filepath"
	"testing"
	"time"

	"nox.app/client-backend/internal/eidolon"
)

// The TLS layer of the channel, on its own. Who is on each end is the channel
// check's question (channel_test.go); what is asked here is that the layer
// under it is TLS 1.3, a full handshake every time, and a certificate that
// claims nothing.

// A plain request is answered with nothing at all - not a 400, not a word.
// There is no flag to turn this off and no fallback: a channel that can be
// downgraded is a channel an attacker downgrades.
func TestAPlainRequestIsAnsweredWithNothing(t *testing.T) {
	ts, _ := newTestServer(t)

	conn, err := net.Dial("tcp", ts.Listener.Addr().String())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer func() { _ = conn.Close() }()
	if _, err := conn.Write([]byte("GET /ws HTTP/1.1\r\nHost: nox\r\n\r\n")); err != nil {
		t.Fatalf("write: %v", err)
	}
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	got, _ := io.ReadAll(conn)
	if len(got) != 0 {
		t.Fatalf("a plain request was answered with %q", got)
	}
}

// TLS 1.2 is refused. The exporter the check signs is TLS 1.3's, and without
// this the minimum version rests on one line nothing would notice the loss of.
func TestATLS12ClientIsRefused(t *testing.T) {
	ts, _ := newTestServer(t)

	conn, err := tls.Dial("tcp", ts.Listener.Addr().String(), &tls.Config{
		//nolint:gosec // deliberately lax everywhere except the version under test
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
		MaxVersion:         tls.VersionTLS12,
	})
	if err == nil {
		_ = conn.Close()
		t.Fatal("a client capped at TLS 1.2 completed a handshake")
	}
}

// presentedCertificate completes a bare TLS handshake and returns what the
// server presented - a handshake only: the check after it is not this test's.
func presentedCertificate(t *testing.T, addr string, cfg *tls.Config) tls.ConnectionState {
	t.Helper()
	conn, err := tls.Dial("tcp", addr, cfg)
	if err != nil {
		t.Fatalf("tls.Dial: %v", err)
	}
	defer func() { _ = conn.Close() }()
	return conn.ConnectionState()
}

// The certificate is technical: a throwaway P-256 key, self-issued, naming no
// host - and above all not the machine's key, which only the channel check
// ever proves. The negotiated protocol is http/1.1, the one the WebSocket
// upgrade exists in.
func TestTheCertificateIsTechnicalAndNotTheMachineKey(t *testing.T) {
	ts, srv := newTestServer(t)
	state := presentedCertificate(t, ts.Listener.Addr().String(), testClientTLS())

	if state.Version != tls.VersionTLS13 {
		t.Fatalf("negotiated %x, want TLS 1.3", state.Version)
	}
	if state.NegotiatedProtocol != "http/1.1" {
		t.Fatalf("negotiated %q, want http/1.1", state.NegotiatedProtocol)
	}
	leaf := state.PeerCertificates[0]
	if _, ok := leaf.PublicKey.(*ecdsa.PublicKey); !ok {
		t.Fatalf("the certificate key is %T, want a throwaway ECDSA key", leaf.PublicKey)
	}
	if len(leaf.DNSNames) != 0 || len(leaf.IPAddresses) != 0 {
		t.Fatalf("the certificate names hosts (%v %v); a device would then be tempted to check them",
			leaf.DNSNames, leaf.IPAddresses)
	}
	if leaf.Issuer.String() != leaf.Subject.String() {
		t.Fatalf("issuer %q is not the subject %q", leaf.Issuer, leaf.Subject)
	}
	// The machine's key is Ed25519 and lives in the store: an ECDSA key above
	// is already not it, and the store still holds the one the links carry.
	if len(serverKeyOf(t, srv)) == 0 {
		t.Fatal("the machine has no key of its own")
	}
}

// A restart hands out a NEW certificate on a NEW key - nothing in it is kept -
// and a device paired before the restart gets in all the same, because what
// it checks is the machine's key in the channel, which the store keeps.
func TestARestartMintsANewCertificateAndPairedDevicesStillGetIn(t *testing.T) {
	path := filepath.Join(t.TempDir(), "restart.db")

	first, srv, closeFirst := openStack(t, path, nil)
	dev := pairedDevice(t, first, srv)
	before := presentedCertificate(t, first.Listener.Addr().String(), testClientTLS()).PeerCertificates[0]
	closeFirst()

	second, srv2, closeSecond := openStack(t, path, nil)
	defer closeSecond()
	after := presentedCertificate(t, second.Listener.Addr().String(), testClientTLS()).PeerCertificates[0]
	if before.SerialNumber.Cmp(after.SerialNumber) == 0 {
		t.Fatal("the restart served the same certificate")
	}
	if before.PublicKey.(*ecdsa.PublicKey).Equal(after.PublicKey) {
		t.Fatal("the restart reused the certificate key, so something is keeping it")
	}

	c := dialAs(t, second, srv2, dev)
	c.expectGreeting()
	c.hello(1, "")
}

// Every connection is a full handshake: the server issues no session tickets,
// so a client that keeps a session cache still cannot resume. A resumed TLS 1.3
// session is not signed by the server again, and the contract wants a verified
// handshake signature on every connection.
func TestEveryConnectionIsAFullHandshake(t *testing.T) {
	ts, _ := newTestServer(t)
	cfg := &tls.Config{
		//nolint:gosec // the certificate is not the question here
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS13,
		NextProtos:         []string{"http/1.1"},
		ClientSessionCache: tls.NewLRUClientSessionCache(4),
		ServerName:         "nox",
	}
	for i := range 3 {
		conn, err := tls.Dial("tcp", ts.Listener.Addr().String(), cfg)
		if err != nil {
			t.Fatalf("dial %d: %v", i, err)
		}
		// A ticket arrives after the handshake, if at all: read for a moment
		// so one would have been taken in before the next dial.
		_ = conn.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
		_, _ = conn.Read(make([]byte, 1))
		resumed := conn.ConnectionState().DidResume
		_ = conn.Close()
		if resumed {
			t.Fatalf("connection %d resumed a session", i)
		}
	}
}

// The binding is the RFC 9266 exporter with an EMPTY context. The app's
// module asks for exactly that (Some(b"") in rustls) while this side passes
// nil; in TLS 1.3 the two are the same value, and if they ever were not, every
// device would fail the check with a signature mismatch nobody could explain.
func TestTheBindingIsTheSameWithANilOrAnEmptyContext(t *testing.T) {
	ts, _ := newTestServer(t)
	conn, err := tls.Dial("tcp", ts.Listener.Addr().String(), testClientTLS())
	if err != nil {
		t.Fatalf("tls.Dial: %v", err)
	}
	defer func() { _ = conn.Close() }()
	state := conn.ConnectionState()
	withNil, err := state.ExportKeyingMaterial(eidolon.ExporterLabel, nil, eidolon.BindingSize)
	if err != nil {
		t.Fatalf("exporter with nil: %v", err)
	}
	withEmpty, err := state.ExportKeyingMaterial(eidolon.ExporterLabel, []byte{}, eidolon.BindingSize)
	if err != nil {
		t.Fatalf("exporter with an empty context: %v", err)
	}
	if !bytes.Equal(withNil, withEmpty) {
		t.Fatalf("nil context %x, empty context %x", withNil, withEmpty)
	}
}

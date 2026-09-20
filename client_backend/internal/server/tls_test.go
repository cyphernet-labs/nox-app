package server

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"nox.app/client-backend/internal/store"
)

// A plain request never reaches a handler. There is no flag to turn this off
// and no fallback: a channel that can be downgraded is a channel an attacker
// downgrades.
//
// The refusal comes from the TLS layer, which answers such a request with a
// plaintext 400 saying so, rather than from a closed socket - so the test is
// written against what a handler would have returned, not against the dial.
func TestAPlainRequestNeverReachesAHandler(t *testing.T) {
	ts, _ := newTestServer(t)

	plain := "http://" + ts.Listener.Addr().String() + "/health"
	resp, err := http.Get(plain) //nolint:noctx // the point is what comes back
	if err != nil {
		return // a closed socket is an even clearer refusal
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode == http.StatusOK {
		t.Fatalf("GET %s was served over plain HTTP", plain)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read the refusal: %v", err)
	}
	if strings.Contains(string(body), `"status"`) {
		t.Fatalf("the health handler answered a plain request: %s", body)
	}
}

// TLS 1.2 is refused. Without this the minimum version rests on one line of
// configuration that nothing would notice the loss of.
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

// The certificate has to carry the key the link fingerprints, or every device
// that followed the link refuses the very server that issued it.
func TestTheCertificateCarriesTheKeyTheLinkFingerprints(t *testing.T) {
	ts, srv := newTestServer(t)
	id, err := srv.store.ServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}

	leaf := ts.TLS.Certificates[0].Leaf
	if leaf == nil {
		t.Fatal("the certificate has no parsed Leaf, so nothing can read what was issued")
	}
	if got := store.FingerprintOfSPKI(leaf.RawSubjectPublicKeyInfo); got != id.Fingerprint {
		t.Fatalf("certificate fingerprint %s, identity fingerprint %s", got, id.Fingerprint)
	}

	// And the same bytes all the way into the link a person carries.
	link, err := BuildPairingLink("127.0.0.1:8080", id.Fingerprint, base64.RawURLEncoding.EncodeToString(make([]byte, 16)))
	if err != nil {
		t.Fatalf("BuildPairingLink: %v", err)
	}
	want, err := base64.StdEncoding.DecodeString(id.Fingerprint)
	if err != nil {
		t.Fatalf("decode the fingerprint: %v", err)
	}
	if got := fingerprintInLink(t, link); !bytes.Equal(got, want) {
		t.Fatalf("the link carries %x, the certificate %x", got, want)
	}
}

// The dates and the name decide nothing, so a restart may hand out a brand-new
// certificate and a device pinned days ago must not notice.
func TestARestartIssuesANewCertificateThePinStillAccepts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "restart.db")

	first, srv, closeFirst := openStack(t, path, nil)
	id, err := srv.store.ServerIdentity(context.Background())
	if err != nil {
		closeFirst()
		t.Fatalf("ServerIdentity: %v", err)
	}
	firstSerial := first.TLS.Certificates[0].Leaf.SerialNumber
	closeFirst()

	second, _, closeSecond := openStack(t, path, nil)
	defer closeSecond()

	leaf := second.TLS.Certificates[0].Leaf
	if leaf.SerialNumber.Cmp(firstSerial) == 0 {
		t.Fatal("the restart reused the certificate, so nothing proves it is rebuilt from the key")
	}
	if got := store.FingerprintOfSPKI(leaf.RawSubjectPublicKeyInfo); got != id.Fingerprint {
		t.Fatalf("the restart changed the key: %s, was %s", got, id.Fingerprint)
	}
	// The proof that matters: a client holding only the old fingerprint still
	// gets in.
	client := &http.Client{Transport: &http.Transport{TLSClientConfig: PinnedTLSConfig(id.Fingerprint)}}
	resp, err := client.Get(second.URL + "/health") //nolint:noctx // a health probe
	if err != nil {
		t.Fatalf("a device pinned before the restart was refused: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health after restart = %d", resp.StatusCode)
	}
}

// A chain whose LEAF is a stranger's is refused, however right the certificate
// on top of it is.
//
// The Go twin of the Dart check, and it earns its place: the Dart side had
// exactly this hole - it judged the TOP of the presented chain, so appending
// this server's public certificate above a stranger's leaf was a complete
// MITM. `rawCerts[0]` is the leaf and always has been here, but nothing held
// it: the mutation to `rawCerts[len-1]` passed every Go test.
func TestAChainWithAStrangerLeafIsRefusedHoweverRightTheTop(t *testing.T) {
	ts, srv := newTestServer(t)
	ours := ts.TLS.Certificates[0]
	id, err := srv.store.ServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}

	stranger, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate a stranger key: %v", err)
	}
	strangerCert, err := buildCertificate(stranger, time.Now())
	if err != nil {
		t.Fatalf("buildCertificate: %v", err)
	}

	// The attacker holds only their own key, and borrows our certificate - it
	// is public, handed to everyone who ever dialled us.
	hostile := tls.Certificate{
		Certificate: [][]byte{strangerCert.Certificate[0], ours.Certificate[0]},
		PrivateKey:  stranger,
		Leaf:        strangerCert.Leaf,
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	cfg := &tls.Config{Certificates: []tls.Certificate{hostile}, MinVersion: tls.VersionTLS13, NextProtos: []string{"http/1.1"}}
	stand := &http.Server{Handler: srv.Handler(), ReadHeaderTimeout: readHeaderTimeout}
	go func() { _ = stand.Serve(tls.NewListener(listener, cfg)) }()
	t.Cleanup(func() { _ = stand.Close() })

	client := &http.Client{Transport: &http.Transport{TLSClientConfig: PinnedTLSConfig(id.Fingerprint)}}
	resp, err := client.Get("https://" + listener.Addr().String() + "/health") //nolint:noctx // expected to fail
	if err == nil {
		_ = resp.Body.Close()
		t.Fatal("a chain with a stranger's leaf and our certificate on top was accepted")
	}
	if !strings.Contains(err.Error(), ErrPinMismatch.Error()) {
		t.Fatalf("refused, but not by the pin: %v", err)
	}
}

// Somebody else's key is refused, which is the entire point of the phase.
func TestAnotherKeyIsRefusedNoMatterHowValidItsCertificateLooks(t *testing.T) {
	ts, _ := newTestServer(t)

	stranger, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate a stranger key: %v", err)
	}
	cert, err := buildCertificate(stranger, time.Now())
	if err != nil {
		t.Fatalf("buildCertificate: %v", err)
	}
	strangerFingerprint := store.FingerprintOfSPKI(cert.Leaf.RawSubjectPublicKeyInfo)

	client := &http.Client{Transport: &http.Transport{TLSClientConfig: PinnedTLSConfig(strangerFingerprint)}}
	resp, err := client.Get(ts.URL + "/health") //nolint:noctx // expected to fail
	if err == nil {
		_ = resp.Body.Close()
		t.Fatal("a client pinned to another key connected anyway")
	}
}

// An expired certificate, a name belonging to somebody else and an unknown
// issuer must all be ACCEPTED when the key is right.
//
// The negative cases above would pass against an implementation that refuses on
// dates or names - and that implementation breaks on the first home server
// whose owner forgot about it. Tolerance has to be asserted positively.
func TestTheWrongDatesNameAndIssuerAreAllToleratedOnTheRightKey(t *testing.T) {
	ts, srv := newTestServer(t)
	id, err := srv.store.ServerIdentity(context.Background())
	if err != nil {
		t.Fatalf("ServerIdentity: %v", err)
	}
	signer, err := srv.store.ServerSigner(context.Background())
	if err != nil {
		t.Fatalf("ServerSigner: %v", err)
	}

	// Long expired, on the machine's real key.
	expired, err := buildCertificate(signer, time.Now().AddDate(-200, 0, 0))
	if err != nil {
		t.Fatalf("buildCertificate: %v", err)
	}
	if !expired.Leaf.NotAfter.Before(time.Now()) {
		t.Fatalf("the fixture is not actually expired: NotAfter %s", expired.Leaf.NotAfter)
	}

	replacement := &tls.Config{
		Certificates: []tls.Certificate{expired},
		MinVersion:   tls.VersionTLS13,
		NextProtos:   []string{"http/1.1"},
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	// Serve, not ServeTLS: the listener below is ALREADY wrapped, and ServeTLS
	// wraps what it is given a second time. That put a tls.Conn inside a
	// tls.Conn - the handshake the pin cares about still happened on the inner
	// one, so the dial succeeded, but the outer layer then read decrypted HTTP
	// as if it were a handshake and answered 400 without a handler ever
	// running. The test passed because it never looked at the status.
	stand := &http.Server{Handler: srv.Handler(), ReadHeaderTimeout: readHeaderTimeout}
	go func() { _ = stand.Serve(tls.NewListener(listener, replacement)) }()
	t.Cleanup(func() { _ = stand.Close() })

	client := &http.Client{Transport: &http.Transport{TLSClientConfig: PinnedTLSConfig(id.Fingerprint)}}
	resp, err := client.Get("https://" + listener.Addr().String() + "/health") //nolint:noctx // a health probe
	if err != nil {
		t.Fatalf("an expired certificate on the right key was refused: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	// The status IS the assertion. Without it this test proves only that a
	// connection was made, which is true of a server answering nothing but
	// errors.
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("the expired-certificate stand answered %d, want 200", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read the health answer: %v", err)
	}
	if string(body) != `{"status":"ok"}` {
		t.Fatalf("health over the expired certificate returned %s", body)
	}

	// The name is not asserted at all - there is no SAN and the subject is not
	// a host name - and the issuer is the key itself, which no store knows.
	leaf := ts.TLS.Certificates[0].Leaf
	if len(leaf.DNSNames) != 0 || len(leaf.IPAddresses) != 0 {
		t.Fatalf("the certificate names hosts (%v %v); a device would then have to reach it by that name",
			leaf.DNSNames, leaf.IPAddresses)
	}
	if leaf.Issuer.String() != leaf.Subject.String() {
		t.Fatalf("issuer %q is not the subject %q, so something signed this but the machine itself",
			leaf.Issuer, leaf.Subject)
	}
}

package server

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"fmt"
	"math/big"
	"time"

	"nox.app/client-backend/internal/store"
)

// This file holds BOTH halves of the same decision: the certificate the server
// presents, and the check a client runs against it. They are one rule read from
// two ends, and keeping them apart is how the two ends drift.
//
// The rule: trust is the KEY, carried as a fingerprint in the pairing link a
// person moved by hand. Nothing else about the certificate decides anything -
// not its name, not its dates, not who signed it. A home server has no domain
// name to be issued a certificate for, so every one of those would be a refusal
// the owner can neither explain nor repair.

// certificateLifetime is how long the certificate claims to be valid.
//
// A hundred years, which is another way of saying the dates decide nothing. An
// expiry would eventually become an unfixable refusal on a server somebody
// installed and forgot about, and nothing on the client side reads it anyway.
const certificateLifetime = 100 * 365 * 24 * time.Hour

// certificateBackdate covers a client whose clock runs behind the server's.
// Home machines have no reason to agree on the time.
const certificateBackdate = 24 * time.Hour

// buildCertificate mints the certificate from the machine's own key.
//
// No SAN and no name that looks like one: the verifying side ignores names by
// construction, and writing a hostname in here would invite somebody to start
// depending on it. The key is the identity; this is its wrapper.
func buildCertificate(signer crypto.Signer, now time.Time) (tls.Certificate, error) {
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("pick a certificate serial: %w", err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "NOX client server"},
		NotBefore:             now.Add(-certificateBackdate),
		NotAfter:              now.Add(certificateLifetime),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, signer.Public(), signer)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("create the server certificate: %w", err)
	}
	// Leaf is filled here rather than left for the handshake to parse: it is
	// the only way a caller can read back what was just issued, and the tests
	// that compare its fingerprint to the link's depend on it.
	leaf, err := x509.ParseCertificate(der)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("parse the certificate just created: %w", err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: signer, Leaf: leaf}, nil
}

// serverTLSConfig builds the configuration the main listener serves with.
//
// Called once per start, and the certificate lives in memory only: there is
// nothing in it worth keeping, since it is rebuilt from the stored key every
// time and a client pins that key rather than this wrapper. Writing it to disk
// would only add a file that can go stale.
func (s *Server) serverTLSConfig(ctx context.Context) (*tls.Config, error) {
	signer, err := s.store.ServerSigner(ctx)
	if err != nil {
		return nil, fmt.Errorf("read the server key: %w", err)
	}
	cert, err := buildCertificate(signer, time.Now())
	if err != nil {
		return nil, err
	}
	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		// Both ends are written today and owe nothing to anything older.
		MinVersion: tls.VersionTLS13,
		// http/1.1 explicitly, because ServeTLS otherwise offers h2 - and the
		// WebSocket upgrade this server is built around does not exist there.
		// A client that negotiated h2 would reach /ws and be refused.
		NextProtos: []string{"http/1.1"},
	}, nil
}

// ErrPinMismatch is what a pinned dial fails with when the machine answering
// is not the one the link named.
var ErrPinMismatch = errors.New("the server presented a different key than the pairing link named")

// PinnedTLSConfig is the CLIENT half: dial anything, trust only this key.
//
// Used by cmd/smoke and by the test helpers, and it is deliberately the same
// shape the Dart client implements - find the certificate's SubjectPublicKeyInfo,
// hash it, compare. InsecureSkipVerify turns off the chain check and the name
// check, neither of which a self-signed certificate on a nameless machine can
// pass; VerifyPeerCertificate then puts back a stricter test than either, since
// it admits exactly one key instead of every key a certificate authority is
// willing to vouch for.
func PinnedTLSConfig(fingerprint string) *tls.Config {
	return &tls.Config{
		MinVersion: tls.VersionTLS13,
		//nolint:gosec // the pin below replaces the chain check; see the doc comment
		InsecureSkipVerify: true,
		VerifyPeerCertificate: func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
			if len(rawCerts) == 0 {
				return fmt.Errorf("%w: it presented no certificate at all", ErrPinMismatch)
			}
			leaf, err := x509.ParseCertificate(rawCerts[0])
			if err != nil {
				return fmt.Errorf("%w: its certificate does not parse: %v", ErrPinMismatch, err)
			}
			got := store.FingerprintOfSPKI(leaf.RawSubjectPublicKeyInfo)
			if got != fingerprint {
				return fmt.Errorf("%w: presented %s, pinned %s", ErrPinMismatch, got, fingerprint)
			}
			return nil
		},
	}
}

package server

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"fmt"
	"math/big"
	"time"
)

// The TLS layer of the channel (contract §1, feature 044) and nothing more.
//
// TLS here buys an encrypted session and the binding the channel check signs;
// it does NOT decide who is on the other end. That is the check's job
// (channel.go): the device proves its key and the server proves the machine's,
// both over this session's exporter. So the certificate is technical - a
// throwaway key minted in memory on every start, which no client compares with
// anything - and the machine's own key never meets a TLS stack at all.

// certificateLifetime is how long the certificate claims to be valid.
//
// A hundred years, which is another way of saying the dates decide nothing:
// nothing on the client side reads them, and an expiry would only be one more
// way for a forgotten home server to fail a library that does.
const certificateLifetime = 100 * 365 * 24 * time.Hour

// certificateBackdate covers a client whose clock runs behind the server's.
// Home machines have no reason to agree on the time.
const certificateBackdate = 24 * time.Hour

// buildCertificate wraps signer in a self-signed certificate.
//
// No SAN and no name that looks like one: the client sends no SNI and checks
// no name, and writing a hostname in here would invite somebody to start
// depending on it.
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
	// the only way a caller - a test - can read back what was just issued.
	leaf, err := x509.ParseCertificate(der)
	if err != nil {
		return tls.Certificate{}, fmt.Errorf("parse the certificate just created: %w", err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: signer, Leaf: leaf}, nil
}

// channelTLSConfig builds the TLS configuration the main port serves the
// channel with - for every path, the one through tor included.
//
// Called once per start. The certificate's key is ECDSA P-256 because every
// TLS implementation speaks it, and it is minted here and kept in memory only:
// nothing in it is worth keeping, and a key that is never written cannot leak
// from a backup.
func channelTLSConfig(now time.Time) (*tls.Config, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate the certificate key: %w", err)
	}
	cert, err := buildCertificate(key, now)
	if err != nil {
		return nil, err
	}
	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		// Both ends are written today and owe nothing to anything older; the
		// exporter the check signs is TLS 1.3's (RFC 9266).
		MinVersion: tls.VersionTLS13,
		// http/1.1 and nothing else: the WebSocket upgrade this server is built
		// around does not exist over h2.
		NextProtos: []string{"http/1.1"},
		// Every connection is a full handshake. A resumed TLS 1.3 session is not
		// signed by the server again, and the contract wants a verified
		// handshake signature on each one; Go's server has no early data to turn
		// off besides.
		SessionTicketsDisabled: true,
	}, nil
}

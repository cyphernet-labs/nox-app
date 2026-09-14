//go:build ignore

// Command generate_pin_fixtures writes the certificate fixtures the Dart side
// pins against.
//
// They are GENERATED here and CHECKED IN there, because the Dart side has
// nothing that can mint an X.509 certificate: there is no such package in
// pubspec.yaml and adding one for a test is not on the table. Go already has
// to produce these bytes for real, so the fixtures come from the same code
// path the server uses.
//
// Deterministic where it matters: the keys come from fixed seeds and the
// validity windows from fixed dates, so the subject public key - the only part
// of a certificate the pin ever reads - is identical on every run.
//
// The SIGNATURE bytes are not, and cannot be made so: Go hedges the ECDSA
// nonce with randomness drawn from a source no caller controls, precisely so
// that nobody depends on how much a signature consumes. A regeneration
// therefore shows a diff in the signature of every ECDSA-signed fixture and in
// nothing else.
//
// Regenerate from the client_backend directory:
//
//	go run internal/server/testdata/generate_pin_fixtures.go
package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

// outDir is where the Dart tests read the fixtures from. Relative to
// client_backend, which is where this is run.
const outDir = "../test/general/pairing/fixtures"

// Two keys and nothing else. Every fixture is on one of them, and the README
// says which - a fixture whose key is ambiguous proves nothing either way.
const (
	seedServer   = "nox/036/fixtures/server-key"
	seedStranger = "nox/036/fixtures/stranger-key"
	seedIssuer   = "nox/036/fixtures/unknown-issuer-key"
)

// Fixed dates: a validity window nobody has to recompute, and an expiry that is
// already in the past and always will be.
var (
	issuedAt  = time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	longAgo   = time.Date(2019, 1, 1, 0, 0, 0, 0, time.UTC)
	deadSince = time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	farFuture = time.Date(2126, 1, 1, 0, 0, 0, 0, time.UTC)
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "generate pin fixtures: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}

	server := keyFromSeed(seedServer)
	stranger := keyFromSeed(seedStranger)
	issuer := keyFromSeed(seedIssuer)

	spki, err := x509.MarshalPKIXPublicKey(server.Public())
	if err != nil {
		return err
	}
	sum := sha256.Sum256(spki)
	fingerprint := base64.StdEncoding.EncodeToString(sum[:])

	// The key the tolerance fixtures are served with. One file for all three,
	// because all three are on the SAME correct key - that is the point of
	// them.
	pkcs8, err := x509.MarshalPKCS8PrivateKey(server)
	if err != nil {
		return err
	}
	if err := writeFile("server_key.pem", pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pkcs8})); err != nil {
		return err
	}
	if err := writeFile("fingerprint.txt", []byte(fingerprint+"\n")); err != nil {
		return err
	}
	// And the foreign key, so a test can actually SERVE the stranger
	// certificate rather than only hash it. A refusal proved against a real
	// handshake is worth more than one proved against a byte array.
	strangerPKCS8, err := x509.MarshalPKCS8PrivateKey(stranger)
	if err != nil {
		return err
	}
	if err := writeFile("stranger_key.pem", pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: strangerPKCS8})); err != nil {
		return err
	}

	// 1. The positive case: an ordinary certificate on the correct key.
	valid, err := issue(certSpec{seed: "valid", key: server, notBefore: issuedAt, notAfter: farFuture, cn: "NOX client server"}, server)
	if err != nil {
		return err
	}
	if err := writeCert("valid", valid); err != nil {
		return err
	}

	// 2. A restart: a DIFFERENT certificate on the SAME key. Must be accepted,
	//    or a server would lock out every device each time it was restarted.
	reissued, err := issue(certSpec{seed: "reissued", key: server, notBefore: issuedAt, notAfter: farFuture, cn: "NOX client server"}, server)
	if err != nil {
		return err
	}
	if err := writeCert("reissued", reissued); err != nil {
		return err
	}

	// 3. Somebody else's key. The whole phase in one file.
	strangerCert, err := issue(certSpec{seed: "stranger", key: stranger, notBefore: issuedAt, notAfter: farFuture, cn: "NOX client server"}, stranger)
	if err != nil {
		return err
	}
	if err := writeCert("stranger", strangerCert); err != nil {
		return err
	}

	// 4. Truncated: the header is there, the key behind it is not.
	//
	//    Cut INSIDE the SubjectPublicKeyInfo, not off the end. Trimming the
	//    tail only removes the signature and leaves the key whole - which a
	//    correct check accepts, so such a fixture would prove nothing. This one
	//    stops twenty bytes into a sixty-five-byte point.
	at := indexOfSPKIPrefix(valid)
	if at < 0 {
		return fmt.Errorf("the valid fixture has no P-256 SubjectPublicKeyInfo in it")
	}
	if err := writeFile("truncated.der", valid[:at+len(spkiPrefix)+20]); err != nil {
		return err
	}

	// 5. No P-256 SubjectPublicKeyInfo at all. An Ed25519 certificate, which is
	//    not a hypothetical shape: it is exactly what this server issued before
	//    feature 036.
	headerless, err := issueEd25519()
	if err != nil {
		return err
	}
	if err := writeFile("headerless.der", headerless); err != nil {
		return err
	}

	// 6. Expired, on the CORRECT key. Must be ACCEPTED: a home server's owner
	//    may not have touched it for years.
	expired, err := issue(certSpec{seed: "expired", key: server, notBefore: longAgo, notAfter: deadSince, cn: "NOX client server"}, server)
	if err != nil {
		return err
	}
	if err := writeCert("expired", expired); err != nil {
		return err
	}

	// 7. Naming somebody else entirely, on the CORRECT key. Must be ACCEPTED:
	//    a home server has no name, and its address changes.
	wrongName, err := issue(certSpec{
		seed:      "wrong-name",
		key:       server,
		notBefore: issuedAt,
		notAfter:  farFuture,
		cn:        "mail.example.com",
		dnsNames:  []string{"mail.example.com", "www.example.com"},
		ips:       []net.IP{net.ParseIP("203.0.113.7")},
	}, server)
	if err != nil {
		return err
	}
	if err := writeCert("wrong_name", wrongName); err != nil {
		return err
	}

	// 8. THE ATTACK. A certificate whose real key is the FOREIGN one, carrying a
	//    verbatim copy of the correct key's SubjectPublicKeyInfo planted in an
	//    earlier field of the same certificate.
	//
	//    This is not exotic. In a TBSCertificate the issuer and subject Names
	//    come BEFORE subjectPublicKeyInfo, so anything that locates the key by
	//    scanning for a byte pattern finds the plant first and hashes it - and
	//    the bytes needed to build the plant are public, handed to every client
	//    that dials the real server. A verifier must read the certificate's
	//    ACTUAL subjectPublicKeyInfo, not the first thing shaped like one.
	planted, err := issue(certSpec{
		seed:      "planted",
		key:       stranger,
		notBefore: issuedAt,
		notAfter:  farFuture,
		cn:        "NOX client server",
		decoy:     spki,
	}, stranger)
	if err != nil {
		return err
	}
	if err := writeCert("planted", planted); err != nil {
		return err
	}
	// The fixture is worthless unless the decoy really does come first and the
	// real key really is the foreign one, so both are asserted here rather than
	// assumed by whoever reads the file later.
	plantedLeaf, err := x509.ParseCertificate(planted)
	if err != nil {
		return err
	}
	decoyAt := bytes.Index(planted, spki)
	realAt := bytes.Index(planted, plantedLeaf.RawSubjectPublicKeyInfo)
	if bytes.Equal(plantedLeaf.RawSubjectPublicKeyInfo, spki) {
		return fmt.Errorf("the planted fixture carries the CORRECT key for real, so it proves nothing")
	}
	if decoyAt < 0 || realAt < 0 || decoyAt >= realAt {
		return fmt.Errorf("the planted fixture does not put the decoy (%d) before the real key (%d)", decoyAt, realAt)
	}
	fmt.Printf("  planted: decoy at %d, real key at %d\n", decoyAt, realAt)

	// 9. Signed by an authority nothing on earth trusts, on the CORRECT key.
	//    Must be ACCEPTED: trust comes from the link, not from an issuer.
	caDER, err := issueCA(issuer)
	if err != nil {
		return err
	}
	ca, err := x509.ParseCertificate(caDER)
	if err != nil {
		return err
	}
	unknownIssuer, err := issueBy(certSpec{seed: "unknown-issuer", key: server, notBefore: issuedAt, notAfter: farFuture, cn: "NOX client server"}, ca, issuer)
	if err != nil {
		return err
	}
	if err := writeCert("unknown_issuer", unknownIssuer); err != nil {
		return err
	}
	// The chain a server actually presents: leaf first, then the authority.
	chain := append(
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: unknownIssuer}),
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})...,
	)
	if err := writeFile("unknown_issuer_chain.pem", chain); err != nil {
		return err
	}

	return writeFile("README.md", []byte(readme(fingerprint)))
}

// spkiPrefix is the fixed 26-byte head of a P-256 SubjectPublicKeyInfo - the
// same bytes the Dart side scans for, written out here so the truncated fixture
// can be cut in the one place that makes it a truncated KEY.
var spkiPrefix = []byte{
	0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
	0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
	0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
	0x42, 0x00,
}

func indexOfSPKIPrefix(der []byte) int { return bytes.Index(der, spkiPrefix) }

type certSpec struct {
	seed      string
	key       *ecdsa.PrivateKey
	notBefore time.Time
	notAfter  time.Time
	cn        string
	dnsNames  []string
	ips       []net.IP
	// decoy, when set, is planted verbatim into the subject as an extra
	// attribute value - ahead of the real key in the encoding.
	decoy []byte
}

func issue(spec certSpec, signer *ecdsa.PrivateKey) ([]byte, error) {
	tmpl := template(spec)
	return x509.CreateCertificate(readerFor(spec.seed), tmpl, tmpl, spec.key.Public(), signer)
}

func issueBy(spec certSpec, parent *x509.Certificate, signer *ecdsa.PrivateKey) ([]byte, error) {
	return x509.CreateCertificate(readerFor(spec.seed), template(spec), parent, spec.key.Public(), signer)
}

func issueCA(key *ecdsa.PrivateKey) ([]byte, error) {
	tmpl := &x509.Certificate{
		SerialNumber:          serialFor("unknown-authority"),
		Subject:               pkix.Name{CommonName: "Nobody's Certificate Authority"},
		NotBefore:             issuedAt,
		NotAfter:              farFuture,
		KeyUsage:              x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	return x509.CreateCertificate(readerFor("unknown-authority"), tmpl, tmpl, key.Public(), key)
}

func issueEd25519() ([]byte, error) {
	// Deterministic seed, so the file does not churn.
	seed := sha256.Sum256([]byte("nox/036/fixtures/ed25519-key"))
	key := ed25519.NewKeyFromSeed(seed[:])
	tmpl := &x509.Certificate{
		SerialNumber:          serialFor("headerless"),
		Subject:               pkix.Name{CommonName: "NOX client server"},
		NotBefore:             issuedAt,
		NotAfter:              farFuture,
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	// Ed25519 signs deterministically, so no reader is consulted.
	return x509.CreateCertificate(readerFor("headerless"), tmpl, tmpl, key.Public(), key)
}

func template(spec certSpec) *x509.Certificate {
	subject := pkix.Name{CommonName: spec.cn}
	if spec.decoy != nil {
		// asn1.RawValue with FullBytes set is emitted verbatim, so the decoy
		// lands in the certificate exactly as the real key would look.
		subject.ExtraNames = []pkix.AttributeTypeAndValue{
			{Type: asn1.ObjectIdentifier{2, 5, 4, 13}, Value: asn1.RawValue{FullBytes: spec.decoy}},
		}
	}
	return &x509.Certificate{
		SerialNumber:          serialFor(spec.seed),
		Subject:               subject,
		NotBefore:             spec.notBefore,
		NotAfter:              spec.notAfter,
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              spec.dnsNames,
		IPAddresses:           spec.ips,
	}
}

// keyFromSeed builds a P-256 key from a fixed string.
//
// Not ecdsa.GenerateKey: that draws from a random source in a way nothing can
// pin down, and a fixture that differs on every regeneration is a diff nobody
// can review.
func keyFromSeed(seed string) *ecdsa.PrivateKey {
	sum := sha512.Sum512([]byte(seed))
	curve := elliptic.P256()
	n := curve.Params().N
	// Reduce into [1, n-1]. The bias is irrelevant for a fixture.
	d := new(big.Int).Mod(new(big.Int).SetBytes(sum[:]), new(big.Int).Sub(n, big.NewInt(1)))
	d.Add(d, big.NewInt(1))
	key := &ecdsa.PrivateKey{D: d}
	key.Curve = curve
	key.X, key.Y = curve.ScalarBaseMult(d.Bytes())
	return key
}

func serialFor(seed string) *big.Int {
	sum := sha256.Sum256([]byte("nox/036/fixtures/serial/" + seed))
	return new(big.Int).SetBytes(sum[:16])
}

// readerFor is the randomness certificate creation draws on: a fixed stream, so
// the same fixture comes out byte for byte on every run.
func readerFor(seed string) io.Reader { return &streamReader{seed: seed} }

type streamReader struct {
	seed    string
	counter uint64
	buf     []byte
}

func (r *streamReader) Read(p []byte) (int, error) {
	// A single-byte read is answered off the stream and does not advance it.
	//
	// crypto/internal/randutil.MaybeReadByte reads one byte, or does not,
	// decided by a random source of its own - it exists to stop callers
	// depending on how much randomness a signature consumes. Letting it shift
	// this stream is precisely what made the fixtures differ between runs.
	if len(p) == 1 {
		p[0] = 0x42
		return 1, nil
	}
	for len(r.buf) < len(p) {
		block := sha512.Sum512(fmt.Appendf(nil, "%s/%d", r.seed, r.counter))
		r.counter++
		r.buf = append(r.buf, block[:]...)
	}
	n := copy(p, r.buf)
	r.buf = r.buf[n:]
	return n, nil
}

func writeCert(name string, der []byte) error {
	if err := writeFile(name+".der", der); err != nil {
		return err
	}
	return writeFile(name+".pem", pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
}

func writeFile(name string, content []byte) error {
	path := filepath.Join(outDir, name)
	if err := os.WriteFile(path, content, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	fmt.Println("wrote", path)
	return nil
}

func readme(fingerprint string) string {
	return `# Certificate fixtures for the server pin (feature 036)

GENERATED. Do not edit by hand. Regenerate from ` + "`client_backend`" + `:

    go run internal/server/testdata/generate_pin_fixtures.go

Deterministic where it matters: keys from fixed seeds, validity windows and
serial numbers from fixed values. The **subject public key** — the only part of
a certificate the pin ever reads — is identical on every run, and so is
` + "`fingerprint.txt`" + `.

The **signature** bytes are not, and cannot be: Go hedges the ECDSA nonce with
randomness from a source no caller controls, exactly so that nobody depends on
how much a signature consumes. Regenerating therefore shows a diff in the
signature of every ECDSA-signed file here and in nothing else — so regenerate
only when the generator actually changed.

They are made in Go because nothing on the Dart side can mint an X.509
certificate: there is no such package in ` + "`pubspec.yaml`" + ` and adding one for a
test is not on the table.

## The two keys

| Key | What it is |
|---|---|
| **correct** | the key the pin names — ` + "`fingerprint.txt`" + ` is its ` + "`sha256(SubjectPublicKeyInfo)`" + ` |
| **foreign** | somebody else's key entirely |

Fingerprint of the correct key:

    ` + fingerprint + `

## The files

| File | Key | Expected verdict | Why it exists |
|---|---|---|---|
| ` + "`valid.der`" + ` / ` + "`.pem`" + ` | correct | **accept** | the ordinary case |
| ` + "`reissued.der`" + ` / ` + "`.pem`" + ` | correct | **accept** | a different certificate on the same key — a server restart must not lock out a paired device |
| ` + "`stranger.der`" + ` / ` + "`.pem`" + ` | foreign | **refuse** | the whole phase in one file |
| ` + "`planted.der`" + ` / ` + "`.pem`" + ` | foreign | **refuse** | the attack: the certificate's real key is the foreign one, but a verbatim copy of the correct key's SPKI is planted in the subject, ahead of it. Anything locating the key by byte pattern hashes the plant and accepts a machine that holds only the attacker's private key |
| ` + "`truncated.der`" + ` | correct | **refuse** | the header is present, the key behind it is not; a check that hashes whatever follows the header would pass this |
| ` + "`headerless.der`" + ` | — (Ed25519) | **refuse** | no P-256 SubjectPublicKeyInfo at all; not hypothetical, it is what this server issued before 036 |
| ` + "`expired.der`" + ` / ` + "`.pem`" + ` | correct | **accept** | expired in 2020; a home server's owner may not have touched it for years |
| ` + "`wrong_name.der`" + ` / ` + "`.pem`" + ` | correct | **accept** | names ` + "`mail.example.com`" + ` and 203.0.113.7; a home server has no name and its address changes |
| ` + "`unknown_issuer.der`" + ` / ` + "`.pem`" + ` | correct | **accept** | signed by an authority nothing trusts; trust comes from the link, not from an issuer |
| ` + "`unknown_issuer_chain.pem`" + ` | correct | — | leaf + that authority, the chain a real server would present |
| ` + "`server_key.pem`" + ` | correct | — | PKCS#8 of the correct key, so a test can actually SERVE the three tolerance certificates |
| ` + "`stranger_key.pem`" + ` | foreign | — | PKCS#8 of the foreign key, so the refusal can be proved against a real handshake — it serves ` + "`stranger.pem`" + ` AND ` + "`planted.pem`" + ` |
| ` + "`fingerprint.txt`" + ` | correct | — | what the pairing link would carry |

The three tolerance cases are deliberately on the **correct** key. Negative
tests alone would be passed by an implementation that refuses on dates or
names — and that implementation breaks on the first home server somebody
forgot about.
`
}

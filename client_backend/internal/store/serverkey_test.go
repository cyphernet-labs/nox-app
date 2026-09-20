package store

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"nox.app/client-backend/internal/db"
)

// openStoreAt opens a store over a named file so a test can close it and open
// it again - the only way to tell "read back through the pool" apart from
// "survived a restart", which is the property that actually matters here.
func openStoreAt(t *testing.T, path string) *Store {
	t.Helper()
	d, err := db.Open(path)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := db.Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	return New(d.Read, d.Write)
}

// The stored halves have to be readable by the standard parsers and have to
// belong to each other. A key stored in a shape only this file understands is
// a key nobody else can build a certificate from.
func TestTheServerKeyIsStoredInShapesTheStandardParsersRead(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	id, err := s.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}

	spki, err := base64.StdEncoding.DecodeString(id.PublicKey)
	if err != nil {
		t.Fatalf("public half is not base64: %v", err)
	}
	pub, err := x509.ParsePKIXPublicKey(spki)
	if err != nil {
		t.Fatalf("public half is not a SubjectPublicKeyInfo: %v", err)
	}
	ec, ok := pub.(*ecdsa.PublicKey)
	if !ok {
		t.Fatalf("public half is %T, want *ecdsa.PublicKey", pub)
	}
	// P-256 by name, not by "whatever was generated": the client digs the SPKI
	// out of the certificate by a fixed header for THIS curve, so another curve
	// would be another wire format.
	if ec.Curve != elliptic.P256() {
		t.Fatalf("curve = %v, want P-256", ec.Curve)
	}

	signer, err := s.ServerSigner(ctx)
	if err != nil {
		t.Fatalf("ServerSigner: %v", err)
	}
	priv, ok := signer.(*ecdsa.PrivateKey)
	if !ok {
		t.Fatalf("private half is %T, want *ecdsa.PrivateKey", signer)
	}
	// The two halves must be one pair. They are written by separate marshallers
	// into separate columns, and this is the only place that is checked at all.
	if !priv.PublicKey.Equal(ec) {
		t.Fatal("the stored halves are not the same key pair")
	}
}

// The fingerprint is what the pairing link carries, so a restart that changed
// it would refuse every paired device. It is derived, never stored, and this
// is what holds the derivation still.
func TestTheFingerprintIsTheHashOfThePublicHalfAndSurvivesARestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "identity.db")

	minted, err := openStoreAt(t, path).EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	spki, err := base64.StdEncoding.DecodeString(minted.PublicKey)
	if err != nil {
		t.Fatalf("decode public half: %v", err)
	}
	sum := sha256.Sum256(spki)
	if want := base64.StdEncoding.EncodeToString(sum[:]); minted.Fingerprint != want {
		t.Fatalf("fingerprint = %q, want sha256 of the SPKI (%q)", minted.Fingerprint, want)
	}

	// A whole second process's worth of reading: new pools, new Store, same file.
	again, err := openStoreAt(t, path).ServerIdentity(ctx)
	if err != nil {
		t.Fatalf("ServerIdentity after restart: %v", err)
	}
	if again.Fingerprint != minted.Fingerprint {
		t.Fatalf("fingerprint changed across a restart: %q then %q", minted.Fingerprint, again.Fingerprint)
	}
	if again.PublicKey != minted.PublicKey {
		t.Fatal("the public half changed across a restart")
	}
}

// A database from before feature 036 holds a raw Ed25519 key. There is no
// migration by decision, so the only acceptable behaviour is to say what to do
// - from the place that knows, rather than as a parse failure three layers up.
func TestAPre036KeyIsRefusedWithAnAnswerRatherThanAParseFailure(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	// Thirty-two raw bytes in both columns: exactly what the old code wrote.
	legacy := base64.StdEncoding.EncodeToString(make([]byte, 32))
	if _, err := s.write.ExecContext(ctx,
		"INSERT INTO server_identity (id, public_key, private_key, claimed_at) VALUES (1, ?, ?, NULL)",
		legacy, legacy); err != nil {
		t.Fatalf("seed a legacy row: %v", err)
	}

	if _, err := s.ServerIdentity(ctx); !errors.Is(err, ErrLegacyServerKey) {
		t.Fatalf("reading a legacy identity gave %v, want ErrLegacyServerKey", err)
	}
	if _, err := s.ServerSigner(ctx); !errors.Is(err, ErrLegacyServerKey) {
		t.Fatalf("reading a legacy private half gave %v, want ErrLegacyServerKey", err)
	}
	// The message has to name the cure, because there is no migration to run.
	if !strings.Contains(ErrLegacyServerKey.Error(), "delete the development database") {
		t.Fatalf("the refusal does not say what to do: %q", ErrLegacyServerKey)
	}
}

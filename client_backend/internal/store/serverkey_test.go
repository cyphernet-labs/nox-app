package store

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"os"
	"path/filepath"
	"reflect"
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

// The machine's key is a plain Ed25519 pair: a 32-byte public key - what the
// pairing link carries whole - and the 32-byte seed it follows from. Stored in
// any other shape, the link and the channel check would be built from
// different things.
func TestTheServerKeyIsAnEd25519SeedAndItsPublicKey(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	id, err := s.EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if len(id.PublicKey) != ed25519.PublicKeySize {
		t.Fatalf("public key is %d bytes, want %d", len(id.PublicKey), ed25519.PublicKeySize)
	}

	var pubB64, seedB64 string
	if err := s.read.QueryRowContext(ctx,
		"SELECT public_key, private_key FROM server_identity WHERE id = 1").Scan(&pubB64, &seedB64); err != nil {
		t.Fatalf("read the row: %v", err)
	}
	seed, err := base64.StdEncoding.DecodeString(seedB64)
	if err != nil || len(seed) != ed25519.SeedSize {
		t.Fatalf("private_key is not a base64 %d-byte seed: %d bytes, err %v", ed25519.SeedSize, len(seed), err)
	}
	if want := base64.StdEncoding.EncodeToString(ed25519.NewKeyFromSeed(seed).Public().(ed25519.PublicKey)); pubB64 != want {
		t.Fatalf("public_key = %s, want the seed's public key %s", pubB64, want)
	}

	priv, err := s.ServerKey(ctx)
	if err != nil {
		t.Fatalf("ServerKey: %v", err)
	}
	// The two halves must be one pair: the link is built from one, the channel
	// check is signed with the other.
	if !id.PublicKey.Equal(priv.Public()) {
		t.Fatal("ServerKey is not the private half of the identity's public key")
	}
}

// The key is what the pairing link carries, so a restart that changed it
// would lock out every paired device.
func TestTheServerKeySurvivesARestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "identity.db")

	minted, err := openStoreAt(t, path).EnsureServerIdentity(ctx)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	// A whole second process's worth of reading: new pools, new Store, same file.
	again := openStoreAt(t, path)
	read, err := again.ServerIdentity(ctx)
	if err != nil {
		t.Fatalf("ServerIdentity after restart: %v", err)
	}
	if !read.PublicKey.Equal(minted.PublicKey) {
		t.Fatalf("the key changed across a restart: %x then %x", minted.PublicKey, read.PublicKey)
	}
	priv, err := again.ServerKey(ctx)
	if err != nil {
		t.Fatalf("ServerKey after restart: %v", err)
	}
	if !minted.PublicKey.Equal(priv.Public()) {
		t.Fatal("after a restart the private half proves another key")
	}
}

// A row whose two halves disagree - a hand edit, half a restore - would hand
// every device a key the server cannot prove. ServerKey runs at startup, and
// refusing there says so where it can be fixed.
func TestAServerKeyThatIsNotOnePairIsRefused(t *testing.T) {
	ctx := context.Background()
	other := base64.StdEncoding.EncodeToString(ed25519.NewKeyFromSeed(bytes.Repeat([]byte{7}, 32)).Public().(ed25519.PublicKey))
	for _, tc := range []struct {
		name, column, value string
	}{
		{"another key's public half", "public_key", other},
		{"a seed of the wrong size", "private_key", base64.StdEncoding.EncodeToString(make([]byte, 31))},
		{"a public key of the wrong size", "public_key", base64.StdEncoding.EncodeToString(make([]byte, 33))},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore(t)
			if _, err := s.EnsureServerIdentity(ctx); err != nil {
				t.Fatalf("EnsureServerIdentity: %v", err)
			}
			// The column name is one of two literals above, never input.
			if _, err := s.write.ExecContext(ctx, "UPDATE server_identity SET "+tc.column+" = ? WHERE id = 1", tc.value); err != nil {
				t.Fatalf("break the row: %v", err)
			}
			if _, err := s.ServerKey(ctx); err == nil {
				t.Fatal("ServerKey handed out a key the row does not hold together")
			}
		})
	}
}

// The onion key is minted with the machine and never changes: a backup is one
// file, and the address it restores has to be the one every device already
// knows (039, FR-008).
func TestTheOnionSeedIsMintedOnceAndSurvivesAReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "onion.db")
	ctx := context.Background()

	first := openStoreAt(t, path)
	if _, err := first.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	seed, err := first.OnionSeed(ctx)
	if err != nil {
		t.Fatalf("OnionSeed: %v", err)
	}
	if len(seed) != 32 || bytes.Equal(seed, make([]byte, 32)) {
		t.Fatalf("seed = %x, want 32 random bytes", seed)
	}
	again, err := first.OnionSeed(ctx)
	if err != nil || !bytes.Equal(again, seed) {
		t.Fatalf("a second read gave %x (err %v), want the same seed", again, err)
	}

	second := openStoreAt(t, path)
	if _, err := second.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity after reopen: %v", err)
	}
	reopened, err := second.OnionSeed(ctx)
	if err != nil || !bytes.Equal(reopened, seed) {
		t.Fatalf("after reopen the seed is %x (err %v), want %x", reopened, err, seed)
	}
}

// The identity handed to the status page and device.invite must not be able to
// carry the onion key: a private key one field away from a page is how it ends
// up on one.
func TestTheServerIdentityHasNoOnionField(t *testing.T) {
	for i := range reflect.TypeFor[ServerIdentity]().NumField() {
		name := reflect.TypeFor[ServerIdentity]().Field(i).Name
		if strings.Contains(strings.ToLower(name), "onion") {
			t.Fatalf("ServerIdentity has field %s; the onion key must stay behind OnionSeed", name)
		}
	}
}

// A backup is the database file and nothing else, so restoring it - anywhere -
// brings back the same onion address (SC-003). VACUUM INTO is how this project
// takes a backup of a live database.
func TestABackupRestoresTheSameOnionKey(t *testing.T) {
	dir := t.TempDir()
	ctx := context.Background()
	live := openStoreAt(t, filepath.Join(dir, "live.db"))
	if _, err := live.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	want, err := live.OnionSeed(ctx)
	if err != nil {
		t.Fatalf("OnionSeed: %v", err)
	}
	backup := filepath.Join(dir, "backup.db")
	if _, err := live.write.ExecContext(ctx, "VACUUM INTO ?", backup); err != nil {
		t.Fatalf("VACUUM INTO: %v", err)
	}

	restored := openStoreAt(t, backup)
	if _, err := restored.EnsureServerIdentity(ctx); err != nil {
		t.Fatalf("EnsureServerIdentity on the restored copy: %v", err)
	}
	got, err := restored.OnionSeed(ctx)
	if err != nil || !bytes.Equal(got, want) {
		t.Fatalf("restored seed = %x (err %v), want %x", got, err, want)
	}
}

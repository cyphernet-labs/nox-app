package store

import (
	"bytes"
	"context"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"

	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/securebox"
)

// openStoreAt opens a store over a named file so a test can close it and open
// it again - the only way to tell "read back through the pool" apart from
// "survived a restart", which is the property that actually matters here.
func openStoreAt(t *testing.T, path string) *Store {
	t.Helper()
	d, err := db.Open(path, testKey)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := db.Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	return New(d.Read, d.Write)
}

// The machine's key comes from RustSecureBox (050): a 32-byte private key and
// the 32-byte public key the library gives for it - what the pairing link
// carries whole. Stored in any other shape, the link and the answer to
// POST /auth would be built from different things.
func TestTheServerKeyIsRustSecureBoxsPairAsItWasMade(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()

	id, err := s.EnsureServerIdentity(ctx, testBox)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	if len(id.PublicKey) != securebox.PublicKeySize {
		t.Fatalf("public key is %d bytes, want %d", len(id.PublicKey), securebox.PublicKeySize)
	}
	var privB64 string
	if err := s.read.QueryRowContext(ctx, "SELECT private_key FROM server_identity WHERE id = 1").Scan(&privB64); err != nil {
		t.Fatalf("read the row: %v", err)
	}
	if raw, err := base64.StdEncoding.DecodeString(privB64); err != nil || len(raw) != securebox.PrivateKeySize {
		t.Fatalf("private_key is not a base64 %d-byte key: %d bytes, err %v", securebox.PrivateKeySize, len(raw), err)
	}

	priv, rekeyed, err := s.ServerKey(ctx, testBox)
	if err != nil || rekeyed {
		t.Fatalf("ServerKey: rekeyed=%v err=%v", rekeyed, err)
	}
	// The two halves must be one pair: the link is built from one, the answer
	// to /auth is signed with the other.
	public, err := testBox.PublicKey(priv)
	if err != nil || !bytes.Equal(public[:], id.PublicKey) {
		t.Fatal("ServerKey is not the private half of the identity's public key")
	}
}

// The key is what the pairing link carries, so a restart that changed it
// would lock out every paired device.
func TestTheServerKeySurvivesARestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "identity.db")

	minted, err := openStoreAt(t, path).EnsureServerIdentity(ctx, testBox)
	if err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	// A whole second process's worth of reading: new pools, new Store, same file.
	again := openStoreAt(t, path)
	read, err := again.ServerIdentity(ctx)
	if err != nil {
		t.Fatalf("ServerIdentity after restart: %v", err)
	}
	if !bytes.Equal(read.PublicKey, minted.PublicKey) {
		t.Fatalf("the key changed across a restart: %x then %x", minted.PublicKey, read.PublicKey)
	}
	priv, rekeyed, err := again.ServerKey(ctx, testBox)
	if err != nil || rekeyed {
		t.Fatalf("ServerKey after restart: rekeyed=%v err=%v", rekeyed, err)
	}
	if public, _ := testBox.PublicKey(priv); !bytes.Equal(public[:], minted.PublicKey) {
		t.Fatal("after a restart the private half proves another key")
	}
}

// A row that is not a key at all - half a restore, a hand edit - is refused at
// startup, where it can be fixed.
func TestAServerKeyOfTheWrongShapeIsRefused(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		name, column, value string
	}{
		{"a private key of the wrong size", "private_key", base64.StdEncoding.EncodeToString(make([]byte, 31))},
		{"a public key of the wrong size", "public_key", base64.StdEncoding.EncodeToString(make([]byte, 33))},
		{"a private key that is not base64", "private_key", "not base64!"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore(t)
			if _, err := s.EnsureServerIdentity(ctx, testBox); err != nil {
				t.Fatalf("EnsureServerIdentity: %v", err)
			}
			// The column name is one of two literals above, never input.
			if _, err := s.write.ExecContext(ctx, "UPDATE server_identity SET "+tc.column+" = ? WHERE id = 1", tc.value); err != nil {
				t.Fatalf("break the row: %v", err)
			}
			if _, _, err := s.ServerKey(ctx, testBox); err == nil {
				t.Fatal("ServerKey handed out a key the row does not hold together")
			}
		})
	}
}

// FR-021: a public key the current RustSecureBox does not give for the stored
// private key means the key was made by another implementation - Eidolon
// before 050, the stub before the real library. Every device's key came from
// it too. The server keeps its private key, takes the public key the library
// gives, and lets every device go in one transaction; everything the person
// wrote stays.
func TestAKeyOfAnotherImplementationIsRekeyedAndEveryDeviceLetGo(t *testing.T) {
	ctx := context.Background()
	s := newStore(t)
	person := pairFirst(t, s, "device-key-of-the-old-check")
	if _, err := s.IssueMachineLink(ctx, 200); err != nil {
		t.Fatalf("IssueMachineLink: %v", err)
	}
	chat, _, _, err := s.CreateChat(ctx, "", "Notes", "Anna", 300)
	if err != nil {
		t.Fatalf("CreateChat: %v", err)
	}
	if _, _, _, err := s.SendMessage(ctx, chat.ChatID, "m1", person, textBody("kept"), "", 301); err != nil {
		t.Fatalf("SendMessage: %v", err)
	}
	// The public key the old implementation gave for the same private key.
	oldPublic := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0x5a}, securebox.PublicKeySize))
	if _, err := s.write.ExecContext(ctx, "UPDATE server_identity SET public_key = ? WHERE id = 1", oldPublic); err != nil {
		t.Fatalf("make the key an old one: %v", err)
	}

	priv, rekeyed, err := s.ServerKey(ctx, testBox)
	if err != nil || !rekeyed {
		t.Fatalf("ServerKey: rekeyed=%v err=%v", rekeyed, err)
	}
	id, err := s.ServerIdentity(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if public, _ := testBox.PublicKey(priv); !bytes.Equal(public[:], id.PublicKey) {
		t.Fatal("the stored public key is not the library's for the private key")
	}
	for table, want := range map[string]int{"devices": 0, "pair_tokens": 0, "pair_requests": 0, "users": 1, "chats": 1, "messages": 1} {
		var n int
		// The table name is one of the literals above, never input.
		if err := s.read.QueryRowContext(ctx, "SELECT COUNT(1) FROM "+table).Scan(&n); err != nil {
			t.Fatalf("count %s: %v", table, err)
		}
		if n != want {
			t.Errorf("%s: %d rows, want %d", table, n, want)
		}
	}
	// Once rekeyed, the next start finds the pair whole.
	if _, rekeyed, err := s.ServerKey(ctx, testBox); err != nil || rekeyed {
		t.Fatalf("the second start: rekeyed=%v err=%v", rekeyed, err)
	}
	// And the page leads with a link again: nobody can reach the machine.
	link, err := s.IssueMachineLink(ctx, 400)
	if err != nil {
		t.Fatalf("IssueMachineLink after the rekey: %v", err)
	}
	again, err := pairID(ctx, s, link.Token, "device-key-of-the-new-check", "test", 401)
	if err != nil {
		t.Fatalf("pair after the rekey: %v", err)
	}
	if again.UserID != person.UserID {
		t.Fatal("the device paired after the rekey is not the same person")
	}
}

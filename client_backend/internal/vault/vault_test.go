package vault

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// cheap are costs a test can afford a hundred times over; what is under test
// is the sealing, not Argon2's price.
var cheap = Params{MemoryKiB: 64, Iterations: 1, Parallelism: 1}

const (
	oldPassword = "correct horse battery"
	newPassword = "staple orbit lantern"
)

func keyPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "nox.db.key")
}

// snapshot is everything about a file a refused attempt must leave alone.
type snapshot struct {
	data []byte
	mod  time.Time
}

func snap(t *testing.T, path string) snapshot {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat %s: %v", path, err)
	}
	return snapshot{data: data, mod: info.ModTime()}
}

func (s snapshot) same(t *testing.T, path string) {
	t.Helper()
	now := snap(t, path)
	if !bytes.Equal(now.data, s.data) || !now.mod.Equal(s.mod) {
		t.Fatal("the key file changed")
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("the directory holds %d entries, want the key file alone", len(entries))
	}
}

func TestTheRightPasswordOpensTheKeyAndAWrongOneNothing(t *testing.T) {
	path := keyPath(t)
	key, err := Create(path, oldPassword, cheap)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if len(key) != KeySize {
		t.Fatalf("data key is %d bytes, want %d", len(key), KeySize)
	}
	got, err := Open(path, oldPassword)
	if err != nil || !bytes.Equal(got, key) {
		t.Fatalf("Open with the password = %x, %v; want the data key", got, err)
	}
	before := snap(t, path)
	if _, err := Open(path, "correct horse batterY"); !errors.Is(err, ErrWrongPassword) {
		t.Fatalf("Open with another password = %v, want ErrWrongPassword", err)
	}
	// SC-003: a wrong password changes not a byte.
	before.same(t, path)
	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatalf("stat: %v", err)
		}
		if perm := info.Mode().Perm(); perm != 0o600 {
			t.Fatalf("key file mode = %v, want 0600", perm)
		}
	}
}

func TestTheKeyFileHoldsNoKeyInTheClear(t *testing.T) {
	path := keyPath(t)
	key, err := Create(path, oldPassword, cheap)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	data := snap(t, path).data
	for _, form := range [][]byte{key, []byte(base64.StdEncoding.EncodeToString(key)), []byte(oldPassword)} {
		if bytes.Contains(data, form) {
			t.Fatalf("the key file carries %q in the clear", form)
		}
	}
}

func TestThePasswordRule(t *testing.T) {
	cases := []struct {
		password string
		ok       bool
	}{
		{"", false},
		{"elevenchars", false},
		{"twelve chars", true},
		{strings.Repeat(" ", 20), false},
		{"\t\n " + strings.Repeat(" ", 12), false},
		{"  abcdefghij", true},
		{"пароль-длинный", true}, // 14 characters, 26 bytes
		{"пароль-длин", false},   // 11 characters, 21 bytes
	}
	for _, c := range cases {
		err := CheckPassword(c.password)
		if c.ok && err != nil {
			t.Errorf("CheckPassword(%q) = %v, want accepted", c.password, err)
		}
		if !c.ok && !errors.Is(err, ErrShortPassword) {
			t.Errorf("CheckPassword(%q) = %v, want ErrShortPassword", c.password, err)
		}
	}
}

func TestCreateNeverReplacesAKeyFile(t *testing.T) {
	path := keyPath(t)
	if _, err := Create(path, oldPassword, cheap); err != nil {
		t.Fatalf("Create: %v", err)
	}
	before := snap(t, path)
	if _, err := Create(path, newPassword, cheap); !errors.Is(err, ErrExists) {
		t.Fatalf("a second Create = %v, want ErrExists", err)
	}
	before.same(t, path)
}

func TestCreateRefusesAShortPasswordAndWritesNothing(t *testing.T) {
	path := keyPath(t)
	if _, err := Create(path, "short", cheap); !errors.Is(err, ErrShortPassword) {
		t.Fatalf("Create with a short password = %v, want ErrShortPassword", err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("a refused Create left a file (stat err %v)", err)
	}
}

func TestChangeReSealsTheSameKey(t *testing.T) {
	path := keyPath(t)
	key, err := Create(path, oldPassword, cheap)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if err := Change(path, oldPassword, newPassword, cheap); err != nil {
		t.Fatalf("Change: %v", err)
	}
	got, err := Open(path, newPassword)
	if err != nil || !bytes.Equal(got, key) {
		t.Fatalf("the new password opens %x, %v; want the same data key", got, err)
	}
	if _, err := Open(path, oldPassword); !errors.Is(err, ErrWrongPassword) {
		t.Fatalf("the old password after a change = %v, want ErrWrongPassword", err)
	}
	if _, err := os.Stat(path + ".tmp"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("a change left its temporary file behind (stat err %v)", err)
	}
}

func TestARefusedChangeChangesNothing(t *testing.T) {
	path := keyPath(t)
	if _, err := Create(path, oldPassword, cheap); err != nil {
		t.Fatalf("Create: %v", err)
	}
	before := snap(t, path)
	if err := Change(path, "not the password", newPassword, cheap); !errors.Is(err, ErrWrongPassword) {
		t.Fatalf("Change with a wrong current password = %v, want ErrWrongPassword", err)
	}
	before.same(t, path)
	if err := Change(path, oldPassword, "too short", cheap); !errors.Is(err, ErrShortPassword) {
		t.Fatalf("Change to a short password = %v, want ErrShortPassword", err)
	}
	before.same(t, path)
}

// A crash between writing the new file and renaming it over the old one: the
// new file lies beside the old, and the old password still opens the key. The
// rename is the one moment the change happens - after it, the new password.
func TestACrashMidChangeLeavesOneOfTheTwoPasswords(t *testing.T) {
	path := keyPath(t)
	key, err := Create(path, oldPassword, cheap)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	resealed, err := seal(key, newPassword, cheap)
	if err != nil {
		t.Fatalf("seal: %v", err)
	}
	// Written and flushed, never renamed: what WriteFile leaves when the power
	// goes between its two steps.
	if err := os.WriteFile(path+".tmp", resealed, 0o600); err != nil {
		t.Fatalf("write the half-done change: %v", err)
	}
	if got, err := Open(path, oldPassword); err != nil || !bytes.Equal(got, key) {
		t.Fatalf("the old password after a crash before the rename = %v, want the key", err)
	}
	if err := os.Rename(path+".tmp", path); err != nil {
		t.Fatalf("rename: %v", err)
	}
	if got, err := Open(path, newPassword); err != nil || !bytes.Equal(got, key) {
		t.Fatalf("the new password after the rename = %v, want the key", err)
	}

	// And a stray temporary left by a crash does not stand in the way of the
	// next change.
	if err := os.WriteFile(path+".tmp", []byte("half"), 0o600); err != nil {
		t.Fatalf("write a stray: %v", err)
	}
	if err := Change(path, newPassword, oldPassword, cheap); err != nil {
		t.Fatalf("Change over a stray temporary: %v", err)
	}
	if _, err := Open(path, oldPassword); err != nil {
		t.Fatalf("Open after that change: %v", err)
	}
}

func TestAKeyFileThatDoesNotReadIsRefusedBeforeAnyWork(t *testing.T) {
	path := keyPath(t)
	if _, err := Create(path, oldPassword, cheap); err != nil {
		t.Fatalf("Create: %v", err)
	}
	good := snap(t, path).data
	edit := func(change func(map[string]any)) []byte {
		var m map[string]any
		if err := json.Unmarshal(good, &m); err != nil {
			t.Fatalf("decode: %v", err)
		}
		change(m)
		out, err := json.Marshal(m)
		if err != nil {
			t.Fatalf("encode: %v", err)
		}
		return out
	}
	cases := map[string][]byte{
		"not json":         []byte("nox"),
		"another version":  edit(func(m map[string]any) { m["version"] = 2 }),
		"another kdf":      edit(func(m map[string]any) { m["kdf"] = "scrypt" }),
		"a terabyte asked": edit(func(m map[string]any) { m["memory_kib"] = 1 << 30 }),
		"no passes":        edit(func(m map[string]any) { m["iterations"] = 0 }),
		"a short salt":     edit(func(m map[string]any) { m["salt"] = base64.StdEncoding.EncodeToString([]byte("salt")) }),
		"a short seal":     edit(func(m map[string]any) { m["sealed"] = base64.StdEncoding.EncodeToString([]byte("seal")) }),
	}
	for name, data := range cases {
		if err := Validate(data); !errors.Is(err, ErrMalformed) {
			t.Errorf("%s: Validate = %v, want ErrMalformed", name, err)
		}
		if _, err := Unseal(data, oldPassword); !errors.Is(err, ErrMalformed) {
			t.Errorf("%s: Unseal = %v, want ErrMalformed", name, err)
		}
	}
	// Costs that read fine but were changed: another key comes out of Argon2,
	// and the seal does not open.
	tampered := edit(func(m map[string]any) { m["iterations"] = 2 })
	if _, err := Unseal(tampered, oldPassword); !errors.Is(err, ErrWrongPassword) {
		t.Fatalf("Unseal with changed costs = %v, want ErrWrongPassword", err)
	}
}

// The costs every real key is sealed with are the ones data-model.md names,
// and they are written into the file exactly so.
func TestTheProductionCostsAreTheDocumentedOnes(t *testing.T) {
	if got, want := DefaultParams(), (Params{MemoryKiB: 65536, Iterations: 3, Parallelism: 4}); got != want {
		t.Fatalf("DefaultParams() = %+v, want %+v", got, want)
	}
	path := keyPath(t)
	key, err := Create(path, oldPassword, DefaultParams())
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal(snap(t, path).data, &m); err != nil {
		t.Fatalf("the key file is not JSON: %v", err)
	}
	for field, want := range map[string]string{
		"version": "1", "kdf": `"argon2id"`, "memory_kib": "65536", "iterations": "3", "parallelism": "4",
	} {
		if got := string(m[field]); got != want {
			t.Errorf("%s = %s, want %s", field, got, want)
		}
	}
	for field, size := range map[string]int{"salt": 16, "nonce": 24, "sealed": 48} {
		var raw []byte
		if err := json.Unmarshal(m[field], &raw); err != nil || len(raw) != size {
			t.Errorf("%s holds %d bytes (%v), want %d", field, len(raw), err, size)
		}
	}
	if len(m) != 8 {
		t.Errorf("the key file has %d fields, want the 8 data-model.md lists", len(m))
	}

	// SC-002 and SC-006 at their root: opening with the real costs leaves the
	// rest of the two seconds for the database, and a change is one open and
	// one seal - well under five, whatever the server holds.
	start := time.Now()
	if got, err := Open(path, oldPassword); err != nil || !bytes.Equal(got, key) {
		t.Fatalf("Open: %v", err)
	}
	if took := time.Since(start); took > 2*time.Second {
		t.Fatalf("opening the key took %v, want well under 2 s", took)
	}
	start = time.Now()
	if err := Change(path, oldPassword, newPassword, DefaultParams()); err != nil {
		t.Fatalf("Change: %v", err)
	}
	if took := time.Since(start); took > 5*time.Second {
		t.Fatalf("a password change took %v, want under 5 s", took)
	}
}

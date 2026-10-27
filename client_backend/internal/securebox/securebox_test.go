package securebox

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"sync"
	"testing"
)

// vectors is the stub's shared vectors file (specs/050-rust-secure-box/
// contracts/rsb-vectors.json): what the app's copy of RustSecureBox answers,
// which this WebAssembly copy must answer byte for byte.
type vectors struct {
	Implementation string `json:"implementation"`
	Probe          struct {
		PrivateKey string `json:"private_key"`
		PublicKey  string `json:"public_key"`
	} `json:"probe"`
	Keys []struct {
		PrivateKey string `json:"private_key"`
		PublicKey  string `json:"public_key"`
	} `json:"keys"`
	Signatures []struct {
		PrivateKey string `json:"private_key"`
		Challenge  string `json:"challenge"`
		Signature  string `json:"signature"`
	} `json:"signatures"`
	Checks []struct {
		PublicKey string `json:"public_key"`
		Challenge string `json:"challenge"`
		Signature string `json:"signature"`
		Valid     bool   `json:"valid"`
	} `json:"checks"`
}

func loadVectors(t *testing.T) vectors {
	t.Helper()
	raw, err := os.ReadFile("testdata/rsb-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var v vectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func unhex(t *testing.T, s string, size int) []byte {
	t.Helper()
	raw, err := hex.DecodeString(s)
	if err != nil || len(raw) != size {
		t.Fatalf("bad hex %q", s)
	}
	return raw
}

func key32(t *testing.T, s string) [32]byte { return [32]byte(unhex(t, s, 32)) }

func sig64(t *testing.T, s string) Signature { return Signature(unhex(t, s, 64)) }

func TestTheCopyIsTheSpecificationsFile(t *testing.T) {
	ours, err := os.ReadFile("testdata/rsb-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	spec, err := os.ReadFile("../../../specs/050-rust-secure-box/contracts/rsb-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	if string(ours) != string(spec) {
		t.Fatal("testdata/rsb-vectors.json is not the specification's copy")
	}
}

func TestTheWebAssemblyCopyGivesTheVectors(t *testing.T) {
	v := loadVectors(t)
	box := New()
	for _, k := range append(v.Keys, v.Probe) {
		got, err := box.PublicKey(key32(t, k.PrivateKey))
		if err != nil {
			t.Fatal(err)
		}
		if hex.EncodeToString(got[:]) != k.PublicKey {
			t.Fatalf("public key of %s: %x, want %s", k.PrivateKey, got, k.PublicKey)
		}
	}
	for _, s := range v.Signatures {
		got, err := box.SignChallenge(key32(t, s.PrivateKey), key32(t, s.Challenge))
		if err != nil {
			t.Fatal(err)
		}
		if hex.EncodeToString(got[:]) != s.Signature {
			t.Fatalf("signature of %s over %s differs", s.PrivateKey, s.Challenge)
		}
	}
	for i, c := range v.Checks {
		valid, err := box.CheckSignature(key32(t, c.PublicKey), key32(t, c.Challenge), sig64(t, c.Signature))
		if err != nil {
			t.Fatal(err)
		}
		if valid != c.Valid {
			t.Fatalf("check %d: %v, want %v", i, valid, c.Valid)
		}
	}
}

// stubImplementation is the name the stub's vectors carry.
const stubImplementation = "stub-v1"

// The stub's answer for the probe is a constant that never moves: the stub's
// vectors hold it to it, and anything else's must differ from it - a real
// RustSecureBox whose vectors made the constant follow them would be
// announced as the stub forever.
func TestTheProbeConstantIsTheStubs(t *testing.T) {
	v := loadVectors(t)
	for i := 0; i < len(v.Probe.PrivateKey); i += 2 {
		if v.Probe.PrivateKey[i:i+2] != "01" {
			t.Fatal("the probe key is not 32 bytes of 0x01")
		}
	}
	if (v.Probe.PublicKey == stubProbePublicKey) != (v.Implementation == stubImplementation) {
		t.Fatalf("the vectors of %q give the probe %s; the stub's is %s", v.Implementation, v.Probe.PublicKey, stubProbePublicKey)
	}
}

func TestTheStubIsRecognisedAndNothingElseIs(t *testing.T) {
	if got, want := New().IsStub(), loadVectors(t).Implementation == stubImplementation; got != want {
		t.Fatalf("IsStub() = %v for the implementation of the vectors", got)
	}
}

// What ANY RustSecureBox must do - the same properties the crate's own
// interface tests hold it to.

func TestOwnSignatureVerifiesAndNoOtherDoes(t *testing.T) {
	box := New()
	device, err := box.GenerateKeys()
	if err != nil {
		t.Fatal(err)
	}
	stranger, err := box.GenerateKeys()
	if err != nil {
		t.Fatal(err)
	}
	challenge, public, err := box.GetChallenge(device.PrivateKey)
	if err != nil {
		t.Fatal(err)
	}
	if public != device.PublicKey {
		t.Fatal("the public key of a challenge is not the pair's")
	}
	own, _ := box.SignChallenge(device.PrivateKey, challenge)
	if ok, err := box.CheckSignature(device.PublicKey, challenge, own); err != nil || !ok {
		t.Fatalf("own signature: %v %v", ok, err)
	}
	other, _ := box.SignChallenge(stranger.PrivateKey, challenge)
	if ok, _ := box.CheckSignature(device.PublicKey, challenge, other); ok {
		t.Fatal("another key's signature verified")
	}
	otherChallenge, _, _ := box.GetChallenge(device.PrivateKey)
	if ok, _ := box.CheckSignature(device.PublicKey, otherChallenge, own); ok {
		t.Fatal("a signature over another challenge verified")
	}
	for i := range own {
		changed := own
		changed[i] ^= 0x01
		if ok, _ := box.CheckSignature(device.PublicKey, challenge, changed); ok {
			t.Fatalf("a signature with byte %d changed verified", i)
		}
	}
}

func TestChallengesDoNotRepeat(t *testing.T) {
	box := New()
	pair, _ := box.GenerateKeys()
	seen := make(map[Challenge]bool)
	for range 1000 {
		c, _, err := box.GetChallenge(pair.PrivateKey)
		if err != nil {
			t.Fatal(err)
		}
		if seen[c] {
			t.Fatal("a challenge repeated")
		}
		seen[c] = true
	}
}

func TestSixteenGoroutinesGetTheAnswersOneGets(t *testing.T) {
	box := New()
	pair, _ := box.GenerateKeys()
	challenge, _, _ := box.GetChallenge(pair.PrivateKey)
	want, _ := box.SignChallenge(pair.PrivateKey, challenge)
	var wg sync.WaitGroup
	errs := make(chan error, 16)
	for range 16 {
		wg.Go(func() {
			for range 200 {
				got, err := box.SignChallenge(pair.PrivateKey, challenge)
				if err != nil || got != want {
					errs <- errors.New("a signature differed under concurrency")
					return
				}
				if ok, err := box.CheckSignature(pair.PublicKey, challenge, got); err != nil || !ok {
					errs <- errors.New("a check failed under concurrency")
					return
				}
			}
		})
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
}

func TestNoRandomBytesIsErrRandom(t *testing.T) {
	failing := true
	box := newWithRandom(func(b []byte) error {
		if failing {
			return errors.New("no entropy")
		}
		clear(b)
		b[0] = 1
		return nil
	})
	if _, err := box.GenerateKeys(); !errors.Is(err, ErrRandom) {
		t.Fatalf("GenerateKeys: %v", err)
	}
	// A key every implementation takes - the probe, not the all-zero seed
	// Ed25519 refuses - so the random source is the only thing that can fail,
	// whichever the implementation looks at first.
	var key PrivateKey
	for i := range key {
		key[i] = probeByte
	}
	if _, _, err := box.GetChallenge(key); !errors.Is(err, ErrRandom) {
		t.Fatalf("GetChallenge: %v", err)
	}
	failing = false
	if _, err := box.GenerateKeys(); err != nil {
		t.Fatalf("the box did not recover from a refusal: %v", err)
	}
}

func TestATrapIsErrBoxAndTheBoxGoesOn(t *testing.T) {
	box := New()
	err := box.call(func(in *instance) error {
		// An address past the end of the module's memory: the generated code
		// panics, as a trap in the library would.
		in.module.Xrsb_sign_challenge(-64, -64, -64)
		return nil
	})
	if !errors.Is(err, ErrBox) {
		t.Fatalf("a trap: %v", err)
	}
	pair, err := box.GenerateKeys()
	if err != nil {
		t.Fatal(err)
	}
	if public, err := box.PublicKey(pair.PrivateKey); err != nil || public != pair.PublicKey {
		t.Fatalf("after a trap: %v", err)
	}
}

func TestACallLeavesNoKeyInTheModule(t *testing.T) {
	box := New()
	pair, err := box.GenerateKeys()
	if err != nil {
		t.Fatal(err)
	}
	// One instance for every call, so the one looked at is the one that
	// signed: a pool may hand out a fresh one (it does under -race).
	in := box.pool.Get().(*instance)
	box.pool = sync.Pool{New: func() any { return in }}
	if _, err := box.SignChallenge(pair.PrivateKey, Challenge{7}); err != nil {
		t.Fatal(err)
	}
	mem := in.mem()
	if bytes.Contains(mem, pair.PrivateKey[:]) {
		t.Fatal("the private key is still in the module's memory")
	}
	for _, b := range mem[in.io : in.io+ioUsed] {
		if b != 0 {
			t.Fatal("the exchange buffer kept bytes of a call")
		}
	}
}

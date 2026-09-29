package tor

import (
	"bytes"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"slices"
	"testing"
)

// The vector is independent of this package: the seed and public key are RFC
// 8032's test 1, and the address and the expanded key were computed by a
// separate Python script (hashlib.sha3_256, hashlib.sha512) - so a mistake in
// the derivation cannot agree with itself here.
const (
	rfcSeedHex     = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
	rfcPublicHex   = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	rfcAddress     = "25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid"
	rfcExpandedB64 = "MHyDhk8oM8tCei7xwAoBPP3/J2jZgMCjpSDwBpBN6U+bTwr+KAt0aneGhOdUQlAgV7dHOgPwj5b1o46Sh+Afjw=="
)

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("hex: %v", err)
	}
	return b
}

func TestTheAddressOfAKnownKeyIsTheIndependentlyComputedOne(t *testing.T) {
	seed := mustHex(t, rfcSeedHex)

	pub, err := PublicKey(seed)
	if err != nil {
		t.Fatalf("PublicKey: %v", err)
	}
	if !bytes.Equal(pub, mustHex(t, rfcPublicHex)) {
		t.Fatalf("public key = %x, want RFC 8032 test 1", []byte(pub))
	}

	addr, err := Address(pub)
	if err != nil {
		t.Fatalf("Address: %v", err)
	}
	if addr != rfcAddress {
		t.Fatalf("address = %s, want %s", addr, rfcAddress)
	}
	if len(addr) != 56 {
		t.Fatalf("address is %d characters, want 56", len(addr))
	}
}

func TestTheExpandedKeyIsTorsFormatNotTheSeed(t *testing.T) {
	seed := mustHex(t, rfcSeedHex)
	got, err := ExpandedKey(seed)
	if err != nil {
		t.Fatalf("ExpandedKey: %v", err)
	}
	if base64.StdEncoding.EncodeToString(got) != rfcExpandedB64 {
		t.Fatalf("expanded key = %s, want %s", base64.StdEncoding.EncodeToString(got), rfcExpandedB64)
	}
	// The scalar half must be clamped: low three bits clear, top bit clear,
	// second-highest set. A key that is not clamped is a different key to tor.
	if got[0]&7 != 0 || got[31]&128 != 0 || got[31]&64 == 0 {
		t.Fatalf("scalar half is not clamped: first=%08b last=%08b", got[0], got[31])
	}
}

func TestClientAuthKeysAreUnpaddedBase32(t *testing.T) {
	key := make([]byte, AccessKeySize)
	for i := range key {
		key[i] = byte(i)
	}
	got, err := ClientAuthKey(key)
	if err != nil {
		t.Fatalf("ClientAuthKey: %v", err)
	}
	// Computed separately (base64.b32encode of bytes 0..31, padding stripped).
	if want := "AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYYDENBWHA5DYPQ"; got != want {
		t.Fatalf("client auth key = %s, want %s", got, want)
	}
}

func TestWrongSizedKeysAreRefusedRatherThanTruncated(t *testing.T) {
	if _, err := PublicKey(make([]byte, 31)); err == nil {
		t.Error("PublicKey accepted a 31-byte seed")
	}
	if _, err := ExpandedKey(make([]byte, 33)); err == nil {
		t.Error("ExpandedKey accepted a 33-byte seed")
	}
	if _, err := Address(ed25519.PublicKey(make([]byte, 31))); err == nil {
		t.Error("Address accepted a 31-byte key")
	}
	if _, err := ClientAuthKey(make([]byte, 16)); err == nil {
		t.Error("ClientAuthKey accepted a 16-byte key")
	}
}

func TestAccessKeysFromTheWireAreExactly32BytesOfBase64(t *testing.T) {
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateKey: %v", err)
	}
	good := base64.StdEncoding.EncodeToString(key.PublicKey().Bytes())
	if raw, err := ParseAccessKey(good); err != nil || len(raw) != 32 {
		t.Fatalf("ParseAccessKey(a real public key) = %x, %v", raw, err)
	}
	for name, in := range map[string]string{
		"empty":        "",
		"not base64":   "!!!!",
		"31 bytes":     base64.StdEncoding.EncodeToString(make([]byte, 31)),
		"33 bytes":     base64.StdEncoding.EncodeToString(make([]byte, 33)),
		"url alphabet": "_" + good[1:],
	} {
		if _, err := ParseAccessKey(in); !errors.Is(err, ErrBadAccessKey) {
			t.Errorf("%s: err = %v, want ErrBadAccessKey", name, err)
		}
	}
}

// A small-order point is refused: tor asserts on the all-zero key, and any of
// these makes the exchange come out as zeros, which would key that client's
// descriptor entry by the onion address alone. The seven encodings libsodium
// blacklists, and each again with the top bit set - x25519 ignores that bit,
// so the same points must not slip through with it.
func TestAccessKeysOfSmallOrderAreRefused(t *testing.T) {
	ff := func(first, last byte) []byte {
		b := make([]byte, 32)
		for i := range b {
			b[i] = 0xff
		}
		b[0], b[31] = first, last
		return b
	}
	points := map[string][]byte{
		"zero (order 4)": make([]byte, 32),
		"one (order 1)":  append([]byte{1}, make([]byte, 31)...),
		"order 8, first": mustHex(t, "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800"),
		"order 8, second": mustHex(t,
			"5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157"),
		"p-1 (order 2)":   ff(0xec, 0x7f),
		"p (zero again)":  ff(0xed, 0x7f),
		"p+1 (one again)": ff(0xee, 0x7f),
	}
	for name, point := range points {
		for _, top := range []byte{0, 0x80} {
			raw := slices.Clone(point)
			raw[31] |= top
			if _, err := ParseAccessKey(base64.StdEncoding.EncodeToString(raw)); !errors.Is(err, ErrBadAccessKey) {
				t.Errorf("%s (top bit %#x): err = %v, want ErrBadAccessKey", name, top, err)
			}
		}
	}
}

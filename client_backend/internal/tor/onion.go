// Package tor owns everything the server knows about tor (feature 039): where
// the binary is and whether it is new enough, the control protocol it is
// commanded through, the onion service's key and address, the supervisor that
// owns the process and publishes the service, and the scrubbing that keeps
// addresses and keys out of the log.
//
// The onion seed is handed in once, at startup, and never leaves this package:
// the server gets the public key and the address from the supervisor, and the
// private half stays where only tor's ADD_ONION line needs it.
package tor

import (
	"crypto/ed25519"
	"crypto/sha3"
	"crypto/sha512"
	"encoding/base32"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
)

const (
	// OnionPort is the virtual port of the onion service. Fixed, so the address
	// a device keeps - host AND port - does not change when somebody moves the
	// direct listener with -addr.
	OnionPort = 443

	// AccessKeySize is the size of an x25519 key, public or private.
	AccessKeySize = 32

	// onionVersion is the address version byte of a v3 onion service.
	onionVersion = 0x03
)

// base32NoPad is the alphabet rend-spec-v3 and the control protocol use for
// onion addresses and client-authorization keys: RFC 4648, no padding.
var base32NoPad = base32.StdEncoding.WithPadding(base32.NoPadding)

// ErrBadAccessKey is returned for an access key that is not 32 bytes of
// standard base64. It names the shape, never the value: what failed to parse
// may still be somebody's key.
var ErrBadAccessKey = errors.New("access key is not 32 bytes of base64")

// PublicKey derives the onion service's public key from its seed.
func PublicKey(seed []byte) (ed25519.PublicKey, error) {
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("onion seed is %d bytes, want %d", len(seed), ed25519.SeedSize)
	}
	pub, ok := ed25519.NewKeyFromSeed(seed).Public().(ed25519.PublicKey)
	if !ok {
		return nil, errors.New("ed25519 key without an ed25519 public half")
	}
	return pub, nil
}

// ExpandedKey is the key blob ADD_ONION ED25519-V3 takes: the clamped secret
// scalar followed by the PRF secret, both halves of SHA-512 over the seed.
//
// Not the seed and not Go's seed‖public form - control-spec says so outright,
// because tor's key blinding cannot work from a seed. Measured (research,
// decision 3): the address tor reports for this blob is the one Address
// computes from the same seed.
func ExpandedKey(seed []byte) ([]byte, error) {
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("onion seed is %d bytes, want %d", len(seed), ed25519.SeedSize)
	}
	h := sha512.Sum512(seed)
	h[0] &= 248
	h[31] &= 63
	h[31] |= 64
	out := make([]byte, len(h))
	copy(out, h[:])
	return out, nil
}

// Address is the 56-character v3 onion address of a public key, without the
// ".onion" suffix: base32(pub ‖ checksum ‖ version), lower case, where the
// checksum is the first two bytes of SHA3-256(".onion checksum" ‖ pub ‖
// version) - rend-spec-v3, section 6.
func Address(pub ed25519.PublicKey) (string, error) {
	if len(pub) != ed25519.PublicKeySize {
		return "", fmt.Errorf("onion public key is %d bytes, want %d", len(pub), ed25519.PublicKeySize)
	}
	input := make([]byte, 0, len(".onion checksum")+len(pub)+1)
	input = append(input, ".onion checksum"...)
	input = append(input, pub...)
	input = append(input, onionVersion)
	sum := sha3.Sum256(input)

	raw := make([]byte, 0, len(pub)+3)
	raw = append(raw, pub...)
	raw = append(raw, sum[0], sum[1], onionVersion)
	return strings.ToLower(base32NoPad.EncodeToString(raw)), nil
}

// ClientAuthKey renders an x25519 public key the way ADD_ONION's ClientAuthV3
// wants it: base32 without padding.
func ClientAuthKey(pub []byte) (string, error) {
	if len(pub) != AccessKeySize {
		return "", fmt.Errorf("access key is %d bytes, want %d", len(pub), AccessKeySize)
	}
	return base32NoPad.EncodeToString(pub), nil
}

// ParseAccessKey decodes an access key as it travels on the wire: standard
// base64 of 32 bytes. x25519 has no invalid points worth rejecting here - tor
// takes any 32 bytes, and a wrong key simply never decrypts a descriptor.
func ParseAccessKey(b64 string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(raw) != AccessKeySize {
		return nil, ErrBadAccessKey
	}
	return raw, nil
}

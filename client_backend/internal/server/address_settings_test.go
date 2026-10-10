package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha3"
	"encoding/base64"
	"encoding/hex"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/store"
)

// Two onion addresses checked independently of this package: RFC 8032 test 1's
// public key (the address computed by a separate script when 039 was written),
// and the example address of contract §3.
const (
	rfcOnionKeyHex   = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	contractOnion    = "6bauzvyr6myctqykmykeuo3p3yc3iy7tilx5g3sxxpuifdwab54o56id.onion"
	contractOnionKey = "f0414cd711f33029c30a66144a3b6fde05b463f342efd36e57bbe8828ec00f78"
)

// onionAddressOf is the v3 onion address of a service key, with its suffix:
// key ‖ checksum ‖ version in lower-case base32 (rend-spec-v3 §6). The inverse
// of parseOnionAddress, and kept here: nothing in the server derives an address
// from a key.
func onionAddressOf(key ed25519.PublicKey, version byte) string {
	sum := onionChecksum(key)
	raw := make([]byte, 0, ed25519.PublicKeySize+3)
	raw = append(raw, key...)
	raw = append(raw, sum[0], sum[1], version)
	return onionAlphabet.EncodeToString(raw) + ".onion"
}

func randomOnion(t *testing.T) (string, ed25519.PublicKey) {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateKey: %v", err)
	}
	return onionAddressOf(pub, onionVersion), pub
}

// The onion addresses that read, and the key each one names: what goes into a
// link for it.
func TestAValidOnionAddressReadsBackToItsKey(t *testing.T) {
	random, randomKey := randomOnion(t)
	for _, tc := range []struct {
		in, stored, keyHex string
	}{
		{testOnionAddr, testOnionAddr, rfcOnionKeyHex},
		{testOnionAddr + ":443", testOnionAddr, rfcOnionKeyHex},
		{contractOnion, contractOnion, contractOnionKey},
		{random, random, hex.EncodeToString(randomKey)},
	} {
		stored, key, err := parseOnionAddress(tc.in)
		if err != nil {
			t.Fatalf("parseOnionAddress(%q): %v", tc.in, err)
		}
		if stored != tc.stored || hex.EncodeToString(key) != tc.keyHex {
			t.Fatalf("parseOnionAddress(%q) = %q, %x; want %q, %s", tc.in, stored, key, tc.stored, tc.keyHex)
		}
	}
}

// Everything that is not a v3 address of this shape is refused - above all a
// typo, which the checksum catches, and a different port, which is a
// different service.
func TestAnOnionAddressThatIsNotV3IsRefused(t *testing.T) {
	name := strings.TrimSuffix(testOnionAddr, ".onion")
	key := ed25519.PublicKey(mustHex(t, rfcOnionKeyHex))
	flip := func(i int, c byte) string {
		b := []byte(name)
		b[i] = c
		return string(b) + ".onion"
	}
	// Version 2 with its own checksum: well-formed in every way but the one
	// that says which kind of address it is.
	sumV2 := onionChecksumWith(key, 0x02)
	v2 := onionAlphabet.EncodeToString(append(append(bytes.Clone([]byte(key)), sumV2[0], sumV2[1]), 0x02)) + ".onion"

	for _, tc := range []struct{ name, in string }{
		{"a typo the checksum catches", flip(10, 'a')},
		{"a typo in the last character", flip(55, 'a')},
		{"version 2", onionAddressOf(key, 0x02)},
		{"version 2 with a version-2 checksum", v2},
		{"55 characters", name[:55] + ".onion"},
		{"57 characters", name + "a.onion"},
		{"upper case", strings.ToUpper(name) + ".onion"},
		{"an upper-case suffix", name + ".ONION"},
		{"no suffix", name},
		{"a subdomain", "www." + testOnionAddr},
		{"another port", testOnionAddr + ":80"},
		{"the direct port", testOnionAddr + ":8443"},
		{"a padded port", testOnionAddr + ":0443"},
		{"an empty port", testOnionAddr + ":"},
		{"a digit outside base32", flip(3, '1')},
		{"a line break inside", name[:20] + "\n" + name[20:] + ".onion"},
		{"a space in front", " " + testOnionAddr},
		{"empty", ""},
		{"a v2 address", "expyuzz4wqqyqhjn.onion"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got, _, err := parseOnionAddress(tc.in); err == nil {
				t.Fatalf("parseOnionAddress(%q) accepted it as %q", tc.in, got)
			}
		})
	}
}

// onionChecksumWith is the checksum over another version byte - to build an
// address that is right in every way but its version.
func onionChecksumWith(key []byte, version byte) [32]byte {
	input := append([]byte(".onion checksum"), key...)
	return sha3.Sum256(append(input, version))
}

// The public addresses that read, each in the one spelling it is stored in.
func TestAPublicAddressReadsAsHostAndPort(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"nox.example.org:8443", "nox.example.org:8443"},
		{"NOX.Example.ORG:8443", "nox.example.org:8443"},
		{"nox.example.org.:8443", "nox.example.org:8443"},
		{"nox.example.org:08443", "nox.example.org:8443"},
		{"203.0.113.7:443", "203.0.113.7:443"},
		{"[2001:DB8::1]:8443", "[2001:db8::1]:8443"},
		{"[::ffff:192.0.2.1]:8443", "192.0.2.1:8443"},
		{"nas:1", "nas:1"},
		{"xn--80ak6aa92e.com:65535", "xn--80ak6aa92e.com:65535"},
		{"a-b.c-d.example:8080", "a-b.c-d.example:8080"},
	} {
		got, err := parsePublicAddress(tc.in)
		if err != nil || got != tc.want {
			t.Errorf("parsePublicAddress(%q) = %q, %v; want %q", tc.in, got, err, tc.want)
		}
	}
}

// What is not host:port with a usable host and port is refused - including
// what the link builder could not encode, because a public address goes into
// every link the machine hands out.
func TestAPublicAddressThatIsNotHostAndPortIsRefused(t *testing.T) {
	for _, tc := range []struct{ name, in string }{
		{"no port", "nox.example.org"},
		{"no host", ":8443"},
		{"an empty port", "nox.example.org:"},
		{"port 0", "nox.example.org:0"},
		{"a port past 65535", "nox.example.org:65536"},
		{"a service name for a port", "nox.example.org:https"},
		{"a signed port", "nox.example.org:+80"},
		{"a negative port", "nox.example.org:-1"},
		{"an unbracketed IPv6 address", "2001:db8::1:8443"},
		{"an IPv6 address with a zone", "[fe80::1%en0]:8443"},
		{"an underscore", "nox_box.example.org:8443"},
		{"a label that starts with a hyphen", "-nox.example.org:8443"},
		{"a label that ends with a hyphen", "nox-.example.org:8443"},
		{"an empty label", "nox..example.org:8443"},
		{"a leading dot", ".nox.example.org:8443"},
		{"a label of 64 characters", strings.Repeat("a", 64) + ".example.org:8443"},
		{"a name of 254 bytes", strings.Repeat("a.", 126) + "ab:8443"},
		{"a mistyped IPv4 address", "192.168.1.300:8443"},
		{"a bare number", "8443:8443"},
		{"an onion address", testOnionAddr + ":443"},
		{"a URL", "https://nox.example.org:8443"},
		{"a path", "nox.example.org:8443/ws"},
		{"a space", "nox example.org:8443"},
		{"a letter outside ASCII", "nox.exämple.org:8443"},
		{"empty", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got, err := parsePublicAddress(tc.in); err == nil {
				t.Fatalf("parsePublicAddress(%q) accepted it as %q", tc.in, got)
			}
		})
	}
}

// Empty is the one value both kinds take without checking: on the page it
// deletes the address.
func TestNormalizeAddressTakesEmptyAsDeletion(t *testing.T) {
	for _, kind := range []store.AddressKind{store.AddressPublic, store.AddressOnion} {
		if got, err := normalizeAddress(kind, ""); err != nil || got != "" {
			t.Fatalf("normalizeAddress(%s, \"\") = %q, %v", kind, got, err)
		}
	}
	if _, err := normalizeAddress(store.AddressKind("direct"), "nox.example.org:8443"); err == nil {
		t.Fatal("an unknown kind was normalised")
	}
}

// startStore is a migrated store with a machine row - what applyAddressParams
// finds at startup.
func startStore(t *testing.T) *store.Store {
	t.Helper()
	d, err := db.Open(filepath.Join(t.TempDir(), "params.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { _ = d.Close() })
	if _, err := db.Migrate(context.Background(), d.Write, os.DirFS("../../migrations")); err != nil {
		t.Fatalf("db.Migrate: %v", err)
	}
	st := store.New(d.Read, d.Write)
	if _, err := st.EnsureServerIdentity(context.Background()); err != nil {
		t.Fatalf("EnsureServerIdentity: %v", err)
	}
	return st
}

// start applies the two parameters the way Run does, and returns what it
// warned about and what it logged.
func start(t *testing.T, st *store.Store, public, onion string) ([]addressWarning, string) {
	t.Helper()
	logs := &syncBuffer{}
	warnings, err := applyAddressParams(context.Background(), st, config.Config{PublicAddr: public, OnionAddr: onion},
		slog.New(slog.NewTextHandler(logs, nil)))
	if err != nil {
		t.Fatalf("applyAddressParams: %v", err)
	}
	return warnings, logs.String()
}

func stored(t *testing.T, st *store.Store) store.Addresses {
	t.Helper()
	got, err := st.Addresses(context.Background())
	if err != nil {
		t.Fatalf("Addresses: %v", err)
	}
	return got
}

// FR-003, start by start: a parameter is written when it appears or changes,
// and only then - so an address set on the page survives a restart with the
// same parameter still in the unit file - and an empty one changes nothing.
func TestAStartParameterIsAppliedWhenItAppearsOrChanges(t *testing.T) {
	st := startStore(t)
	ctx := context.Background()

	if w, _ := start(t, st, "", ""); len(w) != 0 || stored(t, st) != (store.Addresses{}) {
		t.Fatalf("no parameters: warnings %v, stored %+v", w, stored(t, st))
	}

	// New: written, the value in its stored form, the parameter as given.
	w, logs := start(t, st, "nox.example.org:8443", testOnionAddr+":443")
	want := store.Addresses{Public: "nox.example.org:8443", Onion: testOnionAddr,
		PublicParam: "nox.example.org:8443", OnionParam: testOnionAddr + ":443"}
	if len(w) != 0 || stored(t, st) != want {
		t.Fatalf("new parameters: warnings %v, stored %+v, want %+v", w, stored(t, st), want)
	}
	if !strings.Contains(logs, "start parameter applied") {
		t.Fatalf("the log does not say the parameters were applied:\n%s", logs)
	}

	// The owner changes the onion address on the page; the next start carries
	// the same parameter as before and leaves the page's edit alone.
	if err := st.SetAddress(ctx, store.AddressOnion, contractOnion); err != nil {
		t.Fatalf("SetAddress: %v", err)
	}
	start(t, st, "nox.example.org:8443", testOnionAddr+":443")
	if got := stored(t, st); got.Onion != contractOnion {
		t.Fatalf("the same parameter overwrote the page's edit: %+v", got)
	}

	// Changed: written again, over the page's edit.
	start(t, st, "nox.example.org:9443", testOnionAddr)
	if got := stored(t, st); got.Onion != testOnionAddr || got.OnionParam != testOnionAddr ||
		got.Public != "nox.example.org:9443" || got.PublicParam != "nox.example.org:9443" {
		t.Fatalf("changed parameters: %+v", got)
	}

	// Empty after one was applied: nothing moves, and nothing is forgotten.
	before := stored(t, st)
	start(t, st, "", "")
	if got := stored(t, st); got != before {
		t.Fatalf("empty parameters changed %+v into %+v", before, got)
	}
}

// A malformed parameter is not applied and does not stop the start: the
// stored address stays, the warning names the parameter, and - because a
// refused parameter is never recorded - the next start warns again.
func TestAMalformedStartParameterKeepsTheStoredAddressAndWarnsEveryStart(t *testing.T) {
	st := startStore(t)
	start(t, st, "nox.example.org:8443", testOnionAddr)
	before := stored(t, st)

	// A one-character typo of the real address: the checksum catches it.
	name := []byte(strings.TrimSuffix(testOnionAddr, ".onion"))
	name[10] = 'a'
	typo := string(name) + ".onion"
	for range 2 {
		w, logs := start(t, st, "nox.example.org", typo)
		if len(w) != 2 || w[0].Kind != store.AddressPublic || w[1].Kind != store.AddressOnion {
			t.Fatalf("warnings = %+v, want one for each malformed parameter", w)
		}
		if got := stored(t, st); got != before {
			t.Fatalf("a malformed parameter moved %+v to %+v", before, got)
		}
		for _, param := range []string{"-public-addr", "-onion-addr"} {
			if !strings.Contains(logs, param) {
				t.Fatalf("the log does not name %s:\n%s", param, logs)
			}
		}
		// Not the typo, and not the address it is one character away from.
		for _, secret := range []string{string(name), strings.TrimSuffix(testOnionAddr, ".onion")} {
			if strings.Contains(logs, secret) {
				t.Fatalf("an onion address reached the log:\n%s", logs)
			}
		}
	}
}

// A hand edit can leave a value no road in would have written. Startup says
// so once, without the value.
func TestAStoredAddressFromAHandEditIsReportedWithoutItsValue(t *testing.T) {
	st := startStore(t)
	name := []byte(strings.TrimSuffix(testOnionAddr, ".onion"))
	name[0] = 'a'
	if err := st.SetAddress(context.Background(), store.AddressOnion, string(name)+".onion"); err != nil {
		t.Fatalf("SetAddress: %v", err)
	}
	_, logs := start(t, st, "", "")
	if !strings.Contains(logs, "stored onion address is not valid") {
		t.Fatalf("the hand edit went unremarked:\n%s", logs)
	}
	if strings.Contains(logs, string(name)) {
		t.Fatalf("the stored value reached the log:\n%s", logs)
	}
}

// The mask catches an onion address in any spelling a library might quote it
// in, and leaves everything else alone.
func TestMaskOnionHidesOnionAddressesOnly(t *testing.T) {
	name := strings.TrimSuffix(testOnionAddr, ".onion")
	for _, in := range []string{
		`request Origin "evil.example" is not authorized for Host "` + testOnionAddr + `:443"`,
		"host " + strings.ToUpper(testOnionAddr) + " refused",
		"bare " + name + " name",
	} {
		got := maskOnion(in)
		if strings.Contains(strings.ToLower(got), name) || !strings.Contains(got, "[onion]") {
			t.Errorf("maskOnion(%q) = %q", in, got)
		}
	}
	for _, in := range []string{
		`request Origin "evil.example" is not authorized for Host "192.168.1.20:8443"`,
		"websocket: protocol violation",
		base64.StdEncoding.EncodeToString(make([]byte, 16)),
	} {
		if got := maskOnion(in); got != in {
			t.Errorf("maskOnion(%q) = %q, want it unchanged", in, got)
		}
	}
}

// The Host header is the only sign left that a request came through tor.
func TestOnionHostTellsAnOnionNameFromAnythingElse(t *testing.T) {
	for host, want := range map[string]bool{
		testOnionAddr:                    true,
		testOnionAddr + ":443":           true,
		strings.ToUpper(testOnionAddr):   true,
		testOnionAddr + ".:443":          true,
		"192.168.1.20:8443":              false,
		"[fd00::1]:8443":                 false,
		"nox.example.org":                false,
		"onion.example.org:8443":         false,
		"":                               false,
		"example.onion.example.org:8443": false,
	} {
		if got := onionHost(host); got != want {
			t.Errorf("onionHost(%q) = %v, want %v", host, got, want)
		}
	}
}

// The full shared vector, built from STORED addresses: an IPv4 public address,
// a name as the one direct address, and the onion service the stored address
// names. The order of the link and the key in it come out byte for byte the
// app's own vector.
func TestTheFullVectorComesOutOfStoredAddresses(t *testing.T) {
	v := loadLinkVectors(t)
	key := ed25519.PublicKey(mustHex(t, v.Full.ServerPublicKey))
	token := base64.RawURLEncoding.EncodeToString(mustHex(t, v.Full.Token))
	conf := configured(store.Addresses{
		Public: "192.168.1.20:8443",
		Onion:  "c7fxt6zlieqpfmpmmxsbtdlobczi5aj75ma6jjaaqonylymaqdhnusqd.onion",
	})
	if conf.OnionKey == nil || conf.Public == "" {
		t.Fatalf("the stored addresses did not read: %+v", conf)
	}
	link, carries, err := buildLink(key, token, "nox.example.org:8443", conf)
	if err != nil {
		t.Fatalf("buildLink: %v", err)
	}
	if link != v.Full.Link {
		t.Fatalf("link\n got %s\nwant %s", link, v.Full.Link)
	}
	if !carries.Public || !carries.Onion {
		t.Fatalf("carries = %+v, want both", carries)
	}
}

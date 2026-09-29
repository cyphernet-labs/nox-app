package tor

import (
	"strings"
	"testing"
)

func TestScrubRemovesOnionAddressesAndKeys(t *testing.T) {
	const addr = "6bauzvyr6myctqykmykeuo3p3yc3iy7tilx5g3sxxpuifdwab54o56id"
	const b64Key = "MHyDhk8oM8tCei7xwAoBPP3/J2jZgMCjpSDwBpBN6U+bTwr+KAt0aneGhOdUQlAgV7dHOgPwj5b1o46Sh+Afjw=="
	const b32Key = "H52HE6IPAKIP7NYNTJTYICOYDG4ZQFZWZSEOPNQJJX772QQBNFUA"

	for name, in := range map[string]string{
		"address with suffix":    "Uploaded descriptor for " + addr + ".onion to 6 directories",
		"address without suffix": "HS_DESC UPLOADED " + addr + " UNKNOWN",
		"upper-case address":     "service " + strings.ToUpper(addr),
		"base64 key":             "ADD_ONION ED25519-V3:" + b64Key,
		"base32 client key":      "ClientAuthV3=" + b32Key,
	} {
		got := Scrub(in)
		for _, secret := range []string{addr, strings.ToUpper(addr), b64Key, b32Key} {
			if strings.Contains(got, secret) {
				t.Errorf("%s: %q still carries a secret", name, got)
			}
		}
	}
}

func TestScrubLeavesOrdinaryLinesAlone(t *testing.T) {
	for _, in := range []string{
		"Bootstrapped 100% (done): Done",
		"Tor 0.4.9.13 (git-3c575400909efe65) running on Darwin",
		"Opening Control listener on 127.0.0.1:9051",
	} {
		if got := Scrub(in); got != in {
			t.Errorf("Scrub(%q) = %q, want it unchanged", in, got)
		}
	}
}

func TestParseLogLineSplitsTheSeverity(t *testing.T) {
	got := ParseLogLine("Oct 03 11:13:50.000 [notice] Bootstrapped 100% (done): Done\n")
	if got.Level != "notice" || got.Message != "Bootstrapped 100% (done): Done" {
		t.Fatalf("ParseLogLine = %+v", got)
	}
	warn := ParseLogLine("Oct 03 11:14:00.000 [warn] Our clock is 2 hours behind")
	if warn.Level != "warn" {
		t.Fatalf("level = %q, want warn", warn.Level)
	}
	plain := ParseLogLine("no tag here")
	if plain.Level != "" || plain.Message != "no tag here" {
		t.Fatalf("untagged line = %+v", plain)
	}
}

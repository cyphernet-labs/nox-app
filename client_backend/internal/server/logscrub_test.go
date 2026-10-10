package server

import (
	"encoding/base64"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"testing"
	"time"
)

// testLink is a version 3 pairing link of the shared vectors' shape: the
// scheme, then base64url.
const testLink = "nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7"

// The rule catches an onion address in any spelling a library might quote it
// in and a pairing link wherever it sits, and leaves everything else alone.
func TestScrubHidesOnionAddressesAndLinksOnly(t *testing.T) {
	name := strings.TrimSuffix(testOnionAddr, ".onion")
	for _, in := range []string{
		`request Origin "evil.example" is not authorized for Host "` + testOnionAddr + `:443"`,
		"host " + strings.ToUpper(testOnionAddr) + " refused",
		"bare " + name + " name",
	} {
		got := scrub(in)
		if strings.Contains(strings.ToLower(got), name) || !strings.Contains(got, "[onion]") {
			t.Errorf("scrub(%q) = %q", in, got)
		}
	}
	for in, want := range map[string]string{
		"claim it with " + testLink + " now":  "claim it with [link] now",
		"(" + strings.ToUpper(testLink) + ")": "([link])",
		testLink + "==":                       "[link]",
	} {
		if got := scrub(in); got != want {
			t.Errorf("scrub(%q) = %q, want %q", in, got, want)
		}
	}
	for _, in := range []string{
		`request Origin "evil.example" is not authorized for Host "192.168.1.20:8443"`,
		"websocket: protocol violation",
		// The machine's public key, as the startup line prints it.
		base64.StdEncoding.EncodeToString(make([]byte, 32)),
		"nox://id/not-a-pairing-link",
	} {
		if got := scrub(in); got != in {
			t.Errorf("scrub(%q) = %q, want it unchanged", in, got)
		}
	}
}

// A link whose payload happens to hold a run that reads as an onion name goes
// as a whole: masking the run first would leave the tail of the link behind it.
func TestALinkIsMaskedWholeEvenWhenItsPayloadLooksLikeAnOnionName(t *testing.T) {
	link := "nox://pair/" + strings.Repeat("a", 60) + "XYZ_-tail"
	if got := scrub("link " + link + " end"); got != "link [link] end" {
		t.Fatalf("scrub = %q, want the link masked whole", got)
	}
}

// onionValuer is a value that logs itself as an onion address.
type onionValuer struct{}

func (onionValuer) LogValue() slog.Value { return slog.StringValue("via " + testOnionAddr) }

// onionStringer prints an onion address only through fmt.
type onionStringer struct{}

func (onionStringer) String() string { return "dial " + testOnionAddr + ":443" }

// Every part of a line goes through the rule: the message, keys and strings,
// errors, groups, values that log or print themselves, bytes, and attributes
// added with With - while the values with nothing to hide keep their type and
// the rendering the handler gives them.
func TestTheLogHandlerScrubsEveryPartOfALine(t *testing.T) {
	logs := &syncBuffer{}
	logger := slog.New(ScrubLogs(slog.NewJSONHandler(logs, nil))).With("conn", "ab12", "host", testOnionAddr)
	logger.WithGroup("page").Info("set "+testOnionAddr,
		"link", testLink,
		"err", fmt.Errorf("dial %s: %w", testOnionAddr, errors.New("refused")),
		slog.Group("addr", "onion", testOnionAddr+":443", "port", 443),
		"valuer", onionValuer{},
		"stringer", onionStringer{},
		"bytes", []byte(testLink),
		testOnionAddr, "as a key",
		"count", 3,
		"took", 1500*time.Millisecond,
		"cleared", false,
	)
	out := logs.String()
	name := strings.TrimSuffix(testOnionAddr, ".onion")
	if strings.Contains(strings.ToLower(out), name) || strings.Contains(out, "nox://pair/") {
		t.Fatalf("the line still names the onion address or the link:\n%s", out)
	}
	for _, want := range []string{
		`"msg":"set [onion]"`, `"conn":"ab12"`, `"host":"[onion]"`, `"link":"[link]"`,
		`"err":"dial [onion]: refused"`, `"onion":"[onion]:443"`, `"port":443`, `"valuer":"via [onion]"`,
		`"stringer":"dial [onion]:443"`, `"bytes":"[link]"`, `"[onion]":"as a key"`, `"count":3`,
		`"took":1500000000`, `"cleared":false`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("the line lacks %s:\n%s", want, out)
		}
	}
}

// Wrapping twice wraps once - main wraps the process's handler and Run wraps
// what it is handed - and a logger built with With is still the scrubbed one.
func TestScrubbingIsAppliedOnce(t *testing.T) {
	base := slog.NewTextHandler(&syncBuffer{}, nil)
	once := ScrubLogs(base)
	if twice := ScrubLogs(once); twice != once {
		t.Fatal("wrapping a scrubbed handler wrapped it again")
	}
	logger := scrubbedLogger(slog.New(once)).With("conn", "ab12")
	if again := scrubbedLogger(logger); again != logger {
		t.Fatal("a scrubbed logger built with With was wrapped again")
	}
	if _, ok := scrubbedLogger(slog.New(base)).Handler().(scrubHandler); !ok {
		t.Fatal("a plain logger was not wrapped")
	}
}

package tor

import (
	"regexp"
	"strings"
)

var (
	// onionAddr is a v3 onion address, with or without its suffix: 56
	// characters of the base32 alphabet.
	onionAddr = regexp.MustCompile(`(?i)\b[a-z2-7]{56}(\.onion)?\b`)
	// keyLike is anything shaped like key material: a run of 40 or more
	// base64, base64url or base32 characters. Generous on purpose - a relay
	// fingerprint scrubbed by mistake costs nothing, a key let through costs
	// the key.
	keyLike = regexp.MustCompile(`[A-Za-z0-9+/_=-]{40,}`)
	// logLevel finds tor's own severity tag in a log line.
	logLevel = regexp.MustCompile(`\[(debug|info|notice|warn|err)\]`)
)

// Scrub removes what must never reach the server's log or the status page
// (FR-031): onion addresses become "[onion]", anything shaped like a key
// becomes "[key]". It is applied to every line of tor's output and to every
// error that could have been built from tor's words.
func Scrub(line string) string {
	line = onionAddr.ReplaceAllString(line, "[onion]")
	return keyLike.ReplaceAllString(line, "[key]")
}

// LogLine is one line of tor's own log, split into its severity and message.
type LogLine struct {
	Level   string
	Message string
}

// ParseLogLine reads a line of `Log notice stdout` output - "Oct 03 11:13:50.000
// [notice] Bootstrapped 100% (done): Done" - scrubbed. A line without a
// severity tag comes back with an empty Level.
func ParseLogLine(line string) LogLine {
	clean := Scrub(strings.TrimSpace(line))
	m := logLevel.FindStringSubmatchIndex(clean)
	if m == nil {
		return LogLine{Message: clean}
	}
	return LogLine{
		Level:   clean[m[2]:m[3]],
		Message: strings.TrimSpace(clean[m[1]:]),
	}
}

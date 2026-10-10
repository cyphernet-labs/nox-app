package server

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
)

// What the server's log must never carry, however it got into a line - written
// by this code, quoted by a library's error, or sent by a stranger as a request
// path (045, FR-022):
//
//   - an onion address. Since 045 nothing but knowing it stands between a
//     stranger and the onion service - there are no access keys any more - and
//     a log is copied to places the address must not go: a bug report, a
//     support thread, a log collector;
//   - a pairing link. It carries a token that pairs a device with this machine
//     and, packed, the onion service's key - the onion address in another
//     spelling.
//
// Both are replaced at the sink, in the one handler every line of the process
// goes through, rather than at the call sites: a call site covers only the text
// its author thought of.

// onionInText finds a v3 onion address in any text, with or without its suffix
// and in either case. Generous on purpose: a run of base32 masked by mistake
// costs nothing, an onion address let through costs the address.
var onionInText = regexp.MustCompile(`(?i)[a-z2-7]{56}(\.onion)?`)

// linkInText finds a pairing link: the scheme in any case, then the base64url
// after it, with any padding a hand-made link might carry.
var linkInText = regexp.MustCompile(`(?i)nox://pair/[A-Za-z0-9_=-]*`)

// scrub replaces every pairing link with "[link]" and every onion address with
// "[onion]". Links first: a link's payload can hold a run that reads as an
// onion name, and masking that run first would leave the rest of the link
// behind it, no longer recognisable as one.
func scrub(s string) string {
	s = linkInText.ReplaceAllString(s, "[link]")
	return onionInText.ReplaceAllString(s, "[onion]")
}

// scrubHandler hands every record on to next with scrub applied to everything
// it carries: the message, the keys, every string, and the text of every other
// value - an error above all.
type scrubHandler struct {
	next slog.Handler
}

// ScrubLogs wraps h so that no onion address and no pairing link reaches it.
//
// Wrapping twice wraps once. main wraps the process's handler, so that the
// configuration error a start can die of is covered too; Run and New wrap
// whatever logger they are handed, so a server built any other way - a test's,
// above all - is held to the same rule as the binary.
func ScrubLogs(h slog.Handler) slog.Handler {
	if _, ok := h.(scrubHandler); ok {
		return h
	}
	return scrubHandler{next: h}
}

// scrubbedLogger is l with ScrubLogs under it.
func scrubbedLogger(l *slog.Logger) *slog.Logger {
	if _, ok := l.Handler().(scrubHandler); ok {
		return l
	}
	return slog.New(scrubHandler{next: l.Handler()})
}

func (h scrubHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.next.Enabled(ctx, level)
}

func (h scrubHandler) Handle(ctx context.Context, r slog.Record) error {
	clean := slog.NewRecord(r.Time, r.Level, scrub(r.Message), r.PC)
	r.Attrs(func(a slog.Attr) bool {
		clean.AddAttrs(scrubAttr(a))
		return true
	})
	return h.next.Handle(ctx, clean)
}

func (h scrubHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return scrubHandler{next: h.next.WithAttrs(scrubAttrs(attrs))}
}

func (h scrubHandler) WithGroup(name string) slog.Handler {
	return scrubHandler{next: h.next.WithGroup(scrub(name))}
}

func scrubAttrs(attrs []slog.Attr) []slog.Attr {
	out := make([]slog.Attr, len(attrs))
	for i, a := range attrs {
		out[i] = scrubAttr(a)
	}
	return out
}

func scrubAttr(a slog.Attr) slog.Attr {
	return slog.Attr{Key: scrub(a.Key), Value: scrubValue(a.Value)}
}

// scrubValue cleans one value. Numbers, booleans, times and durations carry no
// text and pass as they are. Anything else the next handler would print is
// checked as the text it prints, and replaced by that text scrubbed only when
// there was something to hide - so every other value keeps the rendering the
// handler gives it.
func scrubValue(v slog.Value) slog.Value {
	v = v.Resolve()
	switch v.Kind() {
	case slog.KindString:
		return slog.StringValue(scrub(v.String()))
	case slog.KindGroup:
		return slog.GroupValue(scrubAttrs(v.Group())...)
	case slog.KindAny:
		var text string
		switch x := v.Any().(type) {
		case error:
			text = x.Error()
		case []byte:
			text = string(x)
		default:
			text = fmt.Sprintf("%+v", x)
		}
		if clean := scrub(text); clean != text {
			return slog.StringValue(clean)
		}
	}
	return v
}

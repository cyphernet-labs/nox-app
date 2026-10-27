package server

import (
	"fmt"
	"strings"

	"rsc.io/qr"
)

// qrSVG renders text as an inline SVG QR code.
//
// Inline rather than a PNG endpoint: one request serves the whole page, there
// is no second URL that could be fetched on its own, and nothing has to encode
// the machine link into a path where a browser would keep it in history.
//
// White on black is NOT an option here even though the page has a dark theme:
// scanners expect dark modules on a light ground, and the quiet zone is part of
// the format rather than decoration. The surface is painted white explicitly so
// a browser rendering the page dark cannot invert it.
func qrSVG(text string, pixel int) (string, error) {
	// Level M: the code is read off a screen at arm's length rather than from
	// a printed label under bad light, and the higher levels only make the
	// modules smaller for reach nobody needs here.
	code, err := qr.Encode(text, qr.M)
	if err != nil {
		return "", fmt.Errorf("encode qr: %w", err)
	}
	const quiet = qrQuietZone
	size := code.Size
	side := (size + quiet*2) * pixel

	var b strings.Builder
	fmt.Fprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="Pairing code">`,
		side, side, size+quiet*2, size+quiet*2)
	fmt.Fprintf(&b, `<rect width="%d" height="%d" fill="#ffffff"/>`, size+quiet*2, size+quiet*2)
	b.WriteString(`<path fill="#000000" d="`)
	for y := range size {
		for x := range size {
			if code.Black(x, y) {
				fmt.Fprintf(&b, "M%d %dh1v1h-1z", x+quiet, y+quiet)
			}
		}
	}
	b.WriteString(`"/></svg>`)
	return b.String(), nil
}

// qrQuietZone is the light margin around a code, in modules - mandated by the
// format, and part of what a scanner looks for.
const qrQuietZone = 4

// QRText renders text as a QR code of terminal characters, for `noxd link -qr`
// on a machine with no screen but a terminal (049).
//
// Two rows of modules per line of text, drawn with the half blocks ▀ and ▄ and
// the full block █: a terminal's character cell is about twice as tall as it
// is wide, so the modules come out square. The LIGHT modules and the quiet zone
// are the ones drawn and dark ones are left blank, as `qrencode -t UTF8` does:
// a terminal is light text on a dark ground far more often than not, and there
// the code reads dark modules on a light ground - what every scanner expects.
// On a light terminal it comes out inverted, which many scanners still read,
// and the link printed under it is always there to paste.
//
// No colour escapes: they are the only way to force the ground, and they turn
// into garbage in a log, a pipe, or a console that does not speak them.
func QRText(text string) (string, error) {
	code, err := qr.Encode(text, qr.M)
	if err != nil {
		return "", fmt.Errorf("encode qr: %w", err)
	}
	side := code.Size + 2*qrQuietZone
	// light is outside the code as well, beyond the last row included: the
	// half row an odd side leaves at the bottom is quiet zone, not a module.
	light := func(x, y int) bool {
		x, y = x-qrQuietZone, y-qrQuietZone
		if x < 0 || y < 0 || x >= code.Size || y >= code.Size {
			return true
		}
		return !code.Black(x, y)
	}
	var b strings.Builder
	for y := 0; y < side; y += 2 {
		for x := range side {
			switch top, bottom := light(x, y), light(x, y+1); {
			case top && bottom:
				b.WriteRune('█')
			case top:
				b.WriteRune('▀')
			case bottom:
				b.WriteRune('▄')
			default:
				b.WriteByte(' ')
			}
		}
		b.WriteByte('\n')
	}
	return b.String(), nil
}

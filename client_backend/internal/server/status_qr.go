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
// the claim link into a path where a browser would keep it in history.
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
	const quiet = 4 // modules, mandated by the format
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

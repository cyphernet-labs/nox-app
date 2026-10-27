// Package prompt reads passwords for the server's commands (047): from the
// terminal without echo, or a line at a time from standard input when that is
// not a terminal - which is how an install script sets the first password
// without anybody at the keyboard.
package prompt

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"
)

// ErrNoPassword is standard input that ended before a password.
var ErrNoPassword = errors.New("no password on standard input")

// Reader asks for passwords, one after another, from one source.
type Reader struct {
	// fd is the terminal's descriptor, or -1 when input is not a terminal.
	fd  int
	out io.Writer
	// lines reads standard input that is not a terminal. One reader for every
	// password asked: a second one would find the first's buffer already
	// holding the next line.
	lines *bufio.Reader
}

// New reads from in, prompting on out. A terminal is read without echo, and
// the prompt and the newline the person typed go to out; anything else is
// read a line at a time with no prompt at all, so a script's output stays
// its own.
func New(in *os.File, out io.Writer) *Reader {
	fd := int(in.Fd()) //nolint:gosec // a descriptor fits an int on every platform Go runs on
	if term.IsTerminal(fd) {
		return &Reader{fd: fd, out: out}
	}
	return FromLines(in)
}

// FromLines reads passwords a line at a time from r, prompting nowhere.
func FromLines(r io.Reader) *Reader {
	return &Reader{fd: -1, out: io.Discard, lines: bufio.NewReader(r)}
}

// Terminal says whether the passwords come from a person at a terminal.
func (r *Reader) Terminal() bool {
	return r.fd >= 0
}

// Password asks for one password with label. A line from standard input ends
// at its newline, a carriage return before it included; nothing else is
// trimmed - a password is exactly what was typed.
func (r *Reader) Password(label string) (string, error) {
	if r.fd >= 0 {
		_, _ = fmt.Fprint(r.out, label)
		b, err := term.ReadPassword(r.fd)
		_, _ = fmt.Fprintln(r.out)
		if err != nil {
			return "", fmt.Errorf("read the password: %w", err)
		}
		return string(b), nil
	}
	line, err := r.lines.ReadString('\n')
	if err != nil && !(errors.Is(err, io.EOF) && line != "") {
		if errors.Is(err, io.EOF) {
			return "", ErrNoPassword
		}
		return "", fmt.Errorf("read the password from standard input: %w", err)
	}
	line = strings.TrimSuffix(line, "\n")
	return strings.TrimSuffix(line, "\r"), nil
}

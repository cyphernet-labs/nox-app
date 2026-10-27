package prompt

import (
	"errors"
	"os"
	"strings"
	"testing"
)

// A script sets the first password by piping it twice; each line is one
// password, exactly as written, with only its line end taken off.
func TestPasswordsComeFromStandardInputALineAtATime(t *testing.T) {
	r := FromLines(strings.NewReader("correct horse battery\r\n  spaced  password \nlast-without-newline"))
	for _, want := range []string{"correct horse battery", "  spaced  password ", "last-without-newline"} {
		got, err := r.Password("Password: ")
		if err != nil || got != want {
			t.Fatalf("Password() = %q, %v; want %q", got, err, want)
		}
	}
	if _, err := r.Password("Password: "); !errors.Is(err, ErrNoPassword) {
		t.Fatalf("Password() past the end = %v, want ErrNoPassword", err)
	}
	if r.Terminal() {
		t.Fatal("a string reader reports itself as a terminal")
	}
}

func TestAnEmptyLineIsAnEmptyPasswordNotTheEnd(t *testing.T) {
	r := FromLines(strings.NewReader("\nsecond\n"))
	if got, err := r.Password("Password: "); err != nil || got != "" {
		t.Fatalf("an empty line = %q, %v; want an empty password", got, err)
	}
	if got, err := r.Password("Repeat: "); err != nil || got != "second" {
		t.Fatalf("the next line = %q, %v", got, err)
	}
}

// Standard input that is a pipe, not a terminal: New reads it as lines and
// prompts nowhere, so a script's own output is untouched.
func TestNewReadsAPipeAsLinesAndPromptsNowhere(t *testing.T) {
	rd, wr, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	t.Cleanup(func() { _ = rd.Close() })
	if _, err := wr.WriteString("from a script\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	_ = wr.Close()
	var out strings.Builder
	r := New(rd, &out)
	if r.Terminal() {
		t.Fatal("a pipe was taken for a terminal")
	}
	got, err := r.Password("Password: ")
	if err != nil || got != "from a script" {
		t.Fatalf("Password() = %q, %v", got, err)
	}
	if out.Len() != 0 {
		t.Fatalf("a prompt went out for a pipe: %q", out.String())
	}
}

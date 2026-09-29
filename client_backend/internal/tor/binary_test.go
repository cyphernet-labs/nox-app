package tor

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestParseVersionReadsWhatTorPrints(t *testing.T) {
	for _, tc := range []struct {
		out  string
		want Version
	}{
		{"Tor version 0.4.9.13 (git-3c575400909efe65).\nThis build of Tor is covered by the GNU General Public License", Version{0, 4, 9, 13}},
		{"Tor version 0.4.9.1-alpha.", Version{0, 4, 9, 1}},
		{"Tor version 0.5.0.1 (git-abc).", Version{0, 5, 0, 1}},
		{"Tor version 0.4.8.17.", Version{0, 4, 8, 17}},
		{"Tor version 1.0.0.", Version{1, 0, 0, 0}},
	} {
		got, err := ParseVersion(tc.out)
		if err != nil || got != tc.want {
			t.Errorf("ParseVersion(%q) = %v, %v; want %v", tc.out, got, err, tc.want)
		}
	}
	for _, junk := range []string{"", "tor", "Arti 2.7.0", "Tor version x.y"} {
		if _, err := ParseVersion(junk); err == nil {
			t.Errorf("ParseVersion(%q) accepted junk", junk)
		}
	}
}

func TestTheFloorIsZeroFourNine(t *testing.T) {
	for _, tc := range []struct {
		v    Version
		want bool
	}{
		{Version{0, 4, 8, 17}, false}, // sunset 2026-09-01
		{Version{0, 4, 7, 16}, false},
		{Version{0, 4, 9, 0}, true},
		{Version{0, 4, 9, 13}, true},
		{Version{0, 5, 0, 1}, true},
		{Version{1, 0, 0, 0}, true},
	} {
		if got := tc.v.AtLeast(MinVersion); got != tc.want {
			t.Errorf("%v.AtLeast(%v) = %v, want %v", tc.v, MinVersion, got, tc.want)
		}
	}
}

// fakeTor puts an executable named like tor in a fresh directory.
func fakeTor(t *testing.T) (dir, path string) {
	t.Helper()
	dir = t.TempDir()
	path = filepath.Join(dir, binaryName())
	if err := os.WriteFile(path, []byte("#!/bin/sh\necho 'Tor version 0.4.9.13.'\n"), 0o755); err != nil {
		t.Fatalf("write fake tor: %v", err)
	}
	return dir, path
}

func TestAnExplicitPathIsFinalEvenWithTorInPath(t *testing.T) {
	dir, _ := fakeTor(t)
	t.Setenv("PATH", dir)

	_, err := Find(filepath.Join(t.TempDir(), "no-tor-here"))
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("Find(missing explicit path) err = %v, want ErrNotFound even though PATH has a tor", err)
	}
}

func TestAnExplicitPathThatHoldsTorIsUsed(t *testing.T) {
	_, path := fakeTor(t)
	got, err := Find(path)
	if err != nil || got != path {
		t.Fatalf("Find(%q) = %q, %v", path, got, err)
	}
}

// A bare name is a path like any other: the file in the working directory, made
// absolute - exec would otherwise look a bare name up in PATH and run a tor
// other than the one whose version was checked.
func TestABareNameForTorBinMeansTheFileInTheWorkingDirectory(t *testing.T) {
	here, herePath := fakeTor(t)
	elsewhere, _ := fakeTor(t)
	t.Setenv("PATH", elsewhere)
	t.Chdir(here)

	got, err := Find(binaryName())
	if err != nil || !filepath.IsAbs(got) {
		t.Fatalf("Find(%q) = %q, %v; want an absolute path", binaryName(), got, err)
	}
	if sameFile(t, got) != sameFile(t, herePath) {
		t.Fatalf("Find(%q) = %q, want the working directory's %q", binaryName(), got, herePath)
	}
}

// sameFile resolves symlinks - a temporary directory may sit behind one - so
// two names for one file compare equal.
func sameFile(t *testing.T, path string) string {
	t.Helper()
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		t.Fatalf("EvalSymlinks(%q): %v", path, err)
	}
	return resolved
}

func TestWithoutAPathTorIsLookedUpInPath(t *testing.T) {
	dir, path := fakeTor(t)
	t.Setenv("PATH", dir)
	got, err := Find("")
	if err != nil || got != path {
		t.Fatalf("Find(\"\") = %q, %v; want %q from PATH", got, err, path)
	}
}

func TestNoTorAnywhereIsNotFound(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	if _, err := Find(""); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Find with an empty PATH err = %v, want ErrNotFound", err)
	}
}

func TestReadVersionRunsTheBinary(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the fake tor is a shell script")
	}
	_, path := fakeTor(t)
	v, err := ReadVersion(t.Context(), path)
	if err != nil || v != (Version{0, 4, 9, 13}) {
		t.Fatalf("ReadVersion = %v, %v", v, err)
	}
}

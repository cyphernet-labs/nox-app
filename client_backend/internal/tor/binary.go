package tor

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"time"
)

// Version is tor's own version number. The fourth component is the patch
// level tor counts in; a suffix like "-alpha" is not part of the comparison.
type Version struct {
	Major, Minor, Micro, Patch int
}

// MinVersion is the floor this server runs on. The 0.4.8 series stopped being
// accepted by the network on 2026-09-01; everything above the floor is judged
// by the network itself (the verdict on the status page), not by a table here.
var MinVersion = Version{0, 4, 9, 0}

// String renders the version the way tor prints it.
func (v Version) String() string {
	return fmt.Sprintf("%d.%d.%d.%d", v.Major, v.Minor, v.Micro, v.Patch)
}

// AtLeast reports whether v is o or newer.
func (v Version) AtLeast(o Version) bool {
	for _, d := range [][2]int{{v.Major, o.Major}, {v.Minor, o.Minor}, {v.Micro, o.Micro}, {v.Patch, o.Patch}} {
		if d[0] != d[1] {
			return d[0] > d[1]
		}
	}
	return true
}

var versionLine = regexp.MustCompile(`Tor version (\d+)\.(\d+)\.(\d+)(?:\.(\d+))?`)

// ParseVersion reads the version out of `tor --version` output, whose first
// line is "Tor version 0.4.9.13 (git-3c575400909efe65).".
func ParseVersion(out string) (Version, error) {
	m := versionLine.FindStringSubmatch(out)
	if m == nil {
		return Version{}, errors.New("tor --version printed no version")
	}
	var parts [4]int
	for i := range parts {
		if m[i+1] == "" {
			continue
		}
		n, err := strconv.Atoi(m[i+1])
		if err != nil {
			return Version{}, fmt.Errorf("tor version component %q: %w", m[i+1], err)
		}
		parts[i] = n
	}
	return Version{parts[0], parts[1], parts[2], parts[3]}, nil
}

// ErrNotFound means there is no tor where it was looked for.
var ErrNotFound = errors.New("tor not found")

// Find locates the tor binary.
//
// An explicit path is FINAL: when it holds no tor the answer is "not found",
// never a search elsewhere. An operator who named a binary meant that one, and
// silently running another would be worse than refusing - it would also make
// "tor not found" impossible to reproduce on a machine that has a tor in PATH.
//
// The explicit path is made absolute first. A bare name like "tor" would be
// checked here against the working directory and then run by exec through
// PATH - a different binary from the one whose version was read.
//
// Without one: next to the server's own executable first, because that is
// where a packaged server will ship its tor on macOS and Windows; then PATH,
// which is where a Linux distribution or Homebrew puts it.
func Find(explicit string) (string, error) {
	if explicit != "" {
		abs, err := filepath.Abs(explicit)
		if err == nil && isFile(abs) {
			return abs, nil
		}
		return "", fmt.Errorf("%w at the path given by -tor-bin", ErrNotFound)
	}
	if exe, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(exe), binaryName())
		if isFile(candidate) {
			return candidate, nil
		}
	}
	if path, err := exec.LookPath(binaryName()); err == nil {
		return path, nil
	}
	return "", ErrNotFound
}

// ReadVersion runs `tor --version`. Bounded, because a binary that hangs on
// --version is a binary nothing else will go well with either.
func ReadVersion(ctx context.Context, path string) (Version, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, "--version").Output()
	if err != nil {
		return Version{}, fmt.Errorf("run tor --version: %w", err)
	}
	return ParseVersion(string(out))
}

func binaryName() string {
	if runtime.GOOS == "windows" {
		return "tor.exe"
	}
	return "tor"
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

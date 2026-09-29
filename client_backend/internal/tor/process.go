package tor

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// errTooOld means the tor that was found is below MinVersion.
var errTooOld = errors.New("tor is older than 0.4.9")

const (
	// controlPortWait bounds how long a fresh tor may take to open its control
	// port. Generous: a cold start on a slow board reads a large cache first.
	controlPortWait = 60 * time.Second
	// stopWait is how long tor gets to leave after its owner hangs up before
	// it is killed.
	stopWait = 10 * time.Second
	// commandTimeout bounds one control command. tor answers locally, so a
	// command that takes this long means tor is wedged.
	commandTimeout = 30 * time.Second
	// lineBuffer is how many of tor's lines wait for the supervisor. Nobody
	// reads while tor starts, and the last lines of a start that fails are
	// its reason.
	lineBuffer = 256
	// cookieSize is the length of tor's control cookie.
	cookieSize = 32
)

// controller is the control connection as the supervisor uses it. *Conn is
// the real one; the tests drive the supervisor through a fake.
type controller interface {
	Command(ctx context.Context, line string) ([]string, error)
	GetInfo(ctx context.Context, key string) (string, error)
	Events() <-chan string
	Done() <-chan struct{}
	Close() error
}

// launcher finds tor and runs it. procLauncher is the real one.
type launcher interface {
	// locate finds the binary and checks its version.
	locate(ctx context.Context) (path string, v Version, err error)
	// start runs tor and returns it with an authenticated control connection
	// that owns the process. A tor that dies on the way comes back as a
	// *startFailure carrying what it printed.
	start(ctx context.Context, path string) (running, error)
}

// running is one tor process.
type running interface {
	ctl() controller
	// exited is closed once tor is gone AND every line it printed is in
	// lines or was dropped, so its last words can be read without a race.
	exited() <-chan struct{}
	lines() <-chan string
	stop()
}

// startFailure is a start that ended before tor was usable, together with what
// tor printed on its way out. tor's own reason - a data directory it may not
// use, a lock another tor holds, a consensus that rejects its protocols - is
// in those lines and nowhere else.
type startFailure struct {
	err   error
	lines []string
}

func (e *startFailure) Error() string { return e.err.Error() }
func (e *startFailure) Unwrap() error { return e.err }

// procLauncher runs the real tor.
type procLauncher struct {
	bin     string
	dataDir string
}

func (l procLauncher) locate(ctx context.Context) (string, Version, error) {
	path, err := Find(l.bin)
	if err != nil {
		return "", Version{}, err
	}
	v, err := ReadVersion(ctx, path)
	if err != nil {
		return path, Version{}, err
	}
	if !v.AtLeast(MinVersion) {
		return path, v, fmt.Errorf("%w: found %s", errTooOld, v)
	}
	return path, v, nil
}

// startArgs is everything tor is told, on the command line rather than in a
// config file, so nothing on the machine can add to it.
//
// The empty file passed as BOTH -f and --defaults-torrc is what keeps the
// system's /etc/tor/torrc out: a distribution package configures SocksPort,
// User and more there, and this tor must be exactly what is written below.
// SocksPort 0 and ClientOnly 1 are the "no other doors" of FR-004: no proxy
// for anyone to use and never a relay. No NonAnonymous anywhere - single onion
// mode makes the server easy to find.
func startArgs(dataDir string, pid int) []string {
	torrc := filepath.Join(dataDir, "torrc")
	return []string{
		"-f", torrc,
		"--defaults-torrc", torrc,
		"--DataDirectory", dataDir,
		"--SocksPort", "0",
		"--ControlPort", "auto",
		"--ControlPortWriteToFile", filepath.Join(dataDir, "control.port"),
		"--CookieAuthentication", "1",
		"--CookieAuthFile", filepath.Join(dataDir, "control_auth_cookie"),
		"--__OwningControllerProcess", strconv.Itoa(pid),
		"--ClientOnly", "1",
		"--SafeLogging", "1",
		"--Log", "notice stdout",
	}
}

func (l procLauncher) start(ctx context.Context, path string) (running, error) {
	// 0700, and enforced rather than requested: tor refuses a data directory
	// others can read, and it holds the control cookie.
	if err := os.MkdirAll(l.dataDir, 0o700); err != nil {
		return nil, fmt.Errorf("create the tor directory: %w", err)
	}
	if err := os.Chmod(l.dataDir, 0o700); err != nil {
		return nil, fmt.Errorf("restrict the tor directory: %w", err)
	}
	if err := os.WriteFile(filepath.Join(l.dataDir, "torrc"), nil, 0o600); err != nil {
		return nil, fmt.Errorf("write the empty torrc: %w", err)
	}
	portFile := filepath.Join(l.dataDir, "control.port")
	cookieFile := filepath.Join(l.dataDir, "control_auth_cookie")
	// Files left by the previous run name a port nobody listens on any more and
	// a cookie nobody accepts. tor writes the port before the cookie, so a stale
	// cookie read beside a fresh port would fail the authentication for nothing.
	for _, f := range []string{portFile, cookieFile} {
		if err := os.Remove(f); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("remove a stale tor file: %w", err)
		}
	}

	cmd := exec.Command(path, startArgs(l.dataDir, os.Getpid())...)
	detach(cmd)
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start tor: %w", err)
	}
	p := &proc{cmd: cmd, exit: make(chan struct{}), out: make(chan string, lineBuffer)}
	scanned := make(chan struct{})
	go func() {
		defer close(scanned)
		defer close(p.out)
		scanner := bufio.NewScanner(pr)
		for scanner.Scan() {
			select {
			case p.out <- scanner.Text():
			default:
				// The supervisor reads these as they come; a burst it cannot
				// keep up with loses log lines, never the process.
			}
		}
		// A line too long for the scanner ends it, and tor must still be able
		// to write: on a full pipe it would block, and Wait below with it.
		_, _ = io.Copy(io.Discard, pr)
	}()
	go func() {
		_ = cmd.Wait()
		_ = pw.Close()
		// Only once every line is in out or dropped: whoever sees tor gone can
		// then read its last words without racing the reader for them.
		<-scanned
		close(p.exit)
	}()

	// Until TAKEOWNERSHIP, hanging up does not stop tor - only its owner's pid
	// going away would - so every failure up to there kills it outright rather
	// than waiting stopWait for an exit that is not coming.
	fail := func(err error) (running, error) {
		p.kill()
		return nil, &startFailure{err: err, lines: p.rest()}
	}
	addr, cookie, err := waitStartup(ctx, portFile, cookieFile, p.exit)
	if err != nil {
		return fail(err)
	}
	conn, err := Dial(ctx, addr)
	if err != nil {
		return fail(err)
	}
	p.conn = conn
	actx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()
	if err := conn.Authenticate(actx, cookie); err != nil {
		return fail(err)
	}
	// From here tor exits the moment this connection closes - including when
	// the server dies and the OS closes it (measured: 2 s, research decision
	// 1). __OwningControllerProcess above is the second net.
	if _, err := conn.Command(actx, "TAKEOWNERSHIP"); err != nil {
		return fail(err)
	}
	return p, nil
}

// waitStartup waits for tor to write the port it picked and the cookie that
// opens it. Both, because tor writes the port first - before it has even
// taken its data directory's lock - and the cookie only after.
func waitStartup(ctx context.Context, portFile, cookieFile string, exited <-chan struct{}) (string, []byte, error) {
	deadline := time.NewTimer(controlPortWait)
	defer deadline.Stop()
	tick := time.NewTicker(100 * time.Millisecond)
	defer tick.Stop()
	for {
		if raw, err := os.ReadFile(portFile); err == nil {
			if line := strings.TrimSpace(string(raw)); strings.HasPrefix(line, "PORT=") {
				if cookie, err := os.ReadFile(cookieFile); err == nil && len(cookie) == cookieSize {
					return strings.TrimPrefix(line, "PORT="), cookie, nil
				}
			}
		}
		select {
		case <-ctx.Done():
			return "", nil, ctx.Err()
		case <-exited:
			return "", nil, errors.New("tor exited before opening its control port")
		case <-deadline.C:
			return "", nil, errors.New("tor did not open its control port in time")
		case <-tick.C:
		}
	}
}

// proc is one running tor.
type proc struct {
	cmd  *exec.Cmd
	conn *Conn
	exit chan struct{}
	out  chan string
}

func (p *proc) ctl() controller         { return p.conn }
func (p *proc) exited() <-chan struct{} { return p.exit }
func (p *proc) lines() <-chan string    { return p.out }

// stop hangs up the control connection - which, after TAKEOWNERSHIP, is tor's
// cue to exit - and kills it only if it has not left in time.
//
// The wait follows no context on purpose: hanging up IS the request to leave,
// tor answers it within a second or two, and cutting the wait short whenever
// the server is shutting down would turn every orderly stop into a kill.
func (p *proc) stop() {
	if p.conn != nil {
		_ = p.conn.Close()
	}
	t := time.NewTimer(stopWait)
	defer t.Stop()
	select {
	case <-p.exit:
		return
	case <-t.C:
	}
	p.kill()
}

// kill ends tor at once and waits until it is gone.
func (p *proc) kill() {
	if p.conn != nil {
		_ = p.conn.Close()
	}
	_ = p.cmd.Process.Kill()
	<-p.exit
}

// rest is every line tor printed that nobody has read. Called once tor is
// gone: out is closed by then, so the range ends.
func (p *proc) rest() []string {
	var lines []string
	for line := range p.out {
		lines = append(lines, line)
	}
	return lines
}

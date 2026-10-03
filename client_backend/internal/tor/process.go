package tor

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
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
	// that owns the process.
	start(ctx context.Context, path string) (running, error)
}

// running is one tor process.
type running interface {
	ctl() controller
	exited() <-chan struct{}
	lines() <-chan string
	stop()
}

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
	// A file left by the previous run names a port nobody listens on any more.
	_ = os.Remove(portFile)

	cmd := exec.Command(path, startArgs(l.dataDir, os.Getpid())...)
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start tor: %w", err)
	}
	p := &proc{cmd: cmd, exit: make(chan struct{}), out: make(chan string, 256)}
	go func() {
		_ = cmd.Wait()
		_ = pw.Close()
		close(p.exit)
	}()
	go func() {
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
	}()

	addr, err := waitControlPort(ctx, portFile, p.exit)
	if err != nil {
		p.kill()
		return nil, err
	}
	conn, err := Dial(ctx, addr)
	if err != nil {
		p.kill()
		return nil, err
	}
	p.conn = conn
	cookie, err := os.ReadFile(filepath.Join(l.dataDir, "control_auth_cookie"))
	if err != nil {
		p.stop()
		return nil, fmt.Errorf("read the control cookie: %w", err)
	}
	actx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()
	if err := conn.Authenticate(actx, cookie); err != nil {
		p.stop()
		return nil, err
	}
	// From here tor exits the moment this connection closes - including when
	// the server dies and the OS closes it (measured: 2 s, research decision
	// 1). __OwningControllerProcess above is the second net.
	if _, err := conn.Command(actx, "TAKEOWNERSHIP"); err != nil {
		p.stop()
		return nil, err
	}
	return p, nil
}

// waitControlPort waits for tor to write the port it picked.
func waitControlPort(ctx context.Context, file string, exited <-chan struct{}) (string, error) {
	deadline := time.NewTimer(controlPortWait)
	defer deadline.Stop()
	tick := time.NewTicker(100 * time.Millisecond)
	defer tick.Stop()
	for {
		if raw, err := os.ReadFile(file); err == nil {
			if line := strings.TrimSpace(string(raw)); strings.HasPrefix(line, "PORT=") {
				return strings.TrimPrefix(line, "PORT="), nil
			}
		}
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-exited:
			return "", errors.New("tor exited before opening its control port")
		case <-deadline.C:
			return "", errors.New("tor did not open its control port in time")
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
func (p *proc) stop() {
	if p.conn != nil {
		_ = p.conn.Close()
	}
	select {
	case <-p.exit:
		return
	case <-time.After(stopWait):
	}
	p.kill()
}

func (p *proc) kill() {
	_ = p.cmd.Process.Kill()
	<-p.exit
}

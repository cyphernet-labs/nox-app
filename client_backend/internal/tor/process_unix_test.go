//go:build unix

package tor

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"
)

// A Ctrl+C meant for the server goes to the terminal's foreground process
// group; tor must not be in it, or it leaves while the server still drains.
func TestTorRunsInAProcessGroupOfItsOwn(t *testing.T) {
	cmd := exec.Command("/bin/sh", "-c", "sleep 30")
	detach(cmd)
	if err := cmd.Start(); err != nil {
		t.Fatalf("start: %v", err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	})
	pgid, err := syscall.Getpgid(cmd.Process.Pid)
	if err != nil {
		t.Fatalf("Getpgid: %v", err)
	}
	if pgid != cmd.Process.Pid || pgid == syscall.Getpgrp() {
		t.Fatalf("process group %d (own pid %d, the server's group %d): a signal meant for the server reaches tor",
			pgid, cmd.Process.Pid, syscall.Getpgrp())
	}
}

// fakeTorScript writes a shell script that stands in for tor.
func fakeTorScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "tor")
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body), 0o755); err != nil {
		t.Fatalf("write the fake tor: %v", err)
	}
	return path
}

// A real process that dies while starting: what it printed comes back with
// the failure, and the files a previous run left were gone before it began -
// read beside a fresh port, an old cookie fails the authentication.
func TestARealTorThatDiesAtStartHandsBackWhatItPrinted(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "nox.db-tor")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	stale := map[string][]byte{"control.port": []byte("PORT=127.0.0.1:1\n"), "control_auth_cookie": make([]byte, cookieSize)}
	for name, content := range stale {
		if err := os.WriteFile(filepath.Join(dataDir, name), content, 0o600); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
	script := fakeTorScript(t, "echo 'Oct 03 11:13:50.000 [err] Could not bind to 127.0.0.1:0: Permission denied'\nexit 1\n")

	_, err := procLauncher{dataDir: dataDir}.start(t.Context(), script)
	failed, ok := errors.AsType[*startFailure](err)
	if !ok {
		t.Fatalf("start err = %v, want a startFailure", err)
	}
	if !slices.ContainsFunc(failed.lines, func(l string) bool { return strings.Contains(l, "Could not bind") }) {
		t.Fatalf("tor's last words were lost: %q", failed.lines)
	}
	for name := range stale {
		if _, err := os.Stat(filepath.Join(dataDir, name)); !errors.Is(err, fs.ErrNotExist) {
			t.Errorf("the stale %s survived the start (err=%v)", name, err)
		}
	}
}

// Until TAKEOWNERSHIP, hanging up does not make tor leave. A start that fails
// before it - here the cookie is turned down - kills tor at once instead of
// waiting stopWait for an exit that is not coming.
func TestAStartThatFailsBeforeOwnershipKillsTorAtOnce(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer func() { _ = conn.Close() }()
		if _, err := bufio.NewReader(conn).ReadString('\n'); err != nil {
			return
		}
		_, _ = conn.Write([]byte("515 Authentication failed: Wrong length on authentication cookie.\r\n"))
	}()

	dataDir := filepath.Join(t.TempDir(), "nox.db-tor")
	// The startup files written the way tor writes them, then a process that
	// does not leave when its controller hangs up - as tor before ownership.
	script := fakeTorScript(t, fmt.Sprintf("head -c 32 /dev/zero > %q\necho 'PORT=%s' > %q\nexec sleep 60\n",
		filepath.Join(dataDir, "control_auth_cookie"), ln.Addr().String(), filepath.Join(dataDir, "control.port")))

	began := time.Now()
	if _, err := (procLauncher{dataDir: dataDir}).start(t.Context(), script); err == nil {
		t.Fatal("start succeeded against a port that refuses the cookie")
	}
	if took := time.Since(began); took > stopWait/2 {
		t.Fatalf("start took %v to give up: it waited for an exit only ownership would bring", took)
	}
}

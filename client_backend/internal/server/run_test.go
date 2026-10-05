package server

import (
	"bytes"
	"context"
	"crypto/tls"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"nox.app/client-backend/internal/config"
)

// These tests drive Run itself rather than the harness: what 039 changed is
// the wiring - which goroutines start, on which contexts, in which order they
// stop - and the harness copies Run's steps by hand.

func freeAddr(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := ln.Addr().String()
	_ = ln.Close()
	return addr
}

type syncLog struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *syncLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *syncLog) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// runServer starts Run and returns a function that stops it and reports how.
func runServer(t *testing.T, cfg config.Config) (*syncLog, func() error) {
	t.Helper()
	logs := &syncLog{}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Run(ctx, cfg, os.DirFS("../../migrations"), slog.New(slog.NewTextHandler(logs, nil)))
	}()
	// Run's wiring is the subject here, not the pin - that has its own tests -
	// so this client does not check the certificate.
	client := &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS13}, //nolint:gosec // see above
	}}
	eventually(t, "/health answers", func() bool {
		resp, err := client.Get("https://" + cfg.Addr + "/health")
		if err != nil {
			return false
		}
		_ = resp.Body.Close()
		return resp.StatusCode == http.StatusOK
	})
	return logs, func() error {
		cancel()
		select {
		case err := <-done:
			return err
		case <-time.After(45 * time.Second):
			t.Fatal("Run did not stop")
			return nil
		}
	}
}

func testRunConfig(t *testing.T) config.Config {
	t.Helper()
	dir := t.TempDir()
	db := filepath.Join(dir, "run.db")
	return config.Config{
		Addr:      freeAddr(t),
		DBPath:    db,
		FilesPath: db + "-files",
		Limits:    config.DefaultLimits(),
		TorDir:    db + "-tor",
	}
}

func TestRunWithTorOffServesTheDirectPathAndStopsCleanly(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.Tor = false
	_, stop := runServer(t, cfg)
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	if _, err := os.Stat(cfg.TorDir); !os.IsNotExist(err) {
		t.Fatalf("Tor off, yet its directory exists (err=%v)", err)
	}
}

// FR-007 end to end: Tor on, tor nowhere to be found - the messenger still
// serves, says why in the log, and stops cleanly.
// A stop that lands before the dispatcher's first read of the cursor is a
// stop. The read fails because of the cancel, and that failure used to come
// back out of Run as an error - an intermittent one, whenever shutdown beat
// the dispatcher's first query.
func TestDispatcherStoppedBeforeItsFirstReadStopsCleanly(t *testing.T) {
	_, srv := newTestServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if err := srv.runDispatcher(ctx); err != nil {
		t.Fatalf("runDispatcher on a cancelled context returned %v, want a clean stop", err)
	}
}

func TestRunWithTorMissingStillServesTheDirectPath(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.Tor = true
	cfg.TorBin = filepath.Join(t.TempDir(), "no-tor-here")
	logs, stop := runServer(t, cfg)
	eventually(t, "the reason logged", func() bool { return strings.Contains(logs.String(), "tor not found") })
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	if strings.Contains(logs.String(), ".onion") {
		t.Fatal("an onion address reached the log")
	}
}

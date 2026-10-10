package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
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
//
// Ready means both doors answer: /health on the service page's listener, and
// on the main port a channel that proves the key the startup line printed - a
// device dialling with that key as the only acceptable answer gets in.
func runServer(t *testing.T, cfg config.Config) (*syncLog, func() error) {
	t.Helper()
	logs := &syncLog{}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Run(ctx, cfg, os.DirFS("../../migrations"), slog.New(slog.NewTextHandler(logs, nil)))
	}()
	client := &http.Client{Timeout: 2 * time.Second}
	eventually(t, "/health answers on the service page's listener", func() bool {
		resp, err := client.Get("http://" + cfg.StatusAddr + "/health")
		if err != nil {
			return false
		}
		_ = resp.Body.Close()
		return resp.StatusCode == http.StatusOK
	})
	var key ed25519.PublicKey
	eventually(t, "the startup line names the server key", func() bool {
		raw, err := base64.StdEncoding.DecodeString(loggedServerKey(logs.String()))
		key = raw
		return err == nil && len(raw) == ed25519.PublicKeySize
	})
	_, device, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate a device key: %v", err)
	}
	eventually(t, "the main port opens a channel proving that key", func() bool {
		dctx, dcancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer dcancel()
		conn, err := dialChannel(dctx, cfg.Addr, key, device)
		if err != nil {
			return false
		}
		_ = conn.Close()
		return true
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

// loggedServerKey digs the server key out of the startup line. The text
// handler quotes a value holding '=', which base64 padding does.
func loggedServerKey(logs string) string {
	m := regexp.MustCompile(`server_key="?([A-Za-z0-9+/=]+)`).FindStringSubmatch(logs)
	if m == nil {
		return ""
	}
	return m[1]
}

func testRunConfig(t *testing.T) config.Config {
	t.Helper()
	path := filepath.Join(t.TempDir(), "run.db")
	return config.Config{
		Addr:       freeAddr(t),
		DBPath:     path,
		FilesPath:  path + "-files",
		StatusAddr: freeAddr(t),
		Limits:     config.DefaultLimits(),
		TorDir:     path + "-tor",
	}
}

// The startup line names the machine's PUBLIC key - what an operator compares
// with the key in a link - and never the private one. The key in the log is
// the one the store holds, the one every channel proves.
func TestTheStartupLineNamesTheServerKeyAndNothingSecret(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.Tor = false
	logs, stop := runServer(t, cfg)
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}

	dbs, err := db.Open(cfg.DBPath)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	defer func() { _ = dbs.Close() }()
	var pub, seed string
	if err := dbs.Read.QueryRow("SELECT public_key, private_key FROM server_identity WHERE id = 1").Scan(&pub, &seed); err != nil {
		t.Fatalf("read the key: %v", err)
	}
	out := logs.String()
	if got := loggedServerKey(out); got != pub {
		t.Fatalf("the startup line names %q, want the stored key %s:\n%s", got, pub, out)
	}
	if strings.Contains(out, seed) {
		t.Fatal("the private key reached the log")
	}
	if strings.Contains(out, "fingerprint") {
		t.Fatal("the startup line still speaks of a fingerprint")
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

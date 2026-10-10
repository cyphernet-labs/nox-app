package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
)

// These tests drive Run itself rather than the harness: what they hold is the
// wiring - which goroutines start, what lands before the listeners open, in
// which order everything stops - and the harness copies Run's steps by hand.

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
	}
}

// The startup line names the machine's PUBLIC key - what an operator compares
// with the key in a link - and never the private one. The key in the log is
// the one the store holds, the one every channel proves.
func TestTheStartupLineNamesTheServerKeyAndNothingSecret(t *testing.T) {
	cfg := testRunConfig(t)
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

// SC-005: the server never starts tor (045). Not "with tor turned off" - there
// is no switch any more: a tor waiting on the PATH, where the server of 039
// went looking for one, is never run, and no state directory appears beside
// the database.
func TestRunStartsNoTorEvenWithOneOnThePath(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the stand-in tor is a shell script")
	}
	bin := t.TempDir()
	marker := filepath.Join(t.TempDir(), "tor-ran")
	script := "#!/bin/sh\necho ran > '" + marker + "'\nexec sleep 60\n"
	if err := os.WriteFile(filepath.Join(bin, "tor"), []byte(script), 0o755); err != nil { //nolint:gosec // an executable on purpose
		t.Fatalf("write the stand-in tor: %v", err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	cfg := testRunConfig(t)
	cfg.OnionAddr = testOnionAddr
	_, stop := runServer(t, cfg)
	// Long enough for a supervisor to have looked for its binary and started
	// it; the server of 039 did both before the main port opened.
	time.Sleep(200 * time.Millisecond)
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("the server ran the tor on its PATH (marker err=%v)", err)
	}
	if _, err := os.Stat(cfg.DBPath + "-tor"); !os.IsNotExist(err) {
		t.Fatalf("a tor state directory appeared beside the database (err=%v)", err)
	}
}

// A unit file written for the server of 039 still says -tor=false. The start
// fails before Run is ever called, and says where tor went - main hands Run
// only what config.Load accepted.
func TestTheOldTorFlagStopsTheStartWithAHint(t *testing.T) {
	_, err := config.Load([]string{"-tor=false", "-addr", "0.0.0.0:8443"}, func(string) string { return "" })
	if err == nil || !strings.Contains(err.Error(), "separate service") {
		t.Fatalf("config.Load(-tor=false) = %v, want the separate-service hint", err)
	}
}

// The address parameters end to end (045): a good one lands in the database
// before anything listens - the first link the page shows already names it -
// and a bad one leaves the server running with a warning on the page. Neither
// the onion address nor a link that carries it reaches the log (FR-022): the
// startup line says where the link for a first device is, never what it is
// (046, FR-005).
func TestStartParametersLandBeforeTheLinkAndNeverInTheLog(t *testing.T) {
	cfg := testRunConfig(t)
	cfg.OnionAddr = testOnionAddr + ":443"
	cfg.PublicAddr = "nox.example.org" // no port: refused
	logs, stop := runServer(t, cfg)

	resp, err := (&http.Client{Timeout: 2 * time.Second}).Get("http://" + cfg.StatusAddr + "/")
	if err != nil {
		t.Fatalf("GET the service page: %v", err)
	}
	page, err := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if err != nil {
		t.Fatalf("read the service page: %v", err)
	}
	if err := stop(); err != nil {
		t.Fatalf("Run returned %v", err)
	}

	if !strings.Contains(string(page), "-public-addr is not a valid address. The server keeps no public address.") {
		t.Fatalf("the page does not warn about the refused parameter: %s", page)
	}
	out := logs.String()
	name := strings.TrimSuffix(testOnionAddr, ".onion")
	if strings.Contains(strings.ToLower(out), name) {
		t.Fatalf("the onion address reached the log:\n%s", out)
	}
	if !strings.Contains(out, "-public-addr") || !strings.Contains(out, "start parameter not applied") {
		t.Fatalf("the refused parameter is not named in the log:\n%s", out)
	}
	// The link is on the page, not in the log - not even masked, since no line
	// is ever handed one - and the page's first link names the onion service
	// already.
	if strings.Contains(out, "nox://pair/") || strings.Contains(out, "[link]") {
		t.Fatalf("a link reached the startup log:\n%s", out)
	}
	if !strings.Contains(out, "no device can reach this server yet") {
		t.Fatalf("the startup log does not say where the link for a first device is:\n%s", out)
	}
	if got := readLink(t, linkOf(t, string(page))); got.Onion == nil {
		t.Fatalf("the page's first link names no onion service: %+v", got)
	}

	dbs, err := db.Open(cfg.DBPath)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	defer func() { _ = dbs.Close() }()
	var onion, onionParam string
	var public, publicParam *string
	if err := dbs.Read.QueryRow(
		"SELECT onion_address, onion_address_param, public_address, public_address_param FROM server_identity WHERE id = 1").
		Scan(&onion, &onionParam, &public, &publicParam); err != nil {
		t.Fatalf("read the addresses: %v", err)
	}
	if onion != testOnionAddr || onionParam != testOnionAddr+":443" {
		t.Fatalf("onion = %q (param %q), want the address without its port and the parameter as given", onion, onionParam)
	}
	if public != nil || publicParam != nil {
		t.Fatalf("the refused parameter left public=%v param=%v, want nothing", public, publicParam)
	}
}

package server

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/db"
	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/store"
)

// newTestServer builds the full stack over a temp database and returns the
// running httptest server plus the Server for direct inspection.
func newTestServer(t *testing.T) (*httptest.Server, *Server) {
	t.Helper()
	ts, srv, closeAll := openStack(t, filepath.Join(t.TempDir(), "test.db"))
	t.Cleanup(closeAll)
	return ts, srv
}

// openStack assembles db + hub + server over the given database file and
// returns an explicit close function, so lifecycle tests can stop and restart
// the whole stack against the same file.
func openStack(t *testing.T, path string) (*httptest.Server, *Server, func()) {
	t.Helper()

	dbs, err := db.Open(path)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	if _, err := db.Migrate(context.Background(), dbs.Write, os.DirFS("../../migrations")); err != nil {
		_ = dbs.Close()
		t.Fatalf("db.Migrate: %v", err)
	}

	h := hub.New()
	hubCtx, stopHub := context.WithCancel(context.Background())
	hubDone := make(chan struct{})
	go func() {
		defer close(hubDone)
		h.Run(hubCtx)
	}()

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg := config.Config{Addr: "127.0.0.1:0", DBPath: path, Limits: config.DefaultLimits()}
	srv := New(cfg, store.New(dbs.Read, dbs.Write), h, logger)
	srv.pingInterval = 50 * time.Millisecond

	ts := httptest.NewServer(srv.Handler())
	ts.Config.RegisterOnShutdown(srv.CloseConnections)
	closeAll := func() {
		ts.Close()
		stopHub()
		<-hubDone
		_ = dbs.Close()
	}
	return ts, srv, closeAll
}

func TestHealthServes200(t *testing.T) {
	ts, _ := newTestServer(t)

	resp, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatalf("GET /health: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	if string(body) != `{"status":"ok"}` {
		t.Fatalf("body = %s", body)
	}
}

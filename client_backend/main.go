// Command noxd is the NOX client server: a self-hosted messenger backend for
// a small circle, speaking wire contract v0 over one WebSocket command
// channel plus a small REST surface, backed by embedded SQLite.
package main

import (
	"context"
	"embed"
	"io/fs"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/server"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	cfg, err := config.Load(os.Args[1:], os.Getenv)
	if err != nil {
		logger.Error("configuration", "err", err)
		os.Exit(2)
	}

	migrations, err := fs.Sub(migrationsFS, "migrations")
	if err != nil {
		logger.Error("migrations fs", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := server.Run(ctx, cfg, migrations, logger); err != nil {
		logger.Error("server stopped with error", "err", err)
		os.Exit(1)
	}
	logger.Info("server stopped")
}

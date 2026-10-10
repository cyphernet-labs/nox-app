// Command noxd is the NOX client server: a self-hosted messenger backend for
// ONE person and the devices they own, speaking wire contract v0 over one
// WebSocket command channel plus a small REST surface, backed by embedded
// SQLite.
package main

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/server"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func main() {
	// The commands that talk to a server already running on this machine (046,
	// 047), and the one that needs none (restore). Each exits on its own.
	if len(os.Args) > 1 {
		if command, ok := commands[os.Args[1]]; ok {
			os.Exit(command(os.Args[2:]))
		}
	}

	// Scrubbed from the very first line: a configuration error can quote the
	// onion address it was given (FR-022).
	logger := slog.New(server.ScrubLogs(slog.NewJSONHandler(os.Stderr, nil)))

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

// link is `noxd link` (046): it asks the server running on this machine for a
// new machine link and prints it with its deadline - and, with -qr, as a code
// to scan - for a machine with no screen to open the service page on. The link
// it replaces stops working.
//
// It never opens the database: only the running server does (invariant 1), so
// the link comes from it, over the service page's loopback listener. And it is
// printed here and nowhere else - the server's log never carries a link.
func link(args []string) int {
	cfg, err := config.LoadLink(args, os.Getenv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd link:", err)
		return 2
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	got, err := server.RequestMachineLink(ctx, cfg.StatusAddr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd link:", err)
		return 1
	}
	if cfg.QR {
		if server.LinkReachesOnlyThisMachine(got.Link) {
			fmt.Fprintln(os.Stderr, "This server is reachable from this machine only, so there is no code for a phone to scan - "+
				"the link below works in the NOX app running here. To pair a phone, start the server with -addr set to an "+
				"address on your network, or give it a public or onion address.")
		} else {
			code, err := server.QRText(got.Link)
			if err != nil {
				fmt.Fprintln(os.Stderr, "noxd link:", err)
				return 1
			}
			fmt.Print(code)
		}
	}
	fmt.Println(got.Link)
	fmt.Println(server.ExpiresIn(got.ExpiresAt, time.Now().Unix()))
	return 0
}

//go:build windows

package main

import (
	"context"
	"io/fs"
	"log/slog"
	"path/filepath"
	"time"

	"golang.org/x/sys/windows/svc"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/server"
)

// serviceName is the name deploy/install-windows.ps1 registers the server
// under. The manager starts a service by it; for a service that is the only
// one in its process the name is not checked, so it only has to be the same in
// spirit.
const serviceName = "noxd"

// stopWaitHint is how long the manager is told a stop may take: the main
// server's and the service page's deadlines and the drain of the connections,
// which over Tor can take most of fifteen seconds.
const stopWaitHint = 30 * time.Second

// underServiceManager says whether the Windows service control manager started
// this process (049). Such a process has no console and no Ctrl+C: it logs to
// a file and stops when the manager says so.
func underServiceManager() bool {
	ok, err := svc.IsWindowsService()
	return err == nil && ok
}

// runService runs the server as the Windows service until the manager stops it
// or the server stops by itself, and returns the process's exit code. The log
// goes to noxd.log beside the database.
func runService(cfg config.Config, migrations fs.FS) int {
	logFile, err := openServiceLog(filepath.Dir(cfg.DBPath), serviceLogKeepBytes)
	if err != nil {
		// Nowhere to say it: the manager records the exit code.
		return 1
	}
	defer func() { _ = logFile.Close() }()
	logger := slog.New(slog.NewJSONHandler(logFile, nil))

	h := &service{
		logger: logger,
		run: func(ctx context.Context) error {
			return server.Run(ctx, cfg, migrations, logger)
		},
	}
	if err := svc.Run(serviceName, h); err != nil {
		logger.Error("service control manager", "err", err)
		return 1
	}
	if h.failed {
		return 1
	}
	return 0
}

// service is the server as a Windows service.
type service struct {
	logger *slog.Logger
	run    func(ctx context.Context) error
	// failed is set when the server stopped with an error; read after
	// svc.Run returns, on the same goroutine that set it.
	failed bool
}

// Execute runs the server and answers the manager. It reports Running at
// once - the server is up as soon as its service page listens, locked or
// not - and on Stop or Shutdown cancels the server and waits for its ordered
// shutdown.
func (s *service) Execute(_ []string, requests <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- s.run(ctx) }()

	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case err := <-done:
			return s.stopped(err)
		case req := <-requests:
			switch req.Cmd {
			case svc.Interrogate:
				status <- req.CurrentStatus
			case svc.Stop, svc.Shutdown:
				status <- svc.Status{State: svc.StopPending, WaitHint: uint32(stopWaitHint / time.Millisecond)}
				cancel()
				return s.stopped(<-done)
			}
		}
	}
}

// stopped records how the server ended and turns it into the service's exit.
func (s *service) stopped(err error) (bool, uint32) {
	if err != nil {
		s.logger.Error("server stopped with error", "err", err)
		s.failed = true
		return true, 1
	}
	s.logger.Info("server stopped")
	return false, 0
}

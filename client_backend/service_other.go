//go:build !windows

package main

import (
	"io/fs"

	"nox.app/client-backend/internal/config"
)

// underServiceManager is false outside Windows: launchd and systemd start the
// server as the plain program it is, with standard error as its log.
func underServiceManager() bool {
	return false
}

// runService is never reached outside Windows.
func runService(config.Config, fs.FS) int {
	return 1
}

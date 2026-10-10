package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// serviceLogName is the log of a server the Windows service control manager
// started (049). Such a process has no console, so what it would write to
// standard error goes to this file, beside the database: the one folder the
// service's account may write.
const serviceLogName = "noxd.log"

// serviceLogKeepBytes is the size at which the log is set aside at a start,
// as noxd.log.1, replacing the one set aside before. One person's server
// writes well under a megabyte a day; this keeps weeks of it and caps the
// disk it takes.
const serviceLogKeepBytes = 16 << 20

// openServiceLog opens the service's log in dir for appending, first setting
// the current one aside if it reached keepBytes.
func openServiceLog(dir string, keepBytes int64) (*os.File, error) {
	path := filepath.Join(dir, serviceLogName)
	info, err := os.Stat(path)
	switch {
	case err == nil && info.Size() >= keepBytes:
		if err := os.Rename(path, path+".1"); err != nil {
			return nil, fmt.Errorf("set the log aside: %w", err)
		}
	case err != nil && !errors.Is(err, os.ErrNotExist):
		return nil, fmt.Errorf("look at the log: %w", err)
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open the log: %w", err)
	}
	return f, nil
}

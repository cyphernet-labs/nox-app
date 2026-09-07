// Package config resolves server configuration from flags with NOX_* env
// fallbacks and validates it at startup.
package config

import (
	"flag"
	"fmt"
	"net"
)

// Limits are the server-declared bounds announced in the session.hello reply
// (contract v0 §3). Values follow the contract example; clients must check
// them before sending.
type Limits struct {
	MaxMessageBytes    int64 `json:"max_message_bytes"`
	MaxAttachmentBytes int64 `json:"max_attachment_bytes"`
	MaxFrameBytes      int64 `json:"max_frame_bytes"`
}

// Config is the validated process configuration.
type Config struct {
	Addr      string
	DBPath    string
	FilesPath string
	// StatusAddr is where the service page listens, or empty for no page at
	// all. Always a loopback address: the page shows the claim link, and a
	// claim link reachable over the network hands ownership to everyone on
	// that network. The restriction lives on the SOCKET rather than in a
	// handler, because a check inside the process is a check somebody
	// eventually routes around with a header.
	StatusAddr string
	Limits     Limits
}

// DefaultLimits mirrors the contract v0 §3 example values.
func DefaultLimits() Limits {
	return Limits{
		MaxMessageBytes:    65536,
		MaxAttachmentBytes: 104857600,
		MaxFrameBytes:      131072,
	}
}

// Load parses args (without the program name) into a Config. Flag values win
// over NOX_ADDR / NOX_DB / NOX_FILES environment variables, which win over
// defaults. The files directory defaults to "<db>-files" next to the
// database so backup and relocation stay a two-neighbor affair.
func Load(args []string, getenv func(string) string) (Config, error) {
	defAddr := getenv("NOX_ADDR")
	if defAddr == "" {
		defAddr = "127.0.0.1:8080"
	}
	defDB := getenv("NOX_DB")
	if defDB == "" {
		defDB = "nox.db"
	}
	defFiles := getenv("NOX_FILES")
	defStatus := getenv("NOX_STATUS_ADDR")
	if defStatus == "" {
		defStatus = "127.0.0.1:8081"
	}

	fs := flag.NewFlagSet("noxd", flag.ContinueOnError)
	addr := fs.String("addr", defAddr, "listen address (host:port)")
	dbPath := fs.String("db", defDB, "path to the SQLite database file")
	filesPath := fs.String("files", defFiles, "attachment bytes directory (default <db>-files)")
	statusAddr := fs.String("status-addr", defStatus, "loopback address for the service page, empty to disable it")
	if err := fs.Parse(args); err != nil {
		return Config{}, fmt.Errorf("parse flags: %w", err)
	}

	if _, _, err := net.SplitHostPort(*addr); err != nil {
		return Config{}, fmt.Errorf("invalid -addr %q: %w", *addr, err)
	}
	if err := checkStatusAddr(*statusAddr); err != nil {
		return Config{}, err
	}
	if *dbPath == "" {
		return Config{}, fmt.Errorf("-db must not be empty")
	}
	files := *filesPath
	if files == "" {
		files = *dbPath + "-files"
	}

	return Config{Addr: *addr, DBPath: *dbPath, FilesPath: files, StatusAddr: *statusAddr, Limits: DefaultLimits()}, nil
}

// checkStatusAddr refuses anything the service page must not listen on.
//
// Empty is allowed and means no page. Everything else has to resolve to a
// loopback address: the flag exists to move the port, not to put the page on a
// network, and somebody who writes 0.0.0.0 there has to learn it now rather
// than when a stranger claims their server. A name is resolved rather than
// pattern-matched, so "localhost" passes and a name that quietly points
// somewhere else does not.
func checkStatusAddr(addr string) error {
	if addr == "" {
		return nil
	}
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("invalid -status-addr %q: %w", addr, err)
	}
	if host == "" {
		return fmt.Errorf("invalid -status-addr %q: the service page must be bound to loopback, not to every interface", addr)
	}
	ips, err := net.LookupIP(host)
	if err != nil {
		return fmt.Errorf("invalid -status-addr %q: %w", addr, err)
	}
	for _, ip := range ips {
		if !ip.IsLoopback() {
			return fmt.Errorf("invalid -status-addr %q: the service page must be bound to loopback, and %s is not", addr, ip)
		}
	}
	// LookupIP returns an error rather than an empty answer, so there is no
	// "resolved to nothing" case to handle here.
	//
	// This check catches the mistake at the moment it is made. It is NOT the
	// guarantee: a name can resolve differently between here and the bind, so
	// the address the listener actually got is checked again once it has it.
	return nil
}

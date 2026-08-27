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
	Addr   string
	DBPath string
	Limits Limits
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
// over NOX_ADDR / NOX_DB environment variables, which win over defaults.
func Load(args []string, getenv func(string) string) (Config, error) {
	defAddr := getenv("NOX_ADDR")
	if defAddr == "" {
		defAddr = "127.0.0.1:8080"
	}
	defDB := getenv("NOX_DB")
	if defDB == "" {
		defDB = "nox.db"
	}

	fs := flag.NewFlagSet("noxd", flag.ContinueOnError)
	addr := fs.String("addr", defAddr, "listen address (host:port)")
	dbPath := fs.String("db", defDB, "path to the SQLite database file")
	if err := fs.Parse(args); err != nil {
		return Config{}, fmt.Errorf("parse flags: %w", err)
	}

	if _, _, err := net.SplitHostPort(*addr); err != nil {
		return Config{}, fmt.Errorf("invalid -addr %q: %w", *addr, err)
	}
	if *dbPath == "" {
		return Config{}, fmt.Errorf("-db must not be empty")
	}

	return Config{Addr: *addr, DBPath: *dbPath, Limits: DefaultLimits()}, nil
}

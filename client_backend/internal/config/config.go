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

	// Tor turns the onion service on (039). On by default: the server keeps
	// Tor up for as long as it runs, because a stationary machine has no
	// battery to save and, without a published address, a phone away from
	// home cannot reach it at all. false removes tor entirely - no process, no
	// onion address, nothing announced - while the onion key and the devices'
	// access keys stay in the database, so turning it back on brings back the
	// same address.
	Tor bool
	// TorBin is an explicit path to the tor binary, or empty. When set it is
	// FINAL: a path that holds no tor means "not found", never a reason to look
	// somewhere else - an explicit choice silently replaced by another tor is
	// worse than a refusal, and "tor not found" would be impossible to test on
	// a machine that has one in PATH.
	TorBin string
	// TorDir is tor's own state directory: its cache of the network and the
	// control-port cookie. A cache, outside backups; never the database.
	TorDir string
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
	// Anything but an explicit "false" or "0" leaves Tor on: the variable can
	// turn it off, and a typo in it must not do so silently in the other
	// direction either - it is parsed below with the flag's own rules.
	defTor := true
	if v := getenv("NOX_TOR"); v != "" {
		parsed, err := parseBool(v)
		if err != nil {
			return Config{}, fmt.Errorf("invalid NOX_TOR %q: %w", v, err)
		}
		defTor = parsed
	}

	fs := flag.NewFlagSet("noxd", flag.ContinueOnError)
	addr := fs.String("addr", defAddr, "listen address (host:port)")
	dbPath := fs.String("db", defDB, "path to the SQLite database file")
	filesPath := fs.String("files", defFiles, "attachment bytes directory (default <db>-files)")
	statusAddr := fs.String("status-addr", defStatus, "loopback address for the service page, empty to disable it")
	torOn := fs.Bool("tor", defTor, "publish an onion service through tor (false: no tor at all)")
	torBin := fs.String("tor-bin", getenv("NOX_TOR_BIN"), "path to the tor binary; when set it is final (default: next to noxd, then PATH)")
	torDir := fs.String("tor-dir", getenv("NOX_TOR_DIR"), "tor state directory (default <db>-tor)")
	if err := fs.Parse(args); err != nil {
		return Config{}, fmt.Errorf("parse flags: %w", err)
	}
	// Nothing here takes a positional argument, so one is always a mistake -
	// and the likeliest is "-tor false": a boolean flag does not consume the
	// word after it, so tor would stay ON and parsing would stop there,
	// dropping every flag after it and opening a fresh database in the
	// working directory.
	if fs.NArg() > 0 {
		return Config{}, fmt.Errorf("unexpected argument %q (a boolean flag is written -tor=false)", fs.Arg(0))
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
	dir := *torDir
	if dir == "" {
		dir = *dbPath + "-tor"
	}

	return Config{
		Addr:       *addr,
		DBPath:     *dbPath,
		FilesPath:  files,
		StatusAddr: *statusAddr,
		Limits:     DefaultLimits(),
		Tor:        *torOn,
		TorBin:     *torBin,
		TorDir:     dir,
	}, nil
}

// parseBool reads NOX_TOR with the same words the -tor flag accepts, so the
// two spellings of one setting cannot disagree about what "off" looks like.
func parseBool(v string) (bool, error) {
	switch v {
	case "1", "t", "T", "TRUE", "true", "True":
		return true, nil
	case "0", "f", "F", "FALSE", "false", "False":
		return false, nil
	}
	return false, fmt.Errorf("want true or false")
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

// Package config resolves server configuration from flags with NOX_* env
// fallbacks and validates it at startup.
package config

import (
	"errors"
	"flag"
	"fmt"
	"net"
	"strings"
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
	// StatusAddr is where the service page and /health listen. Always a
	// loopback address: the page hands out the machine link, and a machine
	// link reachable over the network would let anybody on that network pair
	// a device. The restriction lives on the SOCKET rather than in a handler,
	// because a check inside the process is a check somebody eventually
	// routes around with a header. `noxd link` asks the running server through
	// the same listener, and so do `noxd unlock` and `noxd password` (047) -
	// which is why it can no longer be empty: the password that opens the
	// server's data is entered there, and nowhere else.
	StatusAddr string
	Limits     Limits

	// PublicAddr and OnionAddr are the start parameters of the two addresses
	// this machine stores (045): the public host:port and the onion address
	// the separate tor service publishes for it. Raw and unchecked on purpose.
	// A malformed one must not stop the server - a machine that rebooted with
	// nobody at it would otherwise stop every conversation over a typo - so
	// the server validates it when it applies it, keeps the stored address on
	// a refusal and says so in the log and on the service page. Empty means
	// "not given", which changes nothing: an address is deleted only on the
	// service page.
	PublicAddr string
	OnionAddr  string
}

// KeyPath is where the database's data key lies, sealed by the owner's
// password (047): beside the database, named after it. Derived rather than
// configured - the two belong together, and a key file sent elsewhere by a
// flag is a key file a backup or a move eventually leaves behind.
func (c Config) KeyPath() string {
	return c.DBPath + ".key"
}

// errNoServicePage refuses a server with no service page (047): the password
// that opens its data could not be entered anywhere.
var errNoServicePage = errors.New("-status-addr must not be empty: the password that opens this server's data is " +
	"entered on its service page or with noxd unlock, and both use that address")

// DefaultLimits mirrors the contract v0 §3 example values.
func DefaultLimits() Limits {
	return Limits{
		MaxMessageBytes:    65536,
		MaxAttachmentBytes: 104857600,
		MaxFrameBytes:      131072,
	}
}

// errTorIsAService answers every flag the server's own tor once had (039).
//
// They fail rather than being ignored: a unit file still saying -tor=false was
// written by somebody who expects this server to run tor, and silently
// accepting it would leave them believing it does. tor is a separate service
// since 045, and the only thing the server takes from it is the address.
var errTorIsAService = errors.New("tor runs as a separate service now: point its onion service at this server's port " +
	"and give the address with -onion-addr (or set it on the service page)")

// removedTorFlags are the flags 039 added and 045 removed.
var removedTorFlags = []string{"tor", "tor-bin", "tor-dir"}

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
	addr := fs.String("addr", defAddr, "listen address (host:port); tor's onion service points here too")
	dbPath := fs.String("db", defDB, "path to the SQLite database file")
	filesPath := fs.String("files", defFiles, "attachment bytes directory (default <db>-files)")
	statusAddr := fs.String("status-addr", defStatus, "loopback address for the service page, /health and the noxd commands")
	publicAddr := fs.String("public-addr", getenv("NOX_PUBLIC_ADDR"),
		"public address (host:port) written to the database when it first appears or changes")
	onionAddr := fs.String("onion-addr", getenv("NOX_ONION_ADDR"),
		"onion address (<56 characters>.onion) written to the database when it first appears or changes")
	// Boolean-shaped, so a removed flag fails at its own name whatever follows
	// it: "-tor false", "-tor=false" and "-tor-bin /usr/bin/tor" all stop here
	// with the hint, instead of a value-taking flag swallowing the next word.
	for _, name := range removedTorFlags {
		fs.BoolFunc(name, "removed: tor runs as a separate service (see -onion-addr)", func(string) error {
			return errTorIsAService
		})
	}
	if err := fs.Parse(args); err != nil {
		return Config{}, fmt.Errorf("parse flags: %w", err)
	}
	// Nothing here takes a positional argument, so one is always a mistake -
	// and an expensive one: parsing stops at it, every flag after it is dropped,
	// and a fresh database opens in the working directory.
	if fs.NArg() > 0 {
		return Config{}, fmt.Errorf("unexpected argument %q (every flag takes its value as -name value or -name=value)", fs.Arg(0))
	}

	if _, _, err := net.SplitHostPort(*addr); err != nil {
		return Config{}, fmt.Errorf("invalid -addr %q: %w", *addr, err)
	}
	if *statusAddr == "" {
		return Config{}, errNoServicePage
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

	return Config{
		Addr:       *addr,
		DBPath:     *dbPath,
		FilesPath:  files,
		StatusAddr: *statusAddr,
		Limits:     DefaultLimits(),
		PublicAddr: strings.TrimSpace(*publicAddr),
		OnionAddr:  strings.TrimSpace(*onionAddr),
	}, nil
}

// LinkConfig is what `noxd link` needs: where the running server's service
// page listens, and whether to draw the link as a QR code too.
type LinkConfig struct {
	StatusAddr string
	QR         bool
}

// LoadLink parses the arguments of `noxd link` (046). The address follows the
// server's own rule and default - flag, then NOX_STATUS_ADDR, then
// 127.0.0.1:8081 - so the command finds a server started with the same
// environment without being told, and it is held to loopback the same way: the
// command asks for a link, and the answer must not come from anywhere else.
func LoadLink(args []string, getenv func(string) string) (LinkConfig, error) {
	defStatus := getenv("NOX_STATUS_ADDR")
	if defStatus == "" {
		defStatus = "127.0.0.1:8081"
	}
	fs := flag.NewFlagSet("noxd link", flag.ContinueOnError)
	statusAddr := fs.String("status-addr", defStatus, "the running server's service page address (loopback)")
	qr := fs.Bool("qr", false, "draw the link as a QR code in the terminal as well")
	if err := fs.Parse(args); err != nil {
		return LinkConfig{}, fmt.Errorf("parse flags: %w", err)
	}
	if fs.NArg() > 0 {
		return LinkConfig{}, fmt.Errorf("unexpected argument %q (noxd link takes only -status-addr and -qr)", fs.Arg(0))
	}
	if *statusAddr == "" {
		return LinkConfig{}, errors.New("-status-addr must name the running server's service page: " +
			"a server started with it empty has no page, and no way to hand out a link")
	}
	if err := checkStatusAddr(*statusAddr); err != nil {
		return LinkConfig{}, err
	}
	return LinkConfig{StatusAddr: *statusAddr, QR: *qr}, nil
}

// CommandConfig is what `noxd unlock` and `noxd password` need: where the
// running server's service page listens.
type CommandConfig struct {
	StatusAddr string
}

// LoadCommand parses the arguments of `noxd unlock` or `noxd password` (047),
// named by name. The address follows the server's own rule and default, as
// for `noxd link`.
func LoadCommand(name string, args []string, getenv func(string) string) (CommandConfig, error) {
	fs := flag.NewFlagSet("noxd "+name, flag.ContinueOnError)
	statusAddr := statusAddrFlag(fs, getenv)
	if err := fs.Parse(args); err != nil {
		return CommandConfig{}, fmt.Errorf("parse flags: %w", err)
	}
	if fs.NArg() > 0 {
		return CommandConfig{}, fmt.Errorf("unexpected argument %q (noxd %s takes only -status-addr; "+
			"the password is asked for, never given on the command line)", fs.Arg(0), name)
	}
	if err := commandStatusAddr(*statusAddr); err != nil {
		return CommandConfig{}, err
	}
	return CommandConfig{StatusAddr: *statusAddr}, nil
}

// statusAddrFlag is -status-addr as every command reads it: the flag, then
// NOX_STATUS_ADDR, then the server's default - so a command finds a server
// started with the same environment without being told.
func statusAddrFlag(fs *flag.FlagSet, getenv func(string) string) *string {
	def := getenv("NOX_STATUS_ADDR")
	if def == "" {
		def = "127.0.0.1:8081"
	}
	return fs.String("status-addr", def, "the running server's service page address (loopback)")
}

// commandStatusAddr holds a command's address to the server's rule: present,
// and loopback - the command sends a password, and the answer must not come
// from anywhere else.
func commandStatusAddr(addr string) error {
	if addr == "" {
		return errors.New("-status-addr must name the running server's service page")
	}
	return checkStatusAddr(addr)
}

// checkStatusAddr refuses anything the service page must not listen on.
//
// Empty passes here and is refused by every caller, each with its own reason.
// Everything else has to resolve to a loopback address: the flag exists to move the port, not to put the page on a
// network, and somebody who writes 0.0.0.0 there has to learn it now rather
// than when a stranger pairs with their server. A name is resolved rather than
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

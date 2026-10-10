package server

import (
	"context"
	"crypto/ed25519"
	"fmt"
	"net"
	"os"
	"runtime/debug"
	"strings"
	"time"

	"nox.app/client-backend/internal/store"
)

// machineStatus is everything the service page shows, gathered per request.
//
// Per request rather than cached: the state changes while a page is open, and
// a tab left on screen must not go on offering a link that has just been spent.
type machineStatus struct {
	// HasDevices says some device can reach this machine. Without one the page
	// leads with a machine link (FR-003); with them, it offers `Add a device`.
	HasDevices bool
	// HasPerson picks the words for a machine nobody can reach: a fresh one, or
	// one whose person signed out of their last device and has chats and
	// messages waiting for whichever device comes next.
	HasPerson bool
	// Link is the machine link to show, empty when there is none to show.
	Link string
	// LinkLive says Link can still be presented. A link that ran out is shown
	// as `Link expired` with `New link` - never replaced on its own (FR-002).
	LinkLive  bool
	ExpiresAt int64
	// Scannable is whether the link names an address ANOTHER device can reach:
	// a dialable bind, or a public or onion address the person set. False does
	// not mean there is no link: a server bound to loopback is paired from the
	// app on this same machine, and the link is what that app needs. It only
	// means there is no point drawing a code for a camera.
	Scannable bool
	JournalID string
	Schema    int
	Counts    store.Counts
	DBBytes   int64
	Version   string
	Uptime    time.Duration
	// Found are the addresses the machine finds on its own networks - the
	// direct half of the snapshot devices are given. Read-only on the page.
	Found []string
	// Stored is what the database holds for the public and onion address,
	// exactly as stored: the Set forms show it to be changed.
	Stored store.Addresses
}

// collectStatus reads the machine's own state.
//
// The link and the device count come from ONE read (store.PageMachineLink):
// whether the page leads with a link and which link it shows are one fact, and
// reading them apart could show the "no devices" page over a machine somebody
// paired a moment ago.
func (s *Server) collectStatus(ctx context.Context) (machineStatus, error) {
	now := time.Now().Unix()
	page, err := s.store.PageMachineLink(ctx, now)
	if err != nil {
		return machineStatus{}, fmt.Errorf("read the machine link: %w", err)
	}
	counts, err := s.store.CountEverything(ctx)
	if err != nil {
		return machineStatus{}, err
	}
	journalID, err := s.store.JournalID(ctx)
	if err != nil {
		return machineStatus{}, fmt.Errorf("read journal id: %w", err)
	}

	stored, err := s.store.Addresses(ctx)
	if err != nil {
		return machineStatus{}, fmt.Errorf("read addresses: %w", err)
	}
	found := []string{}
	if cur := s.addrs.Load(); cur != nil {
		found = cur.Direct
	}

	status := machineStatus{
		HasDevices: page.Devices > 0,
		HasPerson:  counts.People > 0,
		Found:      found,
		Stored:     stored,
		JournalID:  journalID,
		Schema:     s.schemaVersion,
		Counts:     counts,
		DBBytes:    fileSize(s.cfg.DBPath),
		Version:    buildVersion(),
		Uptime:     time.Since(s.startedAt),
	}
	if page.Found {
		b, err := s.machineLinkBuilder(ctx)
		if err != nil {
			return machineStatus{}, err
		}
		status.Link, status.Scannable, err = b.build(page.Link.Token)
		if err != nil {
			return machineStatus{}, err
		}
		status.LinkLive = page.Link.Live(now)
		status.ExpiresAt = page.Link.ExpiresAt
	}
	return status, nil
}

// buildVersion reads what the binary knows about itself.
//
// From the binary rather than from -ldflags: no build path needs touching, and
// the version cannot drift from what was actually compiled - which is exactly
// what happens to whoever builds with a plain `go build`. Built without a VCS
// it says so, because "v0.0.0" would be a lie about a real question.
func buildVersion() string {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}
	var revision, when string
	dirty := false
	for _, setting := range info.Settings {
		switch setting.Key {
		case "vcs.revision":
			revision = setting.Value
		case "vcs.time":
			when = setting.Value
		case "vcs.modified":
			dirty = setting.Value == "true"
		}
	}
	if revision == "" {
		return "unknown (built without version control)"
	}
	if len(revision) > 12 {
		revision = revision[:12]
	}
	out := revision
	if dirty {
		out += " (modified)"
	}
	if when != "" {
		out += ", " + when
	}
	return out
}

// fileSize is the database file on disk, or zero when it cannot be read.
//
// The file, not the sum of the rows: somebody looking at this number wants to
// know how much disk is gone. The WAL is deliberately left out - it is
// temporary and collapses at a checkpoint, so including it would make the
// figure jump for a reason nobody could explain.
func fileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}

// dialableHost is the address to put in the QR code.
//
// NOT listenAddress: that falls back to loopback under a wildcard bind, which
// is right for a link pasted into the app on this machine and useless for the
// reader the code exists for, a phone reading it off the screen. 127.0.0.1 is not something a phone can dial,
// and 0.0.0.0 is how a household server is ordinarily run, so the old rule
// would have produced a code that never worked.
//
// Empty means this machine has no address anything else could reach, and the
// page says so instead of drawing a code nothing can dial.
func dialableHost(bindAddr string) string {
	host, port, err := net.SplitHostPort(bindAddr)
	if err != nil {
		return ""
	}
	if host != "" && host != "0.0.0.0" && host != "::" {
		// The operator named an address. Theirs is the answer - UNLESS it is
		// loopback, which is the default and means the server is reachable
		// from this machine and nowhere else. A QR pointing at 127.0.0.1 is a
		// code that cannot work, and drawing it confidently is worse than
		// drawing none: the person scans it and gets an error about the
		// network rather than being told to bind an address.
		if ip := net.ParseIP(host); ip != nil {
			if ip.IsLoopback() {
				return ""
			}
			return net.JoinHostPort(host, port)
		}
		// A NAME, resolved rather than compared against "localhost": an alias
		// in /etc/hosts, localhost.localdomain, or a different spelling all
		// point at the same unreachable place, and the code drawn for them
		// would be exactly the one this refuses to draw.
		ips, err := net.LookupIP(host)
		if err != nil || len(ips) == 0 {
			return ""
		}
		for _, ip := range ips {
			if !ip.IsLoopback() {
				return net.JoinHostPort(host, port)
			}
		}
		return ""
	}
	// A wildcard bind. Only interfaces that are actually UP count: a laptop
	// carries a docker bridge, a VPN tap and an unplugged ethernet with a
	// static address, and any of those would produce a code the phone cannot
	// reach while looking exactly as valid as a working one.
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	var fallback string
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagRunning == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok || ipNet.IP.IsLoopback() || ipNet.IP.IsLinkLocalUnicast() || ipNet.IP.IsUnspecified() {
				continue
			}
			// IPv4 first: a QR is read by a camera, and an IPv6 literal is four
			// times the modules for the same reach on a home network.
			if v4 := ipNet.IP.To4(); v4 != nil {
				return net.JoinHostPort(v4.String(), port)
			}
			if fallback == "" && ipNet.IP.IsGlobalUnicast() {
				fallback = net.JoinHostPort(ipNet.IP.String(), port)
			}
		}
	}
	return fallback
}

// humanBytes renders a size the way a person reads one.
func humanBytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for size := n / unit; size >= unit; size /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(n)/float64(div), "KMGTPE"[exp])
}

// humanDuration renders an uptime without false precision.
func humanDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%d seconds", int(d.Seconds()))
	}
	parts := make([]string, 0, 3)
	days := int(d.Hours()) / 24
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60
	if days > 0 {
		parts = append(parts, fmt.Sprintf("%dd", days))
	}
	if hours > 0 {
		parts = append(parts, fmt.Sprintf("%dh", hours))
	}
	parts = append(parts, fmt.Sprintf("%dm", minutes))
	return strings.Join(parts, " ")
}

// linkBuilder is what a machine link is built from, read BEFORE a token is
// minted wherever one is: a failure after minting would leave a fresh link
// nobody was handed, and the one it voided gone.
//
// Only the TOKEN lives anywhere; the link is rebuilt from it every time.
// Caching a built link froze an address for the life of the process while the
// answer to "can a phone reach us" went on being recomputed - so a laptop whose
// Wi-Fi came up after the server did drew a code over a link that still said
// 127.0.0.1. One fact, one record.
type linkBuilder struct {
	key      ed25519.PublicKey
	conf     configuredAddresses
	host     string
	dialable bool
}

// machineLinkBuilder reads the machine's key and addresses.
//
// Two questions, and conflating them cost the page once already. "Can a phone
// dial this address" decides the code - and nothing decides whether there is a
// LINK. A server on the default loopback bind is paired from the app on this
// same machine by pasting, so the link falls back to the address that app can
// dial.
func (s *Server) machineLinkBuilder(ctx context.Context) (linkBuilder, error) {
	id, err := s.store.ServerIdentity(ctx)
	if err != nil {
		return linkBuilder{}, fmt.Errorf("read server identity: %w", err)
	}
	conf, err := s.configuredAddresses(ctx)
	if err != nil {
		return linkBuilder{}, fmt.Errorf("read addresses: %w", err)
	}
	host := dialableHost(s.cfg.Addr)
	b := linkBuilder{key: id.PublicKey, conf: conf, host: host, dialable: host != ""}
	if host == "" {
		b.host = listenAddress(s.cfg.Addr)
	}
	return b, nil
}

// build renders the link for token, and says whether a phone could follow it.
// A public or onion address is reachable from a phone wherever the bind is: a
// machine on loopback behind tor is paired through Tor (045, FR-008), and a
// code is exactly what that phone needs.
func (b linkBuilder) build(token string) (string, bool, error) {
	link, carries, err := buildLink(b.key, token, b.host, b.conf)
	if err != nil {
		// The error can quote the host it could not encode.
		return "", false, fmt.Errorf("build machine link: %s", maskOnion(err.Error()))
	}
	return link, b.dialable || carries.Public || carries.Onion, nil
}

// issueMachineLink mints a new machine link - the previous one stops working
// (SC-004) - and builds it. by says who asked, for the log line, which names
// the asker and never the link (FR-005).
func (s *Server) issueMachineLink(ctx context.Context, by string) (string, store.MachineLink, error) {
	b, err := s.machineLinkBuilder(ctx)
	if err != nil {
		return "", store.MachineLink{}, err
	}
	ml, err := s.store.IssueMachineLink(ctx, time.Now().Unix())
	if err != nil {
		return "", store.MachineLink{}, fmt.Errorf("issue machine link: %w", err)
	}
	link, _, err := b.build(ml.Token)
	if err != nil {
		return "", store.MachineLink{}, err
	}
	s.logger.Info("machine link issued", "by", by)
	return link, ml, nil
}

// ExpiresIn words how long a link has left, in whole minutes rounded up - the
// way the service page and `noxd link` both say it. A link issued a moment ago
// says ten.
func ExpiresIn(expiresAt, now int64) string {
	left := expiresAt - now
	if left <= 0 {
		return "Link expired"
	}
	minutes := (left + 59) / 60
	if minutes == 1 {
		return "Expires in 1 minute"
	}
	return fmt.Sprintf("Expires in %d minutes", minutes)
}

package server

import (
	"context"
	"fmt"
	"net"
	"os"
	"runtime/debug"
	"strings"
	"time"

	"nox.app/client-backend/internal/store"
)

// machineState is which of the three pages to show.
//
// Three, not two. Besides "somebody still has to claim this" and "it is
// claimed", there is a store holding people with no owner - an anomaly only a
// hand-edited database reaches (phase 033). Pair refuses a claim there, so a
// link on that page would be an instruction nobody can follow.
type machineState int

const (
	stateNeedsClaim machineState = iota
	stateClaimed
)

// machineStatus is everything the service page shows, gathered per request.
//
// Per request rather than cached: the state changes while a page is open, and
// a tab left on screen must not go on offering a link that has just been spent.
type machineStatus struct {
	State machineState
	Link  string
	// Scannable is whether the link's address can be reached from ANOTHER
	// device. False does not mean there is no link: a server bound to loopback
	// is perfectly claimable from the app on this same machine, and the link is
	// what that app needs. It only means there is no point drawing a code for a
	// camera.
	Scannable bool
	JournalID string
	Schema    int
	Counts    store.Counts
	DBBytes   int64
	Version   string
	Uptime    time.Duration
}

// collectStatus reads the machine's own state.
//
// Ownership comes from the same ReadOwnershipState the startup announcement
// reads, and the SAME predicate decides: "claimed" means the owner can still
// get in. A second definition here is how phase 033's one fact would go back to
// living in two records - and this one would show a status page to somebody
// locked out of their own machine.
func (s *Server) collectStatus(ctx context.Context) (machineStatus, error) {
	ownership, err := s.store.ReadOwnershipState(ctx)
	if err != nil {
		return machineStatus{}, fmt.Errorf("read ownership: %w", err)
	}
	counts, err := s.store.CountEverything(ctx)
	if err != nil {
		return machineStatus{}, err
	}
	journalID, err := s.store.JournalID(ctx)
	if err != nil {
		return machineStatus{}, fmt.Errorf("read journal id: %w", err)
	}

	status := machineStatus{
		JournalID: journalID,
		Schema:    s.schemaVersion,
		Counts:    counts,
		DBBytes:   fileSize(s.cfg.DBPath),
		Version:   buildVersion(),
		Uptime:    time.Since(s.startedAt),
	}

	switch {
	case ownership.OwnerCanGetIn:
		status.State = stateClaimed
	default:
		status.State = stateNeedsClaim
		link, scannable, err := s.claimLink(ctx)
		if err != nil {
			return machineStatus{}, err
		}
		status.Link, status.Scannable = link, scannable
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
// is right for the line printed in the terminal - read by a person sitting at
// this machine - and useless for the reader this page exists for, a phone
// reading the code off the screen. 127.0.0.1 is not something a phone can dial,
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

// claimLink hands out THE claim link of this process, minting the token once.
//
// Once, not per request. A claim token has no expiry - it dies by being used
// (phase 032) - so minting one per page load would leave an unrevocable door
// behind every browser refresh, and a database full of live tokens nobody
// remembers. The startup announcement seeds this with the token it already
// minted, so the page and the terminal hand out the same right; only the
// ADDRESS differs, because the two have different readers.
func (s *Server) claimLink(ctx context.Context) (string, bool, error) {
	s.claim.Lock()
	defer s.claim.Unlock()

	// The held token can have been spent since it was minted: somebody claims
	// the server, the owner later revokes their last device, and this page is
	// asked for a link again. Showing the burnt one would offer the only way
	// back in as a door that no longer opens - and a claim token has no expiry
	// to make that obvious.
	if s.claimToken != "" {
		usable, err := s.store.ClaimTokenUsable(ctx, s.claimToken)
		if err != nil {
			return "", false, err
		}
		if !usable {
			s.claimToken = ""
		}
	}
	// Two questions, and conflating them cost the whole page once already.
	// "Can a phone dial this address" decides the QR - and nothing decides
	// whether there is a LINK. A server on the default loopback bind is claimed
	// from the app on this same machine by pasting, and refusing to issue a link
	// there left an owner who had logged out with no way back in at all.
	host := dialableHost(s.cfg.Addr)
	scannable := host != ""
	if host == "" {
		host = listenAddress(s.cfg.Addr)
	}

	// The TOKEN is what may be minted only once; the link is rebuilt every time.
	//
	// Caching the built link froze an address for the life of the process while
	// the answer to "can a phone reach us" went on being recomputed - so a
	// laptop whose Wi-Fi came up after the server did would draw a QR over a
	// link that still said 127.0.0.1, which is exactly the code this page
	// refuses to draw. One fact, one cache.
	token := s.claimToken
	if token == "" {
		minted, err := s.store.IssueClaimToken(ctx, time.Now().Unix())
		if err != nil {
			return "", false, fmt.Errorf("issue claim token: %w", err)
		}
		s.claimToken, token = minted, minted
	}
	id, err := s.store.ServerIdentity(ctx)
	if err != nil {
		return "", false, fmt.Errorf("read server identity: %w", err)
	}
	link, err := BuildPairingLink(host, id.PublicKey, token)
	if err != nil {
		return "", false, fmt.Errorf("build claim link: %w", err)
	}
	return link, scannable, nil
}

// seedClaimToken records the token the startup announcement already minted, so
// the page hands out the same right rather than a second one.
func (s *Server) seedClaimToken(token string) {
	s.claim.Lock()
	defer s.claim.Unlock()
	s.claimToken = token
}

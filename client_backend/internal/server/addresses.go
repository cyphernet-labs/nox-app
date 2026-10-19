package server

import (
	"cmp"
	"context"
	"encoding/json"
	"net"
	"slices"
	"strings"
	"time"

	"nox.app/client-backend/internal/protocol"
)

const (
	// maxDirectAddresses caps the direct list. A machine with a dozen
	// container bridges has a dozen useless addresses; the cap keeps the frame
	// small, and the device tries the one that worked last first anyway.
	maxDirectAddresses = 16
	// defaultAddressPoll is how often the watcher looks at the interfaces. A
	// router handing the machine a new address is noticed within this, well
	// inside the minute FR-025 allows; subscribing to interface changes on
	// five operating systems is five APIs for twenty seconds.
	defaultAddressPoll = 30 * time.Second
)

// addressSet is where this machine can be reached (039, 045, contract §3):
// the addresses it finds on its own networks, and the public and onion address
// stored in its database when they are set.
//
// Version only grows and never travels: it is how the watcher - the ONE sender
// of server.addresses - knows which connections already have this list, so no
// connection is ever handed an older list after a newer one.
type addressSet struct {
	Version uint64   `json:"-"`
	Direct  []string `json:"direct"`
	// Public is the stored public host:port, absent when none is set.
	Public string `json:"public,omitempty"`
	// Onion is the stored onion address with the service's port, absent when
	// none is set. Whether tor is running does not enter into it: tor is a
	// separate service, and a device that finds nobody at the address says so
	// itself.
	Onion string `json:"onion,omitempty"`
}

func (a *addressSet) equal(b *addressSet) bool {
	return a.Public == b.Public && a.Onion == b.Onion && slices.Equal(a.Direct, b.Direct)
}

// usableIPs lists the addresses of the machine's interfaces that are up,
// minus the ones nobody elsewhere could dial.
func usableIPs() []net.IP {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var out []net.IP
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagRunning == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			if ipNet, ok := addr.(*net.IPNet); ok && dialableIP(ipNet.IP) {
				out = append(out, ipNet.IP)
			}
		}
	}
	return out
}

// dialableIP is the one rule for "could another machine dial this": not
// loopback, not link-local, not unspecified.
func dialableIP(ip net.IP) bool {
	return ip != nil && !ip.IsLoopback() && !ip.IsLinkLocalUnicast() && !ip.IsLinkLocalMulticast() && !ip.IsUnspecified()
}

// directAddresses is the direct half of the list (FR-026).
//
// A wildcard bind lists every usable interface address with the main port. A
// concrete bind lists itself - unless it is loopback, which a device elsewhere
// can never use and a device on this machine already knows from its link. The
// order is addressRank's, then the text: a reshuffle of
// interfaces is not a change, and the cap drops the least likely addresses
// rather than whichever happen to sort last.
//
// A host NAME is listed when it resolves to something dialable, and a
// resolver that fails is not the name moving: ok is false then, and the
// caller keeps the list it had rather than announcing an empty one to every
// device and the old one again a poll later.
func directAddresses(bindAddr string, ips func() []net.IP, resolve func(string) ([]net.IP, error)) (list []string, ok bool) {
	host, port, err := net.SplitHostPort(bindAddr)
	if err != nil || port == "" || port == "0" {
		return []string{}, true
	}
	if host != "" && host != "0.0.0.0" && host != "::" {
		if ip := net.ParseIP(host); ip != nil {
			if !dialableIP(ip) {
				return []string{}, true
			}
			return []string{net.JoinHostPort(ip.String(), port)}, true
		}
		resolved, err := resolve(host)
		if err != nil {
			return nil, false
		}
		if slices.ContainsFunc(resolved, dialableIP) {
			return []string{net.JoinHostPort(host, port)}, true
		}
		return []string{}, true
	}
	type ranked struct {
		rank int
		addr string
	}
	all := make([]ranked, 0, 4)
	for _, ip := range ips() {
		if !dialableIP(ip) {
			continue
		}
		s := ip.String()
		if v4 := ip.To4(); v4 != nil {
			s = v4.String()
		}
		all = append(all, ranked{addressRank(ip), net.JoinHostPort(s, port)})
	}
	slices.SortFunc(all, func(a, b ranked) int {
		return cmp.Or(cmp.Compare(a.rank, b.rank), strings.Compare(a.addr, b.addr))
	})
	all = slices.CompactFunc(all, func(a, b ranked) bool { return a.addr == b.addr })
	out := make([]string, 0, min(len(all), maxDirectAddresses))
	for _, r := range all[:min(len(all), maxDirectAddresses)] {
		out = append(out, r.addr)
	}
	return out, true
}

// addressRank orders the direct list by how likely an address is to be the one
// a device at home dials: the usual home range first, then the other private
// ranges, then public ones, then the shared range that CGNAT and VPNs such as
// Tailscale use, and IPv6 after all of IPv4. 172.16/12 trails 10/8 because
// container bridges live there. Only a preference - the device keeps the
// address that answered last and tries the rest - but it is what an invite
// carries, and what survives the cap.
func addressRank(ip net.IP) int {
	if v4 := ip.To4(); v4 != nil {
		switch {
		case v4[0] == 192 && v4[1] == 168:
			return 0
		case v4[0] == 10:
			return 1
		case v4[0] == 172 && v4[1]&0xf0 == 16:
			return 2
		case v4[0] == 100 && v4[1]&0xc0 == 64:
			return 4
		}
		return 3
	}
	if ip.IsPrivate() {
		return 5
	}
	return 6
}

// resolveTimeout bounds one lookup of a bind host name: the watcher waits for
// it, and so does shutdown.
const resolveTimeout = 5 * time.Second

// resolveHost is the production resolver behind directAddresses.
func resolveHost(host string) ([]net.IP, error) {
	ctx, cancel := context.WithTimeout(context.Background(), resolveTimeout)
	defer cancel()
	return net.DefaultResolver.LookupIP(ctx, "ip", host)
}

// computeAddresses builds the list as it stands now: the interfaces looked at
// again, the stored addresses read again.
//
// A read that fails is not the addresses changing, any more than a resolver
// that fails is the name moving: the snapshot keeps what it had rather than
// telling every device the addresses are gone and, a look later, back.
func (s *Server) computeAddresses(ctx context.Context) *addressSet {
	cur := s.addrs.Load()
	direct, ok := directAddresses(s.cfg.Addr, s.listIPs, s.resolveHost)
	if !ok {
		direct = []string{}
		if cur != nil {
			direct = cur.Direct
		}
	}
	set := &addressSet{Direct: direct}
	conf, err := s.configuredAddresses(ctx)
	if err != nil {
		if ctx.Err() == nil {
			s.logger.Warn("stored addresses unreadable, keeping the last known", "err", err)
		}
		if cur != nil {
			set.Public, set.Onion = cur.Public, cur.Onion
		}
		return set
	}
	set.Public = conf.Public
	if conf.Onion != "" {
		set.Onion = net.JoinHostPort(conf.Onion, onionPort)
	}
	return set
}

// refreshAddresses stores a new snapshot when the list changed. Only the
// watcher calls it once the server is serving; startup calls it once before
// any listener opens, so the very first greeting already has a list.
func (s *Server) refreshAddresses(ctx context.Context) bool {
	next := s.computeAddresses(ctx)
	cur := s.addrs.Load()
	if cur != nil && cur.equal(next) {
		return false
	}
	next.Version = 1
	if cur != nil {
		next.Version = cur.Version + 1
	}
	s.addrs.Store(next)
	return true
}

// pokeAddresses asks the watcher to look now. Never blocks. A greeting pokes,
// so a list that moved while it was being answered follows the reply; so does
// the service page's Set, which is how a new address reaches the greeted
// connections within moments rather than at the next poll (SC-003).
func (s *Server) pokeAddresses() {
	select {
	case s.addrKick <- struct{}{}:
	default:
	}
}

// runAddressWatcher is the only sender of server.addresses: it refreshes the
// snapshot - storing it FIRST - and then hands it to every greeted connection
// that has an older one.
func (s *Server) runAddressWatcher(ctx context.Context) {
	tick := time.NewTicker(s.addressPoll)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		case <-s.addrKick:
		}
		s.refreshAddresses(ctx)
		s.sendAddresses()
	}
}

// sendAddresses delivers the current snapshot to the greeted connections that
// have not had it yet.
//
// Collected under s.mu and sent outside it, like the other fan-out helpers:
// sendFrame waits for room in a bounded queue, and waiting under the registry
// lock would hold up every connection on the server. The version is recorded
// under the lock BEFORE the frame is queued, so a second pass of this same
// goroutine cannot send it twice - and no other goroutine sends this event at
// all.
func (s *Server) sendAddresses() {
	cur := s.addrs.Load()
	if cur == nil {
		return
	}
	s.mu.Lock()
	targets := make([]*client, 0, 2)
	for c := range s.conns {
		if c.greeted && c.addrVersion < cur.Version {
			c.addrVersion = cur.Version
			targets = append(targets, c)
		}
	}
	s.mu.Unlock()
	if len(targets) == 0 {
		return
	}
	payload, err := json.Marshal(cur)
	if err != nil {
		s.logger.Error("marshal addresses", "err", err)
		return
	}
	for _, c := range targets {
		c.sendFrame(protocol.Event{Seq: 0, Event: protocol.EventServerAddresses, Data: payload})
	}
}

// markGreeted records that this connection's greeting reply - carrying the
// snapshot of version - is already queued. Only now may the watcher send it
// server.addresses: the event can therefore never overtake the reply.
func (s *Server) markGreeted(c *client, version uint64) {
	s.mu.Lock()
	c.greeted = true
	c.addrVersion = version
	s.mu.Unlock()
	if s.afterGreeted != nil {
		s.afterGreeted(c)
	}
}

// inviteDirectAddress is the direct host for an invite requested through the
// onion service, where the Host header holds the onion name: the head of the
// list, which is in order of preference with IPv4 first, else the bind address
// as listenAddress renders it.
func (s *Server) inviteDirectAddress() string {
	if cur := s.addrs.Load(); cur != nil && len(cur.Direct) > 0 {
		return cur.Direct[0]
	}
	return listenAddress(s.cfg.Addr)
}

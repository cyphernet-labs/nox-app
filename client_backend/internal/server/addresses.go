package server

import (
	"context"
	"encoding/json"
	"net"
	"slices"
	"strconv"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/tor"
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

// addressSet is where this machine can be reached (039, contract §3).
//
// Version only grows and never travels: it is how the watcher - the ONE sender
// of server.addresses - knows which connections already have this list, so no
// connection is ever handed an older list after a newer one.
type addressSet struct {
	Version uint64   `json:"-"`
	Direct  []string `json:"direct"`
	Onion   string   `json:"onion,omitempty"`
}

func (a *addressSet) equal(b *addressSet) bool {
	return a.Onion == b.Onion && slices.Equal(a.Direct, b.Direct)
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
// A wildcard bind lists every usable interface address with the port of the
// main entry. A concrete bind lists itself - unless it is loopback, which a
// device elsewhere can never use and a device on this machine already knows
// from its link. Sorted, so a reshuffle of interfaces is not a change; IPv4
// sorts ahead of bracketed IPv6.
func directAddresses(bindAddr string, ips func() []net.IP) []string {
	host, port, err := net.SplitHostPort(bindAddr)
	if err != nil || port == "" || port == "0" {
		return []string{}
	}
	if host != "" && host != "0.0.0.0" && host != "::" {
		if ip := net.ParseIP(host); ip != nil {
			if !dialableIP(ip) {
				return []string{}
			}
			return []string{net.JoinHostPort(ip.String(), port)}
		}
		resolved, err := net.LookupIP(host)
		if err != nil {
			return []string{}
		}
		for _, ip := range resolved {
			if dialableIP(ip) {
				return []string{net.JoinHostPort(host, port)}
			}
		}
		return []string{}
	}
	out := make([]string, 0, 4)
	for _, ip := range ips() {
		if !dialableIP(ip) {
			continue
		}
		s := ip.String()
		if v4 := ip.To4(); v4 != nil {
			s = v4.String()
		}
		out = append(out, net.JoinHostPort(s, port))
	}
	slices.Sort(out)
	out = slices.Compact(out)
	if len(out) > maxDirectAddresses {
		out = out[:maxDirectAddresses]
	}
	return out
}

// computeAddresses builds the list as it stands now.
func (s *Server) computeAddresses() *addressSet {
	set := &addressSet{Direct: directAddresses(s.cfg.Addr, s.listIPs)}
	if s.tor.Offered() {
		set.Onion = s.tor.Address() + ".onion:" + strconv.Itoa(tor.OnionPort)
	}
	return set
}

// refreshAddresses stores a new snapshot when the list changed. Only the
// watcher calls it once the server is serving; startup calls it once before
// any listener opens, so the very first greeting already has a list.
func (s *Server) refreshAddresses() bool {
	next := s.computeAddresses()
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

// pokeAddresses asks the watcher to look now. Never blocks.
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
		s.refreshAddresses()
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
}

// inviteDirectAddress is the direct host for an invite requested over onion,
// where the Host header holds the onion name: the first IPv4 of the list, else
// its first address, else the bind address as the claim link would print it.
func (s *Server) inviteDirectAddress() string {
	if cur := s.addrs.Load(); cur != nil {
		for _, a := range cur.Direct {
			host, _, err := net.SplitHostPort(a)
			if err == nil && net.ParseIP(host).To4() != nil {
				return a
			}
		}
		if len(cur.Direct) > 0 {
			return cur.Direct[0]
		}
	}
	return listenAddress(s.cfg.Addr)
}

package server

import (
	"time"

	"github.com/coder/websocket"
)

// A /ws connection whose key no device row names may only pair (contract §1,
// §8A). The channel accepts every key that proves itself, because a device
// about to pair is unknown by definition - so a key made for the occasion
// passes it like any other, and since 045 anybody who knows the onion address
// can make one. What such a connection may hold is bounded here: in time, and
// in how many are open at once. A paired device's connection is held to
// neither.

const (
	// defaultUnpairedTimeout is how long a connection of a key nobody paired
	// stays open without pairing. pair is one request and one answer, sent
	// right behind the server's greeting, so a device that means to pair has
	// done so within one round trip - seconds through Tor - and two minutes is
	// that many times over. Without a limit the server's own pings would keep
	// such a connection alive for as long as its holder liked.
	//
	// 046 adds a pairing that waits for the person to approve it on another
	// device, for up to an invite's ten minutes. That waiting connection must
	// extend this deadline or be exempt from it, or every approval slower than
	// two minutes fails.
	defaultUnpairedTimeout = 2 * time.Minute
	// defaultMaxUnpaired is how many connections of keys nobody paired may be
	// open at once. A person pairs one device at a time, and 32 leaves room
	// for retries and a slow path many times over. A newcomer past it is taken
	// and the oldest closed, the way the channel's entry makes room
	// (channel.go). Turned away instead, the newcomer would lose to whoever
	// holds the places: 32 connections renewed every two minutes would keep
	// every new device out for good. With the oldest closed, keeping a device
	// out takes 32 new connections within each of its round trips.
	defaultMaxUnpaired = 32
)

// pairedKey reports whether c's key is a paired device's. A store that cannot
// answer counts as "no": the connection is then held to a stranger's limits,
// which a paired device leaves the moment it greets.
func (s *Server) pairedKey(c *client) bool {
	_, found, err := s.store.DeviceOwner(c.ctx, c.deviceKey)
	if err != nil {
		c.logger.Error("read the connection's device", "err", err)
		return false
	}
	return found
}

// holdUnpaired puts c among the connections of keys nobody paired - closing
// the oldest of them if c is one too many - and arms its deadline. The
// returned func disarms the deadline; the handler calls it as the connection
// ends.
func (s *Server) holdUnpaired(c *client) (release func()) {
	cut, report := s.admitUnpaired(c)
	for _, old := range cut {
		// Off this goroutine: a close handshake can take seconds, and the
		// newcomer's greeting must not wait on a stranger's goodbye.
		go old.close(websocket.StatusTryAgainLater, "too many unpaired connections")
	}
	if report > 0 {
		// Counts only, like the channel's entry: no key, no address.
		s.logger.Warn("unpaired connections closed to make room", "closed", report)
	}
	deadline := time.AfterFunc(s.unpairedTimeout, func() {
		// Out of the count at once, the way a connection closed to make room
		// is: its close handshake can take seconds, and a place it no longer
		// needs must not push out somebody else meanwhile.
		if s.forgetUnpaired(c) {
			c.logger.Info("unpaired connection closed: it did not pair in time")
			c.close(websocket.StatusPolicyViolation, "not paired in time")
		}
	})
	return func() { deadline.Stop() }
}

// admitUnpaired makes c the newest unpaired connection and takes the oldest out
// while there are too many, returning them for the caller to close outside the
// lock. It also returns how many to report: everything taken out since the last
// warning, at most once a minute, so that a flood does not flood the log as
// well. What is not reported yet rides on the next warning.
func (s *Server) admitUnpaired(c *client) (cut []*client, report int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	// A loop rather than one cut: a cap shrunk while connections were held
	// still comes out at the cap.
	for s.unpaired.Len() > 0 && s.unpaired.Len() >= s.maxUnpaired {
		oldest := s.unpaired.Front().Value.(*client)
		s.forgetUnpairedLocked(oldest)
		cut = append(cut, oldest)
	}
	c.unpaired = s.unpaired.PushBack(c)
	if len(cut) > 0 {
		s.unpairedCut += len(cut)
		if now := time.Now(); now.Sub(s.unpairedWarned) >= shedLogInterval {
			report, s.unpairedCut, s.unpairedWarned = s.unpairedCut, 0, now
		}
	}
	return cut, report
}

// settleUnpaired takes c out of the unpaired connections once its key is known
// to be a paired device's: it paired, or it greeted as a device that paired on
// another connection after this one opened. Its deadline then finds nothing to
// close.
func (s *Server) settleUnpaired(c *client) {
	s.forgetUnpaired(c)
}

// forgetUnpaired takes c out of the unpaired connections, and reports whether
// it was still there - false once it settled, was closed to make room, or
// left.
func (s *Server) forgetUnpaired(c *client) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.forgetUnpairedLocked(c)
}

// forgetUnpairedLocked is forgetUnpaired with s.mu held.
func (s *Server) forgetUnpairedLocked(c *client) bool {
	if c.unpaired == nil {
		return false
	}
	s.unpaired.Remove(c.unpaired)
	c.unpaired = nil
	return true
}

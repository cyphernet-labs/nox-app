package server

import (
	"context"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/store"
)

// A key no device row names may only pair, and only over /ws (contract §1,
// §8A). The channel accepts every key that proves itself, because a device
// about to pair is unknown by definition - so a key made for the occasion
// passes it like any other, and since 045 anybody who knows the onion address
// can make one. What such a key's connections may hold is bounded here: a /ws
// session in time and in how many are open at once, and any other request by
// ending its connection with the answer. A paired device's connection is held
// to none of it.
//
// A pairing through an invite waits for Allow on the device that issued it
// (046), for up to the invite's ten minutes - far past a stranger's two. While
// its request waits, the connection that presented the invite last is held to
// neither limit and waits instead, under a deadline of the request's own
// (awaitAnswer); when the request closes, an allowed device is paired and a
// refused one is a stranger again (endWait). One connection holds each
// request's wait, so strangers can hold no more connections this way than
// requests wait - and a request opens only with an invite one of the person's
// own devices issued, and lives no longer than it.

const (
	// defaultUnpairedTimeout is how long a connection of a key nobody paired
	// stays open without pairing. pair is one request and one answer, sent
	// right behind the server's greeting, so a device that means to pair has
	// done so within one round trip - seconds through Tor - and two minutes is
	// that many times over. Without a limit the server's own pings would keep
	// such a connection alive for as long as its holder liked. A pairing that
	// waits for Allow is the one stranger that needs longer, and it gets its
	// request's own deadline instead (awaitAnswer).
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

// pairedKey reports whether key is a paired device's. A store that cannot
// answer counts as "no": the connection is then held to a stranger's limits,
// which a paired device leaves the moment it greets - or, off /ws, with the
// next connection it opens.
func (s *Server) pairedKey(ctx context.Context, key string, logger *slog.Logger) bool {
	_, found, err := s.store.DeviceOwner(ctx, key)
	if err != nil {
		logger.Error("read the connection's device", "err", err)
		return false
	}
	return found
}

// limitStrangers is the main port's door. Before any handler runs, it asks
// whether the request's connection proved a paired device's key, and holds a
// key nobody paired to one request per connection: every answer to it but a
// WebSocket upgrade ends the connection (endWithAnswer, strangerWriter). Kept
// open, such a connection would be the stranger's for as long as it asked
// again within each idle timeout. An upgrade goes on as a session, held to the
// deadline and the cap of holdUnpaired. A paired device's request passes as
// it is.
//
// The door decides only whether the connection outlives the request. What the
// request may do is still decided where it was, after the request is
// registered (admitTransfer, handleWS), so a revocation landing between the
// two is caught there - and a 401 there ends the connection too.
func (s *Server) limitStrangers(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if peer, ok := channelPeerFrom(r.Context()); ok && s.pairedKey(r.Context(), peer.deviceKey(), s.logger) {
			next.ServeHTTP(w, r)
			return
		}
		endWithAnswer(w, r)
		next.ServeHTTP(&strangerWriter{ResponseWriter: w}, r)
	})
}

// endWithAnswer makes the answer to r the last thing its connection carries.
// "Connection: close" has net/http close the connection once the answer is
// out, and skip reading the rest of a body before it writes the answer - which
// a declared and unsent body would hold up, the answer not yet written.
// net/http still reads that rest once the answer is out, for up to the body's
// budget (boundRequestBody), so a request that declared one also gets a read
// deadline already past: nothing here reads a body it is about to refuse, and
// the connection ends at once instead of half a minute later.
//
// Only a request that declared a body gets the deadline. Without one net/http
// is already reading the connection behind the handler, to notice the peer
// hanging up, and that read failing on a deadline ends the request's context
// under the handler - a stranger's pairing session with it.
func endWithAnswer(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Connection", "close")
	if r.ContentLength != 0 {
		_ = http.NewResponseController(w).SetReadDeadline(time.Now())
	}
}

// strangerWriter is the response writer of a stranger's request: whatever the
// handler answers says "Connection: close", unless it is the 101 of a
// WebSocket upgrade, which turns the connection into a session instead. The
// header is set again at WriteHeader, not only before the handler, because the
// WebSocket library writes "Connection: Upgrade" onto the refusals it answers
// too, and the value set last is the one sent.
type strangerWriter struct {
	http.ResponseWriter
}

func (w *strangerWriter) WriteHeader(code int) {
	if code != http.StatusSwitchingProtocols {
		w.Header().Set("Connection", "close")
	}
	w.ResponseWriter.WriteHeader(code)
}

// Unwrap is what the WebSocket library follows to take the connection over,
// and http.ResponseController to reach its deadlines.
func (w *strangerWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}

// boundRequestBody is the main port's ConnState hook. Once a request's headers
// are in, it gives the body that may follow them bodyTimeout, the slow path's
// budget - for any key. The main port sets no ReadTimeout, since a transfer
// has no time limit (043), and this bounds no transfer either: a handler that
// reads a body sets a deadline of its own before every read (stallReader),
// and net/http lifts the deadline itself whenever it reads behind a request
// with no body left, to notice the peer hanging up - a download's case. What
// it bounds is a body nobody of ours reads. net/http answers some requests
// itself, before any handler - an Expect it does not support - and reads what
// is left of a declared body before it lets the connection go; it does the
// same behind a handler that answered without reading one. Unbounded, that
// read would wait for good on a peer that declared a body and never sent it.
// The door cuts it short for a stranger's request (endWithAnswer).
//
// net/http calls this on the connection's own goroutine, between reading the
// headers and answering or starting a handler, and nothing in between touches
// the read deadline. Every other state is left alone: a new connection is
// reported on the accept loop, and the rest come with deadlines of their own.
func (s *Server) boundRequestBody(c net.Conn, state http.ConnState) {
	if state == http.StateActive {
		_ = c.SetReadDeadline(time.Now().Add(s.bodyTimeout))
	}
}

// holdUnpaired puts c among the connections of keys nobody paired - closing
// the oldest of them if c is one too many - and arms its deadline. The
// returned func lets go of whatever c is held to by then - its place, or the
// wait it moved to (awaitAnswer) - and the handler calls it as the connection
// ends.
func (s *Server) holdUnpaired(c *client) (release func()) {
	s.mu.Lock()
	cut, report := s.placeUnpairedLocked(c)
	s.mu.Unlock()
	s.closeToMakeRoom(cut, report)
	return func() { s.letGo(c) }
}

// settleUnpaired takes c out of a stranger's limits once its key is known to
// be a paired device's: it paired, or it greeted as a device that paired on
// another connection after this one opened. Its deadline then finds nothing to
// close, and a wait it held ends with it.
func (s *Server) settleUnpaired(c *client) {
	s.letGo(c)
}

// awaitAnswer exempts c from a stranger's limits while r - the request its
// `pair` has just found waiting - waits for the answer of the device that
// issued the invite (046). An Allow can take the invite's whole ten minutes,
// and the two minutes a stranger gets, or a newcomer pushing it out, would end
// every slower one. Called BEFORE the reply, so neither can land between the
// two.
//
// The wait has a deadline of its own all the same: the request's, the one
// sweep it may take to be closed, and the two minutes a stranger gets past
// that. Its end puts the connection back under the limits (endWait) before
// this deadline comes, so this one only bounds a wait whose end nobody
// reported.
//
// One connection holds each request's wait: the one that presented it last.
// The same key presenting the same invite on another connection - the app
// does, on every new connection - takes the wait over, and the connection it
// leaves is a stranger again, with a place and two minutes of its own.
//
// A connection held to no limit has nothing to be exempt from: a paired
// device's, or one already cut, which is closing.
func (c *client) awaitAnswer(r store.PairRequest) {
	s := c.srv
	if s.beforeWait != nil {
		s.beforeWait(r.RequestID)
	}
	s.mu.Lock()
	if c.unpaired == nil && c.waitsOn == "" {
		s.mu.Unlock()
		return
	}
	// Out of its place - or of a wait on another request - first, so the
	// place the displaced holder takes below can never push c itself out.
	s.letGoLocked(c)
	var cut []*client
	var report int
	if prev := s.waits[r.RequestID]; prev != nil {
		s.letGoLocked(prev)
		cut, report = s.placeUnpairedLocked(prev)
	}
	s.waits[r.RequestID] = c
	c.waitsOn = r.RequestID
	s.armLocked(c, time.Until(time.Unix(r.ExpiresAt, 0))+s.requestSweep+s.unpairedTimeout)
	s.mu.Unlock()
	s.closeToMakeRoom(cut, report)

	// The request can close between the store's "pending" and the wait taking
	// hold above - an Allow, a Deny, a cancel, the sweep - and whoever closed
	// it found nobody waiting on it. So it is asked again now that the wait
	// holds: a close from here on finds this connection, and one before is
	// caught by this read.
	outcome, err := s.store.PairRequestOutcome(c.ctx, r.RequestID)
	switch {
	case err != nil && c.ctx.Err() != nil:
		// The connection is going; its handler lets go of the wait.
	case err != nil:
		// A store that cannot answer counts as "no longer waiting", as it
		// counts as "not paired" at the door: the connection is a stranger
		// again, and a device that still waits takes the wait back by
		// presenting its invite on its next connection.
		c.logger.Error("read the pairing request", "err", err)
		r.Outcome = ""
		s.endWait(r)
	case outcome != "":
		r.Outcome = outcome
		s.endWait(r)
	}
}

// endWait ends the wait on r once r has closed, whoever closed it - an answer,
// a cancel, the sweep, a revocation - and before either side is told. Allowed,
// the device is paired, and its connection is a paired device's: held to
// nothing. Any other way, nothing the connection holds says it will pair any
// more, so it is a stranger again: a place and two minutes, like a newcomer.
func (s *Server) endWait(r store.PairRequest) {
	s.mu.Lock()
	var cut []*client
	var report int
	if holder := s.waits[r.RequestID]; holder != nil {
		s.letGoLocked(holder)
		if r.Outcome != store.OutcomeAllowed {
			cut, report = s.placeUnpairedLocked(holder)
		}
	}
	s.mu.Unlock()
	s.closeToMakeRoom(cut, report)
}

// placeUnpairedLocked makes c the newest unpaired connection, with a deadline
// of its own, and takes the oldest out while there are too many, returning
// them for the caller to close outside the lock. It also returns how many to
// report: everything taken out since the last warning, at most once a minute,
// so that a flood does not flood the log as well. What is not reported yet
// rides on the next warning. Waiting connections are not among the places, so
// a newcomer never pushes one out.
func (s *Server) placeUnpairedLocked(c *client) (cut []*client, report int) {
	// A loop rather than one cut: a cap shrunk while connections were held
	// still comes out at the cap.
	for s.unpaired.Len() > 0 && s.unpaired.Len() >= s.maxUnpaired {
		oldest := s.unpaired.Front().Value.(*client)
		s.letGoLocked(oldest)
		cut = append(cut, oldest)
	}
	c.unpaired = s.unpaired.PushBack(c)
	s.armLocked(c, s.unpairedTimeout)
	if len(cut) > 0 {
		s.unpairedCut += len(cut)
		if now := time.Now(); now.Sub(s.unpairedWarned) >= shedLogInterval {
			report, s.unpairedCut, s.unpairedWarned = s.unpairedCut, 0, now
		}
	}
	return cut, report
}

// closeToMakeRoom closes the connections a newcomer took the places of, and
// reports the count it was handed.
func (s *Server) closeToMakeRoom(cut []*client, report int) {
	for _, old := range cut {
		// Off this goroutine: a close handshake can take seconds, and the
		// newcomer's greeting must not wait on a stranger's goodbye.
		go old.close(websocket.StatusTryAgainLater, "too many unpaired connections")
	}
	if report > 0 {
		// Counts only, like the channel's entry: no key, no address.
		s.logger.Warn("unpaired connections closed to make room", "closed", report)
	}
}

// armLocked gives what c is held to now a deadline d away, in place of any
// earlier one. Every change of hold moves holdGen on, so a timer that fires as
// c moves from one hold to the next - a place to a wait, a wait back to a
// place - finds a newer number and closes nothing.
func (s *Server) armLocked(c *client, d time.Duration) {
	if c.deadline != nil {
		c.deadline.Stop()
	}
	c.holdGen++
	gen := c.holdGen
	c.deadline = time.AfterFunc(d, func() { s.outOfTime(c, gen) })
}

// outOfTime closes c when the hold its deadline was armed for is still the
// one c is held to.
func (s *Server) outOfTime(c *client, gen uint64) {
	s.mu.Lock()
	due := c.holdGen == gen
	if due {
		// Out of the count at once, the way a connection closed to make room
		// is: its close handshake can take seconds, and a place it no longer
		// needs must not push out somebody else meanwhile.
		s.letGoLocked(c)
	}
	s.mu.Unlock()
	if due {
		c.logger.Info("unpaired connection closed: it did not pair in time")
		c.close(websocket.StatusPolicyViolation, "not paired in time")
	}
}

// letGo takes c out of a stranger's limits - its place or its wait, with the
// deadline of either.
func (s *Server) letGo(c *client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.letGoLocked(c)
}

// letGoLocked is letGo with s.mu held. A no-op for a connection held to
// nothing - a paired device's, or one that settled, ran out of time, was taken
// out to make room, or left - beyond moving holdGen on.
func (s *Server) letGoLocked(c *client) {
	if c.unpaired != nil {
		s.unpaired.Remove(c.unpaired)
		c.unpaired = nil
	}
	if c.waitsOn != "" {
		delete(s.waits, c.waitsOn)
		c.waitsOn = ""
	}
	if c.deadline != nil {
		c.deadline.Stop()
		c.deadline = nil
	}
	c.holdGen++
}

package server

import (
	"context"
	"encoding/json"
	"time"

	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// Pairing with approval (046, contract §8A): who is told what about a request
// to join through an invite, and when.
//
//   - device.pairRequested goes to every greeted connection of the device that
//     issued the invite, when a request opens - and again after each greeting
//     of that device, for every request still waiting, because the event does
//     not survive a disconnect.
//   - pair.resolved goes to the new device, on the connections it is waiting
//     on, when the request closes - with the identity when it was allowed.
//     Its reliable half is a repeat of `pair`, which answers with the outcome.
//   - device.pairResolved goes to the issuing device when the request closes,
//     whichever way, so its dialog closes.
//   - device.paired goes to the person's connections when a request is
//     allowed: the set of devices changed.
//
// All four are off-journal (seq 0): who may join the machine is not the shared
// world the journal records, and none of them takes a cursor coordinate.
// Every one is sent AFTER the reply to the command that caused it (§9), and
// collected under the registry lock but sent outside it, like every other
// fan-out here: a full queue under Server.mu would hold up every connection.

// defaultRequestSweep is how often the server looks for requests whose time
// ran out. A request ends without anybody acting (FR-007), and a few seconds
// late is nothing against ten minutes - while an exact timer per request would
// be state to keep in step with the store for no difference anybody sees.
const defaultRequestSweep = 2 * time.Second

type pairRequestedData struct {
	RequestID string `json:"request_id"`
	Platform  string `json:"platform"`
	ExpiresAt int64  `json:"expires_at"`
}

type pairResolvedData struct {
	Outcome string `json:"outcome"`
	// Identity is who the new device now speaks as - only when allowed. The
	// same object the pair reply carries, `created` included (always false
	// here: the person existed, and has a name).
	Identity *identity `json:"identity,omitempty"`
}

type devicePairResolvedData struct {
	RequestID string `json:"request_id"`
}

// offJournal builds an event that is not journal content: seq 0, delivered to
// whoever is connected now and to nobody later.
func offJournal(name string, data any) (protocol.Event, error) {
	raw, err := json.Marshal(data)
	if err != nil {
		return protocol.Event{}, err
	}
	return protocol.Event{Seq: 0, Event: name, Data: raw}, nil
}

// pairRequestedEvent is what the issuing device is shown about a request: the
// new device's OS family and the deadline. No key and no token - the key is a
// stranger's, and the token is a credential wherever it lands.
func pairRequestedEvent(r store.PairRequest) (protocol.Event, error) {
	return offJournal(protocol.EventDevicePairRequested,
		pairRequestedData{RequestID: r.RequestID, Platform: r.Platform, ExpiresAt: r.ExpiresAt})
}

// connectionsWhere collects, under the registry lock, the connections match
// picks, so the frames can be sent outside it. match may read the fields the
// lock guards - greeted and identity.
func (s *Server) connectionsWhere(match func(*client) bool) []*client {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]*client, 0, 1)
	for c := range s.conns {
		if match(c) {
			out = append(out, c)
		}
	}
	return out
}

// sendTo builds one event and queues it on every connection given.
func (s *Server) sendTo(targets []*client, name string, data any) {
	if len(targets) == 0 {
		return
	}
	ev, err := offJournal(name, data)
	if err != nil {
		// Cannot fail for these flat structs; the reliable halves - a repeat of
		// `pair`, a greeting - still carry what the event would have.
		s.logger.Error("marshal pairing event", "event", name, "err", err)
		return
	}
	for _, c := range targets {
		c.sendFrame(ev)
	}
}

// announcePairRequested asks the device that issued the invite to answer a
// request just opened - on every one of its connections that has greeted.
//
// Greeted only: a connection still greeting is handed every waiting request
// right after its reply (resendPairRequests), and it marks itself greeted
// BEFORE it reads them - so a request is either in that read or among the
// connections walked here, never lost between the two.
func (s *Server) announcePairRequested(r store.PairRequest) {
	ev, err := pairRequestedEvent(r)
	if err != nil {
		s.logger.Error("marshal pairing event", "event", protocol.EventDevicePairRequested, "err", err)
		return
	}
	for _, c := range s.connectionsWhere(func(c *client) bool { return c.deviceKey == r.IssuerKey && c.greeted }) {
		c.sendFrame(ev)
	}
}

// announcePairClosed tells both sides a request is over: the new device how it
// ended (id set when it was allowed), the issuing device that it no longer
// waits for an answer.
//
// The log says that it ended and how - never which devices, and never the
// invite: the outcome is all an operator needs to see pairing at work.
func (s *Server) announcePairClosed(r store.PairRequest, id *identity) {
	s.logger.Info("pairing request closed", "outcome", r.Outcome)
	s.tellNewDevice(r, id)
	s.tellIssuer(r)
}

// tellNewDevice sends pair.resolved to the new device's connections that have
// not greeted - the ones waiting on the request. One that greeted already was
// paired by the time it could, and knows.
func (s *Server) tellNewDevice(r store.PairRequest, id *identity) {
	targets := s.connectionsWhere(func(c *client) bool { return c.deviceKey == r.DeviceKey && !c.greeted })
	s.sendTo(targets, protocol.EventPairResolved, pairResolvedData{Outcome: r.Outcome, Identity: id})
}

// tellIssuer sends device.pairResolved to the issuing device's greeted
// connections, so a dialog asking about the request closes on all of them.
func (s *Server) tellIssuer(r store.PairRequest) {
	targets := s.connectionsWhere(func(c *client) bool { return c.deviceKey == r.IssuerKey && c.greeted })
	s.sendTo(targets, protocol.EventDevicePairResolved, devicePairResolvedData{RequestID: r.RequestID})
}

// resendPairRequests hands a connection that has just greeted every request
// still waiting for its device's answer (contract §8A). device.pairRequested
// does not survive a disconnect, so this is its reliable half: a device that
// was offline when the request opened - or whose app was closed - is asked as
// soon as it is back, for as long as the request waits.
//
// Called after markGreeted, which is what keeps it from losing one: see
// announcePairRequested.
func (c *client) resendPairRequests() {
	waiting, err := c.srv.store.WaitingPairRequests(c.ctx, c.deviceKey, time.Now().Unix())
	if err != nil {
		if c.ctx.Err() == nil {
			c.logger.Error("read waiting pairing requests", "err", err)
		}
		return
	}
	for _, r := range waiting {
		ev, err := pairRequestedEvent(r)
		if err != nil {
			c.logger.Error("marshal pairing event", "event", protocol.EventDevicePairRequested, "err", err)
			return
		}
		c.sendFrame(ev)
	}
}

// runRequestSweeper closes the requests whose time ran out and tells both
// sides, without anybody acting (FR-007): a new device whose issuer never
// answered sees the request end, and the issuer's dialog closes.
//
// It sends to connections and writes the database, so it runs on a context of
// its own and stops after the connections drain and before the database closes
// (invariant 9), like the address watcher.
func (s *Server) runRequestSweeper(ctx context.Context) {
	tick := time.NewTicker(s.requestSweep)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		closed, err := s.store.ExpirePairRequests(ctx, time.Now().Unix())
		if err != nil {
			if ctx.Err() == nil {
				s.logger.Error("expire pairing requests", "err", err)
			}
			continue
		}
		for _, r := range closed {
			s.announcePairClosed(r, nil)
		}
	}
}

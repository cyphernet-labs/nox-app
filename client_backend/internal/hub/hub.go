// Package hub owns the set of event subscribers. All interaction goes through
// channels; the Run goroutine is the only code touching the subscriber map
// (CLAUDE.md invariant 7 - this program contains no business mutex).
package hub

import "context"

// subscriberBuffer is the per-subscriber frame buffer. A subscriber whose
// buffer overflows is dropped: replay by seq heals it on reconnect, so
// dropping is safe by design (contract §3).
const subscriberBuffer = 16

// Envelope is one broadcast unit: the same event pre-marshaled in the two
// wire variants of contract §5. Full carries client_message_id and is for
// the author's own connections; Stripped is for everyone else. Events with
// no per-recipient difference set both to the same bytes and AuthorID "".
type Envelope struct {
	AuthorID string
	Full     []byte
	Stripped []byte
}

// FrameFor picks the wire bytes for a recipient identity.
func (e Envelope) FrameFor(id string) []byte {
	if e.AuthorID != "" && e.AuthorID == id {
		return e.Full
	}
	return e.Stripped
}

// Subscriber is one delivery target. C yields broadcast envelopes until the
// hub closes it (drop or unregister).
type Subscriber struct {
	ch      chan Envelope
	dropped func()
}

// NewSubscriber creates a subscriber; dropped fires (from the hub goroutine)
// when the subscriber is evicted for falling behind. It MUST NOT block: the
// hub goroutine calls it inline during fan-out.
func NewSubscriber(dropped func()) *Subscriber {
	return &Subscriber{ch: make(chan Envelope, subscriberBuffer), dropped: dropped}
}

// C is the envelope stream. It is closed by the hub when the subscriber
// leaves.
func (s *Subscriber) C() <-chan Envelope {
	return s.ch
}

// Hub fans broadcast envelopes out to subscribers.
type Hub struct {
	register   chan *Subscriber
	unregister chan *Subscriber
	broadcast  chan Envelope
	done       chan struct{}
}

// New builds a Hub; call Run to start it.
func New() *Hub {
	return &Hub{
		register:   make(chan *Subscriber),
		unregister: make(chan *Subscriber),
		broadcast:  make(chan Envelope),
		done:       make(chan struct{}),
	}
}

// Run owns the subscriber set until ctx is cancelled. On exit every remaining
// subscriber channel is closed.
func (h *Hub) Run(ctx context.Context) {
	defer close(h.done)
	subs := make(map[*Subscriber]struct{})
	defer func() {
		for s := range subs {
			close(s.ch)
		}
	}()

	for {
		select {
		case s := <-h.register:
			subs[s] = struct{}{}
		case s := <-h.unregister:
			if _, ok := subs[s]; ok {
				delete(subs, s)
				close(s.ch)
			}
		case env := <-h.broadcast:
			for s := range subs {
				select {
				case s.ch <- env:
				default:
					delete(subs, s)
					close(s.ch)
					s.dropped()
				}
			}
		case <-ctx.Done():
			return
		}
	}
}

// Register adds a subscriber; a no-op after the hub stopped.
func (h *Hub) Register(s *Subscriber) {
	select {
	case h.register <- s:
	case <-h.done:
	}
}

// Unregister removes a subscriber and closes its channel; a no-op after the
// hub stopped or if already removed.
func (h *Hub) Unregister(s *Subscriber) {
	select {
	case h.unregister <- s:
	case <-h.done:
	}
}

// Broadcast fans an envelope out to every current subscriber. Slow
// subscribers are dropped, never waited on; a no-op after the hub stopped.
func (h *Hub) Broadcast(env Envelope) {
	select {
	case h.broadcast <- env:
	case <-h.done:
	}
}

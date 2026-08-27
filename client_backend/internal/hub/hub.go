// Package hub owns the set of event subscribers. All interaction goes through
// channels; the Run goroutine is the only code touching the subscriber map
// (CLAUDE.md invariant 7 - this program contains no business mutex).
package hub

import "context"

// subscriberBuffer is the per-subscriber frame buffer. A subscriber whose
// buffer overflows is dropped: replay by seq heals it on reconnect, so
// dropping is safe by design (contract §3).
const subscriberBuffer = 16

// Subscriber is one delivery target. C yields broadcast frames until the hub
// closes it (drop or unregister).
type Subscriber struct {
	ch      chan []byte
	dropped func()
}

// NewSubscriber creates a subscriber; dropped fires (from the hub goroutine)
// when the subscriber is evicted for falling behind.
func NewSubscriber(dropped func()) *Subscriber {
	return &Subscriber{ch: make(chan []byte, subscriberBuffer), dropped: dropped}
}

// C is the frame stream. It is closed by the hub when the subscriber leaves.
func (s *Subscriber) C() <-chan []byte {
	return s.ch
}

// Hub fans broadcast frames out to subscribers.
type Hub struct {
	register   chan *Subscriber
	unregister chan *Subscriber
	broadcast  chan []byte
	done       chan struct{}
}

// New builds a Hub; call Run to start it.
func New() *Hub {
	return &Hub{
		register:   make(chan *Subscriber),
		unregister: make(chan *Subscriber),
		broadcast:  make(chan []byte),
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
		case frame := <-h.broadcast:
			for s := range subs {
				select {
				case s.ch <- frame:
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

// Broadcast fans a frame out to every current subscriber. Slow subscribers
// are dropped, never waited on; a no-op after the hub stopped.
func (h *Hub) Broadcast(frame []byte) {
	select {
	case h.broadcast <- frame:
	case <-h.done:
	}
}

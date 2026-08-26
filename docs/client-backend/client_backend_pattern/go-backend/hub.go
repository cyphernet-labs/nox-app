package main

import "context"

// Hub is the in-process fan-out point. The subscriber set is owned
// exclusively by the run goroutine; all interaction goes through the three
// Go channels below. No mutex exists anywhere in this program.
type Hub struct {
	register   chan *subscriber
	unregister chan *subscriber
	broadcast  chan Event
}

type subscriber struct {
	send chan Event
}

func newHub() *Hub {
	return &Hub{
		register:   make(chan *subscriber),
		unregister: make(chan *subscriber),
		broadcast:  make(chan Event, 64),
	}
}

// run must outlive the HTTP server: main stops it only after
// http.Server.Shutdown has returned, so Subscribe/Unsubscribe never block
// against a stopped hub.
func (h *Hub) run(ctx context.Context) {
	subs := make(map[*subscriber]struct{})
	for {
		select {
		case <-ctx.Done():
			for s := range subs {
				close(s.send)
			}
			return

		case s := <-h.register:
			subs[s] = struct{}{}

		case s := <-h.unregister:
			if _, ok := subs[s]; ok {
				delete(subs, s)
				close(s.send)
			}

		case ev := <-h.broadcast:
			for s := range subs {
				select {
				case s.send <- ev:
				default:
					// Slow consumer: its buffer is full. Drop it. Its
					// connection closes, the client reconnects with its
					// last-seen seq and replays what it missed. No event
					// is ever lost; only the live push is interrupted.
					delete(subs, s)
					close(s.send)
				}
			}
		}
	}
}

func (h *Hub) Subscribe() *subscriber {
	s := &subscriber{send: make(chan Event, 64)}
	h.register <- s
	return s
}

func (h *Hub) Unsubscribe(s *subscriber) { h.unregister <- s }

func (h *Hub) Broadcast(ev Event) { h.broadcast <- ev }

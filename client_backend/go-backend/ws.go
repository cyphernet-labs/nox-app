package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/coder/websocket"
)

// GET /ws?since=N
//
// Push-only socket: the server sends Event JSON frames; clients mutate via
// the REST API. Protocol per connection:
//
//  1. subscribe to the hub FIRST,
//  2. then replay events with seq > since from the outbox table,
//  3. then stream live events from the subscription.
//
// Subscribing before the replay query guarantees no event is lost in the
// gap; the cost is possible duplicates at the boundary, so clients MUST
// de-duplicate by seq (ignore any seq <= last seen).
func handleWS(store *Store, hub *Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)

		c, err := websocket.Accept(w, r, &websocket.AcceptOptions{
			// TODO: restrict to your application's origins before exposing
			// beyond localhost/Caddy. Native (non-browser) clients send no
			// Origin header and are accepted regardless.
			OriginPatterns: []string{"*"},
		})
		if err != nil {
			return
		}
		defer c.Close(websocket.StatusInternalError, "server error")

		// We expect no data frames from the client; CloseRead answers
		// control frames and cancels ctx when the peer disappears.
		ctx := c.CloseRead(r.Context())

		sub := hub.Subscribe()
		defer hub.Unsubscribe(sub)

		replay, err := store.EventsSince(ctx, since)
		if err != nil {
			log.Printf("ws replay: %v", err)
			return
		}
		for _, ev := range replay {
			if err := writeEvent(ctx, c, ev); err != nil {
				return
			}
		}

		ping := time.NewTicker(30 * time.Second)
		defer ping.Stop()

		for {
			select {
			case <-ctx.Done():
				c.Close(websocket.StatusNormalClosure, "")
				return

			case ev, ok := <-sub.send:
				if !ok { // dropped by hub (slow) or server shutting down
					c.Close(websocket.StatusTryAgainLater, "resubscribe")
					return
				}
				if err := writeEvent(ctx, c, ev); err != nil {
					return
				}

			case <-ping.C:
				pctx, cancel := context.WithTimeout(ctx, 10*time.Second)
				err := c.Ping(pctx)
				cancel()
				if err != nil {
					return
				}
			}
		}
	}
}

func writeEvent(ctx context.Context, c *websocket.Conn, ev Event) error {
	b, err := json.Marshal(ev)
	if err != nil {
		return err
	}
	wctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return c.Write(wctx, websocket.MessageText, b)
}

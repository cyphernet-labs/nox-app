package server

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"log/slog"
	"sync"
	"time"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

// client is one WebSocket connection. One goroutine reads (the HTTP handler),
// one goroutine writes (writePump); everything outbound goes through out.
type client struct {
	srv    *Server
	conn   *websocket.Conn
	logger *slog.Logger

	ctx    context.Context
	cancel context.CancelFunc

	out chan []byte
	sub *hub.Subscriber

	closeOnce sync.Once

	// Owned by the read goroutine.
	helloDone bool
	// deviceKey is the key this connection authenticated with. Written by the
	// read goroutine and read by ANOTHER connection's goroutine in
	// Server.dropDevice, so both sides go through Server.mu - otherwise it is a
	// data race, and a device revoked while it is greeting keeps a full session
	// because the revoker saw an empty key.
	// challenge is the 32 random bytes this connection handed the device in the
	// greeting. Kept per connection so a signature captured on one connection
	// cannot be replayed on another.
	challenge string
	deviceKey string
	// closeReason accompanies the close sentinel through the write queue.
	closeReason string
	// requestHost is the address this device dialled to get here, from the
	// request's Host header. It is the only address the server knows to be
	// reachable from somewhere other than the machine itself, which is what an
	// invite link needs.
	requestHost string
	// identity is the person this connection speaks as, resolved once during
	// the greeting. label mirrors identity.Label for the chat-creation path,
	// which records a name rather than an id.
	identity store.Identity
	label    string
}

func newClient(srv *Server, conn *websocket.Conn, parent context.Context, logger *slog.Logger) *client {
	ctx, cancel := context.WithCancel(parent)
	return &client{
		srv:    srv,
		conn:   conn,
		logger: logger,
		ctx:    ctx,
		cancel: cancel,
		out:    make(chan []byte, outBuffer),
	}
}

// close terminates the connection exactly once with the given status. The
// close handshake runs BEFORE the context is cancelled: cancelling first
// aborts the pending read, which tears the transport down and the peer sees
// a bare EOF instead of the status code.
func (c *client) close(code websocket.StatusCode, reason string) {
	c.closeOnce.Do(func() {
		_ = c.conn.Close(code, reason)
		c.cancel()
	})
}

// closeAfterFlush queues the close BEHIND the frames already waiting, so they
// reach the wire first.
//
// The writer owns the ordering: draining the channel from here and then closing
// still races the write in flight, and the one frame that must not be lost is
// device.revoked - it is the only way the device learns why it was dropped.
func (c *client) closeAfterFlush(reason string) {
	c.closeReason = reason
	select {
	case c.out <- nil:
	case <-c.ctx.Done():
	}
}

// send queues an outbound frame from the read goroutine (greeting, replies,
// replay), applying backpressure instead of dropping: contract §3 forbids
// losing replay frames, so a long catch-up must slow the sender down, never
// evict the client (ws-rest-patterns §4).
func (c *client) send(frame []byte) {
	select {
	case c.out <- frame:
	case <-c.ctx.Done():
	}
}

func (c *client) sendFrame(frame any) {
	raw, err := protocol.MarshalFrame(frame)
	if err != nil {
		c.logger.Error("marshal outbound frame", "err", err)
		go c.close(websocket.StatusInternalError, "internal error")
		return
	}
	c.send(raw)
}

// enqueueLive queues a live frame without blocking. A full queue marks the
// client as a slow consumer: the connection is dropped (off this goroutine -
// the close handshake can block for seconds) and heals via replay on
// reconnect. Returns false once the client is being dropped.
func (c *client) enqueueLive(frame []byte) bool {
	select {
	case c.out <- frame:
		return true
	case <-c.ctx.Done():
		return false
	default:
		c.logger.Warn("outbound queue overflow, dropping connection")
		go c.close(websocket.StatusPolicyViolation, "slow consumer")
		return false
	}
}

// writePump is the sole writer to the connection: it drains out and keeps the
// connection alive with pings (the read loop consumes the pongs).
func (c *client) writePump() {
	ping := time.NewTicker(c.srv.pingInterval)
	defer ping.Stop()
	for {
		select {
		case frame := <-c.out:
			// A nil frame is the close sentinel: everything queued before it has
			// been written, so the socket can go now. Closing from anywhere else
			// races the frames still in this channel - and the one frame that
			// must never be lost is device.revoked, which is the only way the
			// device learns WHY it was dropped.
			if frame == nil {
				c.close(websocket.StatusNormalClosure, c.closeReason)
				return
			}
			wctx, cancel := context.WithTimeout(c.ctx, c.srv.writeTimeout)
			err := c.conn.Write(wctx, websocket.MessageText, frame)
			cancel()
			if err != nil {
				c.close(websocket.StatusNormalClosure, "write failed")
				return
			}
		case <-ping.C:
			wctx, cancel := context.WithTimeout(c.ctx, c.srv.writeTimeout)
			err := c.conn.Ping(wctx)
			cancel()
			if err != nil {
				c.close(websocket.StatusNormalClosure, "ping failed")
				return
			}
		case <-c.ctx.Done():
			return
		}
	}
}

// forward moves live hub envelopes into the outbound queue. It starts after
// the hello replay is queued, preserving subscribe -> reply -> replay ->
// live. Reading c.identity here is safe: it is written once before this
// goroutine starts and never changes (duplicate hello is rejected).
func (c *client) forward() {
	for {
		select {
		case env, ok := <-c.sub.C():
			if !ok {
				return
			}
			if !c.enqueueLive(env.FrameFor(c.identity.UserID)) {
				return
			}
		case <-c.ctx.Done():
			return
		}
	}
}

func newChallenge() (string, error) {
	var buf [32]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(buf[:]), nil
}

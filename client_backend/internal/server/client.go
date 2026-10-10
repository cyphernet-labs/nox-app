package server

import (
	"context"
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
	// deviceKey is the key this connection PROVED in the channel check, base64
	// as devices.device_key stores it - never a key a command named (044). Set
	// once before the connection joins the registry and never changed, so the
	// goroutines that read it - another connection's dropDevice among them -
	// need no lock: joining the registry under Server.mu publishes it. A
	// device revoked while it is still greeting is therefore found by its key
	// from the first byte, not only once the greeting got far enough to say it.
	deviceKey string
	// closeReason accompanies the close sentinel through the write queue.
	closeReason string
	// requestHost is the address this device dialled to get here, from the
	// request's Host header. It is the only address the server knows to be
	// reachable from somewhere other than the machine itself, which is what an
	// invite link needs.
	requestHost string
	// viaOnion says the connection came in through the onion entry (039). Set
	// once, before the read loop starts, and never changed: a claim is refused
	// on it, its timeouts are the onion ones, and an invite asked for over it
	// takes its direct host from the address list rather than from Host.
	viaOnion bool
	// writeTimeout bounds one frame write and one ping's wait for its pong:
	// the server's for a direct connection, onionTimeout for an onion one.
	// Set once before writePump starts.
	writeTimeout time.Duration
	// greeted and addrVersion belong to the registry (Server.mu): greeted is
	// set once the greeting reply - carrying the address snapshot of
	// addrVersion - is queued, and only then does the watcher send this
	// connection server.addresses. Not helloDone: that one is the read
	// goroutine's own, and it is set BEFORE the reply.
	greeted     bool
	addrVersion uint64
	// identity is the person this connection speaks as, resolved once during
	// the greeting. Written and read through Server.setIdentity /
	// Server.currentIdentity: other connections' goroutines touch it -
	// refreshLabel rewrites the label, and the notify helpers match on the id.
	identity store.Identity
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

// writePump is the sole writer of frames to the connection: it drains out,
// and starts keepAlive beside itself.
func (c *client) writePump() {
	timeout := c.writeTimeout
	if timeout == 0 {
		timeout = c.srv.writeTimeout
	}
	go c.keepAlive(timeout)
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
			wctx, cancel := context.WithTimeout(c.ctx, timeout)
			err := c.conn.Write(wctx, websocket.MessageText, frame)
			cancel()
			if err != nil {
				c.close(websocket.StatusNormalClosure, "write failed")
				return
			}
		case <-c.ctx.Done():
			return
		}
	}
}

// keepAlive pings on its own ticker (the read loop consumes the pongs). It runs
// BESIDE the writer, not in it: Ping waits for the pong - a whole round trip,
// which over Tor is seconds - and a writer parked on that wait lets a burst of
// live frames fill the queue behind it until a healthy connection is dropped
// as a slow consumer. The library allows Ping concurrently with Write; one
// ping is in flight at a time, because the next tick waits for this one.
func (c *client) keepAlive(timeout time.Duration) {
	ping := time.NewTicker(c.srv.pingInterval)
	defer ping.Stop()
	for {
		select {
		case <-ping.C:
			pctx, cancel := context.WithTimeout(c.ctx, timeout)
			err := c.conn.Ping(pctx)
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

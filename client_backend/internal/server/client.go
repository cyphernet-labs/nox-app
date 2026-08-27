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
	label     string
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

// close terminates the connection exactly once with the given status.
func (c *client) close(code websocket.StatusCode, reason string) {
	c.closeOnce.Do(func() {
		c.cancel()
		_ = c.conn.Close(code, reason)
	})
}

// enqueue queues an outbound frame. A full queue marks the client as a slow
// consumer: the connection is dropped and heals via replay on reconnect.
func (c *client) enqueue(frame []byte) {
	select {
	case c.out <- frame:
	case <-c.ctx.Done():
	default:
		c.logger.Warn("outbound queue overflow, dropping connection")
		c.close(websocket.StatusPolicyViolation, "slow consumer")
	}
}

func (c *client) enqueueFrame(frame any) {
	raw, err := protocol.MarshalFrame(frame)
	if err != nil {
		c.logger.Error("marshal outbound frame", "err", err)
		c.close(websocket.StatusInternalError, "internal error")
		return
	}
	c.enqueue(raw)
}

// writePump is the sole writer to the connection: it drains out and keeps the
// connection alive with pings (the read loop consumes the pongs).
func (c *client) writePump() {
	ping := time.NewTicker(c.srv.pingInterval)
	defer ping.Stop()
	for {
		select {
		case frame := <-c.out:
			wctx, cancel := context.WithTimeout(c.ctx, writeTimeout)
			err := c.conn.Write(wctx, websocket.MessageText, frame)
			cancel()
			if err != nil {
				c.close(websocket.StatusNormalClosure, "write failed")
				return
			}
		case <-ping.C:
			wctx, cancel := context.WithTimeout(c.ctx, writeTimeout)
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

// forward moves live hub frames into the outbound queue. It starts after the
// hello replay is enqueued, preserving subscribe -> reply -> replay -> live.
func (c *client) forward() {
	for {
		select {
		case frame, ok := <-c.sub.C():
			if !ok {
				return
			}
			c.enqueue(frame)
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

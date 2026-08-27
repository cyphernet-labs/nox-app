package server

import (
	"errors"
	"net/http"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		s.logger.Warn("websocket accept failed", "err", err)
		return
	}
	conn.SetReadLimit(s.cfg.Limits.MaxFrameBytes)

	logger := s.logger.With("conn", randomConnID())
	c := newClient(s, conn, r.Context(), logger)
	s.track(c)
	defer s.untrack(c)
	defer c.close(websocket.StatusNormalClosure, "")
	defer c.cleanup()

	go c.writePump()

	challenge, err := newChallenge()
	if err != nil {
		logger.Error("challenge generation failed", "err", err)
		c.close(websocket.StatusInternalError, "internal error")
		return
	}
	c.enqueueFrame(protocol.Greeting{Srv: protocol.GreetingBody{
		SchemaMax: protocol.SchemaVersion,
		Challenge: challenge,
	}})

	c.readLoop()
}

// readLoop is the single reader of the connection (library invariant). It
// parses command frames and dispatches them; every parsed command gets
// exactly one reply, even on failure.
func (c *client) readLoop() {
	for {
		_, raw, err := c.conn.Read(c.ctx)
		if err != nil {
			status := websocket.CloseStatus(err)
			if status == -1 && !errors.Is(err, c.ctx.Err()) {
				c.logger.Info("connection read ended", "err", err)
			}
			return
		}

		cmd, err := protocol.ParseCommand(raw)
		if err != nil {
			// An unparseable stream has no id to answer; drop the connection
			// (spec edge case) rather than guess.
			c.logger.Warn("unparseable frame", "err", err)
			c.close(websocket.StatusProtocolError, "unparseable frame")
			return
		}

		c.dispatch(cmd)
	}
}

func (c *client) dispatch(cmd protocol.Command) {
	if !c.helloDone && cmd.Cmd != protocol.CmdSessionHello {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "session.hello must be the first command"))
		return
	}

	switch cmd.Cmd {
	case protocol.CmdSessionHello:
		c.handleSessionHello(cmd)
	case protocol.CmdChatCreate:
		c.handleChatCreate(cmd)
	case protocol.CmdMessageSend:
		c.handleMessageSend(cmd)
	default:
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "unknown command"))
	}
	c.logger.Info("command handled", "cmd", cmd.Cmd, "id", cmd.ID)
}

// cleanup releases hub resources after the read loop ends.
func (c *client) cleanup() {
	c.cancel()
	if c.sub != nil {
		c.srv.hub.Unregister(c.sub)
	}
}

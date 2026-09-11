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
	// Track the hijacked connection so shutdown can wait for it (invariant 9).
	s.wg.Add(1)
	defer s.wg.Done()
	conn.SetReadLimit(s.cfg.Limits.MaxFrameBytes)

	logger := s.logger.With("conn", randomConnID())
	c := newClient(s, conn, r.Context(), logger)
	c.requestHost = r.Host
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
	c.challenge = challenge
	c.sendFrame(protocol.Greeting{Srv: protocol.GreetingBody{
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
			// A JSON object without cmd still has an id to answer - reply
			// invalid_request and keep the connection. Anything that is not
			// even a JSON object has no id; drop the connection (spec edge
			// case) rather than guess.
			if errors.Is(err, protocol.ErrMissingCmd) {
				c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "missing cmd"))
				continue
			}
			c.logger.Warn("unparseable frame", "err", err)
			c.close(websocket.StatusProtocolError, "unparseable frame")
			return
		}

		c.dispatch(cmd)
	}
}

func (c *client) dispatch(cmd protocol.Command) {
	// pair is the ONE exception to "hello first", and not for convenience: an
	// unpaired device has nothing to sign the challenge with, so requiring a
	// greeting first would make pairing impossible rather than awkward.
	if !c.helloDone && cmd.Cmd != protocol.CmdSessionHello && cmd.Cmd != protocol.CmdPair {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "session.hello must be the first command"))
		return
	}

	switch cmd.Cmd {
	case protocol.CmdSessionHello:
		c.handleSessionHello(cmd)
	case protocol.CmdPair:
		c.handlePair(cmd)
	case protocol.CmdDeviceList:
		c.handleDeviceList(cmd)
	case protocol.CmdDeviceRevoke:
		c.handleDeviceRevoke(cmd)
	case protocol.CmdDeviceInvite:
		c.handleDeviceInvite(cmd)
	case protocol.CmdIdentitySetLabel:
		c.handleIdentitySetLabel(cmd)
	case protocol.CmdChatsList:
		c.handleChatsList(cmd)
	case protocol.CmdChatGet:
		c.handleChatGet(cmd)
	case protocol.CmdChatCreate:
		c.handleChatCreate(cmd)
	case protocol.CmdChatRename:
		c.handleChatRename(cmd)
	case protocol.CmdChatNameAvailable:
		c.handleChatNameAvailable(cmd)
	case protocol.CmdChatFiles:
		c.handleChatFiles(cmd)
	case protocol.CmdMessagesList:
		c.handleMessagesList(cmd)
	case protocol.CmdMessageSend:
		c.handleMessageSend(cmd)
	case protocol.CmdFileUploadBegin:
		c.handleFileUploadBegin(cmd)
	case protocol.CmdFileDownloadBegin:
		c.handleFileDownloadBegin(cmd)
	default:
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "unknown command"))
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

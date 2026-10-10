package server

import (
	"errors"
	"net/http"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/protocol"
)

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	peer, ok := channelPeerFrom(r.Context())
	if !ok {
		// Unreachable through Run: the listener hands over only connections
		// that passed the channel check. A handler mounted without it - a
		// wiring mistake, a test mux - must not open a session nobody proved a
		// key for, so it refuses before the upgrade rather than greet a
		// stranger.
		http.Error(w, "the connection proved no device key", http.StatusUnauthorized)
		return
	}
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		// The library's message can quote Host, and a connection through the
		// onion service carries the onion name there (FR-022). Nothing tells
		// such a connection apart any more; the log's handler masks the name
		// in every line (logscrub.go).
		s.logger.Warn("websocket accept failed", "err", err)
		return
	}
	// Track the hijacked connection so shutdown can wait for it (invariant 9).
	s.wg.Add(1)
	defer s.wg.Done()
	conn.SetReadLimit(s.cfg.Limits.MaxFrameBytes)

	logger := s.logger.With("conn", randomConnID())
	c := newClient(s, conn, r.Context(), logger)
	c.deviceKey = peer.deviceKey()
	c.requestHost = r.Host
	s.track(c)
	defer s.untrack(c)
	defer c.close(websocket.StatusNormalClosure, "")
	defer c.cleanup()
	// A stranger's connection is held to a deadline and a cap (unpaired.go).
	// Asked AFTER the connection joined the registry, the way a transfer asks
	// (files.go): a revocation from here on finds it and drops it, so a
	// "paired" read here cannot outlive the device, and a "not paired" one
	// can go stale only by a pairing, which settles it.
	if !s.pairedKey(c) {
		release := s.holdUnpaired(c)
		defer release()
	}

	go c.writePump()

	c.sendFrame(protocol.Greeting{Srv: protocol.GreetingBody{SchemaMax: protocol.SchemaVersion}})

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
	// unpaired device proved a key the server does not know, and its greeting
	// would be refused, so requiring one first would make pairing impossible
	// rather than awkward.
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

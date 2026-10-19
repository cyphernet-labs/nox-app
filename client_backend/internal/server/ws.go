package server

import (
	"context"
	"errors"
	"log/slog"
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
		// The library's message quotes the request's headers - Host among
		// them, an onion name through the onion service (FR-022, masked by
		// logscrub.go) - and a header may be up to a megabyte: cut short. A
		// key nobody paired can make this at the handshake rate, so its line
		// is Debug (as logRequests' is); a paired device's is a Warn.
		level := slog.LevelDebug
		if note, ok := r.Context().Value(requestNoteKey{}).(*requestNote); ok && note.paired {
			level = slog.LevelWarn
		}
		s.logger.Log(r.Context(), level, "websocket accept failed", "err", clipped(err))
		return
	}
	// Track the hijacked connection so shutdown can wait for it (invariant 9).
	s.wg.Add(1)
	defer s.wg.Done()
	conn.SetReadLimit(s.cfg.Limits.MaxFrameBytes)

	logger := s.logger.With("conn", randomConnID())
	c := newClient(s, conn, r.Context(), logger)
	c.deviceKey = peer.deviceKey()
	if cc, ok := channelConnFrom(r.Context()); ok {
		c.transport = cc
	}
	c.requestHost = r.Host
	s.track(c)
	defer s.untrack(c)
	defer c.close(websocket.StatusNormalClosure, "")
	defer c.cleanup()
	// A stranger's connection is held to a deadline and a cap (unpaired.go) -
	// or, while an invite it presented waits for Allow, to that request's own
	// deadline alone (awaitAnswer). The returned release lets go of either.
	// Asked AFTER the connection joined the registry, the way a transfer asks
	// (files.go): a revocation from here on finds it and drops it, so a
	// "paired" read here cannot outlive the device, and a "not paired" one
	// can go stale only by a pairing, which settles it. The door asked too,
	// before the upgrade (limitStrangers), but only to decide whether a refusal
	// ends the connection: this answer is the one the session is held to.
	if !s.pairedKey(c.ctx, c.deviceKey, c.logger) {
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
				c.logger.Log(context.Background(), c.lineLevel(), "connection read ended", "err", err)
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
			// At the connection's level, a Warn only once it greeted, and cut
			// short: the error can quote a frame of up to 128 KiB.
			level := c.lineLevel()
			if level == slog.LevelInfo {
				level = slog.LevelWarn
			}
			c.logger.Log(c.ctx, level, "unparseable frame", "err", clipped(err))
			c.close(websocket.StatusProtocolError, "unparseable frame")
			return
		}

		c.dispatch(cmd)
	}
}

func (c *client) dispatch(cmd protocol.Command) {
	// A revoked device's connection runs nothing more of its own while its
	// goodbye goes out: what a revoked device asks is what an unknown one
	// would be answered (contract §2.1).
	if c.revoked.Load() {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnauthenticated, "device is not paired"))
		return
	}
	// pair and pair.cancel are the exceptions to "hello first", and not for
	// convenience: an unpaired device proved a key the server does not know,
	// and its greeting would be refused, so requiring one first would make
	// pairing impossible rather than awkward - and a device waiting for Allow
	// could not withdraw its request.
	if !c.helloDone && cmd.Cmd != protocol.CmdSessionHello && cmd.Cmd != protocol.CmdPair && cmd.Cmd != protocol.CmdPairCancel {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "session.hello must be the first command"))
		return
	}

	switch cmd.Cmd {
	case protocol.CmdSessionHello:
		c.handleSessionHello(cmd)
	case protocol.CmdPair:
		c.handlePair(cmd)
	case protocol.CmdPairCancel:
		c.handlePairCancel(cmd)
	case protocol.CmdDeviceApprove:
		c.handleDeviceApprove(cmd)
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
	c.logger.Log(c.ctx, c.lineLevel(), "command handled", "cmd", cmd.Cmd, "id", cmd.ID)
}

// clipped is an error's text cut to a length a log line can afford: a
// library's message may quote what the peer sent, whole.
func clipped(err error) string {
	const most = 200
	text := err.Error()
	if len(text) <= most {
		return text
	}
	return text[:most] + "..."
}

// lineLevel is how loud a line about this connection's traffic is: Info for a
// device that greeted, Debug before. A key nobody paired can be minted by
// anyone and its session lasts minutes, so its frames at Info would grow the
// log with the frame rate and push out what an operator needs - the rule
// logRequests keeps for HTTP.
func (c *client) lineLevel() slog.Level {
	if c.helloDone {
		return slog.LevelInfo
	}
	return slog.LevelDebug
}

// cleanup releases hub resources after the read loop ends.
func (c *client) cleanup() {
	c.cancel()
	if c.sub != nil {
		c.srv.hub.Unregister(c.sub)
	}
}

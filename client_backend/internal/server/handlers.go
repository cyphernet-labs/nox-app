package server

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/coder/websocket"

	"nox.app/client-backend/internal/config"
	"nox.app/client-backend/internal/hub"
	"nox.app/client-backend/internal/protocol"
	"nox.app/client-backend/internal/store"
)

const maxChatNameRunes = 64

// helloRequest mirrors contract §3. device_key and signature are accepted and
// ignored on stage 1 (constitution VII: no authentication yet).
type helloRequest struct {
	Schema    int    `json:"schema"`
	Since     *int64 `json:"since"`
	Label     string `json:"label"`
	DeviceKey string `json:"device_key"`
	Signature string `json:"signature"`
}

type helloReply struct {
	Schema   int           `json:"schema"`
	Cursor   int64         `json:"cursor"`
	Limits   config.Limits `json:"limits"`
	Identity identity      `json:"identity"`
}

type identity struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

func (c *client) handleSessionHello(cmd protocol.Command) {
	if c.helloDone {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "session.hello already done"))
		return
	}

	var req helloRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed session.hello data"))
		return
	}
	if req.Schema != protocol.SchemaVersion {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnsupportedSchema,
			fmt.Sprintf("schema %d is not supported, server speaks %d", req.Schema, protocol.SchemaVersion)))
		return
	}

	c.label = strings.TrimSpace(req.Label)
	if c.label == "" {
		c.label = fmt.Sprintf("User%d", c.srv.userSeq.Add(1))
	}

	cursor, err := c.srv.store.Cursor(c.ctx)
	if err != nil {
		c.logger.Error("read cursor", "err", err)
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read cursor"))
		return
	}

	// Subscribe FIRST so nothing published after this point can be lost;
	// then reply, then replay, then live (contract §3, load-bearing order).
	c.sub = hub.NewSubscriber(func() {
		c.logger.Warn("hub dropped slow subscriber")
		c.close(websocket.StatusPolicyViolation, "slow consumer")
	})
	c.srv.hub.Register(c.sub)
	c.helloDone = true

	c.enqueueFrame(protocol.OKReply(cmd.ID, helloReply{
		Schema:   protocol.SchemaVersion,
		Cursor:   cursor,
		Limits:   c.srv.cfg.Limits,
		Identity: identity{ID: c.label, Label: c.label},
	}))

	if req.Since != nil {
		since := *req.Since
		if since > cursor {
			c.logger.Warn("client cursor is ahead of the log", "since", since, "cursor", cursor)
		}
		events, err := c.srv.store.EventsSince(c.ctx, since)
		if err != nil {
			c.logger.Error("replay query failed", "err", err)
			c.close(websocket.StatusInternalError, "replay failed")
			return
		}
		for _, ev := range events {
			c.enqueueFrame(protocol.Event{Seq: ev.Seq, Event: ev.Type, Data: ev.Payload})
		}
		c.logger.Info("replay complete", "since", since, "events", len(events))
	}

	go c.forward()
}

type chatCreateRequest struct {
	Name string `json:"name"`
}

type chatCreateReply struct {
	Chat protocol.Chat `json:"chat"`
}

func (c *client) handleChatCreate(cmd protocol.Command) {
	var req chatCreateRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed chat.create data"))
		return
	}

	name := strings.TrimSpace(req.Name)
	if name == "" || utf8.RuneCountInString(name) > maxChatNameRunes {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			fmt.Sprintf("name must be non-empty and at most %d characters", maxChatNameRunes)))
		return
	}

	chat, event, err := c.srv.store.CreateChat(c.ctx, name, c.label, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrNameTaken):
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrNameTaken, "Chat name already exists"))
		return
	case err != nil:
		c.logger.Error("create chat failed", "err", err)
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to create chat"))
		return
	}

	c.enqueueFrame(protocol.OKReply(cmd.ID, chatCreateReply{Chat: chat}))
	c.srv.broadcastEvent(event)
	c.logger.Info("chat created", "seq", event.Seq)
}

type messageSendRequest struct {
	ChatID          string          `json:"chat_id"`
	ClientMessageID string          `json:"client_message_id"`
	Body            json.RawMessage `json:"body"`
}

type messageSendReply struct {
	Message protocol.Message `json:"message"`
}

func (c *client) handleMessageSend(cmd protocol.Command) {
	var req messageSendRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed message.send data"))
		return
	}
	if req.ChatID == "" || req.ClientMessageID == "" || len(req.Body) == 0 {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"chat_id, client_message_id and body are required"))
		return
	}
	if int64(len(req.Body)) > c.srv.cfg.Limits.MaxMessageBytes {
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrPayloadTooLarge,
			fmt.Sprintf("body exceeds max_message_bytes %d", c.srv.cfg.Limits.MaxMessageBytes)))
		return
	}

	msg, event, created, err := c.srv.store.SendMessage(
		c.ctx, req.ChatID, req.ClientMessageID, c.label, c.label, req.Body, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrChatNotFound):
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "chat does not exist"))
		return
	case err != nil:
		c.logger.Error("send message failed", "err", err)
		c.enqueueFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to send message"))
		return
	}

	c.enqueueFrame(protocol.OKReply(cmd.ID, messageSendReply{Message: msg}))
	if created {
		c.srv.broadcastEvent(event)
		c.logger.Info("message stored", "seq", event.Seq)
	}
}

func (s *Server) broadcastEvent(ev store.StoredEvent) {
	raw, err := protocol.MarshalFrame(protocol.Event{Seq: ev.Seq, Event: ev.Type, Data: ev.Payload})
	if err != nil {
		s.logger.Error("marshal event frame", "err", err, "seq", ev.Seq)
		return
	}
	s.hub.Broadcast(raw)
}

func randomConnID() string {
	var buf [4]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "conn"
	}
	return hex.EncodeToString(buf[:])
}

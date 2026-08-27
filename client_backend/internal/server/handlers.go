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

const (
	maxChatNameRunes = 64
	// maxPageSize is the contract's server-side page cap for both
	// pagination commands; larger requested sizes are silently clamped.
	maxPageSize = 100
)

// validChatName applies the contract §4 name rules and returns the trimmed
// name; every command taking a name goes through it.
func validChatName(raw string) (string, bool) {
	name := strings.TrimSpace(raw)
	return name, name != "" && utf8.RuneCountInString(name) <= maxChatNameRunes
}

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
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "session.hello already done"))
		return
	}

	var req helloRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed session.hello data"))
		return
	}
	if req.Schema != protocol.SchemaVersion {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrUnsupportedSchema,
			fmt.Sprintf("schema %d is not supported, server speaks %d", req.Schema, protocol.SchemaVersion)))
		return
	}

	c.label = strings.TrimSpace(req.Label)
	if c.label == "" {
		c.label = fmt.Sprintf("User%d", c.srv.userSeq.Add(1))
	}

	// Subscribe FIRST, then read the cursor: an event committed between the
	// two lands in the subscriber buffer instead of vanishing (a duplicate at
	// the boundary is fine, a gap is not). Then reply, then replay, then live
	// (contract §3, load-bearing order). The dropped callback must not block
	// the hub goroutine - the close handshake can take seconds.
	c.sub = hub.NewSubscriber(func() {
		c.logger.Warn("hub dropped slow subscriber")
		go c.close(websocket.StatusPolicyViolation, "slow consumer")
	})
	c.srv.hub.Register(c.sub)

	cursor, err := c.srv.store.Cursor(c.ctx)
	if err != nil {
		c.srv.hub.Unregister(c.sub)
		c.sub = nil
		c.logger.Error("read cursor", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to read cursor"))
		return
	}
	c.helloDone = true

	c.sendFrame(protocol.OKReply(cmd.ID, helloReply{
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
			env, err := eventEnvelope(ev)
			if err != nil {
				c.logger.Error("replay marshal failed", "err", err, "seq", ev.Seq)
				c.close(websocket.StatusInternalError, "replay failed")
				return
			}
			c.send(env.FrameFor(c.label))
		}
		c.logger.Info("replay complete", "since", since, "events", len(events))
	}

	go c.forward()
}

type chatCreateRequest struct {
	Name string `json:"name"`
}

// chatReply is the shared {chat: Chat} reply of chat.create / chat.get /
// chat.rename.
type chatReply struct {
	Chat protocol.Chat `json:"chat"`
}

func (c *client) handleChatCreate(cmd protocol.Command) {
	var req chatCreateRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed chat.create data"))
		return
	}

	name, ok := validChatName(req.Name)
	if !ok {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			fmt.Sprintf("name must be non-empty and at most %d characters", maxChatNameRunes)))
		return
	}

	chat, event, err := c.srv.store.CreateChat(c.ctx, name, c.label, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrNameTaken):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNameTaken, "Chat name already exists"))
		return
	case err != nil:
		c.logger.Error("create chat failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to create chat"))
		return
	}

	c.sendFrame(protocol.OKReply(cmd.ID, chatReply{Chat: chat}))
	c.srv.kickDispatcher()
	c.logger.Info("chat created", "seq", event.Seq)
}

type chatsListRequest struct {
	Page     int    `json:"page"`
	PageSize int    `json:"page_size"`
	Query    string `json:"query"`
}

type chatsListReply struct {
	Chats   []protocol.Chat `json:"chats"`
	HasMore bool            `json:"has_more"`
}

func (c *client) handleChatsList(cmd protocol.Command) {
	var req chatsListRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed chats.list data"))
		return
	}
	if req.Page < 1 || req.PageSize < 1 {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "page and page_size must be at least 1"))
		return
	}

	chats, hasMore, err := c.srv.store.ListChats(c.ctx, req.Page, min(req.PageSize, maxPageSize), req.Query)
	if err != nil {
		c.logger.Error("list chats failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list chats"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, chatsListReply{Chats: chats, HasMore: hasMore}))
}

type chatGetRequest struct {
	ChatID string `json:"chat_id"`
}

func (c *client) handleChatGet(cmd protocol.Command) {
	var req chatGetRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil || req.ChatID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "chat_id is required"))
		return
	}

	chat, err := c.srv.store.GetChat(c.ctx, req.ChatID)
	switch {
	case errors.Is(err, store.ErrChatNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "chat does not exist"))
		return
	case err != nil:
		c.logger.Error("get chat failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to get chat"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, chatReply{Chat: chat}))
}

type chatRenameRequest struct {
	ChatID string `json:"chat_id"`
	Name   string `json:"name"`
}

func (c *client) handleChatRename(cmd protocol.Command) {
	var req chatRenameRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil || req.ChatID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "chat_id is required"))
		return
	}
	name, ok := validChatName(req.Name)
	if !ok {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			fmt.Sprintf("name must be non-empty and at most %d characters", maxChatNameRunes)))
		return
	}

	chat, event, changed, err := c.srv.store.RenameChat(c.ctx, req.ChatID, name)
	switch {
	case errors.Is(err, store.ErrChatNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "chat does not exist"))
		return
	case errors.Is(err, store.ErrNameTaken):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNameTaken, "Chat name already exists"))
		return
	case err != nil:
		c.logger.Error("rename chat failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to rename chat"))
		return
	}

	c.sendFrame(protocol.OKReply(cmd.ID, chatReply{Chat: chat}))
	if changed {
		c.srv.kickDispatcher()
		c.logger.Info("chat renamed", "seq", event.Seq)
	}
}

type nameAvailableRequest struct {
	Name          string `json:"name"`
	ExcludeChatID string `json:"exclude_chat_id"`
}

type nameAvailableReply struct {
	Available bool `json:"available"`
}

func (c *client) handleChatNameAvailable(cmd protocol.Command) {
	var req nameAvailableRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed chat.nameAvailable data"))
		return
	}
	name, ok := validChatName(req.Name)
	if !ok {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			fmt.Sprintf("name must be non-empty and at most %d characters", maxChatNameRunes)))
		return
	}

	available, err := c.srv.store.NameAvailable(c.ctx, name, req.ExcludeChatID)
	if err != nil {
		c.logger.Error("name availability check failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to check name"))
		return
	}
	c.sendFrame(protocol.OKReply(cmd.ID, nameAvailableReply{Available: available}))
}

type messagesListRequest struct {
	ChatID    string `json:"chat_id"`
	BeforeSeq int64  `json:"before_seq"`
	Limit     int    `json:"limit"`
}

type messagesListReply struct {
	Messages []protocol.Message `json:"messages"`
	HasMore  bool               `json:"has_more"`
}

func (c *client) handleMessagesList(cmd protocol.Command) {
	var req messagesListRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil || req.ChatID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "chat_id is required"))
		return
	}
	if req.Limit < 1 {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "limit must be at least 1"))
		return
	}

	if _, err := c.srv.store.GetChat(c.ctx, req.ChatID); err != nil {
		if errors.Is(err, store.ErrChatNotFound) {
			c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "chat does not exist"))
			return
		}
		c.logger.Error("list messages failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list messages"))
		return
	}

	messages, hasMore, err := c.srv.store.ListMessages(c.ctx, req.ChatID, req.BeforeSeq, min(req.Limit, maxPageSize))
	if err != nil {
		c.logger.Error("list messages failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to list messages"))
		return
	}
	// Contract §5: client_message_id belongs to the author's own frames only.
	for i := range messages {
		if messages[i].AuthorID != c.label {
			messages[i].ClientMessageID = ""
		}
	}
	c.sendFrame(protocol.OKReply(cmd.ID, messagesListReply{Messages: messages, HasMore: hasMore}))
}

type attachmentRef struct {
	FileID string `json:"file_id"`
}

type messageSendRequest struct {
	ChatID          string          `json:"chat_id"`
	ClientMessageID string          `json:"client_message_id"`
	Body            json.RawMessage `json:"body"`
	Attachment      *attachmentRef  `json:"attachment"`
}

type messageSendReply struct {
	Message protocol.Message `json:"message"`
}

func (c *client) handleMessageSend(cmd protocol.Command) {
	var req messageSendRequest
	if err := json.Unmarshal(cmd.Data, &req); err != nil {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest, "malformed message.send data"))
		return
	}
	if req.ChatID == "" || req.ClientMessageID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"chat_id and client_message_id are required"))
		return
	}
	// Contract §5: at least one of body/attachment (the attachment half of
	// the rule activates in the 024 slice).
	fileID := ""
	if req.Attachment != nil {
		fileID = req.Attachment.FileID
	}
	if len(req.Body) == 0 && fileID == "" {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"at least one of body and attachment is required"))
		return
	}
	if int64(len(req.Body)) > c.srv.cfg.Limits.MaxMessageBytes {
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrPayloadTooLarge,
			fmt.Sprintf("body exceeds max_message_bytes %d", c.srv.cfg.Limits.MaxMessageBytes)))
		return
	}

	msg, event, created, err := c.srv.store.SendMessage(
		c.ctx, req.ChatID, req.ClientMessageID, c.label, c.label, req.Body, fileID, time.Now().Unix())
	switch {
	case errors.Is(err, store.ErrChatNotFound):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrNotFound, "chat does not exist"))
		return
	case errors.Is(err, store.ErrFileNotFound), errors.Is(err, store.ErrFileNotReady), errors.Is(err, store.ErrFileTaken):
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInvalidRequest,
			"attachment file_id must reference an uploaded, unbound file"))
		return
	case err != nil:
		c.logger.Error("send message failed", "err", err)
		c.sendFrame(protocol.ErrReply(cmd.ID, protocol.ErrInternal, "failed to send message"))
		return
	}

	c.sendFrame(protocol.OKReply(cmd.ID, messageSendReply{Message: msg}))
	if created {
		c.srv.kickDispatcher()
		c.logger.Info("message stored", "seq", event.Seq)
	}
}

// eventEnvelope builds the broadcast/replay variants of one stored event.
// message.new is delivered in two shapes (contract §5): the author's copy
// keeps client_message_id, everyone else's copy omits it. Other event types
// are identical for all recipients.
func eventEnvelope(ev store.StoredEvent) (hub.Envelope, error) {
	full, err := protocol.MarshalFrame(protocol.Event{Seq: ev.Seq, Event: ev.Type, Data: ev.Payload})
	if err != nil {
		return hub.Envelope{}, err
	}
	if ev.Type != protocol.EventMessageNew {
		return hub.Envelope{Full: full, Stripped: full}, nil
	}

	var msg protocol.Message
	if err := json.Unmarshal(ev.Payload, &msg); err != nil {
		return hub.Envelope{}, fmt.Errorf("decode message payload seq %d: %w", ev.Seq, err)
	}
	authorID := msg.AuthorID
	msg.ClientMessageID = ""
	strippedPayload, err := json.Marshal(msg)
	if err != nil {
		return hub.Envelope{}, fmt.Errorf("marshal stripped payload seq %d: %w", ev.Seq, err)
	}
	stripped, err := protocol.MarshalFrame(protocol.Event{Seq: ev.Seq, Event: ev.Type, Data: strippedPayload})
	if err != nil {
		return hub.Envelope{}, err
	}
	return hub.Envelope{AuthorID: authorID, Full: full, Stripped: stripped}, nil
}

func randomConnID() string {
	var buf [4]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "conn"
	}
	return hex.EncodeToString(buf[:])
}

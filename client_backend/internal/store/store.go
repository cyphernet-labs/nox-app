// Package store is the only code that reads or writes the database. Every
// mutation inserts its events row in the same immediate transaction
// (transactional outbox, CLAUDE.md invariants 2-4); event payloads are built
// at write time so replay never depends on later state.
package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"nox.app/client-backend/internal/protocol"
)

// Sentinel errors callers branch on.
var (
	ErrNameTaken    = errors.New("chat name already taken")
	ErrChatNotFound = errors.New("chat not found")
)

// StoredEvent is one events row, ready to be framed for delivery or replay.
type StoredEvent struct {
	Seq     int64
	Type    string
	Payload json.RawMessage
}

// Store wraps the two pools. The single-connection write pool plus immediate
// transactions make every write helper fully serialized, so existence checks
// inside a transaction are race-free.
type Store struct {
	read  *sql.DB
	write *sql.DB
}

// New builds a Store over the opened pools.
func New(read, write *sql.DB) *Store {
	return &Store{read: read, write: write}
}

// chatColumns is the single authoritative projection of a chats row onto the
// wire model; every chat read goes through it and scanChat so the commands
// can never drift apart field-wise.
const chatColumns = "chat_id, name, created_at, created_by_label, last_message_preview, last_activity_at"

func scanChat(row interface{ Scan(...any) error }) (protocol.Chat, error) {
	var chat protocol.Chat
	err := row.Scan(&chat.ChatID, &chat.Name, &chat.CreatedAt, &chat.CreatedByLabel,
		&chat.LastMessagePreview, &chat.LastActivityAt)
	if err != nil {
		return protocol.Chat{}, err
	}
	return chat, nil
}

// Cursor returns the current maximum event seq (0 for an empty log).
func (s *Store) Cursor(ctx context.Context) (int64, error) {
	var cursor int64
	err := s.read.QueryRowContext(ctx, "SELECT COALESCE(MAX(seq), 0) FROM events").Scan(&cursor)
	if err != nil {
		return 0, fmt.Errorf("read cursor: %w", err)
	}
	return cursor, nil
}

// EventsSince returns all events with seq > since in ascending order.
func (s *Store) EventsSince(ctx context.Context, since int64) ([]StoredEvent, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT seq, type, payload FROM events WHERE seq > ? ORDER BY seq ASC", since)
	if err != nil {
		return nil, fmt.Errorf("query events since %d: %w", since, err)
	}
	defer func() { _ = rows.Close() }()

	var events []StoredEvent
	for rows.Next() {
		var ev StoredEvent
		var payload string
		if err := rows.Scan(&ev.Seq, &ev.Type, &payload); err != nil {
			return nil, fmt.Errorf("scan event: %w", err)
		}
		ev.Payload = json.RawMessage(payload)
		events = append(events, ev)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate events: %w", err)
	}
	return events, nil
}

// ListChats returns one page of the chat list ordered by last activity
// (newest first, chat_id as the stable tiebreaker) with an optional
// case-insensitive substring filter on the name. Unicode case folding and
// page slicing happen in Go: SQLite's lower()/LIKE fold ASCII only, and the
// table is small by design (research R1/R2). page is 1-based; pageSize must
// arrive validated and clamped by the caller.
func (s *Store) ListChats(ctx context.Context, page, pageSize int, query string) ([]protocol.Chat, bool, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT "+chatColumns+" FROM chats ORDER BY last_activity_at DESC, chat_id ASC")
	if err != nil {
		return nil, false, fmt.Errorf("query chats: %w", err)
	}
	defer func() { _ = rows.Close() }()

	needle := strings.ToLower(strings.TrimSpace(query))
	var matched []protocol.Chat
	for rows.Next() {
		chat, err := scanChat(rows)
		if err != nil {
			return nil, false, fmt.Errorf("scan chat: %w", err)
		}
		if needle != "" && !strings.Contains(strings.ToLower(chat.Name), needle) {
			continue
		}
		matched = append(matched, chat)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterate chats: %w", err)
	}

	start := (page - 1) * pageSize
	if start >= len(matched) {
		return []protocol.Chat{}, false, nil
	}
	end := min(start+pageSize, len(matched))
	return matched[start:end], end < len(matched), nil
}

// GetChat returns one chat card or ErrChatNotFound.
func (s *Store) GetChat(ctx context.Context, chatID string) (protocol.Chat, error) {
	chat, err := scanChat(s.read.QueryRowContext(ctx,
		"SELECT "+chatColumns+" FROM chats WHERE chat_id = ?", chatID))
	if errors.Is(err, sql.ErrNoRows) {
		return protocol.Chat{}, ErrChatNotFound
	}
	if err != nil {
		return protocol.Chat{}, fmt.Errorf("get chat: %w", err)
	}
	return chat, nil
}

// ListMessages returns one backward page of a chat's history: up to limit
// messages with seq below beforeSeq (0 = from the tail), ascending inside
// the page (research R3). hasMore reports whether older messages remain.
// The chat must exist - callers check with GetChat for the not_found reply.
func (s *Store) ListMessages(ctx context.Context, chatID string, beforeSeq int64, limit int) ([]protocol.Message, bool, error) {
	q := "SELECT message_id, seq, chat_id, author_id, author_label, client_message_id, sent_at, body FROM messages WHERE chat_id = ?"
	args := []any{chatID}
	if beforeSeq > 0 {
		q += " AND seq < ?"
		args = append(args, beforeSeq)
	}
	q += " ORDER BY seq DESC LIMIT ?"
	args = append(args, limit+1)

	rows, err := s.read.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, false, fmt.Errorf("query messages: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var newestFirst []protocol.Message
	for rows.Next() {
		var msg protocol.Message
		var body string
		if err := rows.Scan(&msg.MessageID, &msg.Seq, &msg.ChatID, &msg.AuthorID,
			&msg.AuthorLabel, &msg.ClientMessageID, &msg.SentAt, &body); err != nil {
			return nil, false, fmt.Errorf("scan message: %w", err)
		}
		msg.Body = json.RawMessage(body)
		newestFirst = append(newestFirst, msg)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterate messages: %w", err)
	}

	hasMore := len(newestFirst) > limit
	if hasMore {
		newestFirst = newestFirst[:limit]
	}
	page := make([]protocol.Message, 0, len(newestFirst))
	for i := len(newestFirst) - 1; i >= 0; i-- {
		page = append(page, newestFirst[i])
	}
	return page, hasMore, nil
}

// NameAvailable reports whether a chat name is free under the Unicode
// case-insensitive uniqueness rule, optionally ignoring one chat (the rename
// form). Advisory only: the authoritative check lives inside the mutation
// transactions (research R5).
func (s *Store) NameAvailable(ctx context.Context, name, excludeChatID string) (bool, error) {
	q := "SELECT COUNT(1) FROM chats WHERE name_ci = ?"
	args := []any{strings.ToLower(name)}
	if excludeChatID != "" {
		q += " AND chat_id != ?"
		args = append(args, excludeChatID)
	}
	var taken int
	if err := s.read.QueryRowContext(ctx, q, args...).Scan(&taken); err != nil {
		return false, fmt.Errorf("check name availability: %w", err)
	}
	return taken == 0, nil
}

// RenameChat renames a chat and inserts its chat.updated event atomically.
// The name must arrive validated. An exact no-op (the stored name equals the
// new one) returns the current card with changed=false and writes nothing;
// a case-only change is a real rename. last_activity_at is deliberately
// untouched: renaming is not activity (contract §4).
func (s *Store) RenameChat(ctx context.Context, chatID, name string) (protocol.Chat, StoredEvent, bool, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("begin rename chat: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	chat, err := scanChat(tx.QueryRowContext(ctx,
		"SELECT "+chatColumns+" FROM chats WHERE chat_id = ?", chatID))
	if errors.Is(err, sql.ErrNoRows) {
		return protocol.Chat{}, StoredEvent{}, false, ErrChatNotFound
	}
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("read chat: %w", err)
	}
	if chat.Name == name {
		return chat, StoredEvent{}, false, nil
	}

	nameCI := strings.ToLower(name)
	var taken int
	err = tx.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM chats WHERE name_ci = ? AND chat_id != ?", nameCI, chatID).Scan(&taken)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("check chat name: %w", err)
	}
	if taken > 0 {
		return protocol.Chat{}, StoredEvent{}, false, ErrNameTaken
	}

	if _, err := tx.ExecContext(ctx,
		"UPDATE chats SET name = ?, name_ci = ? WHERE chat_id = ?", name, nameCI, chatID); err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("update chat name: %w", err)
	}
	chat.Name = name

	payload, err := json.Marshal(chat)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("marshal chat payload: %w", err)
	}
	res, err := tx.ExecContext(ctx,
		"INSERT INTO events (type, payload) VALUES (?, ?)", protocol.EventChatUpdated, string(payload))
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("insert chat.updated event: %w", err)
	}
	seq, err := res.LastInsertId()
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("event seq: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return protocol.Chat{}, StoredEvent{}, false, fmt.Errorf("commit rename chat: %w", err)
	}
	return chat, StoredEvent{Seq: seq, Type: protocol.EventChatUpdated, Payload: payload}, true, nil
}

// CreateChat inserts a chat and its chat.created event atomically. The name
// must arrive validated (trimmed, non-empty, <=64 runes); uniqueness is
// case-insensitive and returns ErrNameTaken.
func (s *Store) CreateChat(ctx context.Context, name, creatorLabel string, now int64) (protocol.Chat, StoredEvent, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("begin create chat: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// Uniqueness is checked against the Go-lowercased name: SQLite's lower()
	// folds ASCII only, so relying on it would admit non-Latin duplicates.
	nameCI := strings.ToLower(name)
	var taken int
	err = tx.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM chats WHERE name_ci = ?", nameCI).Scan(&taken)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("check chat name: %w", err)
	}
	if taken > 0 {
		return protocol.Chat{}, StoredEvent{}, ErrNameTaken
	}

	chat := protocol.Chat{
		ChatID:         "c_" + randomID(),
		Name:           name,
		CreatedAt:      now,
		CreatedByLabel: creatorLabel,
		LastActivityAt: now,
	}
	_, err = tx.ExecContext(ctx,
		"INSERT INTO chats (chat_id, name, name_ci, created_at, created_by_label, last_activity_at, last_message_preview) VALUES (?, ?, ?, ?, ?, ?, '')",
		chat.ChatID, chat.Name, nameCI, chat.CreatedAt, chat.CreatedByLabel, chat.LastActivityAt)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("insert chat: %w", err)
	}

	payload, err := json.Marshal(chat)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("marshal chat payload: %w", err)
	}
	res, err := tx.ExecContext(ctx,
		"INSERT INTO events (type, payload) VALUES (?, ?)", protocol.EventChatCreated, string(payload))
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("insert chat.created event: %w", err)
	}
	seq, err := res.LastInsertId()
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("event seq: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("commit create chat: %w", err)
	}
	return chat, StoredEvent{Seq: seq, Type: protocol.EventChatCreated, Payload: payload}, nil
}

// SendMessage inserts a message and its message.new event atomically, updates
// the chat's activity and preview, and is idempotent by clientMessageID: a
// replay returns the original message with created=false and no new event.
func (s *Store) SendMessage(ctx context.Context, chatID, clientMessageID, authorID, authorLabel string, body json.RawMessage, now int64) (protocol.Message, StoredEvent, bool, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("begin send message: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	if existing, err := messageByClientID(ctx, tx, clientMessageID); err == nil {
		return existing, StoredEvent{}, false, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("check idempotency: %w", err)
	}

	var chatExists int
	err = tx.QueryRowContext(ctx, "SELECT COUNT(1) FROM chats WHERE chat_id = ?", chatID).Scan(&chatExists)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("check chat: %w", err)
	}
	if chatExists == 0 {
		return protocol.Message{}, StoredEvent{}, false, ErrChatNotFound
	}

	res, err := tx.ExecContext(ctx,
		"INSERT INTO events (type, payload) VALUES (?, '')", protocol.EventMessageNew)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("insert message.new event: %w", err)
	}
	seq, err := res.LastInsertId()
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("event seq: %w", err)
	}

	msg := protocol.Message{
		MessageID:       "m_" + randomID(),
		Seq:             seq,
		ChatID:          chatID,
		AuthorID:        authorID,
		AuthorLabel:     authorLabel,
		ClientMessageID: clientMessageID,
		SentAt:          now,
		Body:            body,
	}
	payload, err := json.Marshal(msg)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("marshal message payload: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		"UPDATE events SET payload = ? WHERE seq = ?", string(payload), seq); err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("fill event payload: %w", err)
	}

	_, err = tx.ExecContext(ctx,
		"INSERT INTO messages (message_id, seq, chat_id, author_id, author_label, client_message_id, sent_at, body) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		msg.MessageID, msg.Seq, msg.ChatID, msg.AuthorID, msg.AuthorLabel, msg.ClientMessageID, msg.SentAt, string(msg.Body))
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("insert message: %w", err)
	}

	_, err = tx.ExecContext(ctx,
		"UPDATE chats SET last_activity_at = ?, last_message_preview = ? WHERE chat_id = ?",
		now, previewFromBody(body), chatID)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("touch chat: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("commit send message: %w", err)
	}
	return msg, StoredEvent{Seq: seq, Type: protocol.EventMessageNew, Payload: payload}, true, nil
}

func messageByClientID(ctx context.Context, tx *sql.Tx, clientMessageID string) (protocol.Message, error) {
	var msg protocol.Message
	var body string
	err := tx.QueryRowContext(ctx,
		"SELECT message_id, seq, chat_id, author_id, author_label, client_message_id, sent_at, body FROM messages WHERE client_message_id = ?",
		clientMessageID,
	).Scan(&msg.MessageID, &msg.Seq, &msg.ChatID, &msg.AuthorID, &msg.AuthorLabel, &msg.ClientMessageID, &msg.SentAt, &body)
	if err != nil {
		return protocol.Message{}, err
	}
	msg.Body = json.RawMessage(body)
	return msg, nil
}

// previewFromBody folds an open-text body into the single-line <=120-rune
// preview of contract §6. Server-side preview exists only while Q1 keeps the
// body open (contract §4); any other body shape yields an empty preview.
func previewFromBody(body json.RawMessage) string {
	var parsed struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil || parsed.Type != "text" {
		return ""
	}
	fields := strings.Fields(parsed.Text)
	folded := strings.Join(fields, " ")
	if utf8.RuneCountInString(folded) <= 120 {
		return folded
	}
	runes := []rune(folded)
	return string(runes[:120])
}

func randomID() string {
	var buf [8]byte
	if _, err := rand.Read(buf[:]); err != nil {
		// crypto/rand failing means the platform RNG is broken; treat as fatal.
		panic(fmt.Sprintf("crypto/rand: %v", err))
	}
	return hex.EncodeToString(buf[:])
}

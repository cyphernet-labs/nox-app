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

// CreateChat inserts a chat and its chat.created event atomically. The name
// must arrive validated (trimmed, non-empty, <=64 runes); uniqueness is
// case-insensitive and returns ErrNameTaken.
func (s *Store) CreateChat(ctx context.Context, name, creatorLabel string, now int64) (protocol.Chat, StoredEvent, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return protocol.Chat{}, StoredEvent{}, fmt.Errorf("begin create chat: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var taken int
	err = tx.QueryRowContext(ctx,
		"SELECT COUNT(1) FROM chats WHERE lower(name) = lower(?)", name).Scan(&taken)
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
		"INSERT INTO chats (chat_id, name, created_at, created_by_label, last_activity_at, last_message_preview) VALUES (?, ?, ?, ?, ?, '')",
		chat.ChatID, chat.Name, chat.CreatedAt, chat.CreatedByLabel, chat.LastActivityAt)
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

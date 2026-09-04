// Package store is the only code that reads or writes the database. Every
// mutation VISIBLE ON THE WIRE AS AN EVENT inserts its events row in the
// same immediate transaction (transactional outbox, CLAUDE.md invariants
// 2-4); event payloads are built at write time so replay never depends on
// later state. The file-metadata lifecycle (upload registration,
// mark-uploaded, orphan sweep) is deliberately event-less: files surface to
// other clients only through message.send. Identity resolution (identity.go)
// is the second deliberate exception: a person or a device coming into being
// is not visible on the wire, so it inserts no events row either.
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
	"unicode"
	"unicode/utf8"

	"nox.app/client-backend/internal/protocol"
)

// Sentinel errors callers branch on.
var (
	ErrNameTaken    = errors.New("chat name already taken")
	ErrChatNotFound = errors.New("chat not found")
	ErrFileNotFound = errors.New("file not found")
	ErrFileNotReady = errors.New("file bytes not uploaded")
	ErrFileTaken    = errors.New("file already bound to a message")
)

// attachmentLifetimeSeconds is the stage-1 "indefinite" retention (owner
// decision, 024 clarifications): expires_at must exist on the wire, so it is
// set ten years out. A real TTL arrives in a later phase.
const attachmentLifetimeSeconds = 10 * 365 * 24 * 3600

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

// foldCase maps every rune to the canonical representative of its Unicode
// simple case-folding orbit. Plain ToLower is a lowercase MAPPING, not a
// folding: pairs like the Greek final sigma vs sigma survive it and would
// slip through both name uniqueness and the search filter.
func foldCase(s string) string {
	return strings.Map(func(r rune) rune {
		least := r
		for f := unicode.SimpleFold(r); f != r; f = unicode.SimpleFold(f) {
			if f < least {
				least = f
			}
		}
		return least
	}, s)
}

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

	needle := foldCase(strings.TrimSpace(query))
	var matched []protocol.Chat
	for rows.Next() {
		chat, err := scanChat(rows)
		if err != nil {
			return nil, false, fmt.Errorf("scan chat: %w", err)
		}
		if needle != "" && !strings.Contains(foldCase(chat.Name), needle) {
			continue
		}
		matched = append(matched, chat)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterate chats: %w", err)
	}

	// Guard BEFORE the multiplication: with an attacker-sized page the
	// product (page-1)*pageSize wraps negative and the slice expression
	// panics. page-1 >= len already means an empty page (pageSize >= 1),
	// and past this guard the product is bounded by len*pageSize.
	if page-1 >= len(matched) {
		return []protocol.Chat{}, false, nil
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
	q := "SELECT " + messageColumns + " FROM messages m LEFT JOIN files f ON m.file_id = f.file_id WHERE m.chat_id = ?"
	args := []any{chatID}
	if beforeSeq > 0 {
		q += " AND m.seq < ?"
		args = append(args, beforeSeq)
	}
	q += " ORDER BY m.seq DESC LIMIT ?"
	args = append(args, limit+1)

	rows, err := s.read.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, false, fmt.Errorf("query messages: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var newestFirst []protocol.Message
	for rows.Next() {
		msg, err := scanMessage(rows)
		if err != nil {
			return nil, false, fmt.Errorf("scan message: %w", err)
		}
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

// FileInfo is one files row: the wire attachment plus lifecycle state.
type FileInfo struct {
	Attachment protocol.Attachment
	Uploaded   bool
	MessageID  string
}

// CreateUpload registers a declared upload and returns its wire attachment.
// Size must arrive validated against the limit by the caller.
func (s *Store) CreateUpload(ctx context.Context, name string, size int64, mime string, now int64) (protocol.Attachment, error) {
	att := protocol.Attachment{
		FileID:    "f_" + randomID(),
		Name:      name,
		Size:      size,
		Mime:      mime,
		ExpiresAt: now + attachmentLifetimeSeconds,
	}
	_, err := s.write.ExecContext(ctx,
		"INSERT INTO files (file_id, name, size, mime, created_at, expires_at, uploaded, message_id) VALUES (?, ?, ?, ?, ?, ?, 0, NULL)",
		att.FileID, att.Name, att.Size, att.Mime, now, att.ExpiresAt)
	if err != nil {
		return protocol.Attachment{}, fmt.Errorf("insert file: %w", err)
	}
	return att, nil
}

// MarkUploaded flips the file to uploaded after its bytes are finalized on
// disk. The disk write happens FIRST: the database never promises bytes
// that do not exist.
func (s *Store) MarkUploaded(ctx context.Context, fileID string) error {
	res, err := s.write.ExecContext(ctx,
		"UPDATE files SET uploaded = 1 WHERE file_id = ? AND uploaded = 0", fileID)
	if err != nil {
		return fmt.Errorf("mark uploaded: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil || n == 0 {
		return fmt.Errorf("mark uploaded %s: %w", fileID, ErrFileNotFound)
	}
	return nil
}

// FileByID returns one files row or ErrFileNotFound.
func (s *Store) FileByID(ctx context.Context, fileID string) (FileInfo, error) {
	var info FileInfo
	var messageID sql.NullString
	err := s.read.QueryRowContext(ctx,
		"SELECT file_id, name, size, mime, expires_at, uploaded, message_id FROM files WHERE file_id = ?", fileID,
	).Scan(&info.Attachment.FileID, &info.Attachment.Name, &info.Attachment.Size,
		&info.Attachment.Mime, &info.Attachment.ExpiresAt, &info.Uploaded, &messageID)
	if errors.Is(err, sql.ErrNoRows) {
		return FileInfo{}, ErrFileNotFound
	}
	if err != nil {
		return FileInfo{}, fmt.Errorf("get file: %w", err)
	}
	info.MessageID = messageID.String
	return info, nil
}

// OrphanFiles lists uploads never bound to a message and declared before
// cutoff - the only garbage under indefinite retention. The caller removes
// the bytes first, then calls DeleteFiles: a crash in between leaves rows
// that the next sweep retries, never bytes without rows.
func (s *Store) OrphanFiles(ctx context.Context, cutoff int64) ([]string, error) {
	rows, err := s.read.QueryContext(ctx,
		"SELECT file_id FROM files WHERE message_id IS NULL AND created_at < ?", cutoff)
	if err != nil {
		return nil, fmt.Errorf("query orphans: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan orphan: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate orphans: %w", err)
	}
	return ids, nil
}

// DeleteFiles removes files rows by id (bytes are already gone).
func (s *Store) DeleteFiles(ctx context.Context, ids []string) error {
	for _, id := range ids {
		if _, err := s.write.ExecContext(ctx, "DELETE FROM files WHERE file_id = ?", id); err != nil {
			return fmt.Errorf("delete file %s: %w", id, err)
		}
	}
	return nil
}

// ChatFileEntry is one chat.files row: the attachment plus its message
// anchor (contract §4).
type ChatFileEntry struct {
	protocol.Attachment
	MessageID string `json:"message_id"`
	Seq       int64  `json:"seq"`
}

// ListChatFiles returns one backward page of a chat's attachments using the
// messages.list pagination rules (023). The chat's existence is checked by
// the caller.
func (s *Store) ListChatFiles(ctx context.Context, chatID string, beforeSeq int64, limit int) ([]ChatFileEntry, bool, error) {
	q := `SELECT m.seq, m.message_id, f.file_id, f.name, f.size, f.mime, f.expires_at
		FROM messages m JOIN files f ON m.file_id = f.file_id WHERE m.chat_id = ?`
	args := []any{chatID}
	if beforeSeq > 0 {
		q += " AND m.seq < ?"
		args = append(args, beforeSeq)
	}
	q += " ORDER BY m.seq DESC LIMIT ?"
	args = append(args, limit+1)

	rows, err := s.read.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, false, fmt.Errorf("query chat files: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var newestFirst []ChatFileEntry
	for rows.Next() {
		var e ChatFileEntry
		if err := rows.Scan(&e.Seq, &e.MessageID, &e.FileID, &e.Name, &e.Size, &e.Mime, &e.ExpiresAt); err != nil {
			return nil, false, fmt.Errorf("scan chat file: %w", err)
		}
		newestFirst = append(newestFirst, e)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterate chat files: %w", err)
	}

	hasMore := len(newestFirst) > limit
	if hasMore {
		newestFirst = newestFirst[:limit]
	}
	page := make([]ChatFileEntry, 0, len(newestFirst))
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
	args := []any{foldCase(name)}
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

	nameCI := foldCase(name)
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

	// Uniqueness is checked against the Go-case-folded name: SQLite's lower()
	// folds ASCII only, so relying on it would admit non-Latin duplicates.
	nameCI := foldCase(name)
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

// SendMessage inserts a message and its message.new event atomically, binds
// the optional attachment file inside the same transaction, updates the
// chat's activity and preview, and is idempotent by clientMessageID: a
// replay returns the original message (attachment included) with
// created=false and no new event. fileID "" means no attachment; validation
// that at least one of body/attachment is present belongs to the caller.
func (s *Store) SendMessage(ctx context.Context, chatID, clientMessageID string, author Identity, body json.RawMessage, fileID string, now int64) (protocol.Message, StoredEvent, bool, error) {
	tx, err := s.write.BeginTx(ctx, nil)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("begin send message: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	if existing, err := messageByClientID(ctx, tx, author.UserID, clientMessageID); err == nil {
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

	// Attachment binding is part of the same transaction: the single-writer
	// pool serializes it, so uploaded/unbound checks are race-free.
	var att *protocol.Attachment
	if fileID != "" {
		var a protocol.Attachment
		var uploaded int
		var boundTo sql.NullString
		err := tx.QueryRowContext(ctx,
			"SELECT file_id, name, size, mime, expires_at, uploaded, message_id FROM files WHERE file_id = ?", fileID,
		).Scan(&a.FileID, &a.Name, &a.Size, &a.Mime, &a.ExpiresAt, &uploaded, &boundTo)
		if errors.Is(err, sql.ErrNoRows) {
			return protocol.Message{}, StoredEvent{}, false, ErrFileNotFound
		}
		if err != nil {
			return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("check file: %w", err)
		}
		if uploaded == 0 {
			return protocol.Message{}, StoredEvent{}, false, ErrFileNotReady
		}
		if boundTo.Valid {
			return protocol.Message{}, StoredEvent{}, false, ErrFileTaken
		}
		att = &a
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
		AuthorID:        author.UserID,
		AuthorLabel:     author.Label,
		ClientMessageID: clientMessageID,
		SentAt:          now,
		Body:            body,
		Attachment:      att,
	}
	payload, err := json.Marshal(msg)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("marshal message payload: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		"UPDATE events SET payload = ? WHERE seq = ?", string(payload), seq); err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("fill event payload: %w", err)
	}

	var fileVal any
	if fileID != "" {
		fileVal = fileID
	}
	_, err = tx.ExecContext(ctx,
		"INSERT INTO messages (message_id, seq, chat_id, author_id, author_label, client_message_id, sent_at, body, file_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
		msg.MessageID, msg.Seq, msg.ChatID, msg.AuthorID, msg.AuthorLabel, msg.ClientMessageID, msg.SentAt, string(msg.Body), fileVal)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("insert message: %w", err)
	}
	if att != nil {
		if _, err := tx.ExecContext(ctx,
			"UPDATE files SET message_id = ? WHERE file_id = ?", msg.MessageID, fileID); err != nil {
			return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("bind file: %w", err)
		}
	}

	attName := ""
	if att != nil {
		attName = att.Name
	}
	_, err = tx.ExecContext(ctx,
		"UPDATE chats SET last_activity_at = ?, last_message_preview = ? WHERE chat_id = ?",
		now, previewFor(body, attName), chatID)
	if err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("touch chat: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return protocol.Message{}, StoredEvent{}, false, fmt.Errorf("commit send message: %w", err)
	}
	return msg, StoredEvent{Seq: seq, Type: protocol.EventMessageNew, Payload: payload}, true, nil
}

// messageColumns joins the optional attachment; every message read shares it.
const messageColumns = `m.message_id, m.seq, m.chat_id, m.author_id, m.author_label,
	m.client_message_id, m.sent_at, m.body, f.file_id, f.name, f.size, f.mime, f.expires_at`

type rowScanner interface{ Scan(...any) error }

func scanMessage(row rowScanner) (protocol.Message, error) {
	var msg protocol.Message
	var body string
	var fID, fName, fMime sql.NullString
	var fSize, fExpires sql.NullInt64
	err := row.Scan(&msg.MessageID, &msg.Seq, &msg.ChatID, &msg.AuthorID, &msg.AuthorLabel,
		&msg.ClientMessageID, &msg.SentAt, &body, &fID, &fName, &fSize, &fMime, &fExpires)
	if err != nil {
		return protocol.Message{}, err
	}
	msg.Body = json.RawMessage(body)
	if fID.Valid {
		msg.Attachment = &protocol.Attachment{
			FileID:    fID.String,
			Name:      fName.String,
			Size:      fSize.Int64,
			Mime:      fMime.String,
			ExpiresAt: fExpires.Int64,
		}
	}
	return msg, nil
}

// messageByClientID keys on the person as well as the send key: idempotency is
// per person, so two people colliding on a key do not collide with each other.
func messageByClientID(ctx context.Context, tx *sql.Tx, authorID, clientMessageID string) (protocol.Message, error) {
	return scanMessage(tx.QueryRowContext(ctx,
		"SELECT "+messageColumns+" FROM messages m LEFT JOIN files f ON m.file_id = f.file_id WHERE m.author_id = ? AND m.client_message_id = ?",
		authorID, clientMessageID))
}

// previewFor folds a message into the single-line <=120-rune preview of
// contract §6: the text body when present, otherwise the attachment's file
// name (one shared formula, so server snapshot and client updates agree).
// Server-side preview exists only while Q1 keeps the body open (contract §4).
func previewFor(body json.RawMessage, fileName string) string {
	var parsed struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(body, &parsed); err == nil && parsed.Type == "text" {
		if folded := foldLine(parsed.Text); folded != "" {
			return folded
		}
	}
	return foldLine(fileName)
}

// foldLine collapses whitespace into one line and truncates to 120 runes.
func foldLine(s string) string {
	folded := strings.Join(strings.Fields(s), " ")
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

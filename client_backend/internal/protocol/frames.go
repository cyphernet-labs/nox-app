// Package protocol defines the v0 wire envelope: the four frame kinds and
// the wire models of the 022 slice. Field names come from
// docs/client-backend/protocol/contract-draft.md verbatim; nothing here may
// deviate from it without a contract edit first.
package protocol

import (
	"encoding/json"
	"errors"
	"fmt"
)

// ErrMissingCmd marks a frame that parsed as a JSON object but carries no
// command name. The frame's id (if any) is still returned, so the caller can
// answer invalid_request instead of dropping the connection.
var ErrMissingCmd = errors.New("missing cmd")

// SchemaVersion is the contract schema this server speaks.
const SchemaVersion = 1

// Greeting is the server frame sent exactly once when a socket opens.
type Greeting struct {
	Srv GreetingBody `json:"srv"`
}

// GreetingBody carries the maximum supported schema and the challenge that
// stage 2 will require clients to sign. Stage 1 sends it but never verifies.
type GreetingBody struct {
	SchemaMax int    `json:"schema_max"`
	Challenge string `json:"challenge"`
}

// Command is an incoming client frame. Data stays raw for two-phase decoding;
// unknown fields inside are ignored by design (v0 evolves).
type Command struct {
	ID   int64           `json:"id"`
	Cmd  string          `json:"cmd"`
	Data json.RawMessage `json:"data"`
}

// Reply answers exactly one Command, correlated by ID.
type Reply struct {
	ID   int64      `json:"id"`
	OK   bool       `json:"ok"`
	Data any        `json:"data,omitempty"`
	Err  *WireError `json:"error,omitempty"`
}

// WireError is the error half of a failed Reply. Code is one of the Err*
// constants from errors.go.
type WireError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Event is a server-pushed frame with the global sequence number that doubles
// as the sync cursor.
type Event struct {
	Seq   int64           `json:"seq"`
	Event string          `json:"event"`
	Data  json.RawMessage `json:"data"`
}

// Event type names of the stage-1 slice.
const (
	EventChatCreated = "chat.created"
	EventChatUpdated = "chat.updated"
	EventMessageNew  = "message.new"
)

// Command names of the stage-1 slice (022 + 023 + 024).
const (
	CmdSessionHello      = "session.hello"
	CmdChatsList         = "chats.list"
	CmdChatGet           = "chat.get"
	CmdChatCreate        = "chat.create"
	CmdChatRename        = "chat.rename"
	CmdChatNameAvailable = "chat.nameAvailable"
	CmdChatFiles         = "chat.files"
	CmdMessagesList      = "messages.list"
	CmdMessageSend       = "message.send"
	CmdFileUploadBegin   = "file.uploadBegin"
	CmdFileDownloadBegin = "file.downloadBegin"
)

// Chat is the wire model of contract §4 (022: preview served but unused by
// any implemented command; it feeds chats.list in phase 023).
type Chat struct {
	ChatID             string `json:"chat_id"`
	Name               string `json:"name"`
	CreatedAt          int64  `json:"created_at"`
	CreatedByLabel     string `json:"created_by_label"`
	LastMessagePreview string `json:"last_message_preview"`
	LastActivityAt     int64  `json:"last_activity_at"`
}

// Attachment is the wire model of contract §5/§7: metadata comes from
// file.uploadBegin, never from the bytes.
type Attachment struct {
	FileID    string `json:"file_id"`
	Name      string `json:"name"`
	Size      int64  `json:"size"`
	Mime      string `json:"mime"`
	ExpiresAt int64  `json:"expires_at"`
}

// Message is the wire model of contract §5.
type Message struct {
	MessageID       string          `json:"message_id"`
	Seq             int64           `json:"seq"`
	ChatID          string          `json:"chat_id"`
	AuthorID        string          `json:"author_id"`
	AuthorLabel     string          `json:"author_label"`
	ClientMessageID string          `json:"client_message_id,omitempty"`
	SentAt          int64           `json:"sent_at"`
	Body            json.RawMessage `json:"body,omitempty"`
	Attachment      *Attachment     `json:"attachment,omitempty"`
}

// MarshalFrame encodes any outbound frame as a single JSON object.
func MarshalFrame(frame any) ([]byte, error) {
	raw, err := json.Marshal(frame)
	if err != nil {
		return nil, fmt.Errorf("marshal frame: %w", err)
	}
	return raw, nil
}

// ParseCommand decodes an incoming frame into a Command. A frame that is not
// a JSON object fails outright; a JSON object without a command name returns
// ErrMissingCmd together with the parsed Command (id preserved) so the caller
// can still answer it. Unknown sibling fields are ignored.
func ParseCommand(raw []byte) (Command, error) {
	var cmd Command
	if err := json.Unmarshal(raw, &cmd); err != nil {
		return Command{}, fmt.Errorf("parse command frame: %w", err)
	}
	if cmd.Cmd == "" {
		return cmd, fmt.Errorf("parse command frame: %w", ErrMissingCmd)
	}
	return cmd, nil
}

// OKReply builds a successful reply for id.
func OKReply(id int64, data any) Reply {
	return Reply{ID: id, OK: true, Data: data}
}

// ErrReply builds a failed reply for id with a contract error code.
func ErrReply(id int64, code, message string) Reply {
	return Reply{ID: id, OK: false, Err: &WireError{Code: code, Message: message}}
}

-- The whole pre-release schema lives in this single migration (owner rule:
-- no deployed databases exist yet, so schema changes edit 001 in place;
-- append-only numbering starts with the first release).

-- name_ci is the Unicode case-folded name computed in Go: SQLite's own
-- lower() folds ASCII only, which would let Cyrillic duplicates through.
CREATE TABLE chats (
    chat_id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(name) > 0),
    name_ci TEXT NOT NULL CHECK (length(name_ci) > 0),
    created_at INTEGER NOT NULL,
    created_by_label TEXT NOT NULL,
    last_activity_at INTEGER NOT NULL,
    last_message_preview TEXT NOT NULL DEFAULT ''
) STRICT;

CREATE UNIQUE INDEX idx_chats_name_ci ON chats (name_ci);

-- Attachment metadata. Bytes live outside the database under file_id in the
-- files directory; name/size/mime come from file.uploadBegin, never from the
-- bytes. expires_at is stage-1 "indefinite" (created_at + 10 years).
CREATE TABLE files (
    file_id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(name) > 0),
    size INTEGER NOT NULL CHECK (size > 0),
    mime TEXT NOT NULL CHECK (length(mime) > 0),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    uploaded INTEGER NOT NULL DEFAULT 0,
    message_id TEXT
) STRICT;

CREATE TABLE messages (
    message_id TEXT PRIMARY KEY,
    seq INTEGER NOT NULL UNIQUE,
    chat_id TEXT NOT NULL REFERENCES chats (chat_id),
    author_id TEXT NOT NULL,
    author_label TEXT NOT NULL,
    client_message_id TEXT NOT NULL UNIQUE,
    sent_at INTEGER NOT NULL,
    body TEXT NOT NULL,
    file_id TEXT REFERENCES files (file_id)
) STRICT;

CREATE INDEX idx_messages_chat_seq ON messages (chat_id, seq);

-- One file belongs to at most one message, forever.
CREATE UNIQUE INDEX idx_messages_file ON messages (file_id) WHERE file_id IS NOT NULL;

CREATE TABLE events (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    payload TEXT NOT NULL
) STRICT;

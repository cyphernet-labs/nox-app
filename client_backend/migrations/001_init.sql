CREATE TABLE chats (
    chat_id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(name) > 0),
    created_at INTEGER NOT NULL,
    created_by_label TEXT NOT NULL,
    last_activity_at INTEGER NOT NULL,
    last_message_preview TEXT NOT NULL DEFAULT ''
) STRICT;

CREATE UNIQUE INDEX idx_chats_name_ci ON chats (lower(name));

CREATE TABLE messages (
    message_id TEXT PRIMARY KEY,
    seq INTEGER NOT NULL UNIQUE,
    chat_id TEXT NOT NULL REFERENCES chats (chat_id),
    author_id TEXT NOT NULL,
    author_label TEXT NOT NULL,
    client_message_id TEXT NOT NULL UNIQUE,
    sent_at INTEGER NOT NULL,
    body TEXT NOT NULL
) STRICT;

CREATE INDEX idx_messages_chat_seq ON messages (chat_id, seq);

CREATE TABLE events (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    payload TEXT NOT NULL
) STRICT;

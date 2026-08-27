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

ALTER TABLE messages ADD COLUMN file_id TEXT REFERENCES files (file_id);

-- One file belongs to at most one message, forever.
CREATE UNIQUE INDEX idx_messages_file ON messages (file_id) WHERE file_id IS NOT NULL;

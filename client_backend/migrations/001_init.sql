-- The whole pre-release schema lives in this single migration (owner rule:
-- no deployed databases exist yet, so schema changes edit 001 in place;
-- append-only numbering starts with the first release).

-- A person. user_id is the PUBLIC author identity carried on the wire as
-- messages.author_id; it is not derived from anything the person holds.
-- id_digest is the one-way derivation of the login identifier computed on the
-- device (contract v0 §3, login_ref): the server keeps it as an OPAQUE lookup
-- key, never computes it and never reverses it. NULL means the connection
-- presented none (hand tools, the live probe) - such a person is created on
-- first use and never found again, so the partial index leaves those rows out
-- of uniqueness.
-- Emptiness is tested with <> '' rather than length() > 0: SQLite's length()
-- on TEXT stops at the first NUL, so length(char(0)) is 0 and a value whose
-- first byte is NUL would be rejected as empty. The contract forbids refusing
-- a greeting over the content of a name or a lookup key.
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    label TEXT NOT NULL CHECK (label <> ''),
    id_digest TEXT CHECK (id_digest IS NULL OR id_digest <> ''),
    created_at INTEGER NOT NULL
) STRICT;

CREATE UNIQUE INDEX idx_users_id_digest ON users (id_digest) WHERE id_digest IS NOT NULL;

-- One app installation. device_key is the opaque per-install id presented in
-- session.hello; stage 1 records it and proves nothing (stage 2 turns the same
-- field into a real public key and starts verifying the signature). A device
-- belongs to exactly one person and is re-bound to whichever person the
-- connection presents; created_at survives the re-binding, last_seen_at always
-- moves.
CREATE TABLE devices (
    device_key TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users (user_id),
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL
) STRICT;

CREATE INDEX idx_devices_user ON devices (user_id);

-- The identity of this store, minted in Go once the schema exists. A client
-- that sees a different value knows the world it cached is gone and resets;
-- a rebuilt store that has already overtaken the client's mark is otherwise
-- indistinguishable from the greeting alone. Exactly one row.
CREATE TABLE journal (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    journal_id TEXT NOT NULL CHECK (journal_id <> '')
) STRICT;

-- name_ci is the Unicode case-folded name computed in Go: SQLite's own
-- lower() folds ASCII only, which would let Cyrillic duplicates through.
CREATE TABLE chats (
    chat_id TEXT PRIMARY KEY,
    name TEXT NOT NULL CHECK (name <> ''),
    name_ci TEXT NOT NULL CHECK (name_ci <> ''),
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
    name TEXT NOT NULL CHECK (name <> ''),
    size INTEGER NOT NULL CHECK (size > 0),
    mime TEXT NOT NULL CHECK (mime <> ''),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    uploaded INTEGER NOT NULL DEFAULT 0,
    message_id TEXT
) STRICT;

-- author_id names the person; author_label is a frozen copy of that person's
-- label at send time and deliberately does NOT follow a later rename, so the
-- history shows the name that was in use then.
CREATE TABLE messages (
    message_id TEXT PRIMARY KEY,
    seq INTEGER NOT NULL UNIQUE,
    chat_id TEXT NOT NULL REFERENCES chats (chat_id),
    author_id TEXT NOT NULL REFERENCES users (user_id),
    author_label TEXT NOT NULL,
    client_message_id TEXT NOT NULL,
    sent_at INTEGER NOT NULL,
    body TEXT NOT NULL,
    file_id TEXT REFERENCES files (file_id)
) STRICT;

-- Idempotency is per person: two people colliding on a send key must not
-- collide with each other.
CREATE UNIQUE INDEX idx_messages_cmid ON messages (author_id, client_message_id);

CREATE INDEX idx_messages_chat_seq ON messages (chat_id, seq);

-- One file belongs to at most one message, forever.
CREATE UNIQUE INDEX idx_messages_file ON messages (file_id) WHERE file_id IS NOT NULL;

CREATE TABLE events (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    payload TEXT NOT NULL
) STRICT;

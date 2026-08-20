-- STRICT: the engine enforces column types (SQLite >= 3.37).
CREATE TABLE notes (
    id         INTEGER PRIMARY KEY,
    title      TEXT    NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
    body       TEXT    NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
) STRICT;

-- Transactional outbox. AUTOINCREMENT guarantees seq values are never
-- reused, so "seq" is a strictly increasing total order over all writes
-- (there is exactly one writer). Clients replay with: seq > last_seen.
CREATE TABLE events (
    seq        INTEGER PRIMARY KEY AUTOINCREMENT,
    type       TEXT    NOT NULL,
    entity     TEXT    NOT NULL,
    entity_id  INTEGER NOT NULL,
    payload    TEXT    NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
) STRICT;

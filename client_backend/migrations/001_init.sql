-- The whole pre-release schema lives in this single migration (owner rule:
-- no deployed databases exist yet, so schema changes edit 001 in place;
-- append-only numbering starts with the first release).

-- A person. user_id is the PUBLIC author identity carried on the wire as
-- messages.author_id; it is not derived from anything the person holds.
-- There is no lookup key here on purpose: a person is found through the
-- PUBLIC KEY of whichever device connected (devices.device_key). The login
-- identifier that stage 1 hashed into id_digest does not exist any more -
-- pairing replaced presenting a secret with proving possession of a key.
-- Emptiness is tested with <> '' rather than length() > 0: SQLite's length()
-- on TEXT stops at the first NUL, so length(char(0)) is 0 and a value whose
-- first byte is NUL would be rejected as empty. The contract forbids refusing
-- a greeting over the content of a name.
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    label TEXT NOT NULL CHECK (label <> ''),
    created_at INTEGER NOT NULL
) STRICT;

-- One app installation, and the key that authorises it. device_key is the
-- device's Ed25519 PUBLIC key in base64: the private half is generated on the
-- device and never leaves it, so a row here authorises nothing on its own -
-- the connection has to sign the challenge with the matching private key.
--
-- Revocation DELETES the row rather than marking it. A third state would have
-- to be remembered at every lookup, while deletion buys the property the
-- client actually needs for free: a revoked device is indistinguishable from
-- an unknown one, which is also exactly what a rebuilt server looks like, and
-- both mean "this is not my server any more".
--
-- platform is the OS family and nothing more - enough to recognise one's own
-- tablet among three, while the exact hardware model would be a fingerprint.
CREATE TABLE devices (
    device_key TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users (user_id),
    platform TEXT NOT NULL CHECK (platform <> ''),
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

-- The server's own long-lived identity, and the state machine of ownership.
-- The private key lives HERE, inside the database file, rather than beside it:
-- the authentication model warns that a backup holding only the DB breaks
-- pinning for every paired device at once, and one artifact makes that
-- outcome impossible by construction. Whoever can read this file has already
-- read every message in every chat, so the key adds no new class of exposure,
-- while a key forgotten during a backup adds a new class of loss.
--
-- claimed_at IS the state machine: NULL means nobody owns this server yet and
-- only claim tokens are accepted; once set, claim is dead forever. A separate
-- state column could disagree with this one; a derived state cannot.
CREATE TABLE server_identity (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    public_key TEXT NOT NULL CHECK (public_key <> ''),
    private_key TEXT NOT NULL CHECK (private_key <> ''),
    claimed_at INTEGER
) STRICT;

-- One-shot pairing tokens. kind is known to the server and NEVER travels in
-- the link: the presenter cannot tell a claim from a device invite, and does
-- not need to.
--
-- Spent through used_at rather than by deleting the row, for two reasons.
-- Burning is then an atomic UPDATE ... WHERE used_at IS NULL whose affected-row
-- count settles a race between two simultaneous presentations - exactly one
-- wins - and the server keeps the difference between "never existed" and
-- "already spent" in its own records, even though the wire says invalid_token
-- for both.
--
-- expires_at IS NULL means the token does not expire, and that is the claim
-- token's deliberate shape: it dies by being used, only someone with access to
-- the machine ever sees it, and an expiring claim would leave a freshly
-- installed server unclaimable forever. Device invites carry a real deadline.
CREATE TABLE pair_tokens (
    token TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('claim', 'invite_device')),
    user_id TEXT REFERENCES users (user_id),
    created_at INTEGER NOT NULL,
    expires_at INTEGER,
    used_at INTEGER
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

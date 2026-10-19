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

-- Exactly one person, enforced rather than assumed. A unique index over a
-- CONSTANT admits a single row: the second insert collides with the first no
-- matter what its user_id is.
--
-- This machine belongs to ONE human being (feature 037). Talking to other
-- people goes through a relay, and their servers never become rows here.
-- Without the index the rule would live only in the fact that nothing but the
-- first pairing through a machine link inserts a person, which holds until the
-- next command is written - and an invariant that depends on nobody adding
-- code is not an invariant.
CREATE UNIQUE INDEX idx_users_singleton ON users ((1));

-- One app installation, and the key that authorises it. device_key is the
-- device's Ed25519 PUBLIC key in base64: the private half is generated on the
-- device and never leaves it, so a row here authorises nothing on its own -
-- every connection proves the matching private key in the channel check,
-- signing that TLS session's binding, before its first byte of HTTP.
--
-- Revocation DELETES the row rather than marking it. A third state would have
-- to be remembered at every lookup, while deletion buys the property the
-- client actually needs for free: a revoked device is indistinguishable from
-- an unknown one, which is also exactly what a rebuilt server looks like, and
-- both mean "this is not my server any more".
--
-- platform is the OS family and nothing more - enough to recognise one's own
-- tablet among three, while the exact hardware model would be a fingerprint.
--
-- There is no onion access key here any more (045): the onion address is open
-- to whoever knows it, and what lets a connection in is the channel check and
-- this row - the same on every path.
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

-- The server's own long-lived identity: the machine's Ed25519 key, base64 -
-- the 32-byte public key the pairing link carries, and the 32-byte SEED it
-- follows from. The server proves this key in every channel check; TLS never
-- sees it. The private key lives HERE, inside the database file, rather than
-- beside it: the authentication model warns that a backup holding only the DB
-- locks out every paired device at once, and one artifact makes that outcome
-- impossible by construction. Whoever can read this file has already read every
-- message in every chat, so the key adds no new class of exposure, while a key
-- forgotten during a backup adds a new class of loss.
--
-- There is no owner here any more (046). The machine holds one person, and
-- "nobody has paired yet" and "every device is gone" are both answered by the
-- device count: the machine link pairs a device in either case, creating the
-- person when there is nobody and joining them when there is.
--
-- public_address and onion_address (045) are where this machine can be
-- reached besides the addresses it finds on its own networks: a public
-- host:port, and the <56 characters>.onion address of the onion service a
-- SEPARATE tor publishes for it. NULL means not set. They are addresses, not
-- identities - trust rests on the machine's key, which the channel check
-- proves on every connection whatever address it came in on - so they live
-- here and nowhere else: no settings file to lose in a backup, and the service
-- page changes them without a restart. The onion service's key is not here:
-- it is tor's, in tor's own directory.
--
-- public_address_param and onion_address_param are the start parameter each
-- address was last written from (-public-addr, -onion-addr), NULL while none
-- ever was. A parameter overwrites the address only when it differs from this,
-- so an address set on the service page survives a restart with the same
-- parameter still in the unit file. A parameter that was refused is not
-- recorded, which is what makes its warning repeat until it is fixed.
CREATE TABLE server_identity (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    public_key TEXT NOT NULL CHECK (public_key <> ''),
    private_key TEXT NOT NULL CHECK (private_key <> ''),
    public_address TEXT CHECK (public_address IS NULL OR public_address <> ''),
    onion_address TEXT CHECK (onion_address IS NULL OR onion_address <> ''),
    public_address_param TEXT CHECK (public_address_param IS NULL OR public_address_param <> ''),
    onion_address_param TEXT CHECK (onion_address_param IS NULL OR onion_address_param <> '')
) STRICT;

-- One-shot pairing tokens, of two kinds (046). kind is known to the server and
-- NEVER travels in the link: the presenter cannot tell one from the other, and
-- does not need to - the server finds the token by its value.
--
--   * 'machine' - the machine link, handed out on the service page and by
--     `noxd link`. It pairs at once: it creates the person when there is
--     nobody, and joins them when there is. At most one is unspent at any
--     time: issuing one spends every earlier unspent one in the same
--     transaction. user_id and issuer_key are NULL.
--   * 'invite_device' - an invite issued by a paired device (issuer_key, the
--     person it belongs to in user_id). Presenting it opens a request in
--     pair_requests, and the token is spent when that request is closed.
--
-- Both live ten minutes: expires_at is never NULL. A link that does not
-- expire would be a standing way in for whoever kept a copy, and with pairing
-- possible through the onion service from anywhere, a copy is a real risk.
-- Nobody is locked out by the deadline: the machine link can always be issued
-- again on the machine itself.
--
-- Spent through used_at rather than by deleting the row, for two reasons.
-- Burning is then an atomic UPDATE ... WHERE used_at IS NULL whose affected-row
-- count settles a race between two simultaneous presentations - exactly one
-- wins - and the server keeps the difference between "never existed" and
-- "already spent" in its own records, even though the wire says invalid_token
-- for both. used_at is also how a token is VOIDED without being presented: a
-- newer machine link, a revoked issuer, and the last device going away (for a
-- machine link that already ran out) all set it.
--
-- used_by, paired_user_id and created_person record WHO spent the token and
-- WHAT the spending did, so that replaying a spent token can answer with what
-- actually happened instead of re-deriving it:
--   * without used_by, any device key - a PUBLIC value - could present a spent
--     token and be told that person's id and label,
--   * without created_person, a replay re-derives the outcome from the token
--     kind, so a machine link that joined an existing person answers "created"
--     the second time and walks them back through the naming screen,
--   * without paired_user_id, a replay re-derives the PERSON from the device's
--     current binding, so a key that has since been re-paired is answered
--     about whoever holds it now rather than whoever the token produced.
-- A token spent by a request that was NOT allowed has used_by set and
-- paired_user_id NULL: it produced nobody, and its replay finds nobody.
CREATE TABLE pair_tokens (
    token TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN ('machine', 'invite_device')),
    user_id TEXT REFERENCES users (user_id),
    issuer_key TEXT CHECK (issuer_key IS NULL OR issuer_key <> ''),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    used_at INTEGER,
    used_by TEXT,
    paired_user_id TEXT REFERENCES users (user_id),
    created_person INTEGER NOT NULL DEFAULT 0,
    CHECK ((kind = 'machine') = (issuer_key IS NULL)),
    CHECK ((kind = 'machine') = (user_id IS NULL))
) STRICT;

-- The unspent tokens are the ones every lookup asks about: the live machine
-- link, and the invites a revoked device leaves behind.
CREATE INDEX idx_pair_tokens_unspent ON pair_tokens (kind, issuer_key) WHERE used_at IS NULL;

-- A new device's request to join through an invite (046). It waits until the
-- device that issued the invite answers Allow or Deny, the new device cancels,
-- or the invite's ten minutes run out - and nothing is paired before Allow.
--
-- token is UNIQUE: an invite has ONE request. The device that opened it
-- (device_key, the key its channel proved) is the only one that may present
-- the token again, and gets the same request back; any other key is refused.
--
-- outcome NULL means waiting. A closed request never changes again, and
-- closing it spends the token in the same transaction whatever the outcome:
--   * 'allowed'   - device.approve with allow, and the device row is written
--                   in that same transaction,
--   * 'denied'    - device.approve without allow, or the issuer revoked,
--   * 'expired'   - the deadline passed, closed by the server on its own,
--   * 'cancelled' - pair.cancel from the new device.
--
-- issuer_key is NOT a foreign key on purpose: revoking the issuer deletes its
-- device row, and the request it leaves behind - closed as denied - is the
-- record of what happened. platform is the new device's OS family, the one
-- thing the issuer is shown about it.
CREATE TABLE pair_requests (
    request_id TEXT PRIMARY KEY CHECK (request_id <> ''),
    token TEXT NOT NULL UNIQUE REFERENCES pair_tokens (token),
    device_key TEXT NOT NULL CHECK (device_key <> ''),
    platform TEXT NOT NULL CHECK (platform <> ''),
    issuer_key TEXT NOT NULL CHECK (issuer_key <> ''),
    expires_at INTEGER NOT NULL,
    outcome TEXT CHECK (outcome IS NULL OR outcome IN ('allowed', 'denied', 'expired', 'cancelled')),
    decided_at INTEGER,
    CHECK ((outcome IS NULL) = (decided_at IS NULL))
) STRICT;

-- The waiting requests are what the expiry sweep and the greeting re-send ask
-- for; closed ones are history nobody looks up by deadline.
CREATE INDEX idx_pair_requests_waiting ON pair_requests (expires_at) WHERE outcome IS NULL;

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

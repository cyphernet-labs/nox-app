/// Own-message delivery status (5.2) — the single source of truth (domain). There
/// is no delivered/read in an open shared space (no fixed recipient); a non-own
/// message is always [none]. The message bubble widget re-exports this enum.
enum MessageStatus { none, pending, sent, error }

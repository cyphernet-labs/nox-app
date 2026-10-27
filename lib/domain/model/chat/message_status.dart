/// Own-message delivery status (5.2) — the single source of truth (domain).
/// There is no delivered/read: the message is accepted by this person's OWN
/// server, and there is nobody else to deliver it to until a relay exists. A
/// non-own message is always [none]. The message bubble widget re-exports this
/// enum.
enum MessageStatus { none, pending, sent, error }

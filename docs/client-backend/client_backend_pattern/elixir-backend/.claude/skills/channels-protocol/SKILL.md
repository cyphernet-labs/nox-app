---
name: channels-protocol
description: The realtime wire contract of this backend (Phoenix Channels over WebSockets). Consult this skill whenever the task touches endpoint.ex socket mount, user_socket.ex, events_channel.ex, changes event payloads or types, involves client synchronization, reconnect, replay, "missed events", "duplicate events", offline catch-up, client SDK integration (JS/Swift/Kotlin/Dart), or pruning/cleanup of the events table.
---

# Channels protocol

## Wire contract (stable; changing it breaks all clients)

- Transport: Phoenix Channels v2 over WebSocket at
  `ws://host/ws/websocket?vsn=2.0.0`; frames are JSON arrays
  `[join_ref, ref, topic, event, payload]`. Client libraries implement
  framing, heartbeats, and reconnection: `phoenix` (npm, first-party),
  `phoenix_socket` (Dart), `SwiftPhoenixClient`, `JavaPhoenixClient`
  (community — verify maintenance before adopting a new one).
- Topic: `"events:all"`, joined with `%{"last_seq" => N}` (0 initially).
- Server → client push event name: `"event"`, payload:
  `{"seq","type","entity","entity_id","payload","created_at"}` —
  identical to the sibling Go project's frames.
- Mutations go over REST; the socket is push-only by convention.
- REST catch-up fallback: `GET /api/events?since=N`.

## Semantics clients MUST implement

1. Persist the highest processed `seq` durably; rejoin with it as
   `last_seq` (the client library's channel rejoin params).
2. De-duplicate: ignore any push with `seq <= last processed` —
   duplicates at the replay/live boundary are BY DESIGN.
3. Apply events in `seq` order.

## Server-side rules when modifying the channel layer

- Preserve the replay order in `EventsChannel`: PubSub subscription is
  active when `join/3` returns; replay runs afterwards from the
  self-sent `{:replay, last_seq}` message. Loss impossible, duplicates
  possible. Do not move the replay into `join/3`'s body and do not
  query before returning `{:ok, socket}`.
- `UserSocket.connect/3` is the ONLY authentication point for the
  socket; per-topic authorization belongs in `join/3` (return
  `{:error, reason}` to reject). Do not authenticate inside event
  handlers.
- Broadcasts originate ONLY from the context's `push_event/1` after a
  committed transaction (CLAUDE.md invariant 4). Never
  `Endpoint.broadcast` from controllers or channels.
- New `Event` fields must be additive; never rename or repurpose
  existing fields. Keep frames identical to the Go project if both
  backends are maintained.
- Slow clients: Phoenix disconnects on transport backpressure /
  heartbeat timeout; the client recovers via rejoin + replay. Do not
  add server-side buffering per client.

## Pruning the events table (currently deliberately absent)

Requires a policy first: retain at least the maximum tolerated client
offline window; and define the resync signal for a client whose
`last_seq` predates the oldest retained row — reply to join with a
distinct payload (e.g. `%{"resync" => true, "current_seq" => max}`),
after which the client refetches entities via REST and resets its seq
(`SELECT COALESCE(MAX(seq),0) FROM events`). Implement the signal
before implementing any deletion; never leave a silent gap.

---
name: event-protocol
description: The WebSocket/event wire contract of this backend. Consult this skill whenever the task touches ws.go or hub.go, changes event payloads or types, involves client synchronization, reconnect, replay, "missed events", "duplicate events", offline catch-up, or pruning/cleanup of the events table — and when writing or reviewing ANY client code that consumes /ws or /api/events.
---

# Event protocol

## Wire contract (stable; changing it is a breaking change for all clients)

- Connect: `GET /ws?since=N` (N = highest `seq` the client has
  processed; 0 initially). Push-only: server → client JSON text frames,
  one event per frame; clients mutate via REST.
- Frame: `{"seq","type","entity","entity_id","payload","created_at"}`.
- REST fallback / catch-up poll: `GET /api/events?since=N` returns the
  same rows.
- Server pings every 30 s; a client that cannot keep up is disconnected
  (hub drops slow consumers) and must reconnect.

## Semantics clients MUST implement (put this in client-facing docs/code)

1. Persist the highest processed `seq` durably.
2. Reconnect with exponential backoff, passing `?since=<that seq>`.
3. De-duplicate: ignore any frame with `seq <= last processed`.
   Duplicates at the replay/live boundary are BY DESIGN (server
   subscribes before replaying so nothing is lost).
4. Apply events in `seq` order; frames arrive ordered per connection.

## Server-side rules when modifying ws.go / hub.go

- Preserve the order: `hub.Subscribe()` FIRST, then `EventsSince`,
  then the stream loop. Reversing it silently loses events committed in
  the gap.
- The hub must never block on a subscriber: the buffered-send /
  drop-on-full behavior is load-shedding, correct because replay
  restores state. Do not "fix" it with unbounded buffers or per-client
  goroutine sends that hide backpressure.
- Any new field in `Event` must be additive (clients ignore unknown
  fields); never rename or repurpose existing fields.

## Pruning the events table (currently deliberately absent)

Safe pruning requires a policy first: delete only rows older than the
maximum tolerated client offline window (e.g. 30 days), AND handle the
client whose `since` predates the oldest retained seq — respond by
signaling "resync required" (client refetches entities via REST and
resets its seq to the current max, obtainable via
`SELECT COALESCE(MAX(seq),0) FROM events`). Implement the signal before
implementing the deletion. Never prune in a way that leaves a silent
gap.

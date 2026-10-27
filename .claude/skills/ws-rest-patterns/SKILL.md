---
name: ws-rest-patterns
description: The deep pattern catalog for WebSocket and REST work in client_backend (Go) — connection lifecycle with code sketches, read loop / write pump / ping, hub internals, envelope dispatch, replay ordering, graceful shutdown of hijacked conns, stdlib middleware, upload/download handlers, and testing recipes. Load when implementing or debugging anything on the /ws channel or the REST surface; add-command covers the per-command checklist, this covers the runtime machinery around it.
user-invocable: true
---

# WebSocket & REST patterns — client_backend

Distilled from verified sources (coder/websocket docs and its chat example, gotify's
stream package, ntfy's dispatch, net/http docs, Aug 2026). Sketches are the shape to
follow, not paste-ready code — adapt names to `internal/`.

## 1. Connection lifecycle (one goroutine reads, one writes)

```go
func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
    conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
        // dev: loopback only; origins tighten when TLS/pairing lands
    })
    if err != nil { return }
    conn.SetReadLimit(maxFrameBytes)                 // contract limit, default 32KiB is too small

    c := &client{conn: conn, send: make(chan []byte, 16)}
    s.registry.add(c)                                // for shutdown draining (§5)
    defer s.registry.remove(c)

    ctx, cancel := context.WithCancel(r.Context())
    defer cancel()

    go c.writePump(ctx)                              // sole writer to conn
    c.greet()                                        // {"srv":{...}} frame, once
    c.readLoop(ctx, s.dispatch)                      // sole reader; returns on close/error
}
```

Iron rules (library-enforced): exactly one concurrent reader; all writes go through
`writePump` — handlers never touch `conn` directly, they send into `c.send`.

## 2. Write pump: serialization + ping in one place

```go
func (c *client) writePump(ctx context.Context) {
    ping := time.NewTicker(25 * time.Second)         // NAT floor ~30s
    defer ping.Stop()
    for {
        select {
        case frame := <-c.send:
            wctx, cancel := context.WithTimeout(ctx, 5*time.Second)
            err := c.conn.Write(wctx, websocket.MessageText, frame)
            cancel()
            if err != nil { return }
        case <-ping.C:
            wctx, cancel := context.WithTimeout(ctx, 5*time.Second)
            err := c.conn.Ping(wctx)                 // pong handled by the read loop
            cancel()
            if err != nil { return }
        case <-ctx.Done():
            return
        }
    }
}
```

`Ping` only completes while the read loop is running (pong arrives there). A
write-only endpoint would need `CloseRead` instead — ours always reads.

## 3. Hub: goroutine-owned subscribers, drop-the-slow-client

```go
type Hub struct {
    register, unregister chan *client
    broadcast            chan []byte
}

func (h *Hub) Run(ctx context.Context) {
    subs := map[*client]struct{}{}                   // owned HERE; no mutex anywhere
    for {
        select {
        case c := <-h.register:   subs[c] = struct{}{}
        case c := <-h.unregister: delete(subs, c); close(c.send)
        case frame := <-h.broadcast:
            for c := range subs {
                select {
                case c.send <- frame:                // buffered 16
                default:                             // full = slow client
                    delete(subs, c)
                    c.conn.Close(websocket.StatusPolicyViolation, "slow consumer")
                }
            }
        case <-ctx.Done():
            for c := range subs { c.conn.Close(websocket.StatusGoingAway, "shutdown") }
            return
        }
    }
}
```

Dropping is safe BY DESIGN: the client reconnects with `since` and replays. Never
block the hub on one connection.

## 4. Envelope dispatch & replay ordering

```go
type frameIn struct {
    ID   int             `json:"id"`
    Cmd  string          `json:"cmd"`
    Data json.RawMessage `json:"data"`               // two-phase decode
}
```

- Dispatch: `map[string]func(ctx, *client, json.RawMessage) (any, *wireError)`.
  Unknown `cmd` → `invalid_request`. **Exactly one reply per `id`, always** —
  including panic recovery in the read loop (`internal` + slog, connection stays).
- Unknown JSON fields: ignored (v0 evolves). `DisallowUnknownFields` only inside
  contract tests.
- **Replay (contract §3), order is load-bearing:**

```go
// inside the session.hello handler:
hub.Register(c)                       // 1. subscribe FIRST
reply(cursor, limits, identity)       // 2. answer hello
events := store.EventsSince(ctx, since)
for _, e := range events { c.send <- e.Frame } // 3. replay
// 4. live frames now interleave; duplicates at the boundary are fine (client dedups by seq)
```

Subscribe-before-query is what makes loss impossible; duplicates are the accepted
price. Never "optimize" the order.

## 5. Graceful shutdown — the trap and the cure

`http.Server.Shutdown` is DOCUMENTED not to wait for hijacked connections
(WebSockets are hijacked). Without extra work, shutdown hangs or kills conns mid-frame.

```go
srv.RegisterOnShutdown(func() { s.registry.closeAll(websocket.StatusGoingAway) })
// main: signal.NotifyContext → on ctx.Done():
//   1. srv.Shutdown(5s ctx)   — drains REST, triggers OnShutdown → WS close
//   2. hub stops (its ctx)    — after conns are gone
//   3. store/db Close         — last
```

Registry = the same set the hub owns is not enough (hub may be mid-select): keep a
tiny separate registry (mutex here is acceptable — it is infrastructure, not
business state; or funnel through the hub with a drain message).

## 6. REST surface — stdlib only

```go
mux := http.NewServeMux()
mux.HandleFunc("GET /health", health)
mux.Handle("PUT /files/{token}", maxBytes(maxAttachmentBytes, upload(store)))
mux.HandleFunc("GET /files/{token}", download(store))
mux.HandleFunc("GET /ws", s.handleWS)
handler := logRequests(logger, mux)                  // outermost middleware
```

- Middleware = `func(http.Handler) http.Handler`; compose by nesting; keep the chain
  short and visible in one place.
- Upload: `http.MaxBytesReader(w, r.Body, n)` — over-limit read returns
  `*http.MaxBytesError` → map to 413.
- Download: `http.ServeContent(w, r, name, modtime, readSeeker)` — Range and
  conditional headers handled for you; never hand-roll Range.
- Request log middleware: slog with method, path pattern (`r.Pattern`, 1.23+),
  status (wrap ResponseWriter), duration.

### Long transfers: limit the silence, never the duration (043)

A file over Tor takes tens of minutes. An absolute deadline on the body cuts
exactly the slow path, so there is none; the only limit is a STALL — no byte
for `stallTimeout`:

```go
rc := http.NewResponseController(w)
// upload: renew before EVERY body read
rc.SetReadDeadline(time.Now().Add(stall))
// download: renew before EVERY write, through a wrapper that exposes only
// Header/Write/WriteHeader - hiding ReadFrom keeps io.Copy inside
// ServeContent writing through it
rc.SetWriteDeadline(time.Now().Add(stall))
```

- **Clear the write deadline when the download handler ends** (flush first).
  Belt and braces: net/http (Go 1.27) clears it itself once a handler
  returns, before the connection carries another request - but a deadline
  left behind would cut that request at an arbitrary moment, and a one-line
  reset costs less than depending on that never changing. Hijack clears both.
- **A resumable PUT appends from an offset bound to its token** (the
  continuation that issued the token reported that offset): the part on disk
  is cut back to it before writing, whatever a straggler appended since. The
  body is kept on any break; durability is checkpointed every few MiB
  (`blob.Upload.Checkpoint`: fsync the part, THEN record the length).
- **One writer per part.** A request whose connection died silently waits for
  bytes until its own stall deadline; the next request for the same file
  interrupts it (`ResponseController.SetReadDeadline(time.Now())`, ordered
  against the renewal by one mutex) and waits for it to let go. Never touch a
  ResponseController after its handler returned — mark it finished first.
- **Never return from a PUT without a definite status.** A handler that writes
  nothing answers 200, and a client that does read it takes an unfinished
  upload for a finished one.
- **Commit the last byte on `context.WithoutCancel(r.Context())`.** The client
  may hang up right after it, which cancels the request's context, and a file
  whole on disk but unknown to its row would be sent again from byte one. A
  part already renamed to the file of its declared size counts as complete
  whatever the row says.
- **A new upload token revokes the file's earlier upload tokens.** A PUT on
  an older one that turns up late would cut the part back past bytes a newer
  attempt wrote.

## 7. Testing recipes

```go
srv := httptest.NewServer(newHandler(t, tempStore(t)))   // real mux, real temp DB
defer srv.Close()
conn, _, err := websocket.Dial(ctx, srv.URL+"/ws", nil)  // http:// scheme accepted
```

- Drive frames with `wsjson.Write/Read` or raw `conn.Write`; assert reply `id`
  matching and event `seq` monotonicity.
- Replay test: write N messages → dial with `since` → expect exactly the tail,
  duplicates allowed at the boundary, order by `seq`.
- Slow-client test: fill the send buffer, assert `StatusPolicyViolation` close.
- Shutdown test: open conn → `srv.Config.Shutdown` → expect `StatusGoingAway`.
- Always `-race`; concurrency/time via `testing/synctest`; leak-check handlers
  (gotify pattern): count goroutines before/after.

## 8. Failure modes to check in review

| Smell | Why it breaks |
|---|---|
| `conn.Write` outside writePump | Two writers — library panics/corrupts |
| Ping without a running reader | Pong never read → ping blocks → false-dead conns |
| Hub blocking on `c.send <-` without default | One slow client freezes broadcast for all |
| Reply skipped on error path | Client's `id` correlation hangs forever |
| Replay query before subscribe | Event gap → silent message loss |
| `Shutdown` without conn registry | Hijacked WS conns are never closed |
| Business mutex "just this once" | Ownership model erodes; restructure instead |
| Hand-rolled Range handling | `http.ServeContent` already does it correctly |
| Absolute deadline on a file body | Cuts every transfer slower than size/deadline — the Tor path; renew a stall deadline per read/write instead |
| Write deadline left set after a GET | The next request on the keep-alive connection dies mid-response |
| Blocking wait inside a socket command handler | The same loop reads pongs: a few seconds there and the ping declares a live connection dead |

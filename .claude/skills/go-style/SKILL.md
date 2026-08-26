---
name: go-style
description: The Go expertise pack for client_backend — current-language features to use (Go 1.27), style authority hierarchy, error/context/concurrency canon, forbidden patterns, lint stack. Load before writing or reviewing any Go code in this project; the owner is a senior Dart developer, not a Go expert, so explain idioms when they differ from Dart instincts.
user-invocable: true
---

# Go style & expertise — client_backend

Verified against primary sources (go.dev, style guides, genre exemplars) in August 2026.
When advising, prefer showing the idiomatic snippet over prose. When a Dart instinct
would mislead (exceptions, classes, streams), say so explicitly.

## Authority hierarchy (when advice conflicts)

1. go.dev docs + release notes; **go.dev/wiki/CodeReviewComments** (living, official).
2. **Google Go Style Guide** (living; principles in order: clarity > simplicity >
   concision > maintainability > consistency).
3. Uber Go Style Guide — one company's opinion; adopt only what does not conflict.
4. Effective Go — 2009 spirit-of-the-language intro; go.dev itself marks it not
   actively updated (no generics/modules). Never cite it as the final word.

Line length: Google says there is no fixed limit — refactor long lines instead of
wrapping. Do not enforce a column number.

## Modern features this project MUST default to

| Feature | Since | Use |
|---|---|---|
| ServeMux method+wildcard routing (`"GET /files/{token}"`) | 1.22 | The only router |
| `log/slog` | 1.21 | The only logger |
| `tool` directives in go.mod | 1.24 | Dev tools; never tools.go |
| `omitzero` JSON tag | 1.24 | Instead of `omitempty` for time/structs |
| `os.Root` | 1.24 | Any file-store access confined to a directory |
| `sync.WaitGroup.Go(f)` | 1.25 | Instead of Add(1)+go |
| `testing/synctest` (GA) | 1.25 | Concurrency/replay tests with virtual time |
| `testing.B.Loop` | 1.24 | Benchmarks |
| `net.JoinHostPort` | vet-enforced 1.25 | Never `Sprintf("%s:%d")` — breaks IPv6 |
| Green Tea GC | default 1.26 | Nothing to do; do not tune GOGC prematurely |
| `encoding/json` v1 API | backed by v2 in 1.27 | Default. v2 (`jsontext`,
  `MarshalWrite`, `RejectUnknownMembers`) is a deliberate opt-in, not a habit |
| `go fix` | modernizers home 1.26 | Run after upgrades to modernize idioms |

## Error canon (final — Go team closed the syntax debate in 2025)

```go
if err != nil {
    return fmt.Errorf("open store: %w", err)   // wrap with context, lowercase, no "failed to"
}
```

- Callers branch with `errors.Is` (sentinels) / `errors.As` (typed). Export sentinel
  errors only when callers genuinely branch on them.
- `panic` never crosses a request boundary; acceptable only for programmer errors at
  startup (broken embedded migration). `os.Exit`/`log.Fatal*` only in `main`.
- For Dart people: there are no exceptions. An ignored `err` is the bug class the
  linters exist for — `errcheck` stays on, always.

## Context canon

- `ctx context.Context` is the FIRST parameter of anything that blocks, does I/O, or
  can be cancelled. Never store a context in a struct field (one exception: the
  per-connection struct may hold its conn-lifetime ctx, documented).
- Cancellation flows down: `signal.NotifyContext` at the top → errgroup → handlers →
  store calls (`QueryContext`/`ExecContext` — never the ctx-less variants).

## Concurrency canon (this project's shape)

- Ownership over locking: one goroutine owns mutable state; others talk to it via
  channels (the hub). The project contains **no mutex** — treat "I need a mutex" as
  a design smell and restructure.
- For Dart people: goroutines are not isolates and not futures — they share memory;
  `go test -race` is the safety net and is mandatory.
- Channels: the owner closes; a buffered channel per WS subscriber (~16) with
  close-on-overflow is our backpressure policy — replay makes it safe.
- `errgroup` caveat: a panic inside a goroutine is NOT delivered to `Wait` — do not
  rely on it for panic containment.

## Package & API design

- Small, one-word, lowercase package names describing contents; no `util`, `common`,
  `helpers`, `base`, `shared` (Google guide bans them). No `pkg/` directory.
- Interfaces are declared where they are CONSUMED, not where implemented; accept
  interfaces, return concrete types. Do not create an interface until a second
  implementation or a test double genuinely needs it.
- No `init()`; no package-level mutable state. Constructor funcs (`New…`) wire
  everything from `main`.
- Zero values should be useful; keep structs small; embed rarely.
- For Dart people: no classes/inheritance — composition + methods on small structs;
  no getters/setters — exported fields are fine.

## SQL discipline

- Raw parameterized SQL with `?` placeholders — the SQL on the page is the audited
  artifact. No ORM, no query builders, no fmt.Sprintf into SQL under any pretext.
- All mutations in `internal/store` through the write handle; milliseconds-long
  transactions; the event row in the same transaction (invariants 2–4 of CLAUDE.md).

## Testing style

- Table tests + `t.Run(name, …)`; test names are behavior sentences.
- Real dependencies over mocks: real DB file in `t.TempDir()`, real mux via
  `httptest`, real WS dial. No testify — plain `testing` (miniflux proves it scales);
  a tiny local `assertEqual` helper is fine if it stays in one file.
- `t.Context()` (1.24) for test-scoped cancellation; `synctest` for time-dependent
  concurrency; leak-check WS handler tests (gotify pattern).

## Lint stack (run order)

    gofmt -l .          # empty output
    go vet ./...
    staticcheck ./...   # or golangci-lint v2 (config MUST be version: "2")
    govulncheck ./...
    go test -race ./...

golangci-lint: only v2-format config; v1 examples from old blog posts are invalid.
Never disable `errcheck`.

## Review checklist (apply to every diff)

1. Contract first: does the change match `contract-draft.md`? Field names exactly?
2. Invariants 1–13 of CLAUDE.md hold?
3. Every `err` handled or wrapped; no naked `_ =` on errors.
4. Context threaded; no blocking call without deadline/cancel path.
5. No new dependency, mutex, `init`, `util` package, or interface without need.
6. Tests updated, `-race` clean, `gofmt` clean.

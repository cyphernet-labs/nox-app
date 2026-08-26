# AGENTS.md — NOX client server (Go)

Agent instructions for this directory live in `CLAUDE.md` next to this
file — read it fully before changing code; its invariants are the
architecture. Before writing any Go, also load the `go-style` skill;
for wire changes use `add-command`; for schema changes use `migrations`.

The wire contract is `docs/client-backend/protocol/contract-draft.md`;
the architecture blueprint is `docs/blueprints/client-backend/README.md`.

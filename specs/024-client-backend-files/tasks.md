# Tasks: client-backend-files

**Input**: Design documents from `/specs/024-client-backend-files/` (plan.md, research.md R1–R10, data-model.md, contracts/README.md, quickstart.md)

**Prerequisites**: фазы 022–023 смёржены в `develop`; Go-гейт перед каждым коммитом.

**Organization**: по историям спеки; каждая история независимо тестируема и заканчивается зелёным гейтом.

## Phase 1: Setup

Не требуется: модуль и харнес существуют.

## Phase 2: Foundational (blocking prerequisites)

- [x] T001 Extend the single pre-release migration client_backend/migrations/001_init.sql per data-model.md (owner rule: one migration until the first release): files STRICT table, messages.file_id column, partial unique index idx_messages_file; extend the schema tests in client_backend/internal/db/db_test.go for version 2 and the new schema objects
- [x] T002 [P] Create the blob package in client_backend/internal/blob/blob.go per research R2: Open(dir) over os.Root, Create(id) writing <id>.part with atomic finalize-rename, Open/Remove/Size by id, RemovePart for sweep; table tests in client_backend/internal/blob/blob_test.go (roundtrip, partial file invisible until finalize, remove, size, traversal-shaped ids rejected by os.Root)
- [x] T003 [P] Add the files directory to client_backend/internal/config/config.go: -files flag / NOX_FILES env with default <db>-files, validated non-empty; extend client_backend/internal/config/config_test.go
- [x] T004 [P] Add the 024 protocol surface to client_backend/internal/protocol/frames.go: CmdFileUploadBegin, CmdFileDownloadBegin, CmdChatFiles constants, Attachment wire struct {file_id,name,size,mime,expires_at} and Message.Attachment *Attachment omitempty
- [x] T005 Add the one-shot token registry in client_backend/internal/server/tokens.go per research R3: issue(fileID, op) -> 32-byte token, consume(token, op) -> fileID with single-use and 10-minute TTL, lazy expiry cleanup, documented infrastructure mutex; unit tests in client_backend/internal/server/tokens_test.go (single use, wrong op, expiry, unknown token)

**Checkpoint**: `go build ./...` и все существующие тесты зелёные; поведение провода не изменилось.

## Phase 3: User Story 1 — Отправка файла: цепочка вложения (Priority: P1) 🎯 MVP

**Goal**: uploadBegin → PUT → send{attachment} → эхо/событие с полным объектом; превью — имя файла.

**Independent Test**: quickstart, секция «Отправка»: один клиент проходит цепочку, событие у второго несёт attachment, превью чата — имя файла.

- [x] T006 [US1] Add store methods in client_backend/internal/store/store.go per research R1/R7: CreateUpload (INSERT files, expires_at = created_at + 10 years), MarkUploaded (guarded UPDATE), FileByID; extend SendMessage with the attachment branch — validate uploaded and unbound inside the tx, bind files.message_id + messages.file_id, assemble the wire Attachment into the message and the event payload; sentinel errors ErrFileNotFound/ErrFileNotReady/ErrFileTaken; store tests for the lifecycle, double-bind rejection and the idempotent replay returning the same attachment
- [x] T007 [US1] Extend previewFromBody to previewFor(body, fileName) in client_backend/internal/store/store.go per research R8 (no text + attachment -> file name, same 120-rune fold) with preview table-test additions
- [x] T008 [US1] Add the file.uploadBegin handler and the PUT /files/{token} endpoint in client_backend/internal/server/files.go per research R4: name/mime/size validation (invalid_request), size over limit -> payload_too_large before any bytes, relative upload_url, streaming copy into blob with MaxBytesReader, exact-size enforcement (short -> 400 + discard, over -> 413), MarkUploaded only after rename, token consumed on first use, 404 for bad/used/expired tokens; wire the mux routes and the blob store into Server/Run/openStack
- [x] T009 [US1] Extend the message.send handler in client_backend/internal/server/handlers.go: accept attachment{file_id}, at-least-one-of body/attachment, map the new sentinel errors to invalid_request; keep idempotency and per-recipient client_message_id behavior intact (eventEnvelope re-marshal must preserve the attachment)
- [x] T010 [US1] Add story-1 integration tests in client_backend/internal/server/files_test.go: full chain over httptest (uploadBegin -> PUT 204 -> send -> echo and second-client message.new with the full attachment object), preview equals the file name in chats.list, attachment with text keeps the text preview, byte-for-byte disk content, oversized declaration -> payload_too_large, PUT with oversized body -> 413 and nothing stored, short body -> 400 and nothing stored, reused/unknown upload token -> 404, send with un-uploaded/unknown/already-bound file_id -> invalid_request, send with neither body nor attachment -> invalid_request, duplicate send returns the original attachment without a second event, and an uploaded-but-unsent file survives a server restart and stays sendable (reopen the stack over the same db and files dir)
- [x] T011 [US1] Extend client_backend/README.md with the smoke Е «Отправка» section from specs/024-client-backend-files/quickstart.md, kept in sync

**Checkpoint**: история 1 демонстрируема websocat+curl; полный гейт зелёный.

## Phase 4: User Story 2 — Скачивание вторым участником с докачкой (Priority: P2)

**Goal**: downloadBegin → GET с Range; одноразовость; attachment_gone.

**Independent Test**: quickstart, секция «Скачивание»: полный GET байт-в-байт, затем Range с середины → ровно остаток.

- [x] T012 [US2] Add the file.downloadBegin handler and the GET /files/{token} endpoint in client_backend/internal/server/files.go per research R5/R10: unknown file_id -> not_found, not-yet-uploaded -> invalid_request, expired or bytes missing on disk -> attachment_gone, relative download_url, ServeContent with the stored mime, token consumed on first use, 404 for bad/used/expired tokens
- [x] T013 [US2] Add story-2 integration tests in client_backend/internal/server/files_test.go: second client downloads byte-identical content, Range request from the middle returns 206 with exactly the remainder and the concatenation matches the original (SC-002), reused download token -> 404, downloadBegin for unknown id -> not_found, for un-uploaded id -> invalid_request, for a file whose bytes were removed from disk -> attachment_gone, Range beyond the size -> 416
- [x] T014 [US2] Extend client_backend/README.md with the smoke Е «Скачивание с докачкой» section in sync with quickstart.md

**Checkpoint**: DoD фазы (файл одного клиента скачан вторым с докачкой) демонстрируем вручную.

## Phase 5: User Story 3 — Панель файлов чата (Priority: P3)

**Goal**: chat.files — проекция вложений чата с пагинацией фазы 023.

**Independent Test**: quickstart, секция «Панель файлов»: среди текстовых сообщений выбираются только вложения, порциями, с message_id и seq.

- [x] T015 [US3] Add ListChatFiles in client_backend/internal/store/store.go per research R9 (JOIN projection, before_seq pattern, n+1 hasMore, ascending page) with store tests (mixed chat, empty chat, boundary exclusion)
- [x] T016 [US3] Add the chat.files handler in client_backend/internal/server/files.go with 023 pagination rules (limit validation and clamp, not_found for unknown chat) and the dispatch case in client_backend/internal/server/ws.go for all three 024 commands
- [x] T017 [US3] Add story-3 integration tests in client_backend/internal/server/files_test.go: files-only projection over a mixed chat with paging until has_more false, empty chat, unknown chat -> not_found, limit 0 -> invalid_request, clamp observable over >100 attachments is NOT required (scale) — clamp covered by passing limit 500 over a small set expecting success
- [x] T018 [US3] Extend client_backend/README.md with the smoke Е «Панель файлов» section and the 024 negative checks block in sync with quickstart.md

**Checkpoint**: все три истории демонстрируемы; командный набор этапа 1 полон.

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T019 [P] Add the startup orphan sweep per research R10: SweepOrphans in client_backend/internal/store/store.go (rows without message_id older than 24h) wired with blob removal in Run/openStack before endpoints open, .part leftovers removed; tests (orphan swept with bytes, bound file untouched, fresh upload untouched)
- [x] T020 [P] Audit logging against Principle I in client_backend/internal: no file names, mime types or bodies in slog — only file_id, sizes, codes, seq, durations; extend request logging for the new HTTP endpoints without leaking tokens (log path as /files/<redacted> or method+status only)
- [x] T021 [P] Reconcile the wire contract per Principle VII: update docs/client-backend/protocol/contract-draft.md §7 with the owner-clarified rules (indefinite stage-1 retention with the far expires_at, 10-minute one-shot tokens, relative URLs, startup sweep, 404-for-all token failures, exact-size PUT rule) and §4 chat.files pagination reference to the 023 rules
- [x] T022 Run the full local gate and the 13 CLAUDE.md invariants check, validate specs/024-client-backend-files/quickstart.md end-to-end as the owner would (fresh build, smoke Е with real curl Range resume, ≤10 min per SC-007), reconcile README/quickstart wording, then mark phase 024 implemented in docs/client-backend/roadmap-stage1.md (status + journal row)

## Dependencies & Execution Order

```text
Foundational: T001 → (T002 [P] ∥ T003 [P] ∥ T004 [P]) → T005
US1 (P1):     T006 → T007 → T008 → T009 → T010 → T011      (после T001–T005)
US2 (P2):     T012 → T013 → T014                            (после US1: нужен залитый файл)
US3 (P3):     T015 → T016 → T017 → T018                     (после US1: нужны привязанные вложения)
Polish:       T019 [P], T020 [P], T021 [P] → T022           (после всех историй)
```

- T002/T003/T004 независимы и параллелизуемы; T005 использует T004.
- US2 и US3 обе стоят на US1, между собой независимы.
- Polish: T019 ∥ T020 ∥ T021; T022 — последним.

## Implementation Strategy

**MVP first**: Phase 2 → 3 (T001–T011) даёт сквозную отправку файла — главная ценность фазы. **Incremental delivery**: каждая история заканчивается зелёным гейтом и ручным смоуком; коммит на историю (ритм 022/023). Контракт правится в T021 тем же change-set'ом.

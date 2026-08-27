# Tasks: client-backend-chats-messages

**Input**: Design documents from `/specs/023-client-backend-chats-messages/` (plan.md, research.md R1–R9, data-model.md, contracts/README.md, quickstart.md)

**Prerequisites**: фаза 022 смёржена в `develop`; миграций нет; Go-гейт (`gofmt -l .` пусто → `go vet ./...` → `go test -race ./...`) перед каждым коммитом.

**Organization**: задачи сгруппированы по историям спеки; каждая история независимо тестируема и завершается зелёным гейтом.

## Phase 1: Setup

Не требуется: модуль, схема и харнес существуют с 022.

## Phase 2: Foundational (blocking prerequisites)

- [ ] T001 Add the 023 protocol surface to client_backend/internal/protocol/frames.go: constants CmdChatsList, CmdChatGet, CmdChatRename, CmdChatNameAvailable, CmdMessagesList and EventChatUpdated (names verbatim from contracts/README.md)
- [ ] T002 Extract a shared chat-row scan helper in client_backend/internal/store/store.go (single column list + scan into protocol.Chat) to be reused by GetChat, ListChats and RenameChat (research R7), with a unit test in client_backend/internal/store/store_test.go proving field-for-field equality with a freshly created chat

**Checkpoint**: `go build ./...` green; no behavior change.

## Phase 3: User Story 1 — Обзор пространства: список чатов и карточка (Priority: P1) 🎯 MVP

**Goal**: страницы списка чатов (порядок по активности, поиск, превью) и точечная карточка чата.

**Independent Test**: создать чаты/сообщения командами 022, убедиться в порядке, поиске (кириллица), пагинации и работе chat.get (quickstart, секция «Список и поиск»).

- [ ] T003 [US1] Implement ListChats in client_backend/internal/store/store.go per research R1/R2: read-pool query ordered by last_activity_at DESC, chat_id ASC; Unicode case-insensitive substring filter and page slicing in Go; returns page + hasMore; table tests in client_backend/internal/store/store_test.go (ordering, tiebreaker on equal activity, Cyrillic query, page beyond data → empty + hasMore false)
- [ ] T004 [US1] Implement GetChat in client_backend/internal/store/store.go (read pool, ErrChatNotFound sentinel reuse) with store tests for found and missing ids
- [ ] T005 [US1] Add chats.list and chat.get handlers in client_backend/internal/server/handlers.go plus dispatch cases in client_backend/internal/server/ws.go: page/page_size validation (<1 → invalid_request), silent clamp to 100 (research R6), query pass-through, not_found mapping; requests and replies shaped verbatim per contracts/README.md
- [ ] T006 [US1] Add story-1 integration tests in client_backend/internal/server/chats_test.go: list ordering with preview after a send, Cyrillic case-insensitive search, page_size 500 clamped to ≤100 rows, page 0 → invalid_request, page past the end → empty + has_more false, chat.get full card and not_found
- [ ] T007 [US1] Extend client_backend/README.md with the smoke Д «Список и поиск» section from specs/023-client-backend-chats-messages/quickstart.md, kept in sync

**Checkpoint**: US1 демонстрируема владельцем двумя терминалами; полный гейт зелёный.

## Phase 4: User Story 2 — История чата: постраничная догрузка назад (Priority: P2)

**Goal**: хвост истории + листание назад до начала чата, порция по возрастанию seq.

**Independent Test**: отправить серию сообщений, выбрать историю страницами назад, убедиться в полноте/порядке/has_more (quickstart, секция «История»).

- [ ] T008 [US2] Implement ListMessages in client_backend/internal/store/store.go per research R3: read pool, optional beforeSeq, ORDER BY seq DESC LIMIT n+1, reverse to ascending in Go, hasMore; store tests (tail, middle page, oldest page, empty chat, before_seq boundary excluded)
- [ ] T009 [US2] Add the messages.list handler in client_backend/internal/server/handlers.go plus the dispatch case in client_backend/internal/server/ws.go: chat existence → not_found, limit validation (<1 → invalid_request) and silent clamp to 100, per-recipient client_message_id stripping in the reply (field kept only where author_id equals the session label, per contracts/README.md §5 rule); confirm message.send keeps requiring body (no code change, covered by test)
- [ ] T010 [US2] Add story-2 integration tests in client_backend/internal/server/history_test.go: full backward walk over 25 messages with no gaps or duplicates until has_more false, ascending order inside each page, empty chat → empty page + has_more false, unknown chat → not_found, limit 0 → invalid_request, author sees client_message_id while a second client does not, duplicate send appears exactly once in history
- [ ] T011 [US2] Extend client_backend/README.md with the smoke Д «История» section in sync with quickstart.md

**Checkpoint**: US1 + US2 вместе — read-сторона фазы полностью демонстрируема.

## Phase 5: User Story 3 — Переименование чата вживую (Priority: P3)

**Goal**: rename с юникод-уникальностью (исключая себя), подсказка nameAvailable, событие chat.updated через журнал, позиция строки не меняется.

**Independent Test**: два клиента; rename у первого → событие у второго <1 c; порядок списка неизменен; реплей доносит chat.updated (quickstart, секция «Переименование»).

- [ ] T012 [US3] Implement RenameChat in client_backend/internal/store/store.go per research R4: immediate tx, not_found, exact-match no-op branch (current card returned, no event row), name_ci uniqueness excluding the chat itself, UPDATE name+name_ci, chat.updated event with the full card in the same tx, last_activity_at untouched; store tests (successful rename, case-only rename emits event, no-op leaves the events count unchanged, taken name excluding self, unknown chat, last_activity_at and preview unchanged)
- [ ] T013 [US3] Implement NameAvailable in client_backend/internal/store/store.go per research R5 (read pool, optional exclude id) with store tests (taken, free, excluded self, Cyrillic case fold)
- [ ] T014 [US3] Add chat.rename and chat.nameAvailable handlers in client_backend/internal/server/handlers.go plus dispatch cases in client_backend/internal/server/ws.go: name rules validation (trim/empty/64 runes → invalid_request), error mapping (not_found, name_taken), kickDispatcher after a mutating rename only; verify eventEnvelope passes chat.updated through as a shared-variant frame (no code change expected, covered by test)
- [ ] T015 [US3] Add story-3 integration tests in client_backend/internal/server/chats_test.go: live chat.updated on the second client under 1s with the full card (SC-002), chats.list order unchanged after rename, name_taken on a Cyrillic case-variant of another chat's name, nameAvailable with and without exclude_chat_id consistent with the rename outcome, no-op rename produces no event on the second client, chat.updated replayed after reconnect with since, concurrent renames of two chats to the same name → exactly one success
- [ ] T016 [US3] Extend client_backend/README.md with the smoke Д «Переименование» section and the negative checks block in sync with quickstart.md

**Checkpoint**: все три истории демонстрируемы; событийный набор фазы полон.

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T017 [P] Audit new code against Principle I in client_backend/internal: slog must not log chat names, search queries, message bodies or labels — only cmd names, codes, seq, counts, durations; extend existing log lines for the new commands accordingly
- [ ] T018 [P] Reconcile the wire contract with the owner-clarified rules per Principle VII: update docs/client-backend/protocol/contract-draft.md §4–§5 with the unified cap 100 + silent clamp, ascending in-page order for messages.list, the stable chat_id tiebreaker, and the no-op rename rule (success without an event)
- [ ] T019 Run the full local gate and the 13 CLAUDE.md invariants check, validate specs/023-client-backend-chats-messages/quickstart.md end-to-end as the owner would (fresh build, smoke Д + negatives, ≤10 min per SC-006), reconcile README/quickstart wording, then mark phase 023 implemented in docs/client-backend/roadmap-stage1.md (status + journal row)

## Dependencies & Execution Order

```text
Foundational: T001 → T002                        (T001 и T002 независимы, но оба до историй)
US1 (P1):     T003 → T004 → T005 → T006 → T007   (после T002)
US2 (P2):     T008 → T009 → T010 → T011          (после T001/T002; независима от US1)
US3 (P3):     T012 → T013 → T014 → T015 → T016   (после T002; тест порядка списка в T015 использует ListChats из US1)
Polish:       T017 [P], T018 [P] → T019          (после всех историй)
```

- US2 может идти параллельно с US1 (разные store-методы и тестовые файлы); US3 завершает после US1 (тест неизменности порядка требует chats.list).
- T017 ∥ T018; T019 — последним.

## Implementation Strategy

**MVP first**: Phase 2 → 3 (T001–T007) даёт видимое пространство чатов — самостоятельная ценность для клиента приложения. **Incremental delivery**: каждая фаза заканчивается зелёным гейтом и ручным смоуком своей истории; коммит на историю (рабочий ритм 022). Контракт правится в T018 тем же change-set'ом (Принцип VII).

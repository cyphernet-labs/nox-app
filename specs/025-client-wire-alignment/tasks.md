# Tasks: client-wire-alignment

**Input**: Design documents from `/specs/025-client-wire-alignment/` (plan.md, research.md R1–R10, data-model.md, contracts/README.md, quickstart.md)

**Prerequisites**: `make gate` + `make golden-verify` зелёные на старте (baseline — эталон заморозки); локальный `noxd` собирается (для фикстур).

**Organization**: фундамент — «переключение языка» (типы страниц/ошибок/лимитов + wire-DTO), затем истории спеки. Прим.: истории 1–2 делят wire-слой, поэтому wire-ядро вынесено в фундамент, а истории добавляют своё поведение и тесты.

## Phase 1: Setup

- [x] T001 Verify the freeze baseline: run `make gate` and `make golden-verify` on a clean checkout of the branch; investigate any pre-existing red before touching code

## Phase 2: Foundational (blocking prerequisites)

- [x] T002 Reshape pagination metadata in lib/domain/repository/base/page_metadata.dart to `{required bool hasMore, int? nextPage}` (research R2), update lib/presentation/pagination/paging_state_ext.dart (`isLastPage = !meta.hasMore`) and every compile site: empty-scenario literals in chat_thread_bloc.dart/chats_list_bloc.dart, the dead Item slice (item_list_bloc.dart/item_list_state.dart drop `total`), provideDummy in chat_thread_bloc_send_error_test.dart, tests of page_metadata/paging_state_ext/configs
- [x] T003 [P] Extend lib/domain/exception/repository_exception.dart with wire codes per contracts/README.md (invalidRequest, nameTaken, payloadTooLarge, attachmentGone, rateLimited, unsupportedSchema) and add `wireCodeToException(String)` with the unknown→internal evolution rule; unit tests in test/domain/exception/
- [x] T004 [P] Add ServerLimits to lib/domain/model/app_config/ with contract §3 const defaults and expose `limits` + `updateLimits` on AppConfigRepository (lib/domain/repository/app_config/ + impl); tests in test/data/repository/app_config/
- [x] T005 Rewrite the wire layer 1:1 per data-model.md (research R4): new lib/data/entity/chat/wire/ DTOs — MessageWireEntity (message_id, seq, unix sent_at, optional client_message_id, BodyWireEntity, AttachmentWireEntity {file_id,name,size,mime,expires_at}), ChatWireEntity (chat_id, created_at, created_by_label, last_activity_at), page wrappers {messages|chats, has_more}; ErrorWireEntity {code,message} replacing ResponseEntity.error String (lib/data/entity/base/response_entity.dart); re-register BOTH EntityConverter chains (lib/data/entity/base/entity_converter.dart); run `make generate`
- [x] T006 Update both wire mappers in lib/data/mapper/chat/ (research R4): unix↔DateTime, body.text↔text (non-text type → null), FileType.fromExtension(name), mime/expiresAt through, client_message_id parsed-and-dropped, localPath never from wire; rewrite their unit tests and the wire-entity/entity-converter tests to the new shapes (fixture-based tests arrive in US2)

**Checkpoint**: `make gate` компилируется и зелёный (генераторы ещё на старых формах? — нет: T007 фундаментален) — фактический гейт после T008.

- [x] T007 Update the three mock generators in lib/data/remote/api/chat/ to emit the new wire shapes with deterministic seq minting per research R1: GetChatsApi (created_at/created_by_label, has_more), GetMessagesApi (seed seq = (chatIndex+1)*1000+position, tail/before_seq window, has_more, attachment mime+far expires_at), SendMessageApi (runtime seq = nowMs*1000+counter); update MockMessageRemoteDataSource/MockChatRemoteDataSource pass-through if signatures shift; update generator unit tests
- [x] T008 Run `make gate` and fix all remaining compile/test fallout of the foundational switch (seam_binding_test, api tests, mapper tests); commit checkpoint

## Phase 3: User Story 1 — Сообщения в системе координат сервера (Priority: P1) 🎯 MVP

**Goal**: seq во всех слоях, тред на курсорной пагинации, голдены без изменений.

**Independent Test**: тред на моках — прежний порядок, догрузка старших по before_seq, `make golden-verify` зелёный.

- [x] T009 [US1] Add seq to the message data path per data-model.md: MessageModel (required int seq + kPendingSeq const, research R9), MessageEntity (optional int? seq), MessageMapper (`seq: entity.seq ?? 0`), MessageDao sort by seq with sentAt tiebreaker (lib/data/local/chat/message_dao.dart); `make generate`; update entity/mapper/dao tests
- [x] T010 [US1] Switch GetMessagesConfig to `{chatId, int? beforeSeq, int limit}` with tail/olderThan factories (lib/domain/repository/chat/get_messages_config.dart) and rewrite MessageRepositoryImpl.getMessages to the cursor window over the seq-sorted local list (before_seq exclusive, newest tail when absent, hasMore per remaining older rows); update the seed loop to the has_more wire wrappers; update repository and config tests
- [x] T011 [US1] Rewire ChatThreadBloc to the cursor (research R3): state gains oldestLoadedSeq (drop nextPage/loadedPageCount), loadMessages(reset) → tail, older prefetch → olderThan(oldestLoadedSeq), watch-tick refresh → single tail read with limit items.length+pageSize; allMessages sorts by seq (pending sentinel keeps outgoing at the bottom); optimistic sends get seq: kPendingSeq; update chat_thread_bloc_test.dart and chat_thread_bloc_send_error_test.dart
- [x] T012 [US1] Switch ChatRepositoryImpl.getChats + ChatsListBloc to hasMore semantics (page numbers stay per contract §4): repository computes hasMore without total, bloc keeps loadedPageCount page-window refresh (paged path unchanged), update chats_list_bloc_test.dart offset arithmetic assertions (20/28 counts stay, hasNextPage flips via hasMore)
- [x] T013 [US1] Run `make gate` AND `make golden-verify` — the 216 baselines must pass unregenerated (FR-009/SC-002); fix any ordering drift by adjusting seq minting, never baselines

**Checkpoint**: история 1 демонстрируема; голдены зелёные.

## Phase 4: User Story 2 — Провод говорит на языке контракта (Priority: P2)

**Goal**: живые кадры noxd — истина; фикстуры закоммичены и зелёные.

**Independent Test**: тесты фикстур SC-001 (≥8 кадров) зелёные.

- [ ] T014 [US2] Capture live frames from a local noxd per quickstart.md and commit them under test/fixtures/wire/ (hello, chat_create_echo, chat_created_event, chat_updated_event, message_send_echo, message_new_attachment_event, chats_list_page, messages_list_page, chat_files_page)
- [ ] T015 [US2] Add fixture round-trip tests in test/data/entity/chat/wire/wire_fixtures_test.dart: parse payload → domain mapping asserts → serialize back → field-exact map comparison; unknown-field tolerance (inject an extra key) and non-text body tolerance cases; hello limits → ServerLimits parse
- [ ] T016 [US2] Map envelope errors in repositories: on success==false/error!=null throw wireCodeToException(code) inside execute paths of ChatRepositoryImpl/MessageRepositoryImpl (replacing StateError-only), and extend a mock-generator seam to produce an error envelope for tests; repository tests assert nameTaken/payloadTooLarge/attachmentGone surface as distinct RepositoryException values (SC-005)

**Checkpoint**: SC-001/SC-005 закрыты.

## Phase 5: User Story 3 — Устройство помнит своё место и правила сервера (Priority: P3)

**Goal**: персистентный курсор, expires_at c гейтингом Save, лимиты доступны.

**Independent Test**: курсор переживает рестарт и гибнет с логаутом; просроченное вложение гасит Save.

- [ ] T017 [US3] Add the sync store: lib/data/local/sync/sync_dao.dart (single-record store 'state', field since) + lib/domain/repository/sync/sync_repository.dart + lib/data/repository/sync/sync_repository_impl.dart (getCursor/advanceCursor monotonic max/clear) with DI registration; DAO+repo tests incl. restart persistence over the same in-memory db instance
- [ ] T018 [US3] Wire cursor writers per research R6: _seedChatIfEmpty advances to the max seeded seq, sendMessage advances to the echo seq, simulateIncoming advances; AuthRepositoryImpl.logout afterMutate adds syncRepository.clear(); update auth_repository_impl_test.dart (wipe order) and message_repository tests (cursor advance)
- [ ] T019 [US3] Add attachment expiry per data-model.md: MessageAttachment {mime, expiresAt}, MessageEntity attachment fields, both storage/wire mappers, mock attachment gains far expires_at; FileViewPage Save gating — disabled when expiresAt is past (AppClock), carve-out docstring extended; widget test with an expired fixture in test/presentation/pages/file_view_page/ (no golden changes — stage-1 dates are far future)
- [ ] T020 [US3] Run `make gate` + `make golden-verify`; commit checkpoint

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T021 [P] Update the blueprints per Principle III: docs/blueprints/mobile/07-pagination.md §4/§5 (offset canon → contract canon: hasMore metadata, cursor messages path, paged chats path) and 04-data-layer.md §1 page-wrapper note ({messages|chats, has_more} real shape replaces example/TBD)
- [ ] T022 [P] Reconcile stale doc-comments touched by the phase (chat_repository.dart network-only header; GetMessagesConfig TODO(backend) cursor note now real) and verify no lib/ code references page/total semantics outside the dead Item slice
- [ ] T023 Full local gate: `make gate` + `make golden-verify`; run the owner mock walkthrough from quickstart.md; mark phase 025 implemented in docs/client-backend/roadmap-client-track.md (status + journal row)

## Dependencies & Execution Order

```text
Setup:        T001
Foundational: T002 → (T003 [P] ∥ T004 [P]) → T005 → T006 → T007 → T008   (язык переключён, гейт зелёный)
US1 (P1):     T009 → T010 → T011 → T012 → T013                            (после T008)
US2 (P2):     T014 → T015 → T016                                          (после T008; T014 независим — живой noxd)
US3 (P3):     T017 → T018 → T019 → T020                                   (после US1: advanceCursor пишет seq)
Polish:       T021 [P] ∥ T022 [P] → T023
```

## Implementation Strategy

**MVP first**: Foundational + US1 (T001–T013) — «система координат сервера» с зелёными голденами. Затем US2 (истина провода) и US3 (курсор/срок/лимиты). Коммит на фазу; `make gate` перед каждым коммитом, `make golden-verify` на чек-пойнтах T013/T020/T023.

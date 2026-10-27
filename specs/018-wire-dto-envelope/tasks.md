---
description: "Task list for 018-wire-dto-envelope"
---

# Tasks: Uniform wire-DTO envelope for chat & message (S4)

**Input**: design docs in `specs/018-wire-dto-envelope/`
**Tests**: INCLUDED (round-trips, mapper loss-free, repo unwrap, behavior preservation).
**Organization**: by user story — US1 (chat envelope), US2 (message envelope), US3 (converter registry).

## Path Conventions

Single package `nox_app`: `lib/`, tests deep-mirror under `test/`. Reference to mirror: Item harness (`ItemEntity`/`ItemsEntity`/`ItemMapper`/`GetItemsApi`/`ItemRepositoryImpl`).

---

## Phase 1: Setup

- [X] T001 Confirm baseline green on `018-wire-dto-envelope`: `make gate` + `make golden-verify`.

---

## Phase 2: Foundational (blocks US1/US2/US3)

**Wire entities + mappers + converter registry.**

- [X] T002 [P] Add `lib/data/entity/chat/wire/chat_wire_entity.dart`: `ChatWireEntity` (freezed + json_serializable, basic types) — `id`, `name`, `@JsonKey(name:'last_message_preview')` , `@JsonKey(name:'last_message_at')` ISO String, `@JsonKey(name:'unread_count')` int. Per `data-model.md`.
- [X] T003 [P] Add `lib/data/entity/chat/wire/chats_wire_entity.dart`: `ChatsWireEntity` — `@Default(<ChatWireEntity>[]) items`, `page`, `@JsonKey(name:'page_size') pageSize`, `total` (mirror `ItemsEntity`).
- [X] T004 [P] Add `lib/data/entity/chat/wire/message_wire_entity.dart`: `MessageAttachmentWireEntity` (`id`,`type`,`name`,`@JsonKey(name:'size_bytes') sizeBytes`) + `MessageWireEntity` (`id`,`@JsonKey(name:'chat_id')`,`@JsonKey(name:'author_id')`,`@JsonKey(name:'author_label')`,`text`?,`@JsonKey(name:'sent_at')` ISO,`status` String,`@JsonKey(name:'is_system')` bool,`attachment` nullable nested).
- [X] T005 [P] Add `lib/data/entity/chat/wire/messages_wire_entity.dart`: `MessagesWireEntity` — items + page/page_size/total.
- [X] T006 Add `lib/data/mapper/chat/chat_wire_mapper.dart`: `ChatWireMapper` `@lazySingleton` — `toModel({entity})` (ISO→local DateTime, mirror `ChatMapper`) + `toWire({model})` (UTC ISO). Bidirectional, loss-free.
- [X] T007 Add `lib/data/mapper/chat/message_wire_mapper.dart`: `MessageWireMapper` `@lazySingleton` — `toModel`/`toWire` incl. `MessageStatus`/`FileType` name↔String, nested attachment null-safe, `isSystem`.
- [X] T008 Edit `lib/data/entity/base/entity_converter.dart`: register `fromJson` (Map→`T.fromJson`) and `toJson` (`T`→`.toJson()`) branches for `ItemEntity`,`ItemsEntity`,`ChatWireEntity`,`ChatsWireEntity`,`MessageWireEntity`,`MessagesWireEntity` via the `_isType` guard; unknown `T` still throws `ArgumentError`.
- [X] T009 Run `make generate` (freezed + json_serializable for the 4 wire files; injectable for the 2 mappers). Confirm `.g.dart`/`.freezed.dart` produced and DI wires the mappers.

**Checkpoint**: entities + mappers + converter compile.

---

## Phase 3: US1 — Chat-list through the envelope (P1)

- [X] T010 [US1] Edit `lib/data/remote/api/chat/get_chats_api.dart`: keep the model seed; map `model→wire` (`ChatWireMapper.toWire`); return `ResponseEntity<ChatsWireEntity>(success:true, data: ChatsWireEntity(items, page: config.page, pageSize, total: filtered.length))`.
- [X] T011 [US1] Edit `lib/data/remote/datasource/chat_remote_data_source.dart` + `mock/mock_chat_remote_data_source.dart`: signature → `Future<ResponseEntity<ChatsWireEntity>> getChats(...)`; mock forwards.
- [X] T012 [US1] Edit `lib/data/repository/chat/chat_repository_impl.dart` `_seedIfEmpty`: unwrap each page's `ResponseEntity` — `data == null` → `throw` (caught by the enclosing `execute()` in `getChats`/`watchChats` → `RepositoryResult.error`, mirroring `ItemRepositoryImpl`'s null-data→error), else map `wire→model` via `ChatWireMapper` and continue paging via `page*pageSize<total`. Inject `ChatWireMapper`. Domain output unchanged.
- [X] T013 [P] [US1] Test `test/data/mapper/chat/chat_wire_mapper_test.dart`: `toModel(toWire(model))` is loss-free for all fields (id/name/preview/lastMessageAt/unread).
- [X] T014 [P] [US1] Extend `test/data/repository/chat/chat_repository_impl_test.dart`: after seeding through the enveloped remote, `getChats` returns the same `(List<ChatModel>, PageMetadata)` as before (end-to-end: unwrap happens in `_seedIfEmpty`, `getChats` serves from the DB). Force the error path with a `@GenerateMocks` `ChatRemoteDataSource` returning `ResponseEntity(success:false, data:null)` (getIt.allowReassignment + registerSingleton, as `item_repository_impl_test`) → `getChats` → `RepositoryResult.error`.
- [X] T014b [P] [US1] Update `test/data/remote/api/chat/get_chats_api_test.dart` to the new generator contract: `execute` now returns `ResponseEntity<ChatsWireEntity>` — assert on `response.data.items` (wire) + `page`/`pageSize`/`total` (same seed/pagination facts as before, read off the wire).

**Checkpoint**: chat boundary enveloped; existing chat tests still pass.

---

## Phase 4: US2 — Message-list through the envelope (P1)

- [X] T015 [US2] Edit `lib/data/remote/api/chat/get_messages_api.dart`: keep the model seed; map `model→wire` (`MessageWireMapper.toWire`, nested attachment); return `ResponseEntity<MessagesWireEntity>`.
- [X] T016 [US2] Edit `lib/data/remote/datasource/message_remote_data_source.dart` + `mock/mock_message_remote_data_source.dart`: `getMessages` signature → `Future<ResponseEntity<MessagesWireEntity>>`; mock forwards; `sendMessage` unchanged.
- [X] T017 [US2] Edit `lib/data/repository/chat/message_repository_impl.dart` (`_seedChatIfEmpty` + `getMessages`): unwrap envelope (`data == null` → throw → `execute()` maps to error), map `wire→model` via `MessageWireMapper`, compute `PageMetadata`. Inject `MessageWireMapper`. Own-identity reconciliation is UNCHANGED — it already runs in `_seedChatIfEmpty` over the mapped `MessageModel`s (`authorId == fallbackOwnId`), and the wire preserves `author_id`, so it applies verbatim after the unwrap.
- [X] T018 [P] [US2] Test `test/data/mapper/chat/message_wire_mapper_test.dart`: `toModel(toWire(m))` loss-free incl. attachment present/absent, isSystem, status.
- [X] T019 [P] [US2] Extend `test/data/repository/chat/message_repository_impl_test.dart`: after seeding, `getMessages` returns the same `(List<MessageModel>, PageMetadata)` (incl. attachment + system line); force the error path with a mock `MessageRemoteDataSource` returning `ResponseEntity(success:false, data:null)` → `RepositoryResult.error`.
- [X] T019b [P] [US2] Update `test/data/remote/api/chat/get_messages_api_test.dart` to the new generator contract: `execute` returns `ResponseEntity<MessagesWireEntity>` — assert on `response.data.items` (wire, incl. the seeded attachment) + pagination off the wire.

**Checkpoint**: message boundary enveloped; existing message/thread tests still pass.

---

## Phase 5: US3 — EntityConverter registry resolves all wire entities (P2)

- [X] T020 [P] [US3] Test `test/data/entity/chat/wire/chat_wire_entity_test.dart`: `ChatWireEntity`/`ChatsWireEntity` JSON round-trip (`fromJson∘toJson`); and via `ResponseEntity<ChatsWireEntity>.fromJson({success,data})` → typed data (not throwing); `toJson` symmetric.
- [X] T021 [P] [US3] Test `test/data/entity/chat/wire/message_wire_entity_test.dart`: `MessageWireEntity` (with + without attachment) / `MessagesWireEntity` round-trip; via `ResponseEntity<MessagesWireEntity>.fromJson`.
- [X] T022 [P] [US3] Test `test/data/entity/base/entity_converter_test.dart`: each registered `T` (Item/Items, ChatWire/ChatsWire, MessageWire/MessagesWire) resolves via `EntityConverter().fromJson`/`toJson`; an unregistered type throws `ArgumentError`.

**Checkpoint**: converter round-trips green; unknown type throws.

---

## Phase 6: Polish & Cross-cutting

- [X] T023 Behavior preservation (SC-001): run the FULL existing suite — confirm 0 edits needed to any pre-existing CONSUMER test (chat/message repo, `ChatsListBloc`/`ChatThreadBloc`, page/golden). The ONLY existing tests that change are the two generator tests (`get_chats_api_test`/`get_messages_api_test`, T014b/T019b) whose subject's return type changed by design.
- [X] T024 [P] Drift-fix (Principle II): update `docs/mock-completion-plan.md` §5.1/§5.2 (chat/message now through `ResponseEntity` like Item; `EntityConverter` no longer empty) + `docs/blueprints/mobile/04-data-layer.md` (the ResponseEntity seam note) — reflect that all list boundaries are enveloped and the registry is populated.
- [X] T025 Gate: `make gate` + `make golden-verify` green (no golden delta). Walk `quickstart.md`.

---

## Dependencies & Order

- Setup → Foundational (T002–T009) blocks all stories.
- US1 (T010–T014) and US2 (T015–T019) are independent after Foundational; US3 tests (T020–T022) after T008/T009.
- Polish after stories. `make generate` runs once (T009); a second run only if a later edit adds an annotation.

## Notes

- One new package? No — `ResponseEntity`/`json_serializable`/`freezed` already in `pubspec`.
- The redundant `model→wire→model` round-trip is intentional (exercises the mapper both ways; preserves the seed).
- Local only; never pushed. After all: multi-agent review → fix findings → merge `018-wire-dto-envelope` → `develop` (`--no-ff`).

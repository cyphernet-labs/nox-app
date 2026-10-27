# Implementation Plan: Uniform wire-DTO envelope for chat & message (S4)

**Branch**: `018-wire-dto-envelope` · **Spec**: [spec.md](./spec.md) · **Date**: 2026-07-25

## Summary

Route the chat-list and message-list network boundaries through the same `ResponseEntity<T>` + `EntityConverter` reference envelope the Item harness already uses, and populate the empty `EntityConverter` registry. Zero user-facing change — the repositories keep handing the UI the identical domain models. This is seam preparation (backend/protocol still TBD); the envelope is an example replaced by the real wire shape once the backend is chosen.

## Technical Context

**Language/Runtime**: Dart / Flutter 3.44.1 (FVM). **Package**: `nox_app` (single). **Architecture**: Clean layers (presentation → domain ← data). **DI**: injectable + get_it. **Codegen**: freezed + json_serializable (one `build_runner` run). **Testing**: `flutter_test` + `bloc_test` + `mockito`; goldens excluded from `make test`.

**Reference already in-tree** (mirror it): `ItemEntity`/`ItemsEntity` (freezed + json_serializable, basic types only), `ItemMapper` (wire→model coercion), `GetItemsApi` (returns `ResponseEntity<ItemsEntity>` directly), `ItemRemoteDataSource` (forwards it), `ItemRepositoryImpl.getItems` (unwraps: `data == null` → `RepositoryResult.error`, else map + `PageMetadata` from `page*pageSize < total`).

**Approach (from Clarifications):**
- Generators (`GetChatsApi`/`GetMessagesApi`) keep their elaborate deterministic model-shaped seed, then map `model→wire` and return `ResponseEntity<ChatsWireEntity>` / `ResponseEntity<MessagesWireEntity>` (mirrors `GetItemsApi`). The thin 016 mock data sources forward unchanged.
- The 016 interfaces change signature to carry the envelope: `ChatRemoteDataSource.getChats → Future<ResponseEntity<ChatsWireEntity>>`, `MessageRemoteDataSource.getMessages → Future<ResponseEntity<MessagesWireEntity>>`. `sendMessage` stays as-is (single POST echo — out of scope).
- Repos unwrap in `_seedIfEmpty`/`getChats` (chat) and `_seedChatIfEmpty`/`getMessages` (message) exactly like `ItemRepositoryImpl` — map `wire→model`, compute `PageMetadata`, `data == null` → error.
- Bidirectional `wire↔model` mapping: `model→wire` used by the generator, `wire→model` used by the repo. Round-trip exercises both directions.
- Populate `EntityConverter` registry with all wire entities (Item + chat + message) so `ResponseEntity.fromJson/toJson` resolves them (today it throws).

## Constitution Check

- **I — Privacy / E2EE**: No crypto/network/PII touched; no real transport. PASS.
- **II — Spec-as-truth**: Spec/plan/data-model/contracts drive the change; the Item reference doc-comments are the model. PASS.
- **III — Architecture blueprint**: Follows blueprint 04 (data layer: `RepositoryResult`, mapper/DTO split, `ResponseEntity` seam) + 16 (network boundary). The wire envelope is the blueprint's own TBD placeholder made uniform. PASS.
- **IV — Design-system fidelity**: No UI. PASS (N/A).
- **V — Language discipline**: Code/identifiers English; spec/plan Russian prose. PASS.

**Result: PASS** — presentation/native/crypto untouched; a pure data-layer seam extension mirroring an existing accepted reference.

## Project Structure (files)

```
lib/data/entity/chat/wire/            # NEW — wire DTOs (distinct from local Sembast entities)
├── chat_wire_entity.dart             # ChatWireEntity  (id,name,lastMessagePreview,lastMessageAt,unreadCount)
├── chats_wire_entity.dart            # ChatsWireEntity (items + page/page_size/total)
├── message_wire_entity.dart          # MessageWireEntity + MessageAttachmentWireEntity (nested)
└── messages_wire_entity.dart         # MessagesWireEntity (items + page/page_size/total)
lib/data/mapper/chat/
├── chat_wire_mapper.dart             # NEW — ChatWireEntity <-> ChatModel (bidirectional)
└── message_wire_mapper.dart          # NEW — MessageWireEntity <-> MessageModel (bidirectional, nested attachment)
lib/data/entity/base/entity_converter.dart   # EDIT — register Item + chat + message wire entities
lib/data/remote/api/chat/get_chats_api.dart      # EDIT — return ResponseEntity<ChatsWireEntity>
lib/data/remote/api/chat/get_messages_api.dart   # EDIT — return ResponseEntity<MessagesWireEntity>
lib/data/remote/datasource/chat_remote_data_source.dart      # EDIT — signature -> ResponseEntity<ChatsWireEntity>
lib/data/remote/datasource/message_remote_data_source.dart   # EDIT — getMessages -> ResponseEntity<MessagesWireEntity>
lib/data/remote/datasource/mock/mock_*_remote_data_source.dart  # EDIT — forward the new return type
lib/data/repository/chat/chat_repository_impl.dart     # EDIT — unwrap in _seedIfEmpty
lib/data/repository/chat/message_repository_impl.dart  # EDIT — unwrap in _seedChatIfEmpty/getMessages
```

Tests mirror under `test/` (see quickstart).

## Phasing

- **Phase 0 — research.md**: pin the mapping decisions (model↔wire directions, pagination, converter registration mechanism, JSON key convention).
- **Phase 1 — data-model.md + contracts/**: the wire entity fields, mapper signatures, the data-source contract signatures, and the converter registry contract.
- **Phase 2 — implement** (tasks.md): entities → mappers → converter → generators → data sources → repos → tests → one `build_runner` run → `make gate`.

## Risks

- **Generated `.g.dart` for `ResponseEntity<ChatsWireEntity>`**: `EntityConverter` is a manual registry (no per-generic codegen); the risk is a missed registration → runtime `ArgumentError`. Mitigated by the US3 round-trip tests over every registered type.
- **Behavior drift**: the redundant `model→wire→model` round-trip must be loss-free. Mitigated by SC-001 (all existing repo/BLoC/page tests pass unchanged) + explicit round-trip tests.

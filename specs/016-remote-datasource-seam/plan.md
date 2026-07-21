# Implementation Plan: Remote-Data-Source Seam (mock data layer)

**Branch**: `016-remote-datasource-seam` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/016-remote-datasource-seam/spec.md`

## Summary

Insert a thin **remote-data-source seam** between the repositories and the concrete mock APIs. Introduce one abstract interface per data-layer feature (`ChatRemoteDataSource`, `MessageRemoteDataSource`, `ChatFilesRemoteDataSource`, `ItemRemoteDataSource`), implemented by **mock data sources that delegate to the existing `*Api` mock generators** (kept as-is, so their unit tests are untouched and behaviour is byte-for-byte identical). Repositories depend on the interfaces; DI binds each interface to its mock for every environment the app boots in (`dev`/`prod`/`test`), with the production real binding reduced to a documented ≤3-step flip. No backend, no wire DTOs, no auth/apiUrl — only the raw-data boundary is abstracted.

## Technical Context

**Language/Version**: Dart `>=3.12 <4.0`, Flutter `3.44.1` (FVM-pinned)

**Primary Dependencies**: injectable + get_it (DI, interface binding via `@LazySingleton(as:)`), build_runner (regen `configure_dependencies.config.dart`), mockito (test doubles). No new package.

**Storage**: unchanged — Sembast caches, DAOs, mappers untouched. The seam is upstream of the cache.

**Testing**: `flutter_test` + `bloc_test` against the test-env DI; `mockito` for the two repo tests that construct a repo with a forced-failure double (now mock the interface, not the concrete `*Api`). The `*Api` mock-generator unit tests stay unchanged. Goldens unaffected.

**Target Platform**: iOS, Android, macOS, Windows, Linux. `main.dart` boots `Environment.prod` for the prod flavor and `Environment.dev` otherwise; the test suite uses `Environment.test`. **All three must resolve the mock** this phase (no real impl exists).

**Project Type**: single Flutter package `nox_app`, Clean Architecture layers-as-folders.

**Performance Goals**: zero runtime cost — one extra virtual dispatch (interface → mock) per network-boundary call; no added I/O.

**Constraints**: behaviour byte-for-byte unchanged; `RepositoryResult`/`PageMetadata`/error mapping untouched; no raw `print`; one `build_runner` pass; line length 140.

**Scale/Scope**: 4 new interfaces + 4 mock impls, 3 repository constructors repointed, DI regen, 2 repo-test doubles retargeted, 1 new seam test. No UI/BLoC/DAO/mapper change.

## Constitution Check

*GATE: evaluated against `.specify/memory/constitution.md` v1.1.0 (principles I–V).*

- **I. Privacy & E2EE** — PASS. No change to data, crypto, storage, or logging; purely a wiring abstraction. No PII path touched.
- **II. Spec & design corpus = source of truth** — PASS. Spec-driven. In-same-change-set drift fixes: the tracker `docs/mock-completion-plan.md` §5.1 inventory ("моки инъектятся по конкретному типу") + §5.3 P1/P5 (S1/S2), and a blueprint `04-data-layer.md` note describing the remote-data-source seam, are updated to the now-real structure. No locked out-of-scope expanded (S4/S5/backend stay out).
- **III. Architecture blueprint mandatory** — PASS. The interfaces are a **data-layer remote-boundary contract** (Clean Architecture: `data/remote/`), repositories depend on abstractions not concretes (dependency inversion), single injectable + get_it DI (`@LazySingleton(as:)`), `RepositoryResult<T>` unchanged, no raw `print`. This is exactly the seam the blueprint's networking docs (04/14/15/16, marked TBD) anticipate; it prepares the real-contract slot without inventing it.
- **IV. Design-system fidelity** — PASS. No UI/token/visual change whatsoever.
- **V. Language discipline** — PASS. English code/identifiers/commits; this doc + chat Russian.

**Result: PASS — no violations, Complexity Tracking empty.**

## Project Structure

### Documentation (this feature)

```text
specs/016-remote-datasource-seam/
├── plan.md              # This file
├── research.md          # Phase 0 — delegation vs absorb, env-flip shape, interface granularity
├── data-model.md        # Phase 1 — interface catalog + binding table
├── quickstart.md        # Phase 1 — validation + the ≤3-step flip recipe
├── contracts/           # Phase 1 — the four interface contracts + DI binding contract
│   ├── remote-data-sources.md
│   └── di-binding.md
├── checklists/requirements.md
└── tasks.md             # Phase 2 — /speckit-tasks
```

### Source Code (repository root)

```text
lib/data/remote/
├── api/chat/{get_chats_api,get_chat_files_api,get_messages_api,send_message_api}.dart  # UNCHANGED mock generators
├── api/item/get_items_api.dart                                                          # UNCHANGED
└── datasource/                                        # NEW seam
    ├── chat_remote_data_source.dart                   # abstract: getChats(config)
    ├── chat_files_remote_data_source.dart             # abstract: getChatFiles(chatId)
    ├── message_remote_data_source.dart                # abstract: getMessages(config) + sendMessage(...)
    ├── item_remote_data_source.dart                   # abstract: getItems(config)
    └── mock/                                          # mock impls (delegate to the *Api generators)
        ├── mock_chat_remote_data_source.dart          # @LazySingleton(as: ChatRemoteDataSource, env:[dev,prod,test])
        ├── mock_chat_files_remote_data_source.dart
        ├── mock_message_remote_data_source.dart       # composes GetMessagesApi + SendMessageApi
        └── mock_item_remote_data_source.dart

lib/data/repository/
├── chat/chat_repository_impl.dart     # depends on ChatRemoteDataSource + ChatFilesRemoteDataSource
├── chat/message_repository_impl.dart  # depends on MessageRemoteDataSource (was GetMessagesApi + SendMessageApi)
└── item/item_repository_impl.dart     # depends on ItemRemoteDataSource

test/  (deep-mirror)
├── data/remote/api/**                 # UNCHANGED (generators still tested directly)
├── data/repository/chat/message_repository_impl_test.dart  # forced-failure double: mock MessageRemoteDataSource
├── data/repository/item/item_repository_impl_test.dart     # double: mock ItemRemoteDataSource
└── data/remote/datasource/seam_binding_test.dart           # NEW: rebinding an interface routes the repo to it (SC-002)
```

**Structure Decision**: Delegation, not absorption. The `*Api` classes stay as internal deterministic **mock generators** (`@lazySingleton`), and a per-feature **mock data source** implements the interface by delegating to them. This (a) keeps every `*Api` unit test green with zero edits, (b) gives the interfaces clean domain method names (`getChats`, not `execute`), (c) lets a real impl later replace only the data source (the generators are then deleted). Interfaces live at `data/remote/datasource/` — a data-layer boundary contract the repositories consume (dependency inversion), not a domain type.

## Key design decisions (see research.md)

1. **Delegating mock data sources.** `MockXRemoteDataSource implements XRemoteDataSource` injects the existing `*Api` and forwards. Messages aggregate two generators (`GetMessagesApi` + `SendMessageApi`) behind one `MessageRemoteDataSource` (FR-009).
2. **Mock bound for all boot environments.** `@LazySingleton(as: XRemoteDataSource, env: [dev, prod, test])` — because `main.dart` boots `Environment.prod` for the prod flavor and no real impl exists, scoping the mock away from `prod` now would break the prod build (FR-007). The env-scoped **flip is prepared, not activated**.
3. **The flip is a documented ≤3-step recipe** (SC-006): add `RealXRemoteDataSource` `@LazySingleton(as: X, env:[prod])`, drop `prod` from the mock's env list, rebuild DI. Repos/caches/mappers/UI untouched.
4. **Seam proven by a rebinding test** (SC-002): register a fake `ChatRemoteDataSource` via `getIt` (allowReassignment) and assert `ChatRepository` routes through it — demonstrating the repo is decoupled from the concrete mock without any real backend.
5. **Contracts frozen.** `RepositoryResult`, `PageMetadata`, `BaseRepositoryHelper` error mapping unchanged (FR-011). Item keeps its `ResponseEntity<ItemsEntity>` return through `ItemRemoteDataSource.getItems` (wire-DTO population is S4, out of scope).

## Complexity Tracking

No constitution violations — section intentionally empty.

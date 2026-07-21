# Research: Remote-Data-Source Seam (mock data layer)

Phase 0 decisions, grounded in the current `lib/` code.

## R1 — Delegation vs absorption (do the `*Api` classes become the impls, or get wrapped?)

**Decision**: **Delegation.** Keep the existing `GetChatsApi` / `GetChatFilesApi` / `GetMessagesApi` / `SendMessageApi` / `GetItemsApi` as unchanged deterministic **mock generators** (`@lazySingleton`). Add a per-feature `MockXRemoteDataSource implements XRemoteDataSource` that injects the generator(s) and forwards each call.

**Rationale**:
- The five `*Api` classes each have a direct unit test (`get_chats_api_test`, `get_messages_api_test`, `send_message_api_test`, `get_chat_files_api_test`, `get_items_api_test`) that calls `.execute(...)`. Delegation keeps those classes and tests **byte-for-byte unchanged** (SC-003) — absorption would rename `execute`→`getX` and churn all five.
- Interfaces get clean domain method names (`getChats`, `sendMessage`) instead of a generic `execute`.
- When the real backend lands, the real impl replaces only the data source; the generators are then deleted. Clean lifecycle.

**Alternatives considered**:
- *Absorb: the `*Api` class implements the interface directly (rename `execute`→`getX`)* — fewer classes but churns 5 generator tests and forces `execute` or a rename; rejected.
- *Interface method named `execute`* — avoids the rename but is a poor contract name and breaks down for messages (two operations, two signatures); rejected.

## R2 — Interface granularity (how many interfaces, and how are multi-op features handled?)

**Decision**: **One interface per data-layer feature with a network boundary**, four total: `ChatRemoteDataSource` (`getChats`), `ChatFilesRemoteDataSource` (`getChatFiles`), `MessageRemoteDataSource` (`getMessages` + `sendMessage`), `ItemRemoteDataSource` (`getItems`). Messages aggregate their two generators behind one interface (FR-009).

**Rationale**: Matches the tracker §5.3 P1 inventory (four named interfaces) and the "one seam per feature" success criterion (SC-005). Chat files is kept distinct from chat list per the tracker, even though both serve the chat feature — the repository simply depends on both. Aggregating message read+send matches how a real message endpoint group would be organized.

**Alternatives considered**:
- *One interface per operation (5+)* — a repository would carry one seam per call, not per feature; noisier and diverges from the tracker; rejected.
- *Fold chat files into `ChatRemoteDataSource`* — reasonable, but the tracker lists `ChatFilesRemoteDataSource` separately and `getChatFiles` is a distinct endpoint shape; kept separate for inventory parity.

## R3 — How is the environment flip represented without a real implementation?

**Decision**: Bind the mock `@LazySingleton(as: XRemoteDataSource, env: [Environment.dev, Environment.prod, Environment.test])` — **all three environments the system uses**. The production real binding is a **prepared, documented flip point**, not an active binding.

**Rationale**: `lib/main.dart` resolves `env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev` and calls `configureDependencies(env)`. So the **prod flavor boots `Environment.prod`**. If the mock were scoped to `[dev, test]` only (as the aspirational §5.3 P5 wording suggests), a prod build would have no `XRemoteDataSource` binding and fail DI at boot (FR-007 violated). With no real impl to occupy `prod`, the mock must cover `prod` too. The env-scoping is therefore **structural readiness**: the binding is interface-based and env-annotated, so activating a real prod impl is a localized change.

**Alternatives considered**:
- *Throwing `RealXRemoteDataSource` stub registered for `[prod]`, mock for `[dev,test]`* — makes the split "literal" but the prod-flavor app would resolve a throwing data source and crash at first use; rejected (breaks FR-007).
- *Mock for `[dev,test]` only + document a TODO* — same crash risk for the prod flavor; rejected.

## R4 — Proving the seam works (US2 / SC-002) with no backend

**Decision**: A **rebinding test**: register a fake `ChatRemoteDataSource` into `getIt` (`allowReassignment`) that returns a sentinel page, then assert `getIt<ChatRepository>().getChats(...)` surfaces the sentinel — proving the repository is wired to the interface, not the concrete mock, so a future real impl swaps in via DI alone.

**Rationale**: This is the only way to demonstrate swappability before a real impl exists, and it directly exercises FR-004/FR-005/FR-006. One representative feature (chat) is enough; the pattern is uniform.

## R5 — Blast radius on existing tests

**Decision**: Only two existing tests change, both **behaviour-preserving wiring updates**:
- `message_repository_impl_test` — the forced-failure "a failed send leaves the chat row untouched" case constructs a repo with `MockSendMessageApi`. Retarget to `@GenerateMocks([MessageRemoteDataSource])`, stub `sendMessage(...)` to throw, and construct the repo with the mock data source (the constructor collapses `GetMessagesApi` + `SendMessageApi` into one `MessageRemoteDataSource`).
- `item_repository_impl_test` — constructs `ItemRepositoryImpl(mapper, GetItemsApi)`. Retarget to `@GenerateMocks([ItemRemoteDataSource])` and stub `getItems(...)`.

All other tests (the five `*Api` generator tests, all repo happy-path tests via test-env DI, all BLoC/widget/golden tests) are **untouched** and must stay green (SC-003).

**Rationale**: The generators are unchanged, and the test-env DI now resolves the mock data sources transparently, so only tests that *construct a repo by hand with a concrete mock* need retargeting.

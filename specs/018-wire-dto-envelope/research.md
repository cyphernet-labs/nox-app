# Research: Uniform wire-DTO envelope for chat & message (S4)

## R1 — Where the `model→wire` mapping lives

**Decision**: In the generators (`GetChatsApi`/`GetMessagesApi`). They keep synthesising the elaborate deterministic model-shaped seed (AppClock-relative timestamps, unread ladder, own/other authoring, one attachment, system line), then map `model→wire` and return `ResponseEntity<wire>`.

**Rationale**: Mirrors `GetItemsApi` (returns `ResponseEntity<ItemsEntity>` directly). Keeps the 016 mock data sources thin forwarders (no logic change there). Preserves the seed verbatim (SC-001). The `model→wire→model` round-trip through the boundary is deliberate: it exercises the mapper both ways and faithfully simulates "server sends wire, client maps to model".

**Alternatives**: (a) Rebuild the seed to emit wire directly (most faithful to Item, but churns the elaborate seed + the message identity-reconciliation interaction). (b) Wrap in the data source (splits envelope logic away from the generator). Rejected — R1 keeps the generator the single mock authority and the data source thin.

## R2 — Data-source interface signature

**Decision**: The 016 interfaces carry the envelope: `ChatRemoteDataSource.getChats → Future<ResponseEntity<ChatsWireEntity>>`, `MessageRemoteDataSource.getMessages → Future<ResponseEntity<MessagesWireEntity>>`. `sendMessage` unchanged (out of scope).

**Rationale**: Uniform with `ItemRemoteDataSource.getItems → Future<ResponseEntity<ItemsEntity>>`. The flip-to-backend becomes a real binding swap (the real source returns the same envelope type). Repos unwrap, exactly as `ItemRepositoryImpl`.

## R3 — Pagination in the wire list entity

**Decision**: `ChatsWireEntity`/`MessagesWireEntity` carry `items` + `page`/`page_size`/`total` (JSON keys mirror `ItemsEntity`). The repo computes `PageMetadata(total, nextPage: page*pageSize < total ? page+1 : null)` — the same formula `ItemRepositoryImpl` uses. The generator sets `page`/`pageSize`/`total` from the same slice it already computes.

**Rationale**: One pagination convention across all three list boundaries. `PageMetadata` (domain) is derived in the repo, not carried on the wire (the wire carries raw offsets like a real backend would).

## R4 — `EntityConverter` registration mechanism

**Decision**: Add per-entity branches to the manual registry using the existing `_isType<E, T>()` guard, for BOTH `fromJson` (Map → `T.fromJson`) and `toJson` (`T` → `.toJson()`), covering every entity reachable via `ResponseEntity<T>`: `ItemEntity`, `ItemsEntity`, `ChatWireEntity`, `ChatsWireEntity`, `MessageWireEntity`, `MessagesWireEntity`. Unknown type still throws `ArgumentError` (explicit "no converter").

**Rationale**: The registry is hand-maintained by design (`ResponseEntity<T>`'s `@EntityConverter()` needs a concrete resolver per generic). Item was never registered because the mock builds the envelope directly (never via `fromJson`); S4 completes the registry so a real `ResponseEntity.fromJson` would resolve. The list wrappers (`*sEntity`) are reachable via `ResponseEntity<...sEntity>`; the element entities (`*Entity`) are registered for completeness/symmetry and future single-object envelopes.

## R5 — JSON encoding conventions (basic types only)

**Decision**: Wire entities are freezed + json_serializable, **basic types only** (enum → String, DateTime → ISO-8601 String, nested attachment → nested object), matching `ItemEntity`'s doc contract. All coercion lives in the wire mapper (mirrors `ItemMapper`). Snake_case JSON keys where multi-word (`page_size`, `last_message_at`, `size_bytes`, …) via `@JsonKey`, consistent with `ItemsEntity`.

**Rationale**: Keeps the DTO dumb and the mapper the single coercion site — the project's established rule.

## R6 — Behavior preservation strategy

**Decision**: No domain model, DAO, local Sembast entity, seed values, or UI/BLoC changes. The only observable change is internal (network boundary shape). Guard: run the FULL existing suite unchanged (SC-001) — chat/message repo tests, thread/list BLoC tests, page tests must pass with zero edits. Add new tests only (round-trips + envelope unwrap + error/empty).

**Rationale**: S4 is a behavior-neutral refactor; the existing suite is the regression net.

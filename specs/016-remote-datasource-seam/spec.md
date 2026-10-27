# Feature Specification: Remote-Data-Source Seam (mock data layer)

**Feature Branch**: `016-remote-datasource-seam`

**Created**: 2026-07-25

**Status**: Draft

**Input**: User description: "Per-feature `*RemoteDataSource` abstract interfaces implemented by the existing mock APIs; repositories depend on the interface, not the concrete mock; DI wired so mock↔real is an Environment-scoped configuration flip, not a repository rewrite. Seam/systematization only — no backend built, behaviour byte-for-byte unchanged, the app still runs on mocks in every flavor. Tracker tasks S1 + S2; wire DTOs (S4) and auth/apiUrl seam (S5) are out of scope."

## Overview

Today the repositories reach their network boundary through **concrete mock classes** (`GetChatsApi`, `GetMessagesApi`, `SendMessageApi`, `GetChatFilesApi`, `GetItemsApi`), injected by concrete type. When the real backend lands, swapping a mock for a real network call therefore means **editing every repository constructor and its dependency wiring** — the seam runs through the repositories, not around them.

This feature introduces a thin **remote-data-source seam**: a small abstract interface per feature that names exactly the network-boundary operations the repositories already call. The existing mock classes become the **mock implementations** of those interfaces, and each repository depends on the **interface**. The dependency-injection wiring binds the interface to the mock and is structured so that a future real implementation is introduced by an **environment-scoped configuration change** — not by touching repositories, caches, mappers, result/paging types, or any UI/screen logic.

Nothing about runtime behaviour changes: the mocks stay the only real implementation this phase, every screen and flow behaves identically, and the app boots and runs on mocks in every flavor. The payoff is entirely structural — it turns "integrate the backend" from a cross-cutting rewrite into a localized, well-defined swap.

## User Scenarios & Testing *(mandatory)*

*(The "user" here is a developer integrating the backend and the team maintaining the data layer; the value is delivered to the product indirectly, by making backend integration safe and localized.)*

### User Story 1 - Repositories depend on a seam, not a concrete mock (Priority: P1)

As a developer, when I open a repository I see it depends on an **abstract remote-data-source interface** that names the network operations it needs — not a concrete mock class — so I can reason about the network boundary and later provide a different implementation without editing the repository.

**Why this priority**: This is the seam itself. Without it, every later backend task is a repository rewrite. It is the foundation the environment flip (US2) builds on and delivers value on its own (clarity + testability of the boundary).

**Independent Test**: Inspect each repository — its constructor/field types reference only interfaces for the network boundary; a search shows no repository importing a concrete `*Api` mock class. All existing tests still pass unchanged (behaviour is identical).

**Acceptance Scenarios**:

1. **Given** the chat/message/item repositories, **When** their dependencies are examined, **Then** each network-boundary dependency is an abstract interface (`ChatRemoteDataSource`, `MessageRemoteDataSource`, `ChatFilesRemoteDataSource`, `ItemRemoteDataSource`), and no repository references a concrete mock class.
2. **Given** the existing mock classes, **When** the seam is introduced, **Then** each mock is the implementation of its interface and its deterministic behaviour is unchanged (same data, same delays, same shapes).
3. **Given** the full existing test suite, **When** it runs after the change, **Then** every test passes with no assertion changes attributable to behaviour (only wiring/type references may change).

---

### User Story 2 - Mock↔real is an environment-scoped config flip (Priority: P1)

As a developer, when a real implementation eventually exists, I can put it into use by an **environment-scoped binding change** — registering the real implementation for the production environment and scoping the mock to the non-production environments — **without touching** repositories, caches, mappers, result/paging types, or any UI.

**Why this priority**: This is the whole point of the seam — that the swap is configuration, not surgery. It is independently demonstrable: even with no real implementation, the binding can be shown to be interface-based and environment-scoped, and the flip recipe reduced to a single, localized change.

**Independent Test**: Confirm the interface→implementation binding is resolved through the dependency-injection container per environment; demonstrate (in a test) that rebinding the interface to a different implementation makes the repository use it, with zero repository/cache/mapper/UI edits.

**Acceptance Scenarios**:

1. **Given** the dependency-injection wiring, **When** a repository resolves its remote data source, **Then** the concrete implementation is selected by environment binding (interface → implementation), not hard-referenced in the repository.
2. **Given** a hypothetical real implementation of an interface, **When** it is registered for the production environment and the mock is scoped away from production, **Then** the flip requires changes only to the data-source implementation/registration — repositories, caches, mappers, result/paging types, and UI are untouched.
3. **Given** every flavor the app ships (stage/prod) this phase, **When** the app boots, **Then** it resolves the **mock** implementations and runs exactly as before (no real network call is introduced).

---

### Edge Cases

- **App must still run in every flavor**: because no real implementation exists yet, the mock must remain bound for every environment the app actually boots in; the "production real binding" is a prepared, documented flip point, not an active binding that would break a running build.
- **Test environment**: the test suite continues to resolve the mock implementations exactly as today (the seam must not require test rewrites beyond type/reference updates).
- **A feature with more than one mock class** (messages: read + send): its single interface aggregates all of that feature's network operations, implemented by one mock data source, so a repository has one seam per feature rather than one per operation.
- **The verification-only Item slice**: it participates in the seam for consistency even though it is not mounted, so the pattern is uniform across the data layer.
- **No behavioural divergence**: the seam is a pass-through — an operation's inputs, outputs, ordering, timing, and error surface are identical before and after.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST define one abstract remote-data-source interface per data-layer feature that needs a network boundary: chat list, chat messages (read + send), chat files, and items.
- **FR-002**: Each interface MUST declare exactly the network-boundary operations its repository calls today, with the same inputs and outputs (no added, removed, or reshaped operations).
- **FR-003**: The existing mock classes MUST become the mock implementations of these interfaces, preserving their deterministic behaviour (data, timing, shapes) byte-for-byte.
- **FR-004**: Every repository MUST depend on the relevant interface(s) rather than any concrete mock class; no repository may reference a concrete mock implementation.
- **FR-005**: The dependency-injection container MUST bind each interface to its mock implementation so repositories receive the implementation without naming it.
- **FR-006**: The binding MUST be environment-scoped such that introducing a real implementation for production is a localized registration change that scopes the mock away from production — with no edits to repositories, caches, mappers, result/paging types, or UI.
- **FR-007**: The application MUST continue to boot and run on the mock implementations in every shipped flavor (no real network call is introduced this phase).
- **FR-008**: Observable behaviour MUST be unchanged: every existing screen, flow, and test behaves identically; the only permitted changes are wiring, type references, and the new interfaces/registrations.
- **FR-009**: A feature whose network boundary spans more than one mock operation (message read + send) MUST be represented by a single aggregating interface for that feature.
- **FR-010**: The change MUST introduce no new user-facing visual output (no new golden baselines), and all existing golden baselines MUST remain valid.
- **FR-011**: The seam MUST NOT alter the shared result/paging/error contracts (success-XOR-error results, page metadata, the repository error mapping) — only the boundary through which the repository obtains raw data.
- **FR-012**: The flip recipe (how to introduce a real implementation) MUST be documented so the future backend task is a checklist, not a rediscovery.

### Key Entities *(include if feature involves data)*

- **Remote-data-source interface (per feature)**: an abstract contract naming the network-boundary operations for one feature (chat list / messages / chat files / items). No data of its own; it is the seam type the repository depends on.
- **Mock remote-data-source implementation**: the deterministic, offline implementation of an interface (the current mock classes, re-typed as implementations). Same synthesized data and timing as today.
- **Binding (per environment)**: the dependency-injection mapping from an interface to a concrete implementation, selected by environment; the single point a future real implementation is introduced.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of repository network-boundary dependencies are abstract interfaces; a search finds 0 repositories referencing a concrete mock class.
- **SC-002**: Introducing a hypothetical real implementation for one feature touches only that feature's data-source implementation + its registration — 0 changes to repositories, caches, mappers, result/paging types, or UI (demonstrated by walking the flip on paper/in a test double).
- **SC-003**: 0 behavioural regressions — the entire pre-existing test suite passes unchanged (no assertion edits attributable to behaviour), and all existing golden baselines still match.
- **SC-004**: The app boots and runs on mocks in every flavor after the change (verified by the per-platform compile-smoke/boot path), with 0 real network calls.
- **SC-005**: The number of interfaces equals the number of data-layer features with a network boundary (one seam per feature), and every existing mock class is reachable only as an implementation of its interface.
- **SC-006**: A developer can state the complete "swap to real" recipe for any one feature in ≤ 3 localized steps, all confined to the data layer's remote/DI wiring.

## Assumptions

- **Environment binding, not a throwing prod stub**: because the app must run on mocks in every shipped flavor and no real implementation exists, the mock is bound for the environments the app actually boots in; the production real binding is a prepared, documented flip point rather than an active (throwing) binding that would break a running build. The plan confirms which environment(s) each flavor boots with before scoping.
- **One interface per feature, aggregating its operations**: messages (read + send) are one `MessageRemoteDataSource`; chat list is `ChatRemoteDataSource`; chat files is `ChatFilesRemoteDataSource` (kept distinct per the tracker inventory, though both serve the chat feature); items is `ItemRemoteDataSource`.
- **Interfaces live at the data layer's remote boundary** (they are a data-layer contract the repositories consume), consistent with the architecture blueprint; they are not domain-layer types.
- **The mock classes keep their current data-synthesis logic** — the refactor re-types/relocates them as implementations and, where a feature aggregates multiple mock operations, composes the existing mocks behind one implementation rather than rewriting their logic.
- **Result/paging/error contracts are untouched** — `RepositoryResult`, `PageMetadata`, and the `BaseRepositoryHelper` error mapping (incl. the S3 HTTP→exception mapping already merged) are unchanged; this feature only abstracts the raw-data boundary.
- **Scope boundaries**: no real backend, no wire DTOs / `EntityConverter` population (S4), no `apiUrl`/auth-token/`ApiClient` interceptor seam (S5), no change to Sembast caches, DAOs, mappers, or any BLoC/UI. Non-networked repositories (settings, session, app-state, app-config, log, camera-permission) are out of scope — they have no network boundary to seam.

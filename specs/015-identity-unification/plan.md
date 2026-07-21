# Implementation Plan: Unified Signed-In Identity (mocks)

**Branch**: `015-identity-unification` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/015-identity-unification/spec.md`

## Summary

Make the **local session the single source of truth** for the signed-in identity (technical identifier + display label) and wire every surface to it. Three disconnected placeholders are removed: the thread's hard-coded own author (`me` / `You`), the Settings compile-time default label, and the shell's one-shot avatar-label read. Concretely: (1) the chat thread resolves its own-identity from the session and seeded own-history is reconciled to that identifier so own-vs-other stays correct; (2) the Settings identity card loads the session label and a confirmed rename **persists** it; (3) a confirmed rename **broadcasts live** via a reactive session-label signal so the desktop rail account avatar (and any on-screen surface) updates without a restart. No backend — everything runs on the existing `SessionRepository` (secure storage + preferences) and the mock data path.

## Technical Context

**Language/Version**: Dart `>=3.12 <4.0`, Flutter `3.44.1` (FVM-pinned)

**Primary Dependencies**: flutter_bloc + freezed (BLoC), injectable + get_it (DI), rxdart (stream operators), flutter_secure_storage + shared_preferences (session store), Sembast (chat/message cache). No new package.

**Storage**: existing session store — identifier in `flutter_secure_storage` (unchanged by rename), `label` / onboarding flag in `shared_preferences`. Chat/message history in Sembast (seed reconciliation happens here).

**Testing**: `flutter_test` + `bloc_test` against the test-env DI (`configureDependencies(Environment.test)`); `mockito` only where a path must be forced. Goldens unaffected (no new visual layout — behavioural feature).

**Target Platform**: iOS, Android, macOS, Windows, Linux (web out of scope). The rail account avatar is desktop-only (`_wide`); the identity source + Settings behaviour are shared across both layouts.

**Project Type**: single Flutter package `nox_app`, Clean Architecture layers-as-folders.

**Performance Goals**: a confirmed rename reflects on all on-screen surfaces within ~1s (SC-003); no perceptible added latency opening a thread (one extra cached session read, no network).

**Constraints**: no backend/network; no raw `Color`/size literals outside `lib/design/theme/`; no raw `print` (LogRepository); one `build_runner` pass for codegen; line length 140.

**Scale/Scope**: ~8 source files touched across data + presentation, one interface extension, one pure resolver util. No new screen.

## Constitution Check

*GATE: evaluated against `.specify/memory/constitution.md` v1.1.0 (principles I–V).*

- **I. Privacy & E2EE** — PASS. The technical identifier stays in secure storage and is never fabricated; own-detection uses it internally only (it is NOT surfaced as the scannable `Your ID`, which keeps degrading to empty on a failed read). No PII enters logs/analytics. No content leaves the device. Rename touches only the local non-secret label.
- **II. Spec & design corpus = source of truth** — PASS. Spec-driven. In-same-change-set drift fixes: the `IdentityMockData` doc-comment (`TODO(backend): replace…`), the `SettingsRootBloc` / `TabBarShell` `TODO(backend): live label` notes, and the blueprint `04`/`05` reactive-signal notes are updated to describe the now-real behaviour. No locked out-of-scope is expanded (profile screen / multi-account / real backend stay out).
- **III. Architecture blueprint mandatory** — PASS. Freezed BLoCs (Settings/Thread already), `RepositoryResult<T>` for the new repository method, injectable + get_it (extend the existing `SessionRepository` singleton), design tokens only, no raw `print`. The shell subscription is a **minimal, documented extension of the already-sanctioned 05 §5.1 UI-first carve-out** (the shell already does a one-shot repo read + `setState`; this upgrades it to a subscription). A full shell value-BLoC remains the backend-phase migration.
- **IV. Design-system fidelity** — PASS. No visual/token change; the avatar already renders from tokens. Behavioural only.
- **V. Language discipline** — PASS. Code/identifiers/commits English; this doc + chat Russian; UI microcopy English.

**Result: PASS — no violations, Complexity Tracking empty.**

## Project Structure

### Documentation (this feature)

```text
specs/015-identity-unification/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions (broadcast, seed reconcile, own-id fallback)
├── data-model.md        # Phase 1 — Identity value object + session/label state
├── quickstart.md        # Phase 1 — manual + automated validation guide
├── contracts/           # Phase 1 — SessionRepository extension, resolver, bloc contracts
│   ├── session-repository.md
│   ├── identity-resolver.md
│   └── blocs.md
├── checklists/
│   └── requirements.md  # spec quality checklist (16/16)
└── tasks.md             # Phase 2 — /speckit-tasks (NOT created here)
```

### Source Code (repository root)

```text
lib/
├── general/
│   ├── identity_mock_data.dart          # REPURPOSE: fallback own-id sentinel only (no-session)
│   └── identity/
│       └── identity_resolver.dart        # NEW pure util: resolveIdentity(SessionModel?) → (id, label)
├── domain/
│   ├── model/app/identity.dart           # NEW tiny value object Identity{id,label} (or record alias)
│   └── repository/app/session_repository.dart   # EXTEND: updateLabel(), watchLabel()
├── data/
│   ├── repository/app/session_repository_impl.dart   # EXTEND: label broadcast + updateLabel
│   ├── repository/chat/message_repository_impl.dart  # seed reconcile + send authoring from session
│   └── remote/api/chat/
│       ├── get_messages_api.dart         # seed status check keyed on the fallback sentinel
│       └── send_message_api.dart         # accept resolved author id/label (dumb echo)
└── presentation/
    ├── pages/settings_root_page/bloc/settings_root_bloc.dart   # load label + persist rename
    ├── pages/chat_thread_page/bloc/chat_thread_bloc.dart       # currentId + author label from session
    └── widgets/shell/tab_bar_shell_widget.dart                 # subscribe to watchLabel()

test/  (deep-mirror)
├── general/identity/identity_resolver_test.dart                # NEW
├── data/repository/app/session_repository_impl_test.dart       # NEW/EXTEND: updateLabel + watchLabel
├── data/repository/chat/message_repository_impl_test.dart      # EXTEND: seed reconcile + send authoring
├── presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart  # EXTEND: load + persist
├── presentation/pages/chat_thread_page/bloc/chat_thread_bloc_test.dart      # EXTEND: currentId source
└── presentation/widgets/shell/tab_bar_shell_identity_test.dart # NEW: live avatar-label update
```

**Structure Decision**: Existing single-package Clean Architecture. The identity resolution rule lives in ONE pure util (`resolveIdentity`) consumed by the thread bloc and the message repository so the thread's `currentId` and the seed-reconciled own rows always agree. The reactive label signal is a broadcast stream on the existing `SessionRepository` singleton (not a new repository, not a shell-local notifier), consistent with feature-014's watch-as-change-signal pattern.

## Key design decisions (see research.md for rationale)

1. **Single own-identity, resolved with fallbacks.** `resolveIdentity(session) = (id: session?.identifier ?? kFallbackOwnId, label: session?.label (non-empty) ?? Constants.defaultUserLabel)`. `kFallbackOwnId = 'me'` is the no-session sentinel AND the seed's raw own-author, so with or without a session the thread's `currentId` and the seeded own rows resolve to the **same** id.
2. **Seed reconciliation at seed time.** `MessageRepositoryImpl._seedChatIfEmpty` rewrites seed rows authored with `kFallbackOwnId` to the resolved own-id before persisting. Safe because the identifier is **stable for the life of the local DB** — it changes only on logout, which (feature D1) wipes the chat+message caches → the chat re-seeds with the new identity. No mid-life identifier swap.
3. **Reactive label broadcast.** `SessionRepository.watchLabel()` (broadcast) emits the current cached label on listen, then every subsequent change; `updateLabel()` writes prefs + emits; `clear()` emits null. The shell subscribes (replacing the one-shot read); Settings' rename calls `updateLabel`.
4. **Own-detection is identifier-keyed (rename-invariant).** Renaming changes only the label; no message's own/other side can change (FR-011/SC-006).
5. **No new goldens.** The feature is behavioural; the avatar/thread layouts are unchanged, so existing goldens stay valid. Coverage is unit/repo/bloc/widget.

## Complexity Tracking

No constitution violations — section intentionally empty.

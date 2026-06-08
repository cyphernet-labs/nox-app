# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**NOX** — secure mobile messenger for iOS and Android, to be built in Flutter (Dart). Design anchor: **Signal**-like — end-to-end encrypted text and file exchange. Product name in UI, wordmarks and prose is `NOX` (all caps); the GitHub repo is `cyphernet-labs/nox-app` (lowercase, technically derived). Russian working name in materials: «Секюрный Мессенджер».

**Status — design phase, no application code yet.** The repo holds documentation only: there is no `lib/`, no `pubspec.yaml`, no build system, and Flutter/Dart are not installed here. What *does* exist is a substantial design corpus (vision/requirements drafts, a locked UI/UX spec with a full design system, and a Flutter design-token handoff), the adopted NOX Flutter architecture blueprint, and Spec Kit scaffolding (all below). The transport protocol, sync model and server are still open.

## Language Conventions

| Surface | Language |
|---|---|
| Chat with the user | Russian |
| Documentation prose in `docs/` | Russian |
| Code, identifiers, file/dir names, shell commands | English |
| Commit messages, branch names, PR titles | English |
| **In-product UI microcopy** (labels, buttons, errors — even quoted inside Russian docs) | **English** |

Do not mix languages within one artifact. UI nuance: the app's user-facing languages are **English + Ukrainian** (system default, fallback to English); **Russian is never a UI language** — only the language of internal docs and chat. So UI strings stay English even inside otherwise-Russian design docs.

## Repository / Documentation Map

The big picture is spread across doc clusters; read the relevant one before working in its area.

- **`docs/vision.md`, `docs/requirements.md`** — product vision and functional requirements. **Drafts/skeletons** (many `TODO`s); direction, not settled scope.
- **`docs/design/spec/`** — the authoritative NOX **UI/UX specification** and the most complete part of the repo. `overview.md` (top-level UI requirements + a large decisions table), `top-level-screens.md` (screen map), `screens/*.md` (one spec per screen), `design-system.md` (color/type/shape/motion/icons/component tokens). Top-level UI is **locked**; screens are detailed and reviewed.
- **`docs/design/system/nox-handoff/`** — machine-readable design-system handoff: `tokens/*.tokens.json` (W3C DTCG — the tool-agnostic **source of truth**) plus generated, ready-to-drop Flutter Dart (`nox_theme.dart`, `nox_color_scheme.dart`, `nox_tokens.dart`, `nox_brand.dart`, `nox_text_theme.dart`). Dart and JSON derive from one source — regenerate from tokens rather than hand-editing one out of sync.
- **`docs/patterns/mobile/`** — the **adopted NOX Flutter Clean Architecture blueprint** (`00`–`17`, index in `README.md`). **Consult it at the start of any mobile/Flutter task and build to it** — see its section below.
- **`.specify/` + `.claude/skills/speckit-*`** — Spec Kit tooling; see *Spec Kit workflow*.

Conventions for this phase:
- New design artifacts (architecture, ADRs, threat model, protocol) go in `docs/` as Russian prose.
- Branch model: `master` holds release commits only; `develop` is the working branch where day-to-day work and feature branches start. Remote: `https://github.com/cyphernet-labs/nox-app.git`, hosting `master` + `develop`.
- During bootstrap the user tracks everything: do **not** add `.gitignore` entries for intermediate/temporary files (revisit once Flutter is initialized).
- Do **not** run `flutter create` or scaffold app files unless explicitly asked.

## NOX product model — facts that span the design spec

NOX-specific decisions to know before reasoning about any screen or future data model; each is synthesized from `docs/design/spec/overview.md` (+ `screens/`):

- **Open shared space, not Signal 1:1.** All chats are visible to everyone; no permissions; anyone can create a chat and write in any chat; there is no "join" flow; chats are never deleted. Signal mechanics tied to a fixed 1:1 audience (delivered/read receipts, membership, per-chat subscriptions) are deliberately dropped or reinterpreted.
- **Two-layer identity.** A technical anonymous **identifier** (shown as `Your ID`, a long key-like string entered by paste or QR — no phone/email) plus a public **label** (display name). Server assigns `User<random>` at first login (a name always exists); label is globally unique case-sensitive, ≤32 chars, charset `[A-Za-z0-9._-]`. One identity per device; switching = Logout (full local wipe) + re-login.
- **Message status is local-only:** `sent` (accepted by server) + `pending`/`error`; **no delivered/read** (no fixed recipient in an open space).
- **Shell:** 3-item bottom bar — `Chats` tab, central docked **`+`** FAB (create chat, visible on both tabs), `Settings` tab. **No profile screen** — profile-like items live in Settings.
- **Theming:** Material Design 3, light + dark via `ColorScheme` (default system), seed = teal extracted from the logo. Two brand-fixed exceptions independent of theme: splash background always dark, QR surface always light.
- **Chat name:** globally unique, ≤64 chars, unrestricted charset. Chat avatars are generated (initials + hash-picked color from a fixed palette).
- Explicitly **out of scope** this iteration: calls, reactions/stickers, voice messages, stories, mentions/threads, profile screen, moderation/permissions/owners, multi-account, delivered/read, per-chat mute/pin, Support section, file content previews (type-icon chips only).

## Flutter architecture blueprint (`docs/patterns/mobile/`) — adopted

The adopted architecture for NOX's Flutter app (package `nox_app`, app id `com.cyphernetlabs.noxapp`/`.stage`), de-projectized from an earlier blueprint. Load-bearing decisions: **one Dart package**, Clean Architecture layers as folders (`presentation → domain ← data`, `domain` imports nothing); **BLoC = Freezed** (`@freezed sealed` State/Event, thin `BaseBloc`, computed logic in extension getters, no `*.g.dart` on BLoC types); single **injectable + get_it** DI (`configureDependencies(env)`); `RepositoryResult<T>` (success XOR error) everywhere; **Sembast** cache-first reactive repositories with a **network-only carve-out** for server-owned paginated lists and one-shot POSTs (the open chats list is the first such real feature); `infinite_scroll_pagination` v5 (`PagingState`-in-bloc); design-token-only UI; FVM-pinned Flutter `3.44.1`, line length 140, stock `flutter_lints`; codegen-first (freezed + json_serializable + injectable + flutter_gen, one `build_runner` run).

> **Rule: at the start of any mobile/Flutter task, consult the relevant blueprint doc(s) (`README.md` index → layer docs `00`–`17`) and build to them.** If real code ever drifts from the blueprint, bring the blueprint back to a correct state in the same change-set. **Caveat:** NOX's backend/protocol is not chosen yet, so the networking/auth/envelope/endpoint specifics in `04`/`14`/`15`/`16` are explicit **example placeholders marked TBD** — replace them with the real contract once the backend is decided. The app is not scaffolded yet (no `lib/`/`pubspec.yaml`).

## Spec Kit workflow

Spec Kit is installed (CLI `specify`; tracked under `.specify/` + `.claude/skills/speckit-*`). Spec-driven flow via slash-command skills: `/speckit-constitution` → `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`; optional `/speckit-clarify`, `/speckit-analyze`, `/speckit-checklist`, `/speckit-taskstoissues`. Templates and scripts live in `.specify/templates` and `.specify/scripts/bash`; a new feature scaffolds under `specs/NNN-*`. **The constitution (`.specify/memory/constitution.md`) is still the unfilled template** — run `/speckit-constitution` to populate it before relying on it.

## Build / test / run

There is **no runnable build system in this repo yet** — no `pubspec.yaml`, and Flutter/Dart are not installed. No build/lint/test commands apply at this stage.

When the Flutter app is scaffolded, the canonical (FVM-based) commands are documented in `docs/patterns/mobile/12-dev-commands.md` and are **not applicable until then**: deps `fvm flutter pub get`; codegen `fvm dart run build_runner build --delete-conflicting-outputs` (single pass); format changed files only `fvm dart format -l 140 <paths>`; `fvm flutter analyze` (zero-errors gate); tests `fvm flutter test` (single test `fvm flutter test <path>`, integration `fvm flutter test integration_test`).

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

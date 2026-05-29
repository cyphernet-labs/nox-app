# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**NOX** — secure mobile messenger for iOS and Android, planned to be written in Flutter (Dart). Design anchor: **Signal**-like — end-to-end encrypted text messages and file exchange over a secure protocol. **Product name shown in UI, wordmarks and prose is `NOX` (all caps)**; the GitHub repo is `cyphernet-labs/nox-app` (lowercase, technically derived). Russian-facing user-visible name is «Секюрный Мессенджер».

**Status:** Initial documentation / design phase. There is no source code yet — by design the repo contains only documentation while requirements, scope and architecture are being worked out. The exact transport protocol, sync model and tech stack are intentionally not decided yet.

## Language Conventions

| Surface | Language |
|---|---|
| Chat with the user | Russian |
| Documentation in `docs/` | Russian |
| Code, identifiers, file names | English |
| Commit messages, branch names, PR titles | English |

Do not mix languages within a single artifact: code stays English even when described from a Russian doc; doc prose stays Russian even when quoting English APIs or identifiers.

## Repository Layout

```
docs/   → Project documentation (in Russian). The only populated directory at this stage.
```

Other directories (`lib/`, `android/`, `ios/`, `pubspec.yaml`, etc.) will be added later once the design phase completes. Do **not** run `flutter create` or scaffold Flutter project files unless explicitly requested by the user.

## Working in the Documentation Phase

- New design artifacts (vision, requirements, architecture, ADRs, threat model) go in `docs/`.
- There are no build / test / lint commands yet — Flutter and Dart are not installed in this environment, and `pubspec.yaml` does not exist.
- Do **not** add entries to `.gitignore` for intermediate or temporary files during this phase; the user wants everything tracked while the project bootstraps. This rule will be revisited once Flutter is initialized.
- Repo's local default branch is `master`; the main branch used for PRs is `main` (none of them have commits yet).
- There is no GitHub remote activity yet beyond the empty repo at `https://github.com/cyphernet-labs/nox-app.git`.

## Flutter Stack (Future, Not Yet Adopted)

Sibling Flutter projects under `../` (e.g. `mycitadel-flutter`, `ray-flutter`) use:

- **FVM** for a pinned Flutter SDK version
- **flutter_bloc** + **provider** for state management
- **injectable** + **get_it** for DI
- **freezed** + **json_serializable** for immutable models / serialization
- **build_runner** for code generation
- Clean Architecture split across `lib/` (presentation), `domain/`, `data/` packages

These conventions are **not yet binding** for NOX. Confirm with the user before adopting any specific dependency, architecture pattern or folder layout for this project.

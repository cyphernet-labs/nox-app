# Implementation Plan: Спаривание и устройства — ссылка с машины сервера, `Allow`/`Deny`, список устройств и отзыв

**Branch**: `046-pairing-devices` (от `security-rework` после 044 и 045, PR — в `security-rework`) | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/046-pairing-devices/spec.md`

## Summary

Устройство добавляется двумя путями. Ссылка с машины сервера — 10 минут, живая одна, без подтверждения: со служебной страницы (сразу, пока устройств нет; по `Add a device` — когда есть) и командой `noxd link`, которая получает её у работающего сервера через служебный loopback-адрес; в журнал ссылка не пишется. Приглашение со спаренного устройства — 10 минут, срабатывает только после `Allow` на выдавшем: `pair` отвечает `pending`, сервер держит запрос и шлёт исход событием; выдавшее устройство получает запрос событием и отвечает `device.approve`; новое может отменить ожидание (`pair.cancel`). «Владелец» уходит: один человек, ссылка с машины создаёт его или присоединяет к нему.

В приложении — экран ожидания с `Cancel` и исходами, диалог `New device: <OS>. Allow it to join?` поверх любого экрана; экраны 2.1, 2.2 и 7.8 теряют устаревшие состояния.

## Technical Context

**Language/Version**: Go 1.27 (`client_backend/`); Dart 3.12 (Flutter `3.44.1`).

**Primary Dependencies**: stdlib, `coder/websocket`, `modernc.org/sqlite` — новых зависимостей нет; приложение — существующий стек.

**Storage**: сервер — `pair_tokens` (`kind 'machine'`, `issuer_key`, обязательный `expires_at`), новая `pair_requests`, без `owner_user_id`/`claimed_at` (`001_init.sql` на месте); приложение — без новых хранилищ (запросы — в памяти).

**Testing**: Go `go test -race` (токены, запросы, события, страница, `noxd link`); Dart — блоки ожидания и запросов, виджеты, голдены обеих ширин; сквозной прогон на macOS.

**Target Platform**: пять платформ приложения; сервер — Linux, macOS, Windows.

**Project Type**: мобильное + десктопное приложение и Go-сервер; меняется §8A контракта v0.

**Performance Goals**: второе устройство — меньше минуты, считая `Allow` (SC-001); исход — событием сразу после ответа.

**Constraints**: без `Allow` приглашение не добавляет устройство (SC-002); одна живая ссылка с машины (SC-004); ни ссылки, ни токена в журнале (SC-005).

**Scale/Scope**: один человек, единицы устройств, редкие спаривания.

## Constitution Check

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Запрос несёт только семейство системы; токены и ссылки не пишутся в журнал. | ✅ |
| II. Спека | Экраны ожидания и диалога — новые в `docs/design/spec/` и обоих корпусах; 2.1, 2.2, 7.8 — правятся в том же change-set'е. | ✅ |
| III. Блюпринт | Экран ожидания — состояние экрана подключения (045, свой блок); служба запросов — data/domain; `RepositoryResult`, `LogRepository`. | ✅ |
| IV. Дизайн-система | Диалог — `AlertDialog` по токенам; ожидание — существующие компоненты онбординга. | ✅ |
| V. Языки | Документы — русский; код — английский; микрокопия — EN + UK. | ✅ |
| VI. Паритет | Ожидание, диалог, 7.8 — обе ширины, голдены mobile + desktop. | ✅ |
| VII. Контракт | Дельта §8A — первой (`contracts/wire-pairing.md`); инвариант 3 (события вне журнала) дополняется тремя новыми; «ответ раньше рассылки» соблюдается для `device.approve`. | ✅ |

## Project Structure

### Documentation (this feature)

```text
specs/046-pairing-devices/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/{wire-pairing,service-page-link,pairing-ui}.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
client_backend/
├── migrations/001_init.sql                      # pair_tokens, pair_requests, − owner
├── internal/store/{pairing,serverkey,devices}.go, internal/store/requests.go (НОВОЕ)
├── internal/server/{pairing,ws,handlers,status,status_page,server,client}.go
├── internal/server/requests.go                  # НОВОЕ: запросы, таймер сроков, события
├── internal/server/control.go                   # НОВОЕ: /control/link
├── internal/protocol/frames.go                  # pair.cancel, device.approve, события
├── main.go                                      # подкоманда link
└── cmd/smoke/main.go                            # приглашение с подтверждением

lib/
├── data/remote/socket/nox_socket_client.dart    # pending, pair.cancel, события
├── data/sync/live_identity_handshake.dart       # ожидание исхода
├── domain/service/pair_request_service.dart, data/sync/pair_request_service_impl.dart   # НОВОЕ
├── data/repository/app/auth_repository_impl.dart
├── presentation/pages/connect_page/             # ожидание и исходы (045)
├── presentation/app_root/                       # диалог Allow/Deny
├── presentation/pages/{login_page,qr_scan_page,devices_page}/
└── l10n/app_{en,uk}.arb

docs/ — contract-draft.md §8A; design/spec/screens/{connect,devices,login,qr-scan}.md + новый pair-request.md; корпуса обеих ширин; client_backend/CLAUDE.md; CLAUDE.md
```

**Structure Decision**: на сервере — новые `requests.go` (стор и сервер) и `control.go`; в приложении — служба запросов в data-слое и диалог на уровне `AppRoot`.

## Complexity Tracking

Нет отступлений.

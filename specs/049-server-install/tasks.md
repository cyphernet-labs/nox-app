# Tasks: Установка сервера

**Input**: Design documents from `specs/049-server-install/`
**Prerequisites**: plan.md, spec.md, research.md, quickstart.md; 045–047 влиты в `security-rework`

**Tests**: macOS — на этой машине; статическая проверка скриптов; Linux и Windows — владелец.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] T001 `noxd link -qr` в `client_backend/main.go` / CLI (046): QR-код символами терминала через `rsc.io/qr`; тест вывода (ширина, тихая зона)
- [ ] T002 [P] Шаблоны `deploy/nox-tor.conf.tmpl` (`HiddenServiceDir`, `HiddenServicePort 443 127.0.0.1:<порт>`, `HiddenServicePoWDefensesEnabled 1`), `deploy/noxd.service.tmpl`, `deploy/com.cyphernetlabs.noxd.plist.tmpl`

## Phase 2: User Story 1 — установка с нуля (P1) 🎯 MVP

- [ ] T003 [US1] `deploy/install-macos.sh`: проверки (права, порт, бинарник), учётная запись `_nox`, папки, бинарник (сборка или `--binary`), tor (Expert Bundle, проверка подписи, ad-hoc подпись, launchd), onion-адрес, служба сервера, ожидание `/health`, пароль дважды → `noxd unlock` из stdin, `noxd link -qr`, инструкция после перезагрузки; `--prefix` и `--no-service` для проверки без системы
- [ ] T004 [P] [US1] `deploy/install-linux.sh`: то же для Linux (пакет дистрибутива ≥ 0.4.9 или репозиторий Tor Project, systemd, `nox`)
- [ ] T005 [P] [US1] `deploy/install-windows.ps1`: то же для Windows (Tor Expert Bundle, служба Windows, `NT SERVICE\noxd`)

## Phase 3: User Story 2 — перезагрузка (P1)

- [ ] T006 [US2] Автозапуск обоих сервисов во всех скриптах; сообщение в конце: как открыть сервер (`http://127.0.0.1:8081` или `sudo noxd unlock`); проверка на macOS: перезапуск службы → `locked` → `noxd unlock` → `ok`

## Phase 4: User Story 3 — повтор и без tor (P2)

- [ ] T007 [US3] Режим обновления во всех скриптах (база есть — не трогать базу, пароль, ключ onion-адреса); `--no-tor`; сбой tor — сервер без него и понятное сообщение; откат частичных изменений при сбое; проверка на macOS

## Phase 5: Polish

- [ ] T008 [P] `deploy/README.md` — по системам: запуск скрипта и ручная установка (строки tor как на странице темы 2); `docs/client-backend/{README,demo-runbook}.md`, `client_backend/CLAUDE.md` (сервер ставится скриптом, tor отдельно)
- [ ] T009 Статическая проверка: `shellcheck deploy/*.sh` и `PSScriptAnalyzer` (если установлены); `bash -n`
- [ ] T010 Прогон на macOS по `quickstart.md`; итог — в `research.md`
- [ ] T011 Трекер `docs/client-backend/roadmap-security.md`: 049 реализована; итог переделки тем 1–4

## Dependencies & Execution Order

T001 → T003 → T006 → T007; T002 до T003–T005; T004, T005 — параллельно с T003; Polish — в конце.

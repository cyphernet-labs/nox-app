# Implementation Plan: Установка сервера на Linux, macOS и Windows — сервер, tor, пароль, автозапуск

**Branch**: `049-server-install` (от `security-rework` после 045–047, PR — в `security-rework`) | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/049-server-install/spec.md`

## Summary

По скрипту на систему (`deploy/install-linux.sh`, `deploy/install-macos.sh`, `deploy/install-windows.ps1`): бинарник сервера (сборка при наличии Go или `--binary`), учётная запись службы, автозапуск (systemd, launchd, служба Windows), по желанию — tor ≥ 0.4.9 с проверкой подписи Tor Project и onion-сервисом NOX (443 → порт сервера, PoW), onion- и публичный адрес параметрами запуска, пароль дважды через stdin `noxd unlock`, в конце — ссылка и QR-код (`noxd link -qr`) и инструкция, как открыть сервер после перезагрузки. Повторный запуск обновляет, не трогая данные.

## Technical Context

**Language/Version**: bash (Linux, macOS), PowerShell 5+ (Windows); Go 1.27 — `noxd link -qr`.

**Primary Dependencies**: системные: systemd, launchd, `sc.exe`/`New-Service`, `gpg`, `curl`/`Invoke-WebRequest`; сервер — `rsc.io/qr` (уже есть).

**Storage**: папки данных служб (R1); пароль нигде не хранится.

**Testing**: macOS — установка в изолированный префикс и в систему на этой машине; `shellcheck`/`PSScriptAnalyzer`, если есть; Linux и Windows — владелец.

**Target Platform**: машины сервера — Linux, macOS, Windows.

**Project Type**: скрипты установки + небольшая доработка CLI сервера; провод не меняется.

**Performance Goals**: установка и спаривание телефона — меньше 15 минут (SC-001).

**Constraints**: пароль — только stdin; ссылка — не в файлах и логах; чужие настройки tor не ломаются.

**Scale/Scope**: одна машина.

## Constitution Check

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Пароль не попадает в файлы, логи и аргументы; ссылка — только на экран. | ✅ |
| II–VI | Интерфейс приложения не меняется. | ✅ |
| VII. Контракт | Провод не меняется; tor — отдельная служба, сервер ею не управляет (конституция 1.4.0). | ✅ |

## Project Structure

```text
deploy/
├── install-linux.sh, install-macos.sh, install-windows.ps1
├── nox-tor.conf.tmpl                  # строки onion-сервиса NOX
├── noxd.service.tmpl, com.cyphernetlabs.noxd.plist.tmpl
└── README.md                          # как запустить и как вручную (по системам)
client_backend/cmd → main.go: noxd link -qr
docs/client-backend/{README,demo-runbook}.md, client_backend/CLAUDE.md
```

**Structure Decision**: новый каталог `deploy/` в корне репозитория.

## Complexity Tracking

Нет отступлений.

# Research: Установка сервера

Опора — 045 (`-public-addr`, `-onion-addr`, tor отдельно), 046 (`noxd link`), 047 (`noxd unlock` из stdin, запертый старт), страница темы 2 («Как поставить tor»), `client_backend/CLAUDE.md` (заметки о tor на macOS: официальная сборка без подписи).

## R1. Скрипты и где что лежит

- **Decision:**

| | Linux | macOS | Windows |
|---|---|---|---|
| Скрипт | `deploy/install-linux.sh` (bash) | `deploy/install-macos.sh` (bash) | `deploy/install-windows.ps1` (PowerShell 5+) |
| Бинарник | `/usr/local/bin/noxd` | `/usr/local/bin/noxd` | `C:\Program Files\NOX\noxd.exe` |
| Данные | `/var/lib/nox` | `/Library/Application Support/NOX` | `C:\ProgramData\NOX` |
| Учётная запись | системный `nox` | системный `_nox` | виртуальная `NT SERVICE\noxd` |
| Автозапуск | systemd `noxd.service` (`KillMode=mixed` не нужен — tor отдельно) | launchd `/Library/LaunchDaemons/com.cyphernetlabs.noxd.plist` | служба `noxd` (`sc.exe`/`New-Service`) |
| tor | пакет дистрибутива ≥ 0.4.9 или репозиторий Tor Project; служба `tor` | Tor Expert Bundle (macOS), подпись ad-hoc (`codesign -s -`), launchd `org.torproject.tor` | Tor Expert Bundle, служба `tor` (`tor --service install`) |

- **Rationale:** FR-001, FR-002; служба под своей учётной записью — доступ только к своим данным.

## R2. Бинарник

- **Decision:** `--binary <путь>` — готовый; иначе, если есть Go, `CGO_ENABLED=0 go build -trimpath -ldflags=-s` из `client_backend/` рядом со скриптом; иначе — отказ с инструкцией.
- **Rationale:** уточнение; поставка архивов — вне рамок.

## R3. tor и onion-сервис

- **Decision:** отдельный файл настроек NOX для tor: `HiddenServiceDir <tor-data>/nox`, `HiddenServicePort 443 127.0.0.1:<порт>`, `HiddenServicePoWDefensesEnabled 1`; подключается через `%include` в основной `torrc` (tor ≥ 0.4.0), чужие настройки не трогаются. Onion-адрес — из `<HiddenServiceDir>/hostname` после первого старта tor (ожидание до 60 с). Проверка скачанного: `sha256sums-signed-build.txt` + `.asc` подписью Tor Project через `gpg` (ключ Tor Browser Developers по отпечатку, зашитому в скрипт); нет `gpg` или подпись не сошлась — tor не ставится.
- **Rationale:** FR-002, FR-003, уточнение; PoW на стороне сервиса (тема 2).

## R4. Первый запуск, пароль, ссылка

- **Decision:** порядок: учётная запись и папки → бинарник → tor и onion-адрес (если выбран) → служба сервера с `-addr 0.0.0.0:<порт> -db <данные>/nox.db -status-addr 127.0.0.1:8081 [-onion-addr …] [-public-addr …]` → ожидание `/health` `locked` → на новой установке пароль дважды (без эха, ≥ 12 знаков, повтор при ошибке) → `noxd unlock` из stdin → `noxd link` (ссылка, QR в терминале, срок) → адрес служебной страницы и как открыть сервер после перезагрузки. Пароль передаётся только через stdin команды, не в аргументах и не в файлах.
- **Rationale:** FR-004–FR-007, SC-004.

## R5. Повторный запуск

- **Decision:** есть `<данные>/nox.db` — режим обновления: заменить бинарник, обновить файлы служб и настройку onion-сервиса NOX, перезапустить; пароль не спрашивается (сервер стартует запертым — скрипт напоминает открыть его); ключ onion-адреса (`HiddenServiceDir`) и база не трогаются.
- **Rationale:** FR-008, SC-003.

## R6. Сбои

- **Decision:** проверки до изменений: права администратора, занятость порта (`ss`/`lsof`/`Get-NetTCPConnection`), наличие Go или `--binary`; сбой tor — сервер ставится без него и скрипт говорит, что не вышло; при сбое после частичных изменений — откат созданного этим запуском (служба, файлы службы).
- **Rationale:** FR-009, FR-010.

## R7. QR в терминале

- **Decision:** `noxd link -qr` печатает QR-код символами `▀▄█` (две строки модулей в одной строке терминала) с тихой зоной; кодирует `rsc.io/qr` (уже зависимость сервера).
- **Rationale:** FR-006, уточнение.

## R8. Проверка

- **Decision:** macOS — на этой машине: установка в изолированные пути (`--prefix` для проверки без затрагивания системы), tor из подписанного bundle, служба launchd, перезапуск, `noxd unlock`, спаривание; Linux и Windows — владелец (`shellcheck` и `PSScriptAnalyzer` для статической проверки, если установлены).

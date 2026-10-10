# Implementation Plan: Данные на диске сервера — шифрование базы и файлов, пароль владельца, запертый старт, бэкап

**Branch**: `047-server-data-at-rest` (от `security-rework`, PR — в `security-rework`) | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/047-server-data-at-rest/spec.md`

## Summary

Сервер шифрует базу по страницам (SQLite в Wasm через `ncruces/go-sqlite3` и VFS `adiantum`, без CGO) и вложения кусками по 64 КиБ (ChaCha20-Poly1305) одним случайным ключом данных; ключ данных заперт паролем владельца (Argon2id + XChaCha20-Poly1305) в файле `<db>.key`. После каждого запуска сервер заперт: служебная страница показывает только поле пароля, основной порт закрыт; пароль вводят на странице или `noxd unlock`. Смена пароля перезапирает ключ без перешифровки. `noxd backup` делает работающим сервером один tar-файл со снимком базы, вложениями и запертым ключом; `noxd restore` восстанавливает его на пустом месте другой машины тем же паролем, с новым именем журнала и тем же ключом сервера.

## Technical Context

**Language/Version**: Go 1.27 (`client_backend/`).

**Primary Dependencies**: `github.com/ncruces/go-sqlite3` (+ VFS `adiantum`), `golang.org/x/crypto` (`argon2`, `chacha20poly1305`, `hkdf`), `golang.org/x/term`; уходят `modernc.org/sqlite` и его `libc`.

**Storage**: схема без изменений; новый файл `<db>.key`; формат файлов вложений версии 1 (куски); бэкап — tar.

**Testing**: `go test -race` — шифрование (поиск маркеров), пароль, запертый старт, формы и `/control/*`, вложения кусками, бэкап и восстановление, время; сквозной прогон на macOS.

**Target Platform**: сервер — Linux, macOS, Windows; приложение не меняется.

**Project Type**: Go-сервер; контракт v0 — §1 (запертый сервер, `/health`) и §3 (имя журнала после восстановления).

**Performance Goals**: открытие после пароля ≤ 2 с (SC-002); смена пароля < 5 с (SC-006).

**Constraints**: статический бинарник без C-кода (`CGO_ENABLED=0`); пароль, ключи и содержимое — не в логах и не в выводе команд; один процесс открывает базу.

**Scale/Scope**: база одного человека, вложения до 100 MiB.

## Constitution Check

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Данные сервера на диске и в бэкапе зашифрованы; пароль нигде не хранится; логи без секретов. | ✅ |
| II. Спека | Служебная страница — вне спецификации дизайна приложения; её тексты — в `contracts/control-and-page.md`. | ✅ |
| III. Блюпринт | Сервер — `docs/blueprints/client-backend/`: обновляется раздел о БД и запуске. | ✅ |
| IV–VI | Интерфейса приложения фича не меняет. | ✅ |
| VII. Контракт | Дельта §1 и §3 — первой (`contracts/wire-locked.md`); инварианты `client_backend/CLAUDE.md` сохранены: один процесс открывает базу, один писатель, прагмы те же (+ `temp_store=memory`), порядок остановки тот же; список зависимостей обновляется с обоснованием. | ✅ |

## Project Structure

### Documentation (this feature)

```text
specs/047-server-data-at-rest/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/{wire-locked,control-and-page}.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
client_backend/
├── internal/db/db.go                    # ncruces + adiantum, ключ данных, temp_store=memory
├── internal/vault/                      # НОВОЕ: ключ данных, <db>.key, Argon2id, смена пароля
├── internal/blob/                       # формат версии 1: куски, AEAD, ключ файла
├── internal/server/files.go             # загрузка кусками, .synced по кускам, Range
├── internal/server/{server,status,status_page,control}.go   # запертый старт, формы, /control/*
├── internal/backup/                     # НОВОЕ: бэкап (tar + manifest + MAC) и восстановление
├── internal/config/config.go            # подкоманды unlock, password, backup, restore
├── main.go
├── go.mod, go.sum
└── CLAUDE.md

docs/client-backend/protocol/contract-draft.md, docs/blueprints/client-backend/README.md,
docs/client-backend/{README,demo-runbook}.md, scripts/demo-stand.sh, CLAUDE.md
```

**Structure Decision**: два новых пакета — `internal/vault` (ключ данных) и `internal/backup`; шифрование базы — в `internal/db`, вложений — в `internal/blob`.

## Complexity Tracking

| Отступление | Почему нужно | Почему проще не годится |
|---|---|---|
| Новые прямые зависимости (`ncruces/go-sqlite3`, `x/crypto`, `x/term`) при правиле «ровно четыре» | Шифрующая VFS SQLite без CGO есть только у `ncruces/go-sqlite3`; Argon2id и AEAD — `x/crypto`; пароль без эха — `x/term` | Своя VFS поверх `modernc` — переписывать VFS SQLite; своя криптография — недопустимо |

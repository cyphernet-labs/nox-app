# Implementation Plan: client-backend-files

**Branch**: `024-client-backend-files` | **Date**: 2026-08-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/024-client-backend-files/spec.md`

## Summary

Фаза 024 замыкает этап 1: файловая цепочка контракта §7 (`file.uploadBegin` → `PUT /files/{token}` → `message.send {attachment}` → эхо/событие с полным объектом вложения; `file.downloadBegin` → `GET /files/{token}` с Range) плюс `chat.files` (§4) и код `attachment_gone`. Байты живут вне сокета и вне БД — в каталоге данных под серверным `file_id` (доступ через `os.Root`); метаданные — в новой таблице `files` (правка единой миграции 001 — до релиза схема живёт в одном файле, правило владельца). Одноразовые токены с TTL 10 минут — эфемерное состояние процесса (in-memory, рестарт гасит их безвредно: клиент запрашивает новые). Хранение на этапе 1 бессрочное; стартовая зачистка убирает только загрузки, не привязанные к сообщению за сутки.

## Technical Context

**Language/Version**: Go 1.27 (модуль `nox.app/client-backend`)

**Primary Dependencies**: без новых — stdlib закрывает всё (`http.MaxBytesReader`, `http.ServeContent` с Range из коробки, `os.Root` для confinement каталога)

**Storage**: SQLite — таблица `files` + колонка `messages.file_id` с частичным UNIQUE-индексом «один файл — одно сообщение» (правкой единой миграции 001); байты — файлы `<files-dir>/<file_id>` (`.part` на время заливки, rename по завершении)

**Testing**: `go test -race ./...`; интеграционные тесты websocket + `http.Client` против httptest (PUT/GET с Range) на харнесе 022/023

**Target Platform**: локальный самостоятельный сервер, один статический бинарник без CGO

**Project Type**: продолжение единственного Go-модуля `client_backend/`

**Performance Goals**: SC-001 — цепочка 10 МБ проходит целиком; SC-002 — докачка передаёт только остаток (проверяется точным объёмом частичного ответа)

**Constraints**: контракт §7/§4 — закон; байты никогда не буферизуются в память целиком (стриминг PUT → диск, `ServeContent` ← диск); лимит `max_attachment_bytes` действует на обоих рубежах (uploadBegin и PUT); токены одноразовые, 10 минут, непредсказуемые; имя файла не участвует в путях; сервер по-прежнему не заглядывает в байты (метаданные только из uploadBegin)

**Scale/Scope**: 3 новые команды, 2 HTTP-endpoint'а, расширение схемы (единая миграция 001), 1 новый пакет (`internal/blob`), расширение `message.send`/превью/wire-модели `Message`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Статус | Как соблюдён |
|---|---|---|
| I. Приватность и E2EE-готовность | PASS | Байты — непрозрачный блоб: сервер не читает и не выводит из них ничего (mime/имя/размер — из uploadBegin); slog без имён файлов, mime и содержимого — только file_id, размеры, коды, длительности. `body` не трогается |
| II. Спецификация — источник истины | PASS | spec.md с Clarifications владельца; расхождения решаются правкой спеки в том же change-set |
| III. Архитектурный блюпринт обязателен | PASS | Новый пакет `internal/blob` вписывается в карту пакетов (один — одна ответственность: байты на диске); REST-поверхность — в `internal/server` как предписывает файловая карта CLAUDE.md |
| IV. Верность дизайн-системе | N/A | UI не затрагивается |
| V. Языковая дисциплина | PASS | Код/коммиты английские; спека и план русские |
| VI. Мобильно-десктопный паритет | N/A | Серверная фаза |
| VII. Контракт провода — закон | PASS | Формы §7/§4 дословно; решения вне контракта (бессрочность, TTL токенов, относительные URL, зачистка) подтверждены владельцем и вносятся в контракт в change-set реализации; этап 1 без auth |

Go-гейт: `gofmt -l .` пусто → `go vet ./...` → `go test -race ./...` перед каждым Go-коммитом.

**Post-design re-check (после Phase 1)**: PASS — новых зависимостей нет; секция Complexity Tracking пуста (мьютекс токенов — документированное инфраструктурное исключение класса реестра соединений, ws-rest-patterns §5).

## Project Structure

### Documentation (this feature)

```text
specs/024-client-backend-files/
├── plan.md              # этот файл
├── research.md          # Phase 0: решения R1–R10
├── data-model.md        # Phase 1: таблица files, связка сообщений (правка единой миграции 001)
├── quickstart.md        # Phase 1: смоук Е (websocat + curl, Range-докачка)
├── contracts/README.md  # Phase 1: срез контракта фазы 024
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
client_backend/
├── migrations/001_init.sql    # + files, messages.file_id, частичный UNIQUE (единая миграция до релиза)
├── internal/blob/             # NEW: байты на диске через os.Root (Create/Open/Remove/Stat по id)
│   ├── blob.go
│   └── blob_test.go
├── internal/config/config.go  # + флаг -files / NOX_FILES (дефолт <db>-files)
├── internal/protocol/frames.go # + Attachment, Message.Attachment, Cmd-константы 024
├── internal/store/store.go    # + CreateUpload, FileByID, AttachFile (внутри SendMessage), ListChatFiles, SweepOrphans
├── internal/server/
│   ├── tokens.go              # NEW: одноразовые токены с TTL (инфраструктурный мьютекс, документирован)
│   ├── files.go               # NEW: handlePutFile / handleGetFile + uploadBegin/downloadBegin/chat.files обработчики
│   ├── handlers.go            # message.send: attachment-ветка, body-опциональность
│   ├── server.go              # mux: PUT/GET /files/{token}; стартовая зачистка; wiring blob
│   └── files_test.go          # NEW: интеграционные тесты историй 1–3
├── README.md                  # + смоук Е
└── main.go                    # прокладка каталога файлов
```

**Structure Decision**: байты изолированы в `internal/blob` (store остаётся единственным кодом БД — инвариант 2 не размывается); токены и HTTP-обработчики файлов — в `internal/server` (политика провода — забота адаптера).

## Complexity Tracking

Нарушений Constitution Check нет — секция пуста.

# Implementation Plan: Client-сервер — bootstrap этапа 1

**Branch**: `022-client-backend-bootstrap` | **Date**: 2026-08-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/022-client-backend-bootstrap/spec.md`

## Summary

Первый работающий срез Go client-сервера в `client_backend/`: конверт кадров v0, `session.hello` с курсорным replay (`since`/`seq`, подписка → replay → live, правило «догнан»), команды `chat.create` + `message.send` (идемпотентность по `client_message_id`), события `chat.created`/`message.new` через транзакционный outbox в SQLite, hub с политикой отключения медленного клиента, `GET /health`, упорядоченный shutdown. Аутентификации нет (этап 1, Принцип VII). Первоклассная часть поставки — README с командами запуска и websocat-сценарием: владелец лично разворачивает и тестирует локально.

Технический подход целиком предрешён принятыми документами: контракт v0 (провод), блюпринт `docs/blueprints/client-backend/` (раскладка и рецепты), `client_backend/CLAUDE.md` (13 инвариантов), скиллы `go-style`/`ws-rest-patterns` (идиомы и механика). План не изобретает — распределяет.

## Technical Context

**Language/Version**: Go 1.27 (установлен локально: go1.27.0 darwin/arm64)

**Primary Dependencies**: ровно три — `github.com/coder/websocket` (v1.8.15+), `modernc.org/sqlite` (v1.57.0+; `modernc.org/libc` пинится), `golang.org/x/sync` (errgroup). Стандартная библиотека для всего остального (ServeMux, slog, encoding/json v1-API поверх v2).

**Storage**: SQLite, встроенная (CGO-free), два пула: читающий + пишущий с `SetMaxOpenConns(1)` и `_txlock=immediate`; прагмы фиксированы (busy_timeout(5000) → WAL → synchronous(NORMAL) → foreign_keys(1)); миграции `PRAGMA user_version` + `embed.FS`.

**Testing**: `go test -race ./...` (обязателен); табличные тесты, БД-файл в `t.TempDir()` (никогда `:memory:`), `httptest` + `websocket.Dial`; `testing/synctest` для время-зависимых тестов; leak-check WS-хендлеров.

**Target Platform**: локальный запуск владельца — macOS (arm64) и Linux; сборка `CGO_ENABLED=0`, loopback, без TLS (этап 1).

**Project Type**: single-binary server (`client_backend/` — отдельный Go-модуль в монорепо; имя модуля — `nox.app/client-backend`).

**Performance Goals**: доставка события второму клиенту < 1 с локально (SC-002); от чистого клона до работающего смоука ≤ 10 минут по README (SC-001); shutdown ≤ 10 с (SC-005).

**Constraints**: без аутентификации/крипты (этап 1 — конституция VII); никаких новых зависимостей сверх трёх; ни одного мьютекса в бизнес-коде (владение — горутины); ошибки только кодами контракта §2.1; кириллица в коде/комментариях/коммитах не появляется.

**Scale/Scope**: круг ~10 пользователей, десятки соединений, единицы сообщений в секунду — все решения оптимизируются под простоту и корректность, не под пропускную способность.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Применимость | Статус |
|---|---|---|
| I. Приватность и E2EE | Логи: `slog` **никогда** не пишет тела сообщений, label'ы и содержимое кадров — только типы команд, коды ошибок, `seq`, длительности. E2EE-граница (Q1) не предрешается: сервер уже сейчас не заглядывает в `body` нигде, кроме валидации размера | ✅ PASS |
| II. Спека — источник истины | План выводится из spec.md 022; расхождения контракта, найденные при реализации, правятся в контракте в том же change-set | ✅ PASS |
| III. Блюпринт обязателен | Для Go-компонента — `docs/blueprints/client-backend/` (принят 2026-08-20); раскладка и рецепты ниже — из него | ✅ PASS |
| IV. Дизайн-система | Не применим — UI отсутствует | N/A |
| V. Языковая дисциплина | Код/комментарии/коммиты — английский; спека и план — русский | ✅ PASS |
| VI. Паритет платформ | Не применим — серверный компонент без UI | N/A |
| VII. Контракт — закон | Все кадры/команды/коды — из contract-draft.md v0; решение Q1-кларификации (поле `label`) внесено в контракт §3 **до** плана; этап 1 без аутентификации — блок §8 не реализуется; 13 инвариантов CLAUDE.md — нормы приёмки; Go-гейт (`gofmt` пусто → `go vet` → `go test -race`) перед каждым коммитом | ✅ PASS |

**Post-design re-check** (после Phase 1): нарушений не появилось; data-model вводит только сущности контракта; Complexity Tracking пуст. ✅ PASS

## Project Structure

### Documentation (this feature)

```text
specs/022-client-backend-bootstrap/
├── plan.md              # Этот файл
├── research.md          # Phase 0: консолидация принятых решений
├── data-model.md        # Phase 1: схема SQLite + wire-модели среза
├── quickstart.md        # Phase 1: сборка, запуск, websocat-смоук
├── contracts/           # Phase 1: срез контракта v0 для 022
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
client_backend/                  # отдельный Go-модуль (go.mod, go 1.27)
├── main.go                      # flags → internal/server.Run; ~3 строки логики
├── go.mod / go.sum
├── CLAUDE.md / AGENTS.md        # уже существуют (инварианты)
├── README.md                    # NEW: сборка, запуск, websocat-сценарий (FR-011)
├── migrations/
│   └── 001_init.sql             # chats, messages, events (STRICT)
└── internal/
    ├── config/  config.go       # flags + NOX_* env, валидация
    ├── db/      db.go migrate.go# два пула, прагмы, user_version-раннер
    ├── store/   store.go        # типы + все чтения/записи; единственный писатель
    ├── hub/     hub.go          # горутина-владелец подписчиков
    ├── protocol/ frames.go errors.go  # конверт v0, коды ошибок
    └── server/  server.go ws.go client.go handlers.go health.go
                                  # wiring, /ws, read loop + write pump, диспетчер
```

**Structure Decision**: раскладка блюпринта дословно (`main.go` в корне модуля + один уровень `internal/`); tests — colocated `*_test.go` в каждом пакете. `client_backend/` — самостоятельный Go-модуль: Flutter-тулинг репозитория (`make gate`, `fvm`) его не касается, гейт Go-кода — свой (конституция).

## Complexity Tracking

Нарушений Constitution Check нет — таблица пуста.

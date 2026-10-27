# Implementation Plan: client-backend-chats-messages

**Branch**: `023-client-backend-chats-messages` | **Date**: 2026-08-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/023-client-backend-chats-messages/spec.md`

## Summary

Фаза 023 достраивает командный набор чатов и сообщений контракта v0 (§4–§6) поверх бутстрапа 022: `chats.list` (пагинация, поиск), `chat.get`, `chat.rename` (+ событие `chat.updated`), `chat.nameAvailable`, `messages.list` (обратная пагинация), обязательность `body` в `message.send` на этот срез. Инфраструктура не меняется: конверт, журнал `seq`, диспетчер рассылки, hub, реплей и SQLite-схема 022 переиспользуются как есть; **миграций в этой фазе нет**. Read-команды идут через read-пул без транзакций; единственная новая мутация — `chat.rename` — проходит через writer + транзакционный outbox, как все мутации.

## Technical Context

**Language/Version**: Go 1.27 (модуль `nox.app/client-backend`, тулчейн зафиксирован в go.mod)

**Primary Dependencies**: без изменений — `github.com/coder/websocket` v1.8.15, `modernc.org/sqlite` v1.57.0, `golang.org/x/sync` (errgroup); новых зависимостей фаза не добавляет

**Storage**: существующая SQLite-схема 001 (chats c `name_ci`, messages c индексом `(chat_id, seq)`, events); новых таблиц/колонок нет

**Testing**: `go test -race ./...`; интеграционные тесты через httptest + два-три websocket-клиента (харнес `openStack`/`newTestServer` из 022)

**Target Platform**: локальный самостоятельный сервер (loopback в dev), один статический бинарник без CGO

**Project Type**: продолжение единственного Go-модуля `client_backend/`

**Performance Goals**: SC-001 — первая страница списка и хвост истории < 1 c на базе 250 чатов / 1000 сообщений; SC-002 — `chat.updated` у второго клиента < 1 c

**Constraints**: контракт v0 §4–§6 — закон (Принцип VII); этап 1 без аутентификации; юникод-регистронезависимость имени и поиска (SQLite `lower()`/`LIKE` не годятся — фолдинг в Go); потолок порций 100 (молчаливое ограничение), порция истории по возрастанию `seq`; no-op rename без события

**Scale/Scope**: ~10 пользователей, сотни чатов, тысячи сообщений; 6 команд (5 новых + 1 доработка), 1 новое событие

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Статус | Как соблюдён |
|---|---|---|
| I. Приватность и E2EE-готовность | PASS | Сервер не заглядывает в `body` нигде, кроме готовой свёртки превью (`previewFromBody`, шов Q1 из 022); slog по-прежнему без тел, имён чатов, лейблов и payload'ов — только команды, коды, seq, длительности. Поиск фильтрует по `name` в памяти процесса и в лог не пишет строку запроса |
| II. Спецификация — источник истины | PASS | spec.md с Clarifications владельца; расхождения реализации решаются правкой спеки в том же change-set |
| III. Архитектурный блюпринт обязателен | PASS | Структура пакетов `docs/blueprints/client-backend` не меняется; новые методы ложатся в существующие `internal/store` / `internal/server` |
| IV. Верность дизайн-системе | N/A | UI не затрагивается |
| V. Языковая дисциплина | PASS | Код/коммиты английские; спека и план русские; кириллица в коде не появляется (тестовые кириллические имена чатов — данные, не идентификаторы; в Go-строках тестов допустимы литералы данных — прецедент 022: `store_test.go` «Общий») |
| VI. Мобильно-десктопный паритет | N/A | Серверная фаза |
| VII. Контракт провода — закон | PASS | Все формы данных/ответов/ошибок — из §4–§6 дословно; решения, которых в контракте не было (потолок истории, порядок порции, no-op rename, клампинг), подтверждены владельцем и после реализации фиксируются правкой контракта в том же change-set; этап 1 без auth |

Go-гейт (Принцип VII): `gofmt -l .` пусто → `go vet ./...` → `go test -race ./...` перед каждым коммитом, затрагивающим Go.

**Post-design re-check (после Phase 1)**: PASS — дизайн не добавил ни новых зависимостей, ни отступлений от контракта; секция Complexity Tracking пуста.

## Project Structure

### Documentation (this feature)

```text
specs/023-client-backend-chats-messages/
├── plan.md              # этот файл
├── research.md          # Phase 0: решения R1–R9
├── data-model.md        # Phase 1: сущности и запросы (миграций нет)
├── quickstart.md        # Phase 1: смоук Д (полный чат-сценарий) + негативы
├── contracts/README.md  # Phase 1: срез контракта фазы 023
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
client_backend/
├── internal/protocol/
│   └── frames.go            # + EventChatUpdated, Cmd-константы 023; wire-модели Chat/Message уже есть
├── internal/store/
│   ├── store.go             # + ListChats, GetChat, RenameChat, NameAvailable, ListMessages
│   └── store_test.go        # + табличные тесты новых методов
├── internal/server/
│   ├── ws.go                # + пять case в dispatch
│   ├── handlers.go          # + обработчики 023; message.send: body обязателен
│   ├── integration_test.go  # + негативы новых команд
│   ├── chats_test.go        # NEW: интеграционные тесты историй 1 и 3
│   └── history_test.go      # NEW: интеграционные тесты истории 2
├── README.md                # + смоук Д
└── migrations/              # БЕЗ ИЗМЕНЕНИЙ (001 достаточно)
```

**Structure Decision**: расширение существующих пакетов 022 без новых директорий; вся работа с БД остаётся в `internal/store` (инвариант 2), обработчики — тонкие адаптеры конверта в `internal/server`.

## Complexity Tracking

Нарушений Constitution Check нет — секция пуста.

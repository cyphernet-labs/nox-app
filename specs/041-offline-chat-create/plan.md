# Implementation Plan: Чат без связи — появляется сразу, на сервере — когда будет связь

**Branch**: `041-offline-chat-create` | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/041-offline-chat-create/spec.md`

## Summary

Создание чата становится таким же, как отправка сообщения: на устройстве — сразу, на сервере — когда будет связь. Устройство придумывает id (`c_` + 32 hex), пишет строку чата с состоянием «ждёт создания», кладёт строку «Chat created by …» и открывает чат. Очередь исходящих — единственный отправитель — создаёт такие чаты на сервере раньше любых сообщений (`chat.create {chat_id, name}`), держит сообщения чатов, которых на сервере ещё нет, и разводит ответы на три исхода: принят, «имя занято», «не создан». Сервер принимает `chat_id` идемпотентно: существующий id возвращается как есть, раньше проверки имени. Состояние видно в строке списка (5.1) и плашкой в ленте (5.2) на обеих ширинах. Переименование чата, которого ещё нет на сервере, делается на устройстве. Старый сервер, не знающий `chat_id`, отвечает своим id — приложение его принимает.

## Technical Context

**Language/Version**: Dart (Flutter `3.44.1`, FVM) — клиент; Go (версия из `client_backend/go.mod`) — сервер.

**Primary Dependencies**: клиент — flutter_bloc + freezed, injectable/get_it, sembast, rxdart (без новых зависимостей); сервер — стандартная библиотека, `database/sql` + SQLite (без новых зависимостей).

**Storage**: клиент — Sembast: строка чата (`chats`) получает поля состояния создания; очередь `outbox` без изменения схемы. Сервер — SQLite, схема не меняется (`chats.chat_id` уже TEXT PRIMARY KEY; id устройства — просто другая строка).

**Testing**: клиент — `flutter_test`, `bloc_test`, `mockito`, голдены трёх категорий (`make gate`, `make golden-verify`); сервер — `go test -race ./...`.

**Target Platform**: iOS, Android, macOS, Windows, Linux (поведение одинаково; Tor здесь не участвует).

**Project Type**: мобильное + десктопное приложение и его личный сервер.

**Performance Goals**: чат открывается меньше чем через секунду после `Create` без связи (SC-001); создание на сервере — один обмен по каналу.

**Constraints**: очередь исходящих остаётся единственным отправителем; ни одного дубля чата при повторах (SC-003); имена чатов не попадают в логи (Принцип I); контракт — сначала, обе стороны в одном change-set'е (Принцип VII).

**Scale/Scope**: десятки чатов у одного человека; одновременно «ждут создания» единицы.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Проверка | Итог |
|---|---|---|
| I. Приватность | Новое поле — случайный id без смысла; в логах только id и коды, имена чатов — нет (FR-022). Выход и смена мира стирают ждущие чаты (FR-021). | ✅ |
| II. Спека — источник истины | Обновляются `docs/design/spec/screens/{chats-list,chat,create-chat,chat-card}.md`, оба корпуса экранов и контракт — в том же change-set'е. | ✅ |
| III. Блюпринт | Слои не нарушаются: новое состояние — доменная модель + поля сущности, создание на сервере — в репозитории, отправка — в `OutboxService`. `04-data-layer.md` (раздел очереди) и `14-networking-and-auth.md` получают описание. | ✅ |
| IV. Дизайн-система | Только существующие глифы (`schedule`, `error`) и токены; плашка — существующий `AppNoticeStripWidget`. | ✅ |
| V. Языки | Документы — русский; код, коммиты — английский; микрокопия — английский, EN + UK. | ✅ |
| VI. Паритет | Строка списка и плашка ленты одни и те же на обеих ширинах; голдены mobile + desktop для обоих экранов. | ✅ |
| VII. Контракт — закон | `chat_id` сначала вносится в контракт §4; сервер и клиент — в этом же change-set'е. Схема БД не меняется. | ✅ |

Повторная проверка после дизайна (Phase 1): нарушений нет, таблица сложности не нужна.

## Project Structure

### Documentation (this feature)

```text
specs/041-offline-chat-create/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── chat-create.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
docs/client-backend/protocol/contract-draft.md      # §4: chat.create {chat_id?, name}

client_backend/
├── internal/server/handlers.go                     # chat.create: chat_id, валидация, повтор без события
├── internal/server/chats_test.go                   # тесты провода
├── internal/store/store.go                         # CreateChat(chatID, …): id раньше имени, idempotent
└── internal/store/*_test.go

lib/
├── domain/model/chat/chat_model.dart               # + creation (ChatCreation?)
├── domain/model/chat/chat_creation.dart            # enum pending | nameTaken | failed
├── domain/repository/chat/chat_repository.dart     # createChat локально; pendingCreations; createOnServer; renameLocally; retryCreation
├── domain/repository/chat/outbox_repository.dart   # + moveChat(from, to)
├── data/entity/chat/chat_entity.dart               # + creation, creationAttempts
├── data/mapper/chat/chat_mapper.dart
├── data/local/chat/chat_dao.dart                   # pendingCreations(), delete(id)
├── data/local/chat/outbox_dao.dart                 # moveChat
├── data/remote/datasource/chat_remote_data_source.dart (+ real/mock)  # createChat(chatId, name)
├── data/repository/chat/chat_repository_impl.dart
├── data/repository/chat/outbox_repository_impl.dart
├── data/sync/outbox_service.dart                   # создания раньше сообщений; удержание; исходы
├── data/sync/sync_service.dart                     # chat.created/updated снимает состояние
├── general/id/chat_id.dart                         # mintChatId()
├── presentation/pages/create_chat_page/bloc/       # создание без ожидания + flush
├── presentation/widgets/chat/rename_chat_dialog/   # переименование ждущего чата — локально
├── presentation/widgets/chat/app_chat_item_widget.dart  # состояние в строке
├── presentation/pages/chats_list_page/chats_list_page.dart
└── presentation/widgets/chat/app_thread_view_widget.dart # плашка состояния
lib/l10n/app_en.arb, app_uk.arb                      # новые строки

test/ — зеркально; голдены: app_chat_item_widget (состояния), chats_list_page_creation (mobile+desktop), chat_thread_page_name_taken (mobile+desktop)

docs/design/spec/screens/{chats-list,chat,create-chat,chat-card}.md
docs/design/system/nox-mobile-screens/screens/{5-1-chats,5-2-thread}.md, specs.js
docs/design/system/nox-desktop-screens/screens/01-chats.md, specs.js
docs/blueprints/mobile/04-data-layer.md, 14-networking-and-auth.md
CLAUDE.md
```

**Structure Decision**: один пакет `nox_app` по блюпринту и Go-сервер `client_backend/` — как в 040. Новый код ложится в существующие слои; новых пакетов и зависимостей нет.

## Phase 0 / Phase 1

- Решения и альтернативы — [research.md](research.md).
- Модель данных и переходы состояний — [data-model.md](data-model.md).
- Провод — [contracts/chat-create.md](contracts/chat-create.md).
- Проверка от начала до конца — [quickstart.md](quickstart.md).

## Complexity Tracking

Нарушений Constitution Check нет.

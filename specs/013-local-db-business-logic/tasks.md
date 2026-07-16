---
description: "Task list — business logic on mock repos over a real local Sembast DB"
---

# Tasks: Полная бизнес-логика на mock-репозиториях поверх реальной локальной БД

**Prerequisites**: spec.md, plan.md
**Tests**: включены (DAO/repo/BLoC; blueprint-гейт).

## Phase 1: Chats vertical (P1) 🎯

- [ ] T001 `ChatEntity` (`lib/data/entity/chat/chat_entity.dart`, Freezed + json) — id/name/lastMessagePreview/lastMessageAt(ISO)/unreadCount; `ChatMapper` (`lib/data/mapper/chat/chat_mapper.dart`, DateTime↔ISO) ↔ `ChatModel`.
- [ ] T002 `ChatDao` (`lib/data/local/chat/chat_dao.dart`) по эталону `ItemDao`: store `chats`, `watch()`, `getPage(offset,limit)` (сорт lastMessageAt desc), `count()`, `upsert`, `saveData`, `cleanData`, corrupt-safe decode.
- [ ] T003 Домен: добавить `createChat(name)` + `watchChats()` в `ChatRepository`; конвертировать `ChatRepositoryImpl` на cache-first: сид из `GetChatsApi` на пустой store → пагинация из БД; `createChat` персистит (`uuid`, `AppClock.now()`); `clean()` → `dao.cleanData`.
- [ ] T004 `CreateChatBloc._onCreateRequested`: на success вызвать `chatRepository.createChat(name)` (реальный персист); статусы/ошибки сохранить.
- [ ] T005 `make generate` (Freezed/json/DI). Тесты: `chat_dao_test` (upsert/getPage/watch/corrupt-safe), `chat_repository_impl_test` (сид на пустой → пагинация; createChat персистит; повторный getChats читает из БД без ре-сида).

**Checkpoint**: чаты живут в реальной БД (создание персистит, список из БД); `make gate` зелёный.

## Phase 2: Messages vertical (P1)

- [ ] T006 `MessageEntity` + `MessageMapper` (`lib/data/entity/chat/`, `lib/data/mapper/chat/`) — id/chatId/authorId/authorLabel?/text?/sentAt(ISO)/status/isSystem/attachment(nested).
- [ ] T007 `MessageDao` (`lib/data/local/chat/message_dao.dart`): store `messages`, `watch(chatId)`, `getPage(chatId,offset,limit)` (сорт sentAt), `upsert`, `saveData`, `cleanData`.
- [ ] T008 Конвертировать `MessageRepositoryImpl` на cache-first: сид per chat из `GetMessagesApi` на пустой чат → пагинация из БД; `sendMessage` → `MessageModel(status: sent)` персист (`dao.upsert`); `clean()` → `cleanData`.
- [ ] T009 `ChatRepository.getChatFiles` → строить из persisted attachments сообщений чата (из `MessageDao`), а не мок.
- [ ] T010 `make generate`. Тесты: `message_dao_test`, `message_repository_impl_test` (сид/пагинация/sendMessage персист).

**Checkpoint**: сообщения живут в реальной БД (отправка персистит, лента из БД).

## Phase 3: Polish & Gates

- [ ] T011 Проверить BLoC-состояния (loading/empty/error/offline/пагинация) на chats-list/thread — полные, детерминированные на локальных данных.
- [ ] T012 Формат изменённых файлов; `make gate` + `make golden-verify` — зелёные (goldens детерминированы через `AppClock`/сид). Регенерировать затронутые baseline при необходимости.
- [ ] T013 Пройти DoD (FR-001..FR-012, SC-001..SC-006); парити mobile/desktop.

## Dependencies

- Chats (T001–T005) → Messages (T006–T010, независимы от chats на уровне DAO, но getChatFiles(T009) после MessageDao) → Polish (T011–T013).

# Implementation Plan: Полная бизнес-логика на mock-репозиториях поверх реальной локальной БД

**Branch**: `013-local-db-business-logic` | **Date**: 2026-07-18 | **Spec**: [spec.md](spec.md)

## Summary

Строим полный cache-first Sembast-стек для chat/message (entity + mapper + DAO по эталону `ItemDao`), конвертируем `ChatRepositoryImpl`/`MessageRepositoryImpl` с network-only мока на реальную локальную БД: одноразовый сид из существующих мок-источников (`GetChatsApi`/`GetMessagesApi`), затем чтение/пагинация **из БД**, реактивный `watch`, и реальные мутации (`createChat`, `sendMessage`) с персистом. Полная бизнес-логика BLoC (create персистит; статусы сообщений; пустые/офлайн/ошибки). Бэкенд не трогаем — источник просто локальный (контракт репозитория сохраняется для будущей подмены на транспорт).

## Technical Context

- **Storage**: Sembast (`AppDatabase` per-env уже есть: prod/dev = IO, test = memory). Эталон DAO — `lib/data/local/item/item_dao.dart`.
- **Deps**: sembast (есть), Freezed/json_serializable (entity), injectable+get_it, `RepositoryResult`, `AppClock` (детерминизм), `infinite_scroll_pagination` (список).
- **Constraints**: no backend; blueprint 04 (entity/mapper/DAO/cache-first) + 07 (pagination); детерминизм goldens; парити mobile/desktop.

## Constitution Check — PASS

- **I. Приватность/E2EE** — PASS: только локальная БД, ничего не уходит; крипто/сеть не трогаем.
- **II. Спека — источник истины** — PASS: модель открытого пространства сохранена (statuses local-only, без delivered/read); контракты API остаются TBD-плейсхолдерами.
- **III. Блюпринт** — PASS: строим ровно по 04/07 (entity+mapper+DAO, cache-first watch, `RepositoryResult`, DI, `LogRepository`). Network-only carve-out заменяется local-DB источником — контракт репозитория неизменен для будущего транспорта.
- **IV. Дизайн-система** — PASS: UI не меняется визуально (токены); новые состояния — по существующим виджетам.
- **V. Языковая дисциплина** — PASS.

## Design (по вертикалям)

### Chats (флагман)
- `ChatEntity {id, name, lastMessagePreview, lastMessageAt:String(ISO), unreadCount:int}` + `ChatMapper` (DateTime↔ISO) → `ChatModel`.
- `ChatDao` (store `chats`): `watch()` (onSnapshots, corrupt-safe), `getPage(offset,limit)` (сорт по `lastMessageAt` desc), `upsert`, `saveData`, `count`, `cleanData` — по эталону `ItemDao`.
- `ChatRepositoryImpl`: инъекция `ChatDao` + `GetChatsApi` (сид) + `ChatMapper`. `getChats(config)`: если store пуст → сид (`GetChatsApi.execute` полный набор → mapper → `dao.saveData`), затем страница из БД (offset/limit, `nextPage` из count). НОВОЕ `createChat(name)`: `ChatModel(id: uuid, name, lastMessageAt: AppClock.now(), unreadCount:0)` → `dao.upsert` → success. `watchChats()` (reactive). `clean()` → `dao.cleanData`.
- `CreateChatBloc._onCreateRequested`: на success → `chatRepository.createChat(name)` (персист) вместо чистого стенд-ина.

### Messages (второй)
- `MessageEntity {id, chatId, authorId, authorLabel?, text?, sentAt:ISO, status:String, isSystem:bool, attachment?...}` + `MessageMapper`.
- `MessageDao` (store `messages`): `watch(chatId)`, `getPage(chatId, offset, limit)` (сорт по `sentAt`), `upsert`, `saveData`, `cleanData`.
- `MessageRepositoryImpl`: сид per chat из `GetMessagesApi` на пустой чат → пагинация из БД; `sendMessage` → `MessageModel(status: sent)` → `dao.upsert`. `getChatFiles` (в `ChatRepository`) → из persisted attachments чата.

## Project Structure

```
lib/data/entity/chat/{chat_entity,message_entity}.dart (+ .g/.freezed)
lib/data/mapper/chat/{chat_mapper,message_mapper}.dart
lib/data/local/chat/{chat_dao,message_dao}.dart
lib/data/repository/chat/{chat_repository_impl,message_repository_impl}.dart  # convert
lib/domain/repository/chat/{chat_repository,message_repository}.dart          # + createChat/watch
test/data/local/chat/*_dao_test.dart, test/data/repository/chat/*_test.dart
```

## Complexity Tracking

Нет нарушений — раздел не требуется. Крупная фича реализуется по вертикалям (chats → messages), каждая — зелёный коммит.

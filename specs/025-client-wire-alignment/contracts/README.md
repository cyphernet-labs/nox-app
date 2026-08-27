# Contracts: срез фазы 025 (клиент)

Источник — контракт v0 §3–§7, §9 (переходные требования 1, 2, 4, 5, 7). Фаза учит **данные клиента** этим формам; транспорта нет (027), отправка команд остаётся мок-эхом.

## Что клиент обязан разбирать (фикстуры `test/fixtures/wire/`)

| Фикстура | Форма | Что проверяет |
|---|---|---|
| `hello.json` | `{schema, cursor, limits{max_message_bytes, max_attachment_bytes, max_frame_bytes}, identity{id, label}}` | разбор `limits` в `ServerLimits` |
| `chat_create_echo.json`, `chat_created_event.json`, `chat_updated_event.json` | `Chat {chat_id, name, created_at, created_by_label, last_message_preview, last_activity_at}` | `ChatWireEntity` 1:1, unix-время |
| `message_send_echo.json` | `Message` c `client_message_id` | эхо автора; `client_message_id` разбирается |
| `message_new_attachment_event.json` | `Message` c `attachment{file_id, name, size, mime, expires_at}`, без `client_message_id` | вложение 1:1; отсутствие поля не роняет разбор |
| `messages_list_page.json` | `{messages: [...], has_more}` | страница истории, `body`-объект |
| `chats_list_page.json` | `{chats: [...], has_more}` | страница списка |
| `chat_files_page.json` | `{files: [{file_id, name, size, mime, expires_at, message_id, seq}], has_more}` | форма панели файлов (потребитель — фаза 028; разбор фикстуры — контроль DTO вложения) |

Правила разбора: неизвестные поля игнорируются; `body.type != "text"` → текст null (шов Q1); категория файла — из расширения `name` (`FileType.fromExtension`), не с провода.

## Формы ошибок

`{code, message}`; коды §2.1 → `RepositoryException`: `invalid_request→invalidRequest`, `not_found→notFound`, `name_taken→nameTaken`, `payload_too_large→payloadTooLarge`, `attachment_gone→attachmentGone`, `rate_limited→rateLimited`, `internal→internal`, `unauthenticated→unauthenticated`, `unsupported_schema→unsupportedSchema`; **неизвестный код → `internal`** (правило эволюции).

## Пагинация

- Сообщения: курсор `before_seq` (отсутствует → хвост), `limit` (умолчание 20), порция по возрастанию `seq`, `has_more`; «страница N» и `total` не существуют.
- Чаты: `page`/`page_size` + `has_more` без `total`; дедуп строк по `chat_id` при склейке — обязанность клиента (§4).

## Локальные поля (НЕ на проводе)

`status`, `isSystem`, `localPath`, `unreadCount` — только домен/хранилище. `client_message_id` — на проводе (только собственные сообщения), в домен переносится фазой 026.

# Research: client-wire-alignment (фаза 025)

Решения Phase 0 (по данным пяти параллельных карт реального `lib/`).

## R1. Минтинг `seq` в моках — детерминированный, голдены неизменны

**Decision**: сид — `seq = (chatIndex + 1) * 1000 + position`, где `chatIndex` — индекс чата в мок-наборе (`chat_$index`), `position` — позиция сообщения в итоговом отсортированном по времени списке чата (генезис-строка — position 0). Новые записи времени исполнения (send-эхо, `simulateIncoming`, генезис созданного чата) — `seq = AppClock.now().millisecondsSinceEpoch * 1000 + счётчик` (счётчик различает записи под замороженными часами голденов).

**Rationale**: глобальная уникальность и разреженность внутри чата — как у контракта; порядок внутри чата совпадает с сегодняшним порядком по `sentAt` → видимый порядок и 216 голденов не меняются; runtime-значения всегда больше сидовых и монотонны между запусками (реальные часы).

**Alternatives considered**: сквозной счётчик по порядку первых открытий чатов — недетерминирован (ленивый по-чатовый сид); `seq` из миллисекунд без счётчика — коллизии под замороженным `AppClock` голденов.

## R2. Пагинация треда — курсор, список чатов — страницы (как в контракте)

**Decision**: `GetMessagesConfig` → `{chatId, int? beforeSeq, int limit}` (фабрики `tail`/`olderThan`); `GetChatsConfig` не меняется (контракт §4: `chats.list` странично). `PageMetadata` → `{required bool hasMore, int? nextPage}` (nextPage — только для страничного пути чатов; `total` удаляется). `PagingStateExt.applyPage`: `isLastPage = !meta.hasMore`.

**Rationale**: контракт разный для двух списков — чаты странично + `has_more`, сообщения курсором `before_seq`; единый `PageMetadata.hasMore` покрывает оба, а `nextPage` остаётся страничному пути.

**Alternatives considered**: единый курсор для обоих — противоречит §4; два разных типа метаданных — раздувает `applyPage` без выгоды.

## R3. Refresh треда — окно хвоста вместо перечитывания страниц

**Decision**: состояние треда хранит `oldestLoadedSeq` (минимальный загруженный `seq`) вместо `nextPage`/`loadedPageCount`; догрузка старших — `olderThan(oldestLoadedSeq)`; watch-tick refresh — одно чтение хвоста `tail(limit: items.length + pageSize)`.

**Rationale**: «страница N» не имеет смысла при курсоре; чтение хвоста с запасом покрывает новые прибытия, не роняя загруженный префикс (та же гарантия, что у старого перечитывания страниц 1..N, одним запросом вместо N).

**Alternatives considered**: запрос «всё новее oldestLoadedSeq» — требует второго вида запроса в репозитории ради того же результата на локальных данных.

## R4. Wire-DTO — новые типы 1:1, `body`-объект, без локальных полей

**Decision**: `MessageWireEntity {message_id, seq, chat_id, author_id, author_label, client_message_id?, sent_at:int, body?: BodyWireEntity{type, text?}, attachment?: AttachmentWireEntity{file_id, name, size, mime, expires_at}}`; `ChatWireEntity {chat_id, name, created_at:int, created_by_label, last_message_preview, last_activity_at:int}`; страницы `MessagesWireEntity {messages, has_more}` / `ChatsWireEntity {chats, has_more}`. `status`/`is_system`/`unread_count`/`type`(категория) с провода исчезают; `FileType` выводится из расширения `name` при маппинге; `client_message_id` парсится и до фазы 026 отбрасывается (поля в домене ещё нет).

**Rationale**: §9.2 дословно; required-поля старых DTO уронили бы контрактный JSON; категория файла — правило §9.2 (локальная таблица расширений уже есть — `FileType.fromExtension`).

**Alternatives considered**: постепенная правка старых DTO — required-поля и имена меняются все равно целиком, «постепенности» не существует.

## R5. Envelope-ошибка — `{code, message}` и маппинг в коды репозитория

**Decision**: `ResponseEntity.error` меняет тип `String?` → `ErrorWireEntity? {code, message}`; `RepositoryException` расширяется значениями `invalidRequest, nameTaken, payloadTooLarge, attachmentGone, rateLimited, unsupportedSchema`; хелпер `RepositoryException.fromWireCode(code)` (неизвестный код → `internal` — правило эволюции §2.1); репозитории при `success == false`/`error != null` бросают маппированное значение (вместо `StateError` → `unknown`).

**Rationale**: §9.5; сегодняшний путь схлопывает всё в `unknown`, а мок-генераторы никогда не бросают `DioException` — код провода обязан доезжать до `RepositoryResult.error`.

**Alternatives considered**: отдельный enum wire-ошибок рядом — два источника истины при одном потребителе.

## R6. Курсор `since` — Sembast-store `sync`, гибнет с логаутом

**Decision**: новый одно-записный store `sync` (`SyncDao`, record key `state`, поле `since`); `SyncRepository {getCursor, advanceCursor(seq), clear}`; `advanceCursor` — монотонный max; писатели на моках: сид сообщений (максимальный сидовый `seq`), send-эхо, `simulateIncoming`; `AuthRepositoryImpl.logout.afterMutate` дополняется `syncRepository.clear()`.

**Rationale**: §9.4; жизненный цикл курсора обязан совпадать с локальными сообщениями (вместе пишутся — вместе гибнут), поэтому Sembast, а не prefs; писатели-моки дают честную семантику «максимальный применённый seq» до появления транспорта.

**Alternatives considered**: SharedPreferences — переживает wipe-путь логаута отдельно от данных (риск рассинхрона «курсор есть, сообщений нет»).

## R7. `limits` — в `AppConfig`, контрактные дефолты

**Decision**: доменная модель `ServerLimits {maxMessageBytes, maxAttachmentBytes, maxFrameBytes}` с const-дефолтами контракта §3; `AppConfigRepository` отдаёт `limits` (in-memory) и получает сеттер `updateLimits` — писатель появится с рукопожатием 027.

**Rationale**: §9.5 требует место и шов, не транспорт; `AppConfigRepository` уже хранит процессную конфигурацию.

**Alternatives considered**: Sembast — лишняя персистентность для значений, приходящих в каждом hello.

## R8. Sembast-поля — только необязательные добавления

**Decision**: `MessageEntity` получает `int? seq`, `String? attachmentMime`, `int? attachmentExpiresAt`; `ChatEntity` — `String? createdAt`… нет: `int? createdAt` (unix) и `String? createdByLabel`; паттерн `attachmentLocalPath` (не-required, отсутствующий ключ → null). Домен: `MessageModel.seq` — required int (маппер: `entity.seq ?? 0`); сортировка DAO — по `seq`, вторичный ключ `sentAt`.

**Rationale**: `_tryDecode` молча выкидывает нечитаемые записи — required-поле опустошило бы существующие dev-базы; фолбэк `?? 0` даёт легаси-строкам стабильный порядок по вторичному ключу до пересида.

**Alternatives considered**: чистка баз при апгрейде — механизм на один случай, паттерн опциональности уже принят.

## R9. Оптимистичные сообщения — сентинел `seq`

**Decision**: оптимистичная запись очереди получает `seq = kPendingSeq` (большой const в домене); сортировка `allMessages` — по `seq`, при равенстве по `sentAt` → pending-строки стабильно в хвосте (визуально как сегодня); `_adoptOutgoing` заменяет запись эхом с настоящим `seq`.

**Rationale**: сортировка становится единой (по `seq`) без ветвлений; поведение «своё сообщение мгновенно внизу» сохраняется дословно.

**Alternatives considered**: nullable `seq` в домене — ветвящиеся компараторы и null-проверки по всем потребителям.

## R10. Фикстуры — живые кадры `noxd` в `test/fixtures/wire/`

**Decision**: снять с локального `noxd` (websocat/curl) и закоммитить: `hello.json`, `chat_create_echo.json`, `chat_created_event.json`, `chat_updated_event.json`, `message_send_echo.json`, `message_new_attachment_event.json`, `chats_list_page.json`, `messages_list_page.json`, `chat_files_page.json`; тесты: разбор payload'а → домен → сериализация → сравнение map'ов. Расхождение чинится в коде (Принцип VII).

**Rationale**: FR-004/SC-001 — единственная защита от «переписали DTO по памяти, а не по проводу».

**Alternatives considered**: рукописные фикстуры — воспроизводят ту же память, что и DTO, и ничего не ловят.

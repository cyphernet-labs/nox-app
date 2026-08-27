# Research: client-backend-files (фаза 024)

Решения Phase 0. Все «неизвестные» Technical Context закрыты.

## R1. Схема — таблица `files` + связка с сообщениями (правкой единой миграции 001)

**Decision**: правка `001_init.sql` (до релиза схема живёт в одной миграции — правило владельца): таблица `files` (file_id PK, name, size, mime, created_at, expires_at, uploaded INTEGER 0/1, message_id TEXT NULL) STRICT; колонка `file_id TEXT REFERENCES files(file_id)` в `messages`; частичный уникальный индекс `ON messages(file_id) WHERE file_id IS NOT NULL` — «один файл — одно сообщение» на уровне схемы.

**Rationale**: метаданные нужны и до отправки сообщения (между uploadBegin и send), поэтому отдельная таблица, а не колонки в messages; частичный индекс закрывает повторную привязку конструктивно.

**Alternatives considered**: метаданные в messages — не живут до send; JSON-блоб вложения в messages — не даёт `chat.files` и уникальности file_id.

## R2. Байты — пакет `internal/blob` поверх `os.Root`

**Decision**: новый пакет: `Open(dir)` (создаёт каталог, открывает `os.Root`), `Create(id)` — временный `<id>.part` c финализацией rename → `<id>`, `Open(id)`, `Remove(id)`, `Size(id)`. Все пути — только серверные id (hex), имя пользователя в пути не участвует.

**Rationale**: store остаётся единственным кодом БД (инвариант 2) — байты не его забота; `os.Root` даёт confinement от traversal бесплатно; `.part`+rename делает появление файла атомарным: недокачанные байты никогда не видны читателям.

**Alternatives considered**: байты в SQLite (BLOB) — раздувает БД, ломает Range-стриминг и `VACUUM INTO`-бэкапы; прямые `os.*` пути — ручная защита от traversal.

## R3. Одноразовые токены — in-memory с мьютексом (инфраструктурное исключение)

**Decision**: `internal/server/tokens.go`: map token→{fileID, op, expiresAt} под `sync.Mutex`; выдача — 32 случайных байта base64url; `Consume(token, op)` удаляет запись первым обращением; протухшие вычищаются лениво при выдаче. Рестарт процесса теряет токены — штатно (клиент запрашивает новые).

**Rationale**: токены — эфемерное состояние сессии процесса, как реестр соединений; тащить их в БД — лишняя запись на каждый файл и мусор после рестарта. Мьютекс здесь — инфраструктура (ws-rest-patterns §5, тот же класс, что `conns`), бизнес-состояния в нём нет.

**Alternatives considered**: таблица в SQLite — писательская нагрузка и зачистка ради данных, живущих 10 минут; горутина-владелец с каналами — три канала ради map на десяток записей, читаемость хуже.

## R4. `PUT /files/{token}` — стриминг с двойным рубежом лимита

**Decision**: токен потребляется первым обращением (повторная попытка = новый uploadBegin); тело читается через `http.MaxBytesReader(w, r.Body, declaredSize)` и копируется в blob-файл `io.Copy`; итоговый счётчик обязан равняться заявленному `size` (меньше → 400, файл удаляется; больше → MaxBytesReader даёт 413). `uploaded=1` ставится в БД только после успешного rename.

**Rationale**: заявленный размер — контракт клиента (uploadBegin уже отверг size > max_attachment_bytes), MaxBytesReader обрывает сверхлимит без буферизации; строгое равенство ловит обрывы и обманы одинаково; порядок «байты на диске → флаг в БД» не оставляет окна, где БД обещает байты, которых нет.

**Alternatives considered**: неограниченный Body с проверкой постфактум — приняли бы гигабайты в /tmp; допуск size-меньше — прятал бы обрывы под видом успеха.

## R5. `GET /files/{token}` — `http.ServeContent`

**Decision**: токен потребляется первым обращением; отдача — `http.ServeContent(w, r, "", modTime, f)` с `Content-Type` из `files.mime`; Range и 416 — из коробки. Имя в `Content-Disposition` не ставится (клиент знает имя из объекта вложения).

**Rationale**: ServeContent — эталонная реализация Range/If-Range; имя из метаданных в заголовке потребовало бы экранирования и ничего не даёт нашему клиенту.

**Alternatives considered**: ручной Range-парсинг — переизобретение с багами.

## R6. Относительные `upload_url`/`download_url`

**Decision**: в ответах команд — относительные пути `/files/<token>`; клиент соединяет со своим базовым адресом сервера.

**Rationale**: сервер не знает своего публичного адреса (туннель, NAT — Q9/Q13); относительный путь верен при любом способе достижимости.

**Alternatives considered**: абсолютный URL из конфигурации — лишняя ручка и источник рассинхрона.

## R7. `message.send` с вложением — привязка в той же транзакции

**Decision**: запрос получает `attachment {file_id}`; валидация: хотя бы одно из body/attachment; файл обязан существовать, иметь `uploaded=1` и `message_id IS NULL` — иначе `invalid_request`. В транзакции SendMessage: `UPDATE files SET message_id = ?` + `UPDATE messages SET file_id`(через INSERT-колонку); wire-объект `attachment` собирается из строки files и входит в эхо и в payload события (журнал самодостаточен для replay). Идемпотентный повтор возвращает прежнее эхо со сборкой вложения из БД.

**Rationale**: инварианты 2–4 — привязка и событие в одной транзакции; payload события строится в момент записи, поэтому replay не зависит от последующего состояния.

**Alternatives considered**: сборка attachment при доставке — replay стал бы зависеть от JOIN'а на живые данные (нарушение принципа «payload при записи»).

## R8. Превью вложения без текста — имя файла

**Decision**: `previewFromBody` расширяется до `previewFor(body, fileName)`: пустое/нетекстовое body при наличии вложения → имя файла (усечение той же формулой ≤120 рун).

**Rationale**: правило §6 «сообщение-вложение без текста → имя файла», формула свёртки едина.

## R9. `chat.files` — проекция сообщений с вложениями

**Decision**: `SELECT m.seq, m.message_id, f.<cols> FROM messages m JOIN files f ON m.file_id = f.file_id WHERE m.chat_id = ? [AND m.seq < ?] ORDER BY m.seq DESC LIMIT n+1` → разворот в Go; правила пагинации фазы 023 (потолок 100, клампинг, порция по возрастанию seq); ряды `{file_id, name, size, mime, expires_at, message_id, seq}`.

**Rationale**: паттерн `messages.list` дословно; JOIN по частично-уникальному индексу дёшев.

## R10. Бессрочность и стартовая зачистка

**Decision**: `expires_at = created_at + 10 лет` (константа этапа 1 — «бессрочно», поле обязано присутствовать по контракту); `downloadBegin` отвечает `attachment_gone`, если срок истёк ИЛИ байты физически отсутствуют; `not_found` — если file_id неизвестен; `invalid_request` — если байты ещё не залиты. Зачистка на старте (`SweepOrphans` в store + удаление байтов через blob): строки files с `message_id IS NULL AND created_at < now-24h` удаляются вместе с байтами/`.part`.

**Rationale**: решение владельца (Clarifications); зачистка покрывает единственный источник мусора при бессрочном хранении — брошенные загрузки; на старте — без фоновых таймеров, предсказуемо.

**Alternatives considered**: фоновый тикер — отклонён владельцем как вторая ступень; настоящий TTL — отложен.

# Data model — фаза 030

Схема правится **на месте** в единственной миграции `client_backend/migrations/001_init.sql` (предрелизное правило владельца от 2026-08-27). Никаких `002_*.sql`.

---

## 1. Новые таблицы

Обе вставляются в начало файла, до `chats`: `messages` ссылается на `users`, а SQLite при `foreign_keys(1)` требует, чтобы родитель был объявлен раньше.

```sql
-- A person. user_id is the PUBLIC author identity carried on the wire as
-- messages.author_id; it is not derived from anything the person holds.
-- id_digest is the one-way derivation of the login identifier computed on the
-- device: the server keeps it as an OPAQUE lookup key, never computes it and
-- never reverses it. NULL means the connection presented none (hand tools, the
-- live probe) - such a person is created on first use and never found again,
-- so the partial index leaves those rows out of uniqueness.
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    label TEXT NOT NULL CHECK (length(label) > 0),
    id_digest TEXT CHECK (id_digest IS NULL OR length(id_digest) > 0),
    created_at INTEGER NOT NULL
) STRICT;

CREATE UNIQUE INDEX idx_users_id_digest ON users (id_digest) WHERE id_digest IS NOT NULL;

-- One app installation. device_key is the opaque per-install id presented in
-- session.hello; stage 1 records it and proves nothing. A device belongs to
-- exactly one person and is re-bound to whichever person the connection
-- presents; created_at survives the re-binding, last_seen_at always moves.
CREATE TABLE devices (
    device_key TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users (user_id),
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL
) STRICT;

CREATE INDEX idx_devices_user ON devices (user_id);

-- The identity of this store. Minted once when the schema is created; a client
-- that sees a different value knows the world it cached is gone. One row.
CREATE TABLE journal (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    journal_id TEXT NOT NULL CHECK (length(journal_id) > 0)
) STRICT;
```

**Частичный уникальный индекс, а не `UNIQUE` в объявлении колонки.** SQLite считает все `NULL` различными в обычном `UNIQUE`, так что формально хватило бы и его, но частичный индекс делает намерение читаемым и не даёт будущему `NOT NULL` тихо изменить смысл.

**`journal_id` не минтится в SQL** — там нет источника случайности, годного для этого. Строка вставляется Go-кодом сразу после успешной миграции, если её нет.

---

## 2. Изменения в `messages`

```sql
-- author_id names the person; author_label is a frozen copy of that person's
-- label at send time and deliberately does NOT follow a later rename.
CREATE TABLE messages (
    message_id TEXT PRIMARY KEY,
    seq INTEGER NOT NULL UNIQUE,
    chat_id TEXT NOT NULL REFERENCES chats (chat_id),
    author_id TEXT NOT NULL REFERENCES users (user_id),
    author_label TEXT NOT NULL,
    client_message_id TEXT NOT NULL,
    sent_at INTEGER NOT NULL,
    body TEXT NOT NULL,
    file_id TEXT REFERENCES files (file_id)
) STRICT;

-- Idempotency is per person: two people colliding on a send key must not
-- collide with each other.
CREATE UNIQUE INDEX idx_messages_cmid ON messages (author_id, client_message_id);
```

Изменилось ровно три вещи: у `author_id` появился внешний ключ; `UNIQUE` снят с объявления `client_message_id` и заменён составным индексом; добавлен комментарий про вмороженность `author_label`. Остальные колонки, индексы и таблицы (`chats`, `files`, `events`) не трогаются.

**Внешний ключ — средство целостности, не сигнализация.** Защитой от устаревшей базы служит стартовая проверка схемы (см. §5), потому что раннер гейтится `PRAGMA user_version` и правленая миграция к наполненной базе не применится вовсе.

---

## 3. Сущности и связи

| Сущность | Ключ | Связи | Живёт |
|---|---|---|---|
| `users` | `user_id` — `u_` + 16 строчных hex | родитель `devices` и `messages` | вечно; не удаляется |
| `devices` | `device_key` — непрозрачная строка от клиента | ребёнок `users`, перепривязываем | вечно; отзыв — этап 2 |
| `journal` | одна строка, `id = 1` | ни с чем | пока существует файл базы |

**`user_id`.** Форма `u_` + 16 строчных шестнадцатеричных знаков (64 бита из `crypto/rand`). Префикс отделяет его от служебных значений, которые клиент уже использует локально, и делает вид идентификатора узнаваемым в логах отладки на стороне клиента. Непрозрачен для клиента: разбирать его никто не имеет права.

**`label`.** Принадлежит человеку, а не устройству. Не уникален, не валидируется (решение владельца). При пустом заявлении назначается как `User` + случайное четырёхзначное число.

**`id_digest`.** 64 строчных шестнадцатеричных знака, приходят готовыми. Сервер не вычисляет и не проверяет — только ищет. `NULL` допустим и означает «эту личность больше не найти».

---

## 4. Разрешение личности при приветствии

Единственная точка, где создаются и находятся личности. Порядок проверок нормативен.

```
вход: idDigest (может быть пусто), deviceKey (может быть пусто), label (может быть пусто)

1. idDigest не пуст?
     да  → найти users по id_digest
             найдено   → это личность
             не найдено → создать личность с этим id_digest
     нет → шаг 2

2. deviceKey не пуст?
     да  → найти devices по device_key
             найдено   → личность = devices.user_id
             не найдено → создать личность с id_digest = NULL
     нет → шаг 3

3. ни того, ни другого → личность В ПАМЯТИ, без записи (см. §6)

4. deviceKey не пуст → upsert devices:
       нет строки  → вставить (device_key, личность, now, now)
       есть строка → user_id := личность (ПЕРЕПРИВЯЗКА), last_seen_at := now
                     created_at не трогается

5. label не пуст И label != личность.label → UPDATE users SET label
   (приветствие без label имя НЕ меняет)
```

**Правило конфликта — шаг 4.** След человека авторитетен: известное устройство, предъявившее след другого человека, перепривязывается. Обратный порядок позволил бы старому устройству удерживать чужую переписку.

**Шаг 5 — почему условие, а не безусловная запись.** Устройство заявляет имя только когда только что его сменило. Безусловная запись при каждом приветствии дала бы пинг-понг: устройство с устаревшим кэшем вернуло бы старое имя поверх нового.

Вся последовательность — **одна транзакция записи** на едином писателе (`SetMaxOpenConns(1)` + `_txlock=immediate`), поэтому два одновременных первых подключения одного человека сериализуются и вторая транзакция находит строку, созданную первой. Событий в `events` эта запись **не** пишет: создание личности на проводе не видно.

---

## 5. Стартовая проверка схемы

После успешной миграции и до открытия конечных точек сервер проверяет, что таблицы `users`, `devices` и `journal` существуют. Если нет — отказывается стартовать с сообщением, называющим причину (база предшествует фазе 030) и лекарство (предрелизное правило правит `001_init.sql` на месте, поэтому файл базы и его спутники `-wal`, `-shm` и каталог файлов надо удалить).

Причина в том, что раннер пропускает уже применённые номера (`if num <= version { continue }`), поэтому база, дошедшая до `user_version = 1` до этой фазы, новых таблиц не получит никогда, а отказ выродился бы в `internal` на каждом приветствии — тихую поломку вместо громкой.

Там же, при первом старте на новой схеме, вставляется строка `journal`, если её нет.

---

## 6. Ленивая личность подключения без опознавательных знаков

Подключение без `login_ref` и без `device_key` получает личность **в памяти**: `user_id` минтится, строка не пишется. Запись материализуется при первой отправке сообщения — единственном пути, которому нужна родительская строка из-за внешнего ключа.

Так живой пробник, `websocat`, проверки здоровья и сканеры портов не оставляют мусорных строк, а FR-009 («обслуживать, а не отвергать») выполняется.

---

## 7. Что НЕ меняется

- `chats`, `files`, `events` — ни одной колонки. У чата по-прежнему только `created_by_label`, без ссылки на личность: на проводе у чата нет поля создателя-идентификатора.
- Вмороженная полезная нагрузка событий. `events.payload` собирается один раз при записи и не переписывается никогда — на этом стоит независимость replay от последующего состояния.
- Никаких колонок под фразу восстановления, токены, ключевой материал, сроки жизни и отзыв — этап 2.

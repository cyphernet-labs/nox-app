# 16 — Загрузка вложения в чат (picker → uploadBegin → PUT → attach to message)

> **Назначение:** зафиксировать клиентский контракт вложения файла в сообщение чата в `nox_app` — выбор файла через `FilePickerService`, загрузка байтов по одноразовому токену и прикрепление загруженного файла к сообщению. Цепочка **задана контрактом v0 §7** ([contract-draft.md](../../client-backend/protocol/contract-draft.md)): `file.uploadBegin` (команда по сокету) → `PUT` байтов → `message.send {attachment: {file_id}}`; обратная сторона — `file.downloadBegin` → `GET` с поддержкой Range. Вложение-**изображение** с реальным локальным файлом рендерится инлайн-эскизом с переходом в полноэкранный просмотр (фича 020), любой другой тип — чип с иконкой типа файла. Worked-аналог `Item` из блюпринта здесь — пара `MessageAttachment` (загруженный файл) + `MessageModel` (сообщение, к которому файл прикреплён). Сетевой слой **не переизобретается** — берётся из [14-networking-and-auth.md](14-networking-and-auth.md): команды идут по WebSocket-конверту v0 (транспорт приехал в фазе 026), REST остаётся **только** под байты файлов.
> **Когда читать:** перед реализацией composer'а вложений в треде (picker → upload → attach), перед правкой файлового датасорса `uploadBegin → PUT → send` в `lib/data/` и очереди исходящих и при работе со скачиванием вложения (`downloadBegin` → `GET` Range).
> **Связанные документы:** [../../client-backend/protocol/contract-draft.md](../../client-backend/protocol/contract-draft.md) (**контракт v0** — §5 `message.send`, §7 файлы, §2.1 коды ошибок, §9 переходные требования), [04-data-layer.md](04-data-layer.md) (`ApiClient`, `BaseApiRepository`, `BaseRepositoryHelper.execute`/`unwrapEnvelope`, `ResponseEntity<T>`/`EntityConverter<E>`, мапперы, REST-слой, network-only POST), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозиториев, per-call конфиги), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, `BaseBloc.executeLogic`, статус-эффекты + `BlocListener`, `state.when`), [14-networking-and-auth.md](14-networking-and-auth.md) (сетевой слой — не переизобретать), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, регистрация репозиториев), [07-pagination.md](07-pagination.md) (список чатов — куда возвращается сообщение с вложением), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`file_selector`, `dio`).

---

## 0. Идея: три шага — begin, put, attach

Отправка вложения в NOX — это **не** один общий POST. Контракт v0 §7 разносит её на три шага, каждый со своим каналом и своими побочными эффектами:

1. **`file.uploadBegin`** — команда по сокету, `data` запроса `{name, size, mime, file_id?}`, ответ `{file_id, upload_url, upload_token, max_attachment_bytes, received}`. Метаданные сервер берёт отсюда, а не из байтов; `mime` клиент выводит из расширения имени (`MimeTypes`, §2). С `file_id` — продолжение незаконченной загрузки этого файла (фаза 043); `received` — сколько первых байтов сервер уже хранит надёжно, и его наличие — признак, что сервер продолжать умеет.
2. **`PUT <upload_url>`** — сырые байты по одноразовому токену (REST, тот же порт): **остаток файла от `received` до конца**, возможно пустой. `upload_url` — **относительный** путь `/files/<token>`; токен одноразовый, TTL 10 минут, гасится первым обращением, которое до него дошло (отказ `401` — ключ соединения не спарен — токен не тратит). Оборванный `PUT` оставляет на сервере всё, что пришло, и следующая попытка продолжает оттуда. Пробрасывается прогресс аплоада — доля **всего** файла.
3. **`message.send {chat_id, client_message_id, body?, attachment: {file_id}}`** — отправка сообщения, ссылающегося на загруженный `file_id`; сервер собирает объект `attachment` из метаданных шага 1 в эхо и в событие `message.new`. Идемпотентность — по `client_message_id` (UUID, генерируется клиентом): при повторе сервер возвращает **прежнее эхо**, дубля не создаёт.

Обратная сторона — скачивание: `file.downloadBegin {file_id}` → `{download_url, download_token}` → `GET` с поддержкой Range (докачка), тот же одноразовый токен с TTL 10 минут. Недокачанное хранится на устройстве вместе с `Last-Modified` сервера, и следующая попытка просит `Range` от того, что есть, с `If-Range` (фаза 043).

**На устройстве файлы запечатаны (фаза 048).** Копия исходящего и скачанное лежат в папке данных приложения в формате `SealedFile` (куски по 64 КиБ под ключом локальной базы, [04-data-layer.md](04-data-layer.md) §6г). Поэтому `PUT` получает открытые байты из потока расшифровки (`FileRemoteDataSource.putBytes({size, offset, body})`, а не путь к файлу), и продолжение с `received` отправляет ровно остаток, где бы внутри куска он ни начинался. Поток расшифровки — `Stream<Uint8List>`, и реальный источник принимает его как любой `Stream<List<int>>`: свой обработчик ошибок он привязывает через `bind`, а не `body.transform(...)`, который сверяет аргумент с типом элементов потока во время выполнения и бросает `TypeError` ([04-data-layer.md](04-data-layer.md) §6г); скачивание запечатывает байты кусками по мере прихода, а `Range` следующей попытки начинается с конца последнего целого куска части. По каналу уходит и приходит сам файл, а не его запечатанная форма: формат на диске проводу не виден.

```
[picker] FilePickerService.pickFile() → PickedFile{name, sizeBytes, extension, path}
   │
   ▼
   ▼  FileRepository.upload(path:, mime:, name:, from:, onUnfinished:, onProgress:, cancellation:) — шаги 1 и 2:
1. FileRemoteDataSource.uploadBegin(...) → cmd file.uploadBegin → UploadTicketWireEntity{ fileId, uploadUrl, uploadToken, maxAttachmentBytes, received? }
   │
   ▼
2. FileRemoteDataSource.putBytes(...)    → PUT /files/<token>   → 204 (остаток от received)
   │  upload возвращает fileId только после подтверждения байтов; держим его для шага 3
   ▼
3. MessageRepository.sendMessage(chatId:, clientMessageId:, text:, attachment:) → cmd message.send → MessageModel (эхо, status=sent)
        повтор с тем же client_message_id → то же эхо, без дубля
```

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив).

> **Picker даёт метаданные, не репозиторий.** Picker живёт за доменным швом `FilePickerService` (`lib/domain/service/file_picker_service.dart`) и **не читает байты** — отдаёт `name`/`sizeBytes`/`extension`/`path`. Категория файла (`FileType`) выводится из расширения на клиенте и на проводе не живёт; на провод идёт `mime`.

---

## 1. Контракт и инварианты (что соблюдать дословно)

> Поля, коды и семантика ниже — **контракт v0 §7/§5**, а не иллюстрация. Открытым остаётся только то, что контракт сам помечает открытым: граница E2EE (Q1) — она задевает `body`, но не `attachment`.

- **Аутентификацию даёт канал, а не запрос.** Каждое соединение — и сокет команд, и каждая передача `PUT`/`GET` — открывает канал нативного модуля: TLS 1.3 и проверка `POST /auth` → `POST /auth2`, в которой устройство доказывает свой ключ, а сервер — ключ из ссылки спаривания, **на каждом соединении**, до первого запроса `PUT`/`GET` ([14-networking-and-auth.md](14-networking-and-auth.md) §6.0; [authentication.md](../../client-backend/architecture/authentication.md)). Устройство получает доступ спариванием (контракт §8A); нынешний `AuthInterceptor` с Bearer-токеном — шов без писателя, **не** наша модель. Не проектировать вокруг per-request-токенов.
- **`/files` требует двух вещей:** ключа спаренного устройства на соединении и действующего токена передачи. Ключа нет среди спаренных — `401`, и токен не тратится. Для приложения `401` (строка таблицы §7) — неудавшаяся передача: отказ сервера, считается как `internal`, новый пропуск не просит, и **никогда не выход**: принудительный выход принадлежит сессии — `unauthenticated` в ответ на `session.hello` и событие `device.revoked`.
- **Токены файлов — не аутентификация, а capability.** `upload_token`/`download_token` одноразовые, TTL 10 минут, гасятся первым обращением, которое до них дошло (отказы до токена — `401`, сбой поиска устройства, `HEAD` — его не тратят); после обрыва клиент запрашивает новый токен той же командой (`uploadBegin`/`downloadBegin`). Любой отказ токена на HTTP — единый `404` без раскрытия причин.
- **`PUT` несёт остаток от `received`:** `Content-Length = size − received`; больше остатка → `413` (пришедшее этим запросом не сохраняется), чистый конец раньше остатка → `400`, застой или обрыв → `408` (пришедшее сохранено), прежняя попытка не отпустила файл → `409`. `size` в `uploadBegin` берётся из того же файла, что и байты, — пересчитывать между шагами нельзя.
- **Передачи продолжаются, а не повторяются (фаза 043).** Загрузку повторяет очередь исходящих: ручка `UnfinishedUpload {fileId, sourceSize, sourceModifiedAt}` пишется в запись очереди **до первого байта**, каждая попытка продолжает с `received`, сервер, потерявший загрузку (`not_found`), получает новую без ошибки, изменившийся исходник не продолжается никогда (`notFound`, проверка до и после каждого `PUT`). Скачивание повторяет `AttachmentDownloadService`: одна передача на файл, та же лестница пауз, что у очереди, пробуждение при возвращении канала; путь в сообщение он записывает сам, поэтому скачивание идёт и после закрытия 5.3. Обрыв связи не исчерпывает повторов ни в одну сторону — только отказы сервера: 10 на отправку или на скачивание, и обрывы между ними счёт не обнуляют и не растят. Отказ — это и ответ, которого контракт не называет (5xx, чужой статус, `200` без размера): он считается как `internal`, а не как обрыв. Смена пути под передачей — не обрыв: передача, которую оборвал переход REST на другой адрес (`ApiClient.pathGeneration`), продолжается сразу в той же попытке. Файл загружается из **своей копии**: при постановке в очередь он копируется — запечатанным — в папку данных приложения, `nox_outbox/<client_message_id>/copy` (`OutboxCopies`; имя файла путь не выдаёт — его объявляет загрузка, `FileRepository.upload(name:)`), и запись очереди называет копию, — поэтому выбранный файл, который после отправки исчез, изменился или перестал читаться (песочница macOS после перезапуска), загрузке не мешает. Перед `message.send` копия переносится туда, куда легло бы скачивание (`FileRepository.cachePathFor`, `OutboxRepository.keepCopy`), и сообщение сохраняется с этим путём; запись, покинувшая очередь, уносит свою папку. Исходник, который не открывается (копию сделать не удалось), — `notFound` ещё до объявления загрузки. Сообщение, выброшенное во время загрузки (`OutboxService.discard`), обрывает её (`TransferCancellation`), и очередь сразу идёт дальше.
- **Предела времени на передачу нет.** Обрыв — только застой: приложение сдаётся через 45 с без движения байтов (сервер — через 60 с). После последнего отданного байта загрузка ждёт ответа до 3 минут: хвост ещё сливается из буферов медленного пути. Смена пути (новый адрес REST в `ApiClient.initBase`) обрывает идущие передачи сразу, и они продолжаются по новому пути.
- **`file_id` — единственное поле из шага 1, которое нужно держать для шага 3.** `upload_url`/`upload_token` живут только до `PUT`.
- **Идемпотентность по `client_message_id`.** Повторная отправка того же ключа не создаёт дубль: сервер хранит ключ и возвращает **прежнее эхо**. Клиент не различает «создано» и «уже было» — и не должен: ключ назначается при постановке в очередь и персистится с ней (переходное требование §9.3, закрыто фазой 027), повтор после реконнекта/рестарта идёт с тем же ключом.
- **Правила полей `uploadBegin`:** `name` ≤ 255 символов, `mime` ≤ 128, оба после трима непустые — нарушение → `invalid_request`. `mime` выводится клиентом из расширения имени (неизвестное расширение → `application/octet-stream`); байты пикер не читает.
- **Чтения и команды репозиториев возвращают `RepositoryResult<T>`** ([03-domain-layer.md](03-domain-layer.md)); `upload` и `sendMessage` принимают именованные параметры — канон файловой цепочки (§4). Коды провода §2.1 уже живут в enum `RepositoryException` (`invalidRequest`, `nameTaken`, `payloadTooLarge`, `attachmentGone`, `rateLimited`, `unsupportedSchema` + общие) и разбираются статикой `RepositoryException.fromWireCode(String)` — неизвестный код трактуется как `internal`. Маркерный тип — `BaseRepositoryException`.
- **Загрузочная цепочка сама по себе network-only** (one-shot команды) — без Sembast-DAO (carve-out [04-data-layer.md](04-data-layer.md) §8). Оговорка про шаг 3: сам `message.send` **не** one-shot — он идёт через долговечную очередь (`outbox`, [04-data-layer.md](04-data-layer.md) §6а), и отправитель у него ровно один. Файловая цепочка даёт очереди `file_id`, а не новый путь отправки. Отправленное сообщение затем подхватывается списком сообщений/чатов ([07-pagination.md](07-pagination.md)); само вложение персистится в записи сообщения (`MessageAttachment`, §4).

---

## 2. Выбор файла: `FilePickerService` поверх `file_selector`

Picker живёт за доменным швом `FilePickerService`, а не в репозитории и не в BLoC'е напрямую (фича 017, зеркалит `CameraPermissionService` из QR-фичи): так BLoC тестируется без системного диалога, а плагин остаётся сменным. Реализация — `file_selector` (официальный плагин flutter.dev, все пять таргетов). **`file_picker` брать нельзя**: его пин `win32 ^5.x` конфликтует с `package_info_plus` — это зафиксированный запрет `pubspec.yaml`, а не предпочтение.

Шов отдаёт **только метаданные** — байты не читаются (`openFile()` + `XFile.length()` статит размер), поэтому большой файл не блокирует UI и ничего не покидает устройство (Constitution I). Оба метода **никогда не бросают**: `null` = отмена ИЛИ отказ плагина.

`lib/domain/service/file_picker_service.dart` (реальный код):

```dart
/// The transient result of the native file picker - metadata only (no bytes read).
typedef PickedFile = ({String name, int sizeBytes, String? extension, String? path});

abstract class FilePickerService {
  Future<PickedFile?> pickFile();

  /// Save-as dialog for the file view's real Save (feature F2).
  Future<String?> pickSaveLocation({required String suggestedName});
}
```

Из `PickedFile` собирается запрос шага 1 — и та же тройка идёт в `PUT`:

```dart
final picked = await getIt<FilePickerService>().pickFile();
if (picked == null) return; // cancelled or unavailable

// Contract 7: the mime travels on the wire; the CATEGORY is client-side only.
final mime = MimeTypes.forFileName(picked.name);      // domain/model/file/mime_types.dart
final type = FileType.fromExtension(picked.extension); // drives the icon, never sent

// Preflight against the handshake limits instead of discovering payload_too_large on send.
if (picked.sizeBytes > getIt<AppConfigRepository>().limits.maxAttachmentBytes) {
  // inline error in the composer; contract 2.1 says payload_too_large is NOT retryable
  return;
}
```

> **Капы — не константы этого документа.** Потолок вложения приходит в рукопожатии (`session.hello`) и лежит в data-слое как `ServerLimits.maxAttachmentBytes` (`lib/domain/model/app_config/server_limits.dart`, доступ — `AppConfigRepository.limits`). Живой транспорт приехал в фазе 026: `LiveSessionStarter` (`lib/data/sync/live_session_starter.dart`) забирает лимиты рукопожатия из `NoxSocketClient` и записывает их через `AppConfigRepository.updateLimits`. До первого рукопожатия — и на мок-флаворах — отдаются контрактные дефолты (`ServerLimits.contractDefaults`: 100 MB на вложение). Предполётная проверка **обязательна**, а не «опциональна ради UX»: §2.1 помечает `payload_too_large` как неповторяемый — его предотвращают, а не обрабатывают повтором.

> **Allow-list'а MIME на клиенте нет.** Тип не ограничивается — `MimeTypes` покрывает изображения/видео/аудио/документы/архивы, неизвестное расширение уходит как `application/octet-stream` (дефолт самого контракта). Ограничение по типу — продуктовое решение, которого в NOX сейчас нет.

> На десктопе (Windows/Linux/macOS — целевые платформы NOX, см. [00-architecture-overview.md](00-architecture-overview.md)) `file_selector` использует нативные системные диалоги. Отдельного камера-picker'а в цепочке вложения нет: камера в NOX задействована только сканером QR (фича 010).

---

## 3. Контракт (v0 §7 — файлы, §5 — сообщение)

> Источник истины — [contract-draft.md](../../client-backend/protocol/contract-draft.md); ниже — клиентская выжимка. Все `*_at` в протоколе — целое unix-время в секундах UTC, других форматов дат нет.

### Шаг 1 — `file.uploadBegin` (команда по сокету)

`data` запроса: `{name, size, mime}` (`name` ≤ 255, `mime` ≤ 128, после трима непустые; нарушение → `invalid_request`).

`data` ответа:

```json
{
  "file_id": "f_77",
  "upload_url": "/files/9c1f…",
  "upload_token": "9c1f…",
  "max_attachment_bytes": 104857600,
  "received": 0
}
```

Ключевое поле — **`file_id`**: его держат для шага 3. `upload_url` — **относительный** путь (сервер своего публичного адреса не знает); базу подставляет клиент. `received` — с какого байта `PUT` по этому токену несёт файл; при продолжении (`file_id` в запросе) сервер называет здесь то, что уже хранит.

### Шаг 2 — `PUT <upload_url>` (байты, REST)

Тело — сырые байты файла **от `received` до конца**, по соединению клиента передач: каждое его соединение — канал модуля, прошедший проверку `/auth` и `/auth2` при открытии, как соединение сокета. Токен одноразовый (TTL 10 минут, гасится первым обращением, которое до него дошло, идущую передачу не обрывает); любой отказ токена — единый `404` без раскрытия причин; ключ соединения не спарен — `401`, токен не тратится. После обрыва — `uploadBegin` с тем же `file_id` (продолжение), а не повтор того же `PUT`; коды — в §1.

### Шаг 3 — `message.send` (команда по сокету)

`data` запроса:

```json
{
  "chat_id": "c_9f2",
  "client_message_id": "550e8400-e29b-41d4-a716-446655440000",
  "attachment": {"file_id": "f_77"}
}
```

- `chat_id` — обязателен (id чата, в который уходит сообщение).
- `client_message_id` — обязателен (UUID); ключ идемпотентности, генерируется клиентом; при повторе сервер возвращает прежнее эхо.
- `body` — опционален **при наличии** `attachment` (сообщение-вложение без текста — штатный случай); хотя бы одно из двух обязательно.
- `attachment` — `{file_id}` и только он: `name`/`size`/`mime` сервер берёт из `uploadBegin`, клиент их не дублирует.
- **Авторства в запросе нет** — `author_id`/`author_label` сервер берёт из сессии.
- Таймаут отправки — 10 секунд: нет ответа → локальный статус `error`, повтор с тем же `client_message_id`.

`data` ответа — `{message: Message}` (серверное эхо, оно же приходит другим как событие `message.new`):

```json
{
  "message_id": "m_51c", "seq": 1042, "chat_id": "c_9f2",
  "author_id": "…", "author_label": "Anna",
  "client_message_id": "550e8400-e29b-41d4-a716-446655440000",
  "sent_at": 1755600123,
  "attachment": {"file_id": "f_77", "name": "photo.jpg", "size": 238942,
                 "mime": "image/jpeg", "expires_at": 1758200000}
}
```

`expires_at` — срок хранения байтов: клиент **персистит** его вместе с вложением (`MessageAttachment.expiresAt`) и гасит кнопку Save заранее, а не узнаёт об истечении при открытии. На этапе 1 хранение бессрочное (`created_at + 10 лет`), но поле обязательно — логика гейтинга остаётся рабочей.

### Скачивание — `file.downloadBegin` + `GET`

`{file_id}` → `{download_url, download_token}` → `GET <download_url>` с поддержкой **Range** (докачка после обрыва): `Range: bytes=<сколько есть>-` и `If-Range: <Last-Modified>`; `206` — остаток, `200` — файл не тот, принятое выбрасывается, `416` — часть не короче файла, выбрасывается. Готовым считается только файл заявленного в сообщении размера. Токен — те же правила (одноразовый, 10 минут, отказ = `404`). Истёкший срок либо физически отсутствующие байты → `attachment_gone`: по §2.1 это **терминальное error-состояние экрана файла (5.3), без кнопки повтора**, а не фатальный экран приложения.

| Шаг | Канал | Эффект |
|---|---|---|
| 1 `file.uploadBegin` | сокет | метаданные → `file_id` + одноразовый `upload_token` |
| 2 `PUT /files/<token>` | REST | байты (с прогрессом), ровно заявленный `size` |
| 3 `message.send` | сокет | сообщение с `{file_id}` → эхо; повтор `client_message_id` → то же эхо, без дубля |
| ↩ `file.downloadBegin` + `GET` | сокет + REST | скачивание с Range; `attachment_gone` — терминально |

---

## 4. Доменный слой: модели, конфиги, контракты

Доменные модели — Freezed без `fromJson` ([03-domain-layer.md](03-domain-layer.md)); JSON живёт в entity-слое (§5). Категория файла — существующий enum `FileType` (`lib/domain/model/file/file_type.dart`, 9 значений от `image` до `other`) с `FileType.fromExtension(String?)`: она **не** ходит по проводу, а выводится из расширения имени. На провод идёт `mime` (`MimeTypes.forFileName`, §2).

> **Состав домена цепочки.** В `lib/domain/model/file/` — `file_type.dart`, `mime_types.dart`, `unfinished_upload.dart` (`UnfinishedUpload`, ручка продолжения загрузки), `transfer_cancellation.dart`, `attachment_transfer.dart` (запись реестра передач); модель вложения — `lib/domain/model/chat/message_attachment.dart`; контракт — `lib/domain/repository/file/file_repository.dart`; шов пикера — `lib/domain/service/file_picker_service.dart`. **Принцип «один конфиг на вызов» ([08-conventions-and-constitution.md](08-conventions-and-constitution.md), Принцип 4) для файловой цепочки сужен:** `FileRepository.upload` и `MessageRepository.sendMessage` принимают именованные параметры, и это канон для неё — в вызове едут не параметры запроса, а колбэки (`onUnfinished`, `onProgress`), ручка продолжения `from`, токен отмены и готовая модель вложения. Блоки ниже зеркалят код.

`lib/domain/model/chat/message_attachment.dart` — модель вложения (результат шага 3 и то, что персистится в Sembast):

```dart
@freezed
abstract class MessageAttachment with _$MessageAttachment {
  const factory MessageAttachment({
    required String id,      // wire file_id
    required FileType type,  // derived from the name extension, never on the wire
    required String name,
    required int sizeBytes,
    String? mime,            // contract 7 metadata; null for a locally-picked draft
    DateTime? expiresAt,     // contract expires_at; gates Save in advance
    String? localPath,       // device-local file (features F4/F2); NOT on the wire
  }) = _MessageAttachment;
}
```

Пропуск (`upload_url`/`download_url` и токены) доменной модели не получает: он живёт ровно до `PUT`/`GET`, никуда не персистится, и `FileRepositoryImpl` разбирает `UploadTicketWireEntity` / `DownloadTicketWireEntity` сам (§5.1). Наружу из `upload` выходит только `file_id` — после того как сервер подтвердил байты.

Контракты репозиториев (реализуются в `lib/data/`):

`lib/domain/repository/file/file_repository.dart` (сокращено; шаги 1 и 2 — объявление и байты — спрятаны внутрь `upload`, который возвращает `file_id` **только** после подтверждения байтов сервером):

```dart
typedef TransferFraction = void Function(double fraction);

abstract class FileRepository {
  /// Declares the file, sends its bytes, returns the server's id once the bytes are confirmed.
  /// Continues [from] (phase 043); [onUnfinished] hears the upload worth continuing before the first byte.
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    String? name,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
    TransferCancellation? cancellation,
  });

  /// One attempt, going on from whatever an earlier one left on this device; returns where the bytes landed.
  Future<RepositoryResult<String>> download({
    required String fileId,
    required String suggestedName,
    int? expectedSize,
    TransferFraction? onProgress,
  });

  Future<String?> localPathFor({required String fileId, required String suggestedName});
  Future<String> cachePathFor({required String fileId, required String suggestedName});
  Future<void> cancelTransfers();
  Future<void> clean();
}
```

Шаг 3 отдельного репозитория не заводит — это обычный `sendMessage` чат-фичи: очередь исходящих (`OutboxService`) сначала зовёт `FileRepository.upload`, а затем `sendMessage` с вложением, у которого `id` — уже серверный `file_id`, а `localPath` — копия файла на устройстве (§1).

`lib/domain/repository/chat/message_repository.dart` (остальные члены интерфейса к файловой цепочке не относятся и опущены):

```dart
abstract class MessageRepository {
  /// One-shot send. Returns the accepted (server) message on success.
  Future<RepositoryResult<MessageModel>> sendMessage({
    required String chatId,
    required String clientMessageId, // owned by the caller, reused on every retry
    String? text,
    MessageAttachment? attachment,   // id = server file_id; localPath re-attached onto the echo
  });
}
```

> **Вложение едет моделью.** `sendMessage` получает `MessageAttachment` целиком: `id` у неё — серверный `file_id`, который вернул `upload`, а `localPath`, которого на проводе нет, датасорс не отправляет, и репозиторий возвращает его на эхо. Переходные требования контракта §9.3 (`client_message_id` назначается при постановке в очередь и персистится с ней) и §9.6 (файловая цепочка) закрыты — фазами 027 и 028.

> **Почему не `(MessageModel, bool isCreated)`.** Различия «создано» vs «уже было» на проводе **нет**: при повторе того же `client_message_id` сервер возвращает **прежнее эхо**, неотличимое от первого. Клиенту это и не нужно — идемпотентность закрывает очередь исходящих (фаза 027): ключ назначается при постановке и служит ключом записи store `outbox`, повтор после реконнекта/рестарта идёт с тем же ключом, дубль невозможен. Никаких HTTP-статусов `201`/`200` в этой цепочке нет — `message.send` идёт по сокету.

> **`MessageModel` / `MessageEntity` — конкретный аналог worked-example `Item`** для чат-фичи (модель `lib/domain/model/chat/message_model.dart`, локальная entity `lib/data/entity/chat/message_entity.dart`, wire-DTO `lib/data/entity/chat/wire/message_wire_entity.dart`), а **не** типы из [07-pagination.md](07-pagination.md) (там список построен на абстрактном `ItemModel`). Ссылки на `07` — про **механику** списка (куда уходит отправленное сообщение), а не про определение `MessageModel`. Внимание: `ItemsEntity{items, page, page_size, total}` из той верификационной нарезки — **заморожённый** offset-пример, к файловой цепочке отношения не имеющий.

---

## 5. Слой данных: entities, мапперы, транспорт, репозитории

### 5.1 Entities + `ResponseEntity<T>`

Entities — `@freezed` + `json_serializable`, только базовые типы; коэрция — в маппере ([04-data-layer.md](04-data-layer.md) §1). Времена контракта — **unix-секунды `int`**, не ISO-строки. Каждый entity, ходящий через `ResponseEntity<T>`, регистрируется в **обеих** цепочках `EntityConverter` ([04-data-layer.md](04-data-layer.md) §3) — пропуск одной из них даёт `ArgumentError` в рантайме.

Конверт — реальный `lib/data/entity/base/response_entity.dart`, зеркалящий ответ команды из §2 контракта (`ok` → `success`, объект ошибки `{code, message}` → `ErrorWireEntity`):

```dart
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({@Default(false) bool success, ErrorWireEntity? error, @EntityConverter() T? data}) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
```

Вложение сообщения уже описано реальным wire-DTO `lib/data/entity/chat/wire/message_wire_entity.dart` — его не дублировать:

```dart
@freezed
abstract class AttachmentWireEntity with _$AttachmentWireEntity {
  const factory AttachmentWireEntity({
    @JsonKey(name: 'file_id') required String fileId,
    required String name,
    required int size,
    required String mime,
    @JsonKey(name: 'expires_at') required int expiresAt, // unix seconds
  }) = _AttachmentWireEntity;

  factory AttachmentWireEntity.fromJson(Map<String, dynamic> json) => _$AttachmentWireEntityFromJson(json);
}
```

Ответ шага 1 — `UploadTicketWireEntity` (`lib/data/entity/file/upload_ticket_wire_entity.dart`): `@JsonKey(name: 'file_id') fileId`, `@JsonKey(name: 'upload_url') uploadUrl`, `@JsonKey(name: 'upload_token') uploadToken`, `@JsonKey(name: 'max_attachment_bytes') maxAttachmentBytes`, `@JsonKey(name: 'received') int? received` (нет поля — сервер не умеет продолжать, файл уходит целиком) — и в том же файле симметричный ему `DownloadTicketWireEntity` (`download_url`, `download_token`). Обе зарегистрированы в `EntityConverter`.

### 5.2 Мапперы (вся коэрция здесь)

`BaseMapper` — 4-аргументный generic из кода (`lib/data/mapper/base_mapper.dart`): `abstract class BaseMapper<E, M, AdResult, AdParam>` с `toModel({required E entity, AdResult Function(AdParam entity)? ad})` и `toEntity({required M model, AdResult Function(AdParam entity)? ad})`. Конкретный маппер без вспомогательного контекста подставляет `dynamic, dynamic` в `AdResult/AdParam` и игнорирует `ad` ([04-data-layer.md](04-data-layer.md) §2).

Маппера для пропусков нет: `UploadTicketWireEntity` / `DownloadTicketWireEntity` наружу из `FileRepositoryImpl` не выходят, и доменной модели для них нет (§4).

Вложение сообщения маппит уже существующий `MessageWireMapper` (`lib/data/mapper/chat/message_wire_mapper.dart`): `file_id → id`, `expires_at` (unix-секунды) → `DateTime`, а `type` — **вывод** `FileType.fromExtension(MimeTypes.extensionOf(name))`, потому что категории на проводе нет. Локальные поля (`status`, `localPath`) эту границу не пересекают: применение эха/события — **merge, а не replace** (контракт §6), иначе свежепикнутый `localPath` затрётся серверным эхом и инлайн-эскиз исчезнет.

### 5.3 Транспорт шага 1 и шага 2

Оба шага живут за одним швом — `FileRemoteDataSource` (`lib/data/remote/datasource/file_remote_data_source.dart`, per-feature шов по канону [016](../../../specs/016-remote-datasource-seam/contracts/remote-data-sources.md)); реальный источник — `RealFileRemoteDataSource` (`[Environment.dev]`), мок — `MockFileRemoteDataSource` (`[prod, test]`).

Шаг 1 — **команда по сокету**, а не REST: `uploadBegin({name, sizeBytes, mime, fileId?})` кладёт `{name, size, mime, file_id?}` в конверт `{"id": N, "cmd": "file.uploadBegin", "data": {...}}` и разбирает ответ в `ResponseEntity<UploadTicketWireEntity>` (WS-клиент `NoxSocketClient`, `lib/data/remote/socket/nox_socket_client.dart` — [14-networking-and-auth.md](14-networking-and-auth.md)); `downloadBegin({fileId})` — то же для скачивания.

Шаг 2 — **единственная REST-операция цепочки отправки** (на приёме ей симметричен `openBytes` — `GET` с `Range`/`If-Range`): сырой `PUT` по относительному `upload_url` через `ApiClient.dio`. Никакого `multipart/form-data`: тело — открытые байты файла от `offset` до конца, потоком (в память файл не поднимаем; копия очереди на диске запечатана, и байты отдаёт тот, кто её открыл). Прогресс считается от всего файла (`offset + sent`). Ответ разбирает сам датасорс (`validateStatus` < 500) и превращает отказ в `FileTransferException` с видом `FileTransferFailure` (`passRejected`, `sizeMismatch`, `staleRange`, `connection`, `pathChanged`, `serverError`, `sourceUnreadable`, …), а не отдаёт сырой `DioException` общему мапперу: `404` на `/files/<token>` значит «нужен новый пропуск», а общий маппер сделал бы из него терминальный `notFound`.

`lib/data/remote/datasource/file_remote_data_source.dart` (сокращено):

```dart
abstract class FileRemoteDataSource {
  Future<ResponseEntity<UploadTicketWireEntity>> uploadBegin({
    required String name,
    required int sizeBytes,
    required String mime,
    String? fileId, // continue that upload (phase 043)
  });

  /// The file's plain bytes from [offset] to its end; [size] is the whole file's length.
  /// [body] may be a Stream<Uint8List>: bind a transformer to it, never body.transform(...).
  Future<void> putBytes({
    required String uploadPath,
    required int size,
    required int offset,
    required Stream<List<int>> body,
    TransferProgress? onProgress,
    TransferCancellation? cancellation,
  });

  Future<ResponseEntity<DownloadTicketWireEntity>> downloadBegin({required String fileId});

  /// The rest from [offset] when [validator] (Last-Modified) still names the server's version, the whole file otherwise.
  Future<FetchedBytes> openBytes({required String downloadPath, required int offset, String? validator});

  void cancelTransfers();
}
```

### 5.4 Шаг 3: attach to message (`message.send` по сокету)

Шаг 3 **не заводит своего API-класса** — это существующий шов отправки сообщения: `MessageRemoteDataSource.sendMessage(...)` (`lib/data/remote/datasource/message_remote_data_source.dart`). Реальная команда `message.send` по сокету живёт в `RealMessageRemoteDataSource` (`Environment.dev`); мок `SendMessageApi` — за `MockMessageRemoteDataSource` (`prod`/`test`). Возврат — `ResponseEntity<MessageWireEntity>` (эхо), **без** статус-кодов: их в этой цепочке нет. Авторства в запросе нет (сервер берёт его из сессии); вложение уходит как `attachment: {file_id: attachment.id}` — `id` к этому моменту уже серверный `file_id`, который вернул `FileRepository.upload`.

```dart
abstract class MessageRemoteDataSource {
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config});

  // Contract 5 shape: no authorship; the idempotency key is assigned when queued (phase 027).
  // The real source sends only {file_id: attachment.id}; localPath never leaves the device.
  Future<ResponseEntity<MessageWireEntity>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    MessageAttachment? attachment,
  });
}
```

### 5.5 Репозитории (network-only)

Network-only команды: **без** DAO (carve-out [04-data-layer.md](04-data-layer.md) §8). Каждый метод обёрнут в `execute<T>()` (mixin `BaseRepositoryHelper`, `lib/data/exception/base_repository_helper.dart`) — он всегда логирует через `LogRepository` и имеет **четыре** catch-ветки: `on BaseRepositoryException` (уже смапленный доменный код проходит наверх **неразбавленным**), `on SocketUnavailableException` → `connection`, `on DioException` (коэрция по типу/статусу: таймауты и `connectionError` → `connection`, 401 → `unauthenticated`, 403 → `authentication`, 404 → `notFound`, остальное → `internal`) и catch-all → `unknown`.

Конверт разворачивает **готовый** хелпер `unwrapEnvelope<TD>(response, what)` того же миксина — руками `response.data` не проверять:

```dart
TD unwrapEnvelope<TD>(ResponseEntity<TD> response, String what) {
  final data = response.data;
  if (data != null) return data;
  final error = response.error;
  if (error != null) throw RepositoryException.fromWireCode(error.code); // contract 2.1
  throw StateError('$what envelope has no data (success=${response.success})');
}
```

`lib/data/repository/file/file_repository_impl.dart`: `@LazySingleton(as: FileRepository, env: [Environment.dev, Environment.prod, Environment.test])`, `FileRepositoryImpl(this._remote, this._config, this._vault)` — `FileRemoteDataSource`, `AppConfigRepository` (лимиты) и `DeviceVault` (запечатывание, фаза 048). Каждый публичный метод обёрнут в `execute`. `upload` открывает источник и снимает его отпечаток (размер и время изменения, проба открытия) **до** объявления, объявляет файл (`uploadBegin`, с `file_id` — продолжение), сообщает ручку `UnfinishedUpload` через `onUnfinished` **до** первого байта, шлёт остаток от `received` (`putBytes`) и возвращает `file_id` только после того, как сервер принял байты, а отпечаток источника не изменился. Отказ передачи он классифицирует сам — не так, как очередь сообщений:

| `FileTransferFailure` | Итог в `upload` |
|---|---|
| `passRejected` | один новый пропуск в той же попытке; второй отказ подряд — `internal` (считается очередью) |
| `pathChanged` | продолжение по новому пути сразу, без паузы и счёта (не больше 5 раз подряд, дальше — `connection`) |
| `sizeMismatch` | `invalidRequest` — терминально |
| `sourceUnreadable` | `notFound` — терминально |
| `serverError` | `internal` — считается как отказ сервера |
| `connection`, `staleRange` | `connection` — обрыв, повтор по лестнице |

`download` — одна попытка на файл (второй вызов присоединяется к идущей), продолжение части `<cache>.part` по `Range`/`If-Range`, запечатывание кусками по мере прихода, файл готов только при размере, заявленном в сообщении (`expectedSize`).

`lib/data/repository/chat/message_repository_impl.dart`, шаг 3:

```dart
@override
Future<RepositoryResult<MessageModel>> sendMessage({
  required String chatId,
  required String clientMessageId,
  String? text,
  MessageAttachment? attachment,
}) {
  return execute<MessageModel>(() async {
    final response = await _messageRemote.sendMessage(
      chatId: chatId,
      clientMessageId: clientMessageId,
      text: text,
      attachment: attachment, // the real source sends only {file_id: attachment.id}
    );
    final data = unwrapEnvelope(response, 'send');
    // The wire carries no statuses (contract 5): an echoed own message is "accepted by server".
    var message = _wireMapper.toModel(entity: data).copyWith(status: MessageStatus.sent);
    // The echo carries no device-local path - re-attach the sent one (contract 6:
    // merge, not replace), otherwise the inline thumbnail disappears.
    final sentPath = attachment?.localPath;
    if (sentPath != null && message.attachment != null) {
      message = message.copyWith(attachment: message.attachment!.copyWith(localPath: sentPath));
    }
    await _messageDao.upsert(_mapper.toEntity(model: message));
    await _touchChatRow(chatId, message); // the list row follows the thread
    return RepositoryResult<MessageModel>.success(data: message);
  });
}
```

> **Маппинг ошибок в доменный код.** Отдельного «разбора статусов» больше не требуется: коды провода §2.1 приходят в объекте `error` ответа и превращаются в доменные `unwrapEnvelope` → `RepositoryException.fromWireCode`, а ветка `on BaseRepositoryException` в `execute` доносит их до UI неразбавленными. Значимые для этой цепочки: `payload_too_large` (предотвращается предполётной проверкой §2, **не повторять**), `attachment_gone` (терминальное состояние экрана файла, без кнопки повтора), `rate_limited` (**автоповтор с backoff**), `invalid_request` (ошибка программиста — лог + фатальный экран), `not_found` (нет такого `file_id`/чата). Неизвестный код трактуется как `internal` (inline-повтор) — правило эволюции контракта. Транспортные отказы `PUT`/`GET` до общего маппера `DioException` не доходят: датасорс превращает их в `FileTransferException`, а `FileRepositoryImpl` — в доменный код по таблице выше.

DI: `@lazySingleton` на API/мапперах, `@LazySingleton(as: ..., env:[dev,prod,test])` на репозиториях, real/mock-датасорсы — по окружению (`[dev]` / `[prod, test]`); единый прогон `build_runner` сгенерит `configure_dependencies.config.dart` ([02-dependency-injection.md](02-dependency-injection.md), [12-dev-commands.md](12-dev-commands.md)).

---

## 6. BLoC панели вложения (Freezed, executeLogic позиционный)

Экран ведёт пользователя по трём шагам (выбрать файл → `FileRepository.upload` — `uploadBegin` + `PUT` → отправить) и держит весь конвейер в одном BLoC. State — `@freezed sealed` union; Event — `@freezed sealed` union; обёртка асинхронной логики — `BaseBloc.executeLogic` с **позиционным** первым аргументом ([05-presentation-layer.md](05-presentation-layer.md) §2). Снэкбар и уход с экрана — **статус-эффекты в состоянии** (`failure`, `sent`), которые страница ловит `BlocListener` ([05-presentation-layer.md](05-presentation-layer.md) §5.6). Варианты состояния названы каноническими bare-именами `Initializing`/`Initialized`/`Error` (как в shipped-коде; префиксные `<Feature>Initializing` — допустимый вариант против коллизий, см. [05-presentation-layer.md](05-presentation-layer.md) §3).

> **Где это живёт в приложении.** `upload_page` ниже — worked example одной страницы; в shipped-коде та же роль у composer'а треда (`AppThreadViewWidget` + `ChatThreadBloc`), который уже дёргает `FilePickerService` и рисует черновик вложения. Читать как канон конвейера, а не как «нужно завести ещё один экран».

### 6.1 Event

`lib/presentation/pages/upload_page/bloc/upload_event.dart`:

```dart
part of 'upload_bloc.dart';

@freezed
sealed class UploadEvent with _$UploadEvent {
  const factory UploadEvent.initialize({required String chatId}) = Initialize;

  /// The user picked a file - upload it (uploadBegin + PUT, inside FileRepository.upload).
  const factory UploadEvent.addAttachment({required PickedFile file}) = AddAttachment;

  /// Drop an attachment that has not been sent yet.
  const factory UploadEvent.removeAttachment({required String localId}) = RemoveAttachment;

  /// Step 3: send the message carrying the uploaded file_id.
  const factory UploadEvent.sendRequested({@Default('') String text}) = SendRequested;

  /// The page has shown the failure (snackbar): the status effect goes back to rest.
  const factory UploadEvent.failureShown() = FailureShown;
}
```

### 6.2 State

`lib/presentation/pages/upload_page/bloc/upload_state.dart`:

```dart
part of 'upload_bloc.dart';

@freezed
sealed class UploadState with _$UploadState {
  const factory UploadState.initializing() = Initializing;

  const factory UploadState.initialized({
    required String chatId,
    @Default(<UploadedAttachment>[]) List<UploadedAttachment> attachments, // загруженные/в процессе
    @Default(false) bool sendInProgress,

    /// Status effect: a failure to tell the person (snackbar), cleared by failureShown().
    BaseRepositoryException? failure,

    /// Status effect: the server's echo of the sent message - the page closes with it.
    MessageModel? sent,
  }) = Initialized;

  const factory UploadState.error({BaseRepositoryException? exception}) = Error;
}

/// One attachment: upload status + (once done) the attachment with its wire file_id.
@freezed
sealed class UploadedAttachment with _$UploadedAttachment {
  const factory UploadedAttachment.uploading({required String localId, required double progress}) = AttachmentUploading;
  const factory UploadedAttachment.ready({required String localId, required MessageAttachment attachment}) = AttachmentReady;
  const factory UploadedAttachment.failed({required String localId, required BaseRepositoryException exception}) = AttachmentFailed;
}

extension InitializedExt on Initialized {
  List<String> get readyFileIds =>
      attachments.whereType<AttachmentReady>().map((a) => a.attachment.id).toList();

  /// Ready to send: at least one uploaded file and no send in flight.
  bool get canSend =>
      readyFileIds.isNotEmpty &&
      !sendInProgress;

  bool get isAnyUploading => attachments.any((a) => a is AttachmentUploading);
}
```

> **Прогресс аплоада — в state, гранулярно.** Каждое вложение несёт свой `progress` (`AttachmentUploading.progress` 0.0..1.0). Глубокое value-equality Freezed ([05-presentation-layer.md](05-presentation-layer.md) §3.2) даёт точечные ребилды прогресс-бара без перерисовки всего экрана.

### 6.3 BLoC — handlers

`lib/presentation/pages/upload_page/bloc/upload_bloc.dart`:

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/mime_types.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'upload_event.dart';
part 'upload_state.dart';
part 'upload_bloc.freezed.dart';

class UploadBloc extends BaseBloc<UploadEvent, UploadState> {
  UploadBloc() : super(const UploadState.initializing()) {
    on<Initialize>(_onInitialize);
    on<AddAttachment>(_onAddAttachment);
    on<RemoveAttachment>(_onRemoveAttachment);
    on<SendRequested>(_onSendRequested);
    on<FailureShown>(_onFailureShown);
  }

  final _fileRepository = getIt<FileRepository>();
  final _messageRepository = getIt<MessageRepository>();

  void _onInitialize(Initialize event, Emitter<UploadState> emit) {
    emit(UploadState.initialized(chatId: event.chatId));
  }

  FutureOr<void> _onAddAttachment(AddAttachment event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized) return;

    final file = event.file;
    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    emit(state.copyWith(
      attachments: [...state.attachments, UploadedAttachment.uploading(localId: localId, progress: 0)],
    ));

    final path = file.path;
    if (path == null) {
      _fail(emit, localId, RepositoryException.notFound); // the platform exposed no path
      return;
    }
    final mime = MimeTypes.forFileName(file.name);

    await executeLogic(
      () async {
        // Steps 1 and 2 in one call: uploadBegin, then the bytes. The server's
        // file_id comes back only once the bytes are confirmed (contract 7).
        final result = await _fileRepository.upload(
          path: path,
          mime: mime,
          name: file.name,
          onProgress: (p) => _patchProgress(emit, localId, p),
        );
        result.match(
          onData: (fileId) => _replaceAttachment(
            emit,
            localId,
            UploadedAttachment.ready(
              localId: localId,
              attachment: MessageAttachment(
                id: fileId, // the server's file_id from here on
                type: FileType.fromExtension(file.extension),
                name: file.name,
                sizeBytes: file.sizeBytes,
                mime: mime,
                localPath: path, // device-local; never leaves the device
              ),
            ),
          ),
          onError: (exception) => _fail(emit, localId, exception),
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        _fail(emit, localId, RepositoryException.unknown);
      },
    );
  }

  FutureOr<void> _onSendRequested(SendRequested event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized || !state.canSend) return;
    final chatId = state.chatId;
    final ready = state.attachments.whereType<AttachmentReady>().first;
    // The key is NOT minted here in the shipped code: OutboxRepositoryImpl.enqueue
    // assigns it once and persists it with the queue row (phase 027), and the
    // OutboxService implementation is the only sender. This example calls sendMessage
    // directly to keep the file chain in one place, so the local is a stand-in for
    // the key the outbox hands back.
    final clientMessageId = const Uuid().v4();

    emit(state.copyWith(sendInProgress: true));

    await executeLogic(
      () async {
        final result = await _messageRepository.sendMessage(
          chatId: chatId,
          clientMessageId: clientMessageId,
          text: event.text.isEmpty ? null : event.text, // body is optional WITH an attachment
          attachment: ready.attachment, // id = file_id; localPath is re-attached onto the echo
        );
        final updated = this.state;
        if (updated is! Initialized) return;
        result.match(
          // The echo is the same whether this was the first send or a retry of the
          // same client_message_id - the server never creates a duplicate.
          onData: (message) => emit(updated.copyWith(sendInProgress: false, sent: message)),
          onError: (exception) => emit(updated.copyWith(sendInProgress: false, failure: exception)),
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        final updated = this.state;
        if (updated is Initialized) {
          emit(updated.copyWith(sendInProgress: false, failure: RepositoryException.unknown));
        }
      },
    );
  }

  void _onFailureShown(FailureShown event, Emitter<UploadState> emit) {
    final state = this.state;
    if (state is Initialized) emit(state.copyWith(failure: null));
  }

  // --- helpers (мутация списка вложений) ---
  // Получают `Emitter<UploadState> emit` активного хендлера: в bloc v8+ `emit` —
  // НЕ метод блока, а только параметр `on<Event>(handler, emit)`. Все вызовы ниже
  // приходят из колбэков (onProgress / result.match / executeLogic.onError), которые
  // исполняются ДО завершения Future хендлера, поэтому переданный `emit`
  // ещё валиден (канон 05 §2/§3.3 — эмиссия только через Emitter активного хендлера).

  void _patchProgress(Emitter<UploadState> emit, String localId, double progress) {
    final state = this.state;
    if (state is! Initialized) return;
    _replaceAttachment(emit, localId, UploadedAttachment.uploading(localId: localId, progress: progress));
  }

  void _replaceAttachment(Emitter<UploadState> emit, String localId, UploadedAttachment next) {
    final state = this.state;
    if (state is! Initialized) return;
    emit(state.copyWith(
      attachments: [for (final a in state.attachments) if (a.localId == localId) next else a],
    ));
  }

  void _fail(Emitter<UploadState> emit, String localId, BaseRepositoryException exception) {
    _replaceAttachment(emit, localId, UploadedAttachment.failed(localId: localId, exception: exception));
    final state = this.state;
    if (state is Initialized) emit(state.copyWith(failure: exception));
  }
}
```

> **`executeLogic` — позиционный первый аргумент** (`executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})`), `onError` — именованный. Это дословный канон [05-presentation-layer.md](05-presentation-layer.md) §2: репозитории уже залогировали ошибку через `LogRepository` ([04-data-layer.md](04-data-layer.md)), BLoC лишь переводит её в UX. `result.match(onData:, onError:)` — **никогда** `result.data!`. **Без `onError` `executeLogic` молча глотает** (ни emit, ни rethrow) — на обеих ветках выше он передан.

---

## 7. Страница: прогресс, вложение в UI, исход отправки

Страница — `StatefulWidget` + `BaseStatePage<T>` ([05-presentation-layer.md](05-presentation-layer.md) §4–5): BLoC в `initState` и `close()` в `dispose`, статус-эффекты — `BlocListener` с `listenWhen`, тело — через `state.when(...)`. Навигируемая страница **обязана** иметь свой BLoC (правило описано в [05-presentation-layer.md](05-presentation-layer.md); номерной Инвариант 3a — в [08-conventions-and-constitution.md](08-conventions-and-constitution.md)).

`lib/presentation/pages/upload_page/upload_page.dart` (ключевые куски):

```dart
@override
void initState() {
  super.initState();
  _bloc = UploadBloc()..add(UploadEvent.initialize(chatId: widget.chatId));
}

@override
void dispose() {
  _bloc.close();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  return BlocProvider<UploadBloc>.value(
    value: _bloc,
    child: MultiBlocListener(
      listeners: [
        // Snackbars carry LOCALIZED copy, never a raw exception (presentation/helpers/app_feedback_helper.dart).
        // The domain code -> string lookup happens HERE because AppLocalizations is
        // context-bound: _copyFor reads context.l10n (ARB, EN + UK, identical key sets).
        // `attachment_gone` is terminal - inform, offer no retry.
        BlocListener<UploadBloc, UploadState>(
          listenWhen: (previous, current) =>
              current is Initialized && current.failure != null && (previous is! Initialized || previous.failure != current.failure),
          listener: (context, state) {
            showAppSnackBar(context, text: _copyFor(context, (state as Initialized).failure!), error: true);
            _bloc.add(const UploadEvent.failureShown());
          },
        ),
        // One outcome only: the echo. A repeat of the same client_message_id returns the
        // same message, so there is no "already sent" branch to render.
        BlocListener<UploadBloc, UploadState>(
          listenWhen: (previous, current) => current is Initialized && current.sent != null && (previous is! Initialized || previous.sent == null),
          listener: (context, state) => Navigator.of(context).pop((state as Initialized).sent),
        ),
      ],
      child: BlocBuilder<UploadBloc, UploadState>(builder: (context, state) => /* state.when(...) */),
    ),
  );
}
```

Вложение в UI — чип или инлайн-эскиз, по типу и наличию локального файла:

```dart
// inside state.when(initialized: (s) { ... })
// IMAGE + a readable localPath -> AppImageAttachmentWidget (inline thumbnail, tap ->
// full-screen viewer); anything else -> AppFileChipWidget (type glyph + name + size).
// AttachmentUploading -> progress bar on a.progress; AttachmentFailed -> error icon + retry.
// The send button follows s.canSend; while s.isAnyUploading the uploads are still running.
```

> **Прогресс в реальном приложении — не в BLoC загрузки, а в общем реестре передач.** Шаблон выше держит прогресс в state своего экрана; в NOX отправку делает очередь исходящих (`OutboxService`, фазы 027–028), которая переживает и экран, и процесс, поэтому прогресс живёт отдельно — в `AttachmentTransferService` (`lib/domain/service/`, реализация в `lib/data/service/`), только в памяти. Пишут в него двое: очередь (`upload` под `client_message_id` сообщения — это id его пузыря до принятия сервером; передача длится до принятия самого сообщения, а не только до последнего байта) и докачка картинок `AttachmentPrefetchService` (`download` под id сохранённого сообщения). Читает `ChatThreadBloc`, проецируя карту в `Initialized.transfers`; пузырь рисует кольцо над картинкой, `Sending… 45%` над полоской в чипе и заполняющееся кольцо в плейсхолдере принимаемой картинки. Реестр публикует изменение только при смене целого процента — иначе каждый колбэк Dio перерисовывал бы ленту.

> **Превью изображений — в скоупе (фича 020, ревизии владельца 2026-07-26 и 2026-09-20).** Вложение-**изображение**, у которого есть реальный локальный файл (`MessageAttachment.localPath`), рендерится инлайн-эскизом с переходом в полноэкранный просмотр (`AppImageAttachmentWidget`; при нечитаемом файле — грациозный откат на чип, никогда «битая картинка»). Изображение, чьи байты ещё не пришли, занимает место эскиза с глифом картинки и спиннером (подкачка уже идёт); состояния разводят два предиката — `AppImageAttachmentWidget.wouldRender` (это станет эскизом, когда байты придут) и `canRender` (файл на диске). Формат, который эскизом не станет никогда, и любой другой тип остаются чипом с иконкой типа (`AppFileChipWidget`). Видео на экране файла 5.3 играет внутри приложения на iOS/Android/macOS (`VideoPlaybackCapability`), и только из локального файла. Скачанные с сервера байты дают `localPath` тем же путём (`downloadBegin` → `GET` → файл на устройстве, запечатанный; картинки читаются в память через `LocalFileImage`). Формулировка «type-icon chips only» из списка вне скоупа в `docs/design/spec/overview.md` этими ревизиями отменена.

---

## 8. Удаление вложения до отправки (клиентское)

Удалить ещё **не** отправленное вложение из набора — чисто клиентская операция: событие `RemoveAttachment` убирает запись из `attachments` в state, никаких сетевых вызовов. Если аплоад файла ещё идёт (`AttachmentUploading`), отмена снимает его из списка; уже загруженный, но не привязанный к сообщению `file_id` остаётся на сервере осиротевшим — **контракт §7 закрывает это сам:** загрузки, не привязанные к сообщению за сутки, зачищаются при старте сервера (строка и байты). Клиенту здесь делать нечего — команды «отменить загрузку» в контракте нет.

> **Инвариант.** Пока сообщение не отправлено (шаг 3), вложение существует только в клиентском state как `file_id`. Никакого специального серверного «отката» загрузки на клиенте не делается. В NOX нет понятий квоты/расхода/возврата — удаление до отправки бесплатно и локально.

---

## 9. Чеклист

- [ ] **Picker** — `FilePickerService` поверх `file_selector` (`file_picker` **запрещён** — конфликт `win32` с `package_info_plus`); только метаданные (`PickedFile`), байты не читаются; `mime` — `MimeTypes.forFileName`, категория — `FileType.fromExtension`; нативные диалоги на всех пяти платформах.
- [ ] **Предполётная проверка** — `picked.sizeBytes` против `ServerLimits.maxAttachmentBytes` (рукопожатие §3, пишется живым транспортом с фазы 026; до первого рукопожатия и на мок-флаворах — `contractDefaults`, 100 MB) **до** `uploadBegin`: `payload_too_large` по §2.1 неповторяем, его предотвращают.
- [ ] **Шаг 1 (`file.uploadBegin`)** — команда по сокету `{name, size, mime, file_id?}` → `{fileId, uploadUrl, uploadToken, maxAttachmentBytes, received}`; `name` ≤ 255, `mime` ≤ 128, иначе `invalid_request`; ручка незаконченной загрузки — в записи очереди до первого байта; `received` отсутствует — сервер не умеет продолжать, файл идёт целиком.
- [ ] **Шаг 2 (`PUT`)** — сырые байты потоком по относительному `upload_url`, **остаток от `received`**; прогресс — доля всего файла; сторож застоя 45 с, после последнего байта ответ ждётся до 3 минут; после обрыва — **продолжение** (`uploadBegin` с `file_id`), а не повтор `PUT`; слепок исходника (с пробным открытием) сверяется до и после; 5xx и неназванные статусы, `401` включительно, — отказ (`internal`), а не выход; `408`/`409` — обрыв; смена пути — продолжение в той же попытке; выброшенное сообщение обрывает свой `PUT`.
- [ ] **Шаг 3 (`message.send`)** — `{chat_id, client_message_id, body?, attachment: {file_id}}` по сокету → эхо `{message: Message}`; `body` опционален при наличии вложения; авторства в запросе нет; таймаут 10 с → локальный `error` + повтор тем же ключом.
- [ ] **Идемпотентность** — ключ `client_message_id` (UUID) назначается **при постановке в очередь** и персистится с ней (фаза 027); повтор возвращает **прежнее эхо** — различать «создано»/«уже было» нечем и не нужно; никаких `201`/`200` в цепочке нет.
- [ ] **Скачивание** — `file.downloadBegin` → `GET` с `Range` + `If-Range` от части на устройстве (`.part` + `.part.tag`); повторы — `AttachmentDownloadService` (одна передача на файл, лестница пауз, путь в сообщение пишет сам); часть пишется `RandomAccessFile` с ожиданием каждого куска, сбой диска отпускает передачу; при выходе и смене мира — сброс подкачки, затем `reset()` (не дольше 5 с, `fetch()` в это время отказывает), затем очистка кэша отдельно; `expires_at` персистится в `MessageAttachment` и гасит Save заранее; `attachment_gone` — терминальное состояние экрана файла (5.3) **без** кнопки повтора.
- [ ] **Мапперы** — `BaseMapper<E, M, dynamic, dynamic>` (4-арг generic из кода); коэрция (unix-секунды ↔ `DateTime`, `file_id` → `id`, категория из расширения) — в `toModel`/`toEntity`; применение эха/события — **merge, а не replace** (`localPath`/`status` не затирать).
- [ ] **Network-only** — цепочка без Sembast-DAO ([04-data-layer.md](04-data-layer.md) §8); каждый метод в `execute<T>()` (лог через `LogRepository`; **четыре** ветки: `on BaseRepositoryException` — пропуск неразбавленным, `on SocketUnavailableException` → `connection`, `on DioException` — коэрция по типу/статусу, catch-all → `unknown`; отказы байтовых передач классифицирует сам `FileRepositoryImpl` через `FileTransferFailure`, §5.5); конверт разворачивать `unwrapEnvelope(...)`, коды провода — `RepositoryException.fromWireCode` (неизвестный → `internal`).
- [ ] **BLoC** — `@freezed sealed` State/Event (bare-имена `Initializing`/`Initialized`/`Error`); `executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})` (позиционный первый арг, **всегда** с `onError`); прогресс per-attachment в state (гранулярные ребилды); снэкбар и уход с экрана — статус-эффекты в состоянии (`failure`, `sent`), страница ловит их `BlocListener`, `failure` гасится событием; `result.match`, никогда `result.data!`.
- [ ] **Страница** — `BaseStatePage<T>`, BLoC в `initState`/`dispose`, статус-эффекты — `BlocListener` с `listenWhen`, `state.when`; изображение с локальным файлом — инлайн-эскиз + полноэкранный просмотр (фича 020), остальное — чип с иконкой типа; исход отправки — возврат в чат; снэкбары — локализованный текст из ARB, не сырое исключение.
- [ ] **Сеть/транспорт** — команды по WebSocket-конверту v0 (транспорт приехал в фазе 026), REST только под байты файлов; `ApiClient`/`baseClient` — из [14-networking-and-auth.md](14-networking-and-auth.md), **не переизобретать**; каждое соединение — канал модуля с проверкой `/auth` и `/auth2` (§6.0 там же), per-request Bearer-токенов в модели NOX нет.
- [ ] **Удаление до отправки** — `RemoveAttachment` чисто клиентский (убрать из state, без сети); осиротевшие загрузки зачищает сервер сам (не привязанные за сутки — при старте, §7).
- [ ] **Что реально открыто:** граница E2EE (Q1 — задевает `body`, не `attachment`); аутентификация закрыта каналом (проверка `POST /auth` → `POST /auth2` на каждом соединении, контракт §1) и спариванием (§8A); файловая цепочка §7 **закрыта** и реализована (фазы 028, 043, 048). DI-флип по [016](../../../specs/016-remote-datasource-seam/contracts/di-binding.md) сделан для chat/message/file: `Real*RemoteDataSource` связаны `env: [Environment.dev]`, моки — `[Environment.prod, Environment.test]` (окружение dev — это флейвор stage).

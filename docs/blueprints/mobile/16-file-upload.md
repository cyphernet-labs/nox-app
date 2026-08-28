# 16 — Загрузка вложения в чат (picker → uploadBegin → PUT → attach to message)

> **Назначение:** зафиксировать клиентский контракт вложения файла в сообщение чата в `nox_app` — выбор файла через `FilePickerService`, загрузка байтов по одноразовому токену и прикрепление загруженного файла к сообщению. Цепочка **задана контрактом v0 §7** ([contract-draft.md](../../client-backend/protocol/contract-draft.md)): `file.uploadBegin` (команда по сокету) → `PUT` байтов → `message.send {attachment: {file_id}}`; обратная сторона — `file.downloadBegin` → `GET` с поддержкой Range. Вложение-**изображение** с реальным локальным файлом рендерится инлайн-эскизом с переходом в полноэкранный просмотр (фича 020), любой другой тип — чип с иконкой типа файла. Worked-аналог `Item` из блюпринта здесь — пара `MessageAttachment` (загруженный файл) + `MessageModel` (сообщение, к которому файл прикреплён). Сетевой слой **не переизобретается** — берётся из [14-networking-and-auth.md](14-networking-and-auth.md): команды идут по WebSocket-конверту v0 (транспорт — фаза 027), REST остаётся **только** под байты файлов.
> **Когда читать:** перед реализацией composer'а вложений в треде (picker → upload → attach), перед поднятием файлового датасорса `uploadBegin → PUT → send` в `lib/data/` (переходное требование контракта §9.6, фаза 028) и при работе со скачиванием вложения (`downloadBegin` → `GET` Range).
> **Связанные документы:** [../../client-backend/protocol/contract-draft.md](../../client-backend/protocol/contract-draft.md) (**контракт v0** — §5 `message.send`, §7 файлы, §2.1 коды ошибок, §9 переходные требования), [04-data-layer.md](04-data-layer.md) (`ApiClient`, `BaseApiRepository`, `BaseRepositoryHelper.execute`/`unwrapEnvelope`, `ResponseEntity<T>`/`EntityConverter<E>`, мапперы, REST-слой, network-only POST), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозиториев, per-call конфиги), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, `BaseBloc.executeLogic`, side-эффект-стримы, `state.when`), [14-networking-and-auth.md](14-networking-and-auth.md) (сетевой слой — не переизобретать), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, регистрация репозиториев), [07-pagination.md](07-pagination.md) (список чатов — куда возвращается сообщение с вложением), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`file_selector`, `dio`).

---

## 0. Идея: три шага — begin, put, attach

Отправка вложения в NOX — это **не** один общий POST. Контракт v0 §7 разносит её на три шага, каждый со своим каналом и своими побочными эффектами:

1. **`file.uploadBegin`** — команда по сокету, `data` запроса `{name, size, mime}`, ответ `{file_id, upload_url, upload_token, max_attachment_bytes}`. Метаданные сервер берёт отсюда, а не из байтов; `mime` клиент выводит из расширения имени (`MimeTypes`, §2).
2. **`PUT <upload_url>`** — сырые байты по одноразовому токену (REST, тот же порт). `upload_url` — **относительный** путь `/files/<token>`; токен одноразовый, TTL 10 минут, гасится первым обращением независимо от исхода. Пробрасывается прогресс аплоада для прогресс-бара.
3. **`message.send {chat_id, client_message_id, body?, attachment: {file_id}}`** — отправка сообщения, ссылающегося на загруженный `file_id`; сервер собирает объект `attachment` из метаданных шага 1 в эхо и в событие `message.new`. Идемпотентность — по `client_message_id` (UUID, генерируется клиентом): при повторе сервер возвращает **прежнее эхо**, дубля не создаёт.

Обратная сторона — скачивание: `file.downloadBegin {file_id}` → `{download_url, download_token}` → `GET` с поддержкой Range (докачка), тот же одноразовый токен с TTL 10 минут.

```
[picker] FilePickerService.pickFile() → PickedFile{name, sizeBytes, extension, path}
   │
   ▼
1. FileRepository.uploadBegin(...)   → cmd file.uploadBegin  → UploadTicket{ fileId, uploadUrl, uploadToken, maxAttachmentBytes }
   │
   ▼
2. FileRepository.putBytes(...)      → PUT /files/<token>    → 204 (ровно заявленный size)
   │  (держим fileId для шага 3)
   ▼
3. MessageRepository.sendMessage(...) → cmd message.send     → MessageModel (серверное эхо, status=sent)
        повтор с тем же client_message_id → то же эхо, без дубля
```

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив).

> **Picker даёт метаданные, не репозиторий.** Picker живёт за доменным швом `FilePickerService` (`lib/domain/service/file_picker_service.dart`) и **не читает байты** — отдаёт `name`/`sizeBytes`/`extension`/`path`. Категория файла (`FileType`) выводится из расширения на клиенте и на проводе не живёт; на провод идёт `mime`.

---

## 1. Контракт и инварианты (что соблюдать дословно)

> Поля, коды и семантика ниже — **контракт v0 §7/§5**, а не иллюстрация. Открытым остаётся только то, что контракт сам помечает открытым: аутентификация (этап 2, §8.1) и граница E2EE (Q1) — она задевает `body`, но не `attachment`.

- **Аутентификации на этапе 1 нет.** Сокет открывается без подписи: `challenge` в приветствии сервера присутствует, но не проверяется. Модель этапа 2 — спаривание + подпись challenge ключом устройства **однократно при установлении соединения**, не на каждый запрос ([authentication.md](../../client-backend/architecture/authentication.md); нынешний `AuthInterceptor` с Bearer-токеном — **не** наша модель). Не проектировать вокруг per-request-токенов.
- **Токены файлов — не аутентификация, а capability.** `upload_token`/`download_token` одноразовые, TTL 10 минут, гасятся первым обращением независимо от исхода; после обрыва клиент запрашивает новый токен той же командой (`uploadBegin`/`downloadBegin`). Любой отказ токена на HTTP — единый `404` без раскрытия причин.
- **`PUT` принимает ровно заявленный `size`:** больше → `413`, меньше → `400`, байты не сохраняются. Значит `size` в `uploadBegin` берётся из того же `PickedFile`, что и байты, — пересчитывать между шагами нельзя.
- **`file_id` — единственное поле из шага 1, которое нужно держать для шага 3.** `upload_url`/`upload_token` живут только до `PUT`.
- **Идемпотентность по `client_message_id`.** Повторная отправка того же ключа не создаёт дубль: сервер хранит ключ и возвращает **прежнее эхо**. Клиент не различает «создано» и «уже было» — и не должен: ключ назначается при постановке в очередь и персистится с ней (переходное требование §9.3, фаза 026), повтор после реконнекта/рестарта идёт с тем же ключом.
- **Правила полей `uploadBegin`:** `name` ≤ 255 символов, `mime` ≤ 128, оба после трима непустые — нарушение → `invalid_request`. `mime` выводится клиентом из расширения имени (неизвестное расширение → `application/octet-stream`); байты пикер не читает.
- **Все методы репозиториев возвращают `RepositoryResult<T>`** ([03-domain-layer.md](03-domain-layer.md)). Коды провода §2.1 уже живут в enum `RepositoryException` (`invalidRequest`, `nameTaken`, `payloadTooLarge`, `attachmentGone`, `rateLimited`, `unsupportedSchema` + общие) и разбираются статикой `RepositoryException.fromWireCode(String)` — неизвестный код трактуется как `internal`. Маркерный тип — `BaseRepositoryException`.
- **Это network-only-фича** (one-shot команды) — без Sembast-DAO и `BehaviorSubject` (carve-out [04-data-layer.md](04-data-layer.md) §8). Отправленное сообщение затем подхватывается списком сообщений/чатов ([07-pagination.md](07-pagination.md)); само вложение персистится в записи сообщения (`MessageAttachment`, §4).

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

> **Капы — не константы этого документа.** Потолок вложения приходит в рукопожатии (`session.hello`) и лежит в data-слое как `ServerLimits.maxAttachmentBytes` (`lib/domain/model/app_config/server_limits.dart`, доступ — `AppConfigRepository.limits`). До появления живого транспорта (фаза 027) отдаются контрактные дефолты (`ServerLimits.contractDefaults`: 100 MB на вложение). Предполётная проверка **обязательна**, а не «опциональна ради UX»: §2.1 помечает `payload_too_large` как неповторяемый — его предотвращают, а не обрабатывают повтором.

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
  "max_attachment_bytes": 104857600
}
```

Ключевое поле — **`file_id`**: его держат для шага 3. `upload_url` — **относительный** путь (сервер своего публичного адреса не знает); базу подставляет клиент.

### Шаг 2 — `PUT <upload_url>` (байты, REST)

Тело — сырые байты файла, **ровно заявленный `size`**: больше → `413`, меньше → `400`, байты не сохраняются. Токен одноразовый (TTL 10 минут, гасится первым обращением независимо от исхода); любой отказ токена — единый `404` без раскрытия причин. После обрыва — новый `uploadBegin`, а не повтор того же `PUT`.

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

`{file_id}` → `{download_url, download_token}` → `GET <download_url>` с поддержкой **Range** (докачка после обрыва). Токен — те же правила (одноразовый, 10 минут, отказ = `404`). Истёкший срок либо физически отсутствующие байты → `attachment_gone`: по §2.1 это **терминальное error-состояние экрана файла (5.3), без кнопки повтора**, а не фатальный экран приложения.

| Шаг | Канал | Эффект |
|---|---|---|
| 1 `file.uploadBegin` | сокет | метаданные → `file_id` + одноразовый `upload_token` |
| 2 `PUT /files/<token>` | REST | байты (с прогрессом), ровно заявленный `size` |
| 3 `message.send` | сокет | сообщение с `{file_id}` → эхо; повтор `client_message_id` → то же эхо, без дубля |
| ↩ `file.downloadBegin` + `GET` | сокет + REST | скачивание с Range; `attachment_gone` — терминально |

---

## 4. Доменный слой: модели, конфиги, контракты

Доменные модели — Freezed без `fromJson` ([03-domain-layer.md](03-domain-layer.md)); JSON живёт в entity-слое (§5). Категория файла — существующий enum `FileType` (`lib/domain/model/file/file_type.dart`, 9 значений от `image` до `other`) с `FileType.fromExtension(String?)`: она **не** ходит по проводу, а выводится из расширения имени. На провод идёт `mime` (`MimeTypes.forFileName`, §2).

> **Что здесь РЕАЛЬНОЕ, а что ЦЕЛЕВОЕ — читать до кода ниже.** Из файловой части домена в shipped-коде существуют **только** `lib/domain/model/file/file_type.dart` и `lib/domain/model/file/mime_types.dart` (весь каталог `lib/domain/model/file/` — это ровно два файла), плюс модель вложения `lib/domain/model/chat/message_attachment.dart` и шов `lib/domain/service/file_picker_service.dart`. Всего остального в этом параграфе в `lib/` **нет**: ни `upload_ticket.dart`, ни каталога `lib/domain/repository/file/` (а значит ни `FileRepository`, ни `UploadConfig`), ни `SendMessageConfig`. Это **целевая форма**, приезжающая вместе с файловым датасорсом в **фазе 028** (переходное требование контракта §9.6); контрактная форма самого `sendMessage` — фаза 026 (§9.3). Каждый блок ниже помечен явно: **РЕАЛЬНОЕ** — файл существует и снипет зеркалит его; **ЦЕЛЕВОЕ** — файла в `lib/` ещё нет, снипет описывает форму, к которой приводим. Реален и общий каркас, в который целевое встраивается: маркер `RepositoryConfig` (`lib/domain/repository/base/repository_config.dart`) и per-call конфиги вроде `GetMessagesConfig` уже в коде.

**РЕАЛЬНОЕ** — `lib/domain/model/chat/message_attachment.dart`, единственная существующая сегодня модель вложения (результат шага 3 и то, что персистится в Sembast):

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

Результат шага 1 — отдельная транзиентная модель: она живёт ровно до `PUT` и никуда не персистится.

**ЦЕЛЕВОЕ (фаза 028)** — `lib/domain/model/file/upload_ticket.dart`, файла в `lib/` ещё нет:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload_ticket.freezed.dart';

/// Reply of `file.uploadBegin` (contract 7). One-shot, 10-minute TTL: nothing
/// here outlives the PUT, so it is never persisted.
@freezed
abstract class UploadTicket with _$UploadTicket {
  const factory UploadTicket({
    required String fileId,
    required String uploadUrl,   // relative path /files/<token>
    required String uploadToken,
    required int maxAttachmentBytes,
  }) = _UploadTicket;
}
```

Per-call конфиги — по одному на вызов (маркер `RepositoryConfig`, [03-domain-layer.md](03-domain-layer.md)). Сам маркер и конфиги чат-фичи (`GetChatsConfig`, `GetMessagesConfig`) — реальные; оба конфига ниже — нет.

**ЦЕЛЕВОЕ (фаза 028)** — `lib/domain/repository/file/upload_config.dart`; каталога `lib/domain/repository/file/` в `lib/` сегодня нет:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'upload_config.freezed.dart';

/// Everything `file.uploadBegin` needs, taken straight from the PickedFile:
/// `size` MUST be the size the bytes will actually have - the PUT accepts
/// exactly the declared value (contract 7).
@freezed
abstract class UploadConfig with _$UploadConfig implements RepositoryConfig {
  const factory UploadConfig({
    required String path,     // device-local path from PickedFile; bytes are streamed
    required String name,
    required int size,
    required String mime,     // MimeTypes.forFileName(name)
  }) = _UploadConfig;
}
```

**ЦЕЛЕВОЕ (фаза 026)** — `lib/domain/repository/chat/send_message_config.dart`, файла в `lib/` ещё нет (вложение — это тот же `message.send`, отдельной команды нет):

```dart
@freezed
abstract class SendMessageConfig with _$SendMessageConfig implements RepositoryConfig {
  const factory SendMessageConfig({
    required String chatId,
    required String clientMessageId, // UUID, assigned when queued (phase 026), persisted with the queue row
    String? text,                    // body; optional WHEN an attachment is present
    String? fileId,                  // attachment: {file_id} from step 1
    String? localPath,               // device-local file, re-attached onto the echo; never sent
  }) = _SendMessageConfig;
}
```

Контракты репозиториев (реализуются в `lib/data/`):

**ЦЕЛЕВОЕ (фаза 028)** — `lib/domain/repository/file/file_repository.dart`: файлового репозитория в `lib/` нет вообще; реальные подкаталоги `lib/domain/repository/` — `app`, `app_config`, `base`, `chat`, `item`, `qr`, `settings`, `sync` (плюс `log_repository.dart`), директории `file/` среди них нет:

```dart
import 'package:nox_app/domain/model/file/upload_ticket.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/file/upload_config.dart';

abstract class FileRepository {
  /// Step 1: reserve a file_id + one-shot upload token.
  Future<RepositoryResult<UploadTicket>> uploadBegin({required UploadConfig config});

  /// Step 2: PUT the bytes. onProgress feeds the progress bar (0.0..1.0).
  Future<RepositoryResult<bool>> putBytes({
    required UploadTicket ticket,
    required UploadConfig config,
    void Function(double progress)? onProgress,
  });

  /// Download side: a fresh one-shot token, then a Range-capable GET.
  Future<RepositoryResult<String>> downloadToFile({required String fileId, required String destinationPath});
}
```

Шаг 3 отдельного репозитория не заводит — это обычный `sendMessage` чат-фичи. Шов **уже существует, но в доконтрактной форме**, поэтому здесь обе стороны показаны рядом.

**РЕАЛЬНОЕ** — `lib/domain/repository/chat/message_repository.dart` в shipped-коде (остальные члены интерфейса — `getMessages`, `watchMessages`, `chatFiles`, `seedCreatedChat`, `simulateIncoming`, `clean` — к файловой цепочке не относятся и опущены):

```dart
abstract class MessageRepository {
  /// One-shot send. Returns the accepted (server) message on success.
  Future<RepositoryResult<MessageModel>> sendMessage({required String chatId, String? text, MessageAttachment? attachment});
}
```

**ЦЕЛЕВОЕ (фаза 026)** — та же операция после перевода на per-call конфиг:

```dart
abstract class MessageRepository {
  /// Step 3: the attachment rides the ordinary send (contract 5).
  Future<RepositoryResult<MessageModel>> sendMessage({required SendMessageConfig config});
}
```

> **Что именно меняется.** В нынешней форме ключа идемпотентности нет, а вложение передаётся моделью `MessageAttachment` целиком — вместе с `localPath`, которого на проводе не существует. Контрактная форма заменяет её на `SendMessageConfig` с `clientMessageId` + `fileId` — переходные требования §9.3/§9.6, фаза 026 (`client_message_id` назначается при постановке в очередь и персистится с ней). До этого перехода весь блок «целевого» кода в §4–§5 читается как проект, а не как описание `lib/`.

> **Почему не `(MessageModel, bool isCreated)`.** Различия «создано» vs «уже было» на проводе **нет**: при повторе того же `client_message_id` сервер возвращает **прежнее эхо**, неотличимое от первого. Клиенту это и не нужно — идемпотентность закрывает очередь исходящих (фаза 026): ключ назначается при постановке, повтор после реконнекта/рестарта идёт с тем же ключом, дубль невозможен. Никаких HTTP-статусов `201`/`200` в этой цепочке нет — `message.send` идёт по сокету.

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

Новым здесь остаётся только ответ шага 1 — `UploadTicketWireEntity` (`lib/data/entity/file/wire/upload_ticket_wire_entity.dart`): `@JsonKey(name: 'file_id') fileId`, `@JsonKey(name: 'upload_url') uploadUrl`, `@JsonKey(name: 'upload_token') uploadToken`, `@JsonKey(name: 'max_attachment_bytes') maxAttachmentBytes` — и симметричный ему `DownloadTicketWireEntity` (`download_url`, `download_token`).

### 5.2 Мапперы (вся коэрция здесь)

`BaseMapper` — 4-аргументный generic из кода (`lib/data/mapper/base_mapper.dart`): `abstract class BaseMapper<E, M, AdResult, AdParam>` с `toModel({required E entity, AdResult Function(AdParam entity)? ad})` и `toEntity({required M model, AdResult Function(AdParam entity)? ad})`. Конкретный маппер без вспомогательного контекста подставляет `dynamic, dynamic` в `AdResult/AdParam` и игнорирует `ad` ([04-data-layer.md](04-data-layer.md) §2).

`lib/data/mapper/file/upload_ticket_wire_mapper.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/file/wire/upload_ticket_wire_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/file/upload_ticket.dart';

@lazySingleton
class UploadTicketWireMapper extends BaseMapper<UploadTicketWireEntity, UploadTicket, dynamic, dynamic> {
  @override
  UploadTicket toModel({required UploadTicketWireEntity entity, dynamic Function(dynamic entity)? ad}) => UploadTicket(
        fileId: entity.fileId,
        uploadUrl: entity.uploadUrl,
        uploadToken: entity.uploadToken,
        maxAttachmentBytes: entity.maxAttachmentBytes,
      );

  @override
  UploadTicketWireEntity toEntity({required UploadTicket model, dynamic Function(dynamic entity)? ad}) => UploadTicketWireEntity(
        fileId: model.fileId,
        uploadUrl: model.uploadUrl,
        uploadToken: model.uploadToken,
        maxAttachmentBytes: model.maxAttachmentBytes,
      );
}
```

Вложение сообщения маппит уже существующий `MessageWireMapper` (`lib/data/mapper/chat/message_wire_mapper.dart`): `file_id → id`, `expires_at` (unix-секунды) → `DateTime`, а `type` — **вывод** `FileType.fromExtension(MimeTypes.extensionOf(name))`, потому что категории на проводе нет. Локальные поля (`status`, `localPath`) эту границу не пересекают: применение эха/события — **merge, а не replace** (контракт §6), иначе свежепикнутый `localPath` затрётся серверным эхом и инлайн-эскиз исчезнет.

### 5.3 Транспорт шага 1 и шага 2

Шаг 1 — **команда по сокету**, а не REST: `FileRemoteDataSource` (новый per-feature шов по канону [016](../../../specs/016-remote-datasource-seam/contracts/remote-data-sources.md), методы `uploadBegin`/`downloadBegin`) кладёт `{name, size, mime}` в конверт `{"id": N, "cmd": "file.uploadBegin", "data": {...}}` и разбирает ответ в `ResponseEntity<UploadTicketWireEntity>` (WS-клиент — фаза 027, [14-networking-and-auth.md](14-networking-and-auth.md)).

Шаг 2 — **единственная REST-операция цепочки отправки** (на приёме ей симметричен `GET` скачивания): сырой `PUT` по относительному `upload_url`. Никакого `multipart/form-data`: тело — байты файла, потоком с диска (в память файл не поднимаем). `onSendProgress` Dio пробрасывается наверх для прогресс-бара. На non-2xx Dio бросает `DioException` — его **не** ловят на уровне API (канон [04-data-layer.md](04-data-layer.md) §7г).

`lib/data/remote/api/file/put_file_bytes_api.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/api/base/base_api_repository.dart';
import 'package:nox_app/domain/model/file/upload_ticket.dart';
import 'package:nox_app/domain/repository/file/upload_config.dart';

@lazySingleton
class PutFileBytesApi extends BaseApiRepository {
  /// Contract 7: raw bytes, EXACTLY the declared size (bigger -> 413, smaller -> 400).
  /// The url is the relative path handed out by uploadBegin; any token failure is a
  /// bare 404 with no reason, and the token is burned either way - retry means a new
  /// uploadBegin, never a second PUT with the same token.
  Future<void> execute({
    required UploadTicket ticket,
    required UploadConfig config,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(config.path);
    await baseClient.put(
      ticket.uploadUrl,
      data: file.openRead(), // streamed; never buffered into memory
      options: Options(
        contentType: config.mime,
        headers: {Headers.contentLengthHeader: config.size},
      ),
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) onProgress(sent / total);
      },
    );
  }
}
```

### 5.4 Шаг 3: attach to message (`message.send` по сокету)

Шаг 3 **не заводит своего API-класса** — это существующий шов отправки сообщения: `MessageRemoteDataSource.sendMessage(...)` (`lib/data/remote/datasource/message_remote_data_source.dart`), сегодня за ним мок `SendMessageApi`, в фазе 028 — реальная команда `message.send` по сокету. Возврат — `ResponseEntity<MessageWireEntity>` (эхо), **без** статус-кодов: их в этой цепочке нет.

К форме контракта датасорс приводится в фазе 026 (переходное требование §9.6): уходят `authorId`/`authorLabel` (сервер берёт их из сессии), появляются `client_message_id` и `attachment: {file_id}`:

```dart
abstract class MessageRemoteDataSource {
  Future<ResponseEntity<MessagesWireEntity>> getMessages({required GetMessagesConfig config});

  // Contract 5 shape (phase 026): no authorship in the request, idempotency key
  // assigned when queued, attachment referenced by file_id only.
  Future<ResponseEntity<MessageWireEntity>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    String? fileId,
  });
}
```

### 5.5 Репозитории (network-only)

Network-only команды: **без** DAO/`BehaviorSubject` (carve-out [04-data-layer.md](04-data-layer.md) §8). Каждый метод обёрнут в `execute<T>()` (mixin `BaseRepositoryHelper`, `lib/data/exception/base_repository_helper.dart`) — он всегда логирует через `LogRepository` и имеет **три** catch-ветки: `on BaseRepositoryException` (уже смапленный доменный код проходит наверх **неразбавленным**), `on DioException` (коэрция по типу/статусу: таймауты и `connectionError` → `connection`, 401 → `unauthenticated`, 403 → `authentication`, 404 → `notFound`, остальное → `internal`) и catch-all → `unknown`.

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

`lib/data/repository/file/file_repository_impl.dart`:

```dart
@LazySingleton(as: FileRepository, env: [Environment.dev, Environment.prod, Environment.test])
class FileRepositoryImpl with BaseRepositoryHelper implements FileRepository {
  FileRepositoryImpl(this._remote, this._putApi, this._ticketMapper);

  final FileRemoteDataSource _remote;
  final PutFileBytesApi _putApi;
  final UploadTicketWireMapper _ticketMapper;

  @override
  Future<RepositoryResult<UploadTicket>> uploadBegin({required UploadConfig config}) {
    return execute<UploadTicket>(() async {
      final response = await _remote.uploadBegin(config: config);
      // A wire error code (invalid_request / payload_too_large / rate_limited) is
      // thrown as a BaseRepositoryException and passes through execute unchanged.
      final entity = unwrapEnvelope(response, 'file.uploadBegin');
      return RepositoryResult<UploadTicket>.success(data: _ticketMapper.toModel(entity: entity));
    });
  }

  @override
  Future<RepositoryResult<bool>> putBytes({
    required UploadTicket ticket,
    required UploadConfig config,
    void Function(double progress)? onProgress,
  }) {
    return execute<bool>(() async {
      await _putApi.execute(ticket: ticket, config: config, onProgress: onProgress);
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
```

`lib/data/repository/chat/message_repository_impl.dart` (целевой фрагмент шага 3, после расширения шва в фазе 026):

```dart
@override
Future<RepositoryResult<MessageModel>> sendMessage({required SendMessageConfig config}) {
  return execute<MessageModel>(() async {
    final response = await _remote.sendMessage(
      chatId: config.chatId,
      clientMessageId: config.clientMessageId,
      text: config.text,
      fileId: config.fileId,
    );
    final entity = unwrapEnvelope(response, 'message.send');
    final model = _wireMapper.toModel(entity: entity);
    // The echo carries no localPath - re-attach the device-local one before persisting
    // (contract 6: merge, not replace), otherwise the inline thumbnail disappears.
    return RepositoryResult<MessageModel>.success(
      data: model.copyWith(attachment: model.attachment?.copyWith(localPath: config.localPath)),
    );
  });
}
```

> **Маппинг ошибок в доменный код.** Отдельного «разбора статусов» больше не требуется: коды провода §2.1 приходят в объекте `error` ответа и превращаются в доменные `unwrapEnvelope` → `RepositoryException.fromWireCode`, а ветка `on BaseRepositoryException` в `execute` доносит их до UI неразбавленными. Значимые для этой цепочки: `payload_too_large` (предотвращается предполётной проверкой §2, **не повторять**), `attachment_gone` (терминальное состояние экрана файла, без кнопки повтора), `rate_limited` (**автоповтор с backoff**), `invalid_request` (ошибка программиста — лог + фатальный экран), `not_found` (нет такого `file_id`/чата). Неизвестный код трактуется как `internal` (inline-повтор) — правило эволюции контракта. Транспортные отказы `PUT` (`413`/`400`/`404`) остаются `DioException` и коэрсятся веткой Dio.

DI: `@lazySingleton` на API/мапперах, `@LazySingleton(as: ..., env:[dev,prod,test])` на репозиториях; единый прогон `build_runner` сгенерит `configure_dependencies.config.dart` ([02-dependency-injection.md](02-dependency-injection.md), [12-dev-commands.md](12-dev-commands.md)).

---

## 6. BLoC панели вложения (Freezed, executeLogic позиционный)

Экран ведёт пользователя по трём шагам (выбрать файл → `uploadBegin` + `PUT` → отправить) и держит весь конвейер в одном BLoC. State — `@freezed sealed` union; Event — `@freezed sealed` union; обёртка асинхронной логики — `BaseBloc.executeLogic` с **позиционным** первым аргументом ([05-presentation-layer.md](05-presentation-layer.md) §2). Навигация и снэкбары — через `PublishSubject`-стримы, **не** через state. Варианты состояния названы каноническими bare-именами `Initializing`/`Initialized`/`Error` (как в shipped-коде; префиксные `<Feature>Initializing` — допустимый вариант против коллизий, см. [05-presentation-layer.md](05-presentation-layer.md) §3).

> **Где это живёт в приложении.** `upload_page` ниже — worked example одной страницы; в shipped-коде та же роль у composer'а треда (`AppThreadViewWidget` + `ChatThreadBloc`), который уже дёргает `FilePickerService` и рисует черновик вложения. Читать как канон конвейера, а не как «нужно завести ещё один экран».

### 6.1 Event

`lib/presentation/pages/upload_page/bloc/upload_event.dart`:

```dart
part of 'upload_bloc.dart';

@freezed
sealed class UploadEvent with _$UploadEvent {
  const factory UploadEvent.initialize({required String chatId}) = Initialize;

  /// The user picked a file - queue it, then run uploadBegin + PUT.
  const factory UploadEvent.addAttachment({required UploadConfig config}) = AddAttachment;

  /// Drop an attachment that has not been sent yet.
  const factory UploadEvent.removeAttachment({required String localId}) = RemoveAttachment;

  /// Step 3: send the message carrying the uploaded file_id.
  const factory UploadEvent.sendRequested({@Default('') String text}) = SendRequested;
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
  }) = Initialized;

  const factory UploadState.error({BaseRepositoryException? exception}) = Error;
}

/// One attachment: upload status + (once done) its wire file_id.
@freezed
sealed class UploadedAttachment with _$UploadedAttachment {
  const factory UploadedAttachment.uploading({required String localId, required double progress}) = AttachmentUploading;
  const factory UploadedAttachment.ready({required String localId, required String fileId, required UploadConfig config}) = AttachmentReady;
  const factory UploadedAttachment.failed({required String localId, required BaseRepositoryException exception}) = AttachmentFailed;
}

extension InitializedExt on Initialized {
  List<String> get readyFileIds =>
      attachments.whereType<AttachmentReady>().map((a) => a.fileId).toList();

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
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/upload_ticket.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/send_message_config.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/file/upload_config.dart';
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
  }

  final _fileRepository = getIt<FileRepository>();
  final _messageRepository = getIt<MessageRepository>();

  // The domain code travels; the page turns it into copy via context.l10n
  // (AppLocalizations is context-bound, so a BLoC cannot hold the string).
  final _errorsController = PublishSubject<BaseRepositoryException>();
  final _messageSentController = PublishSubject<MessageModel>();

  Stream<BaseRepositoryException> get errors => _errorsController.stream;

  Stream<MessageModel> get messageSent => _messageSentController.stream;

  @override
  Future<void> close() async {
    await _errorsController.close();
    await _messageSentController.close();
    await super.close();
  }

  void _onInitialize(Initialize event, Emitter<UploadState> emit) {
    emit(UploadState.initialized(chatId: event.chatId));
  }

  FutureOr<void> _onAddAttachment(AddAttachment event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized) return;

    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    emit(state.copyWith(
      attachments: [...state.attachments, UploadedAttachment.uploading(localId: localId, progress: 0)],
    ));

    await executeLogic(
      () async {
        // Step 1: reserve file_id + one-shot token.
        final begun = await _fileRepository.uploadBegin(config: event.config);
        final ticket = begun.match<UploadTicket?>(
          onData: (ticket) => ticket,
          onError: (exception) {
            _fail(emit, localId, exception);
            return null;
          },
        );
        if (ticket == null) return;
        // Step 2: PUT the bytes under that token. A broken PUT means a NEW
        // uploadBegin next time - the token is burned either way (contract 7).
        final put = await _fileRepository.putBytes(
          ticket: ticket,
          config: event.config,
          onProgress: (p) => _patchProgress(emit, localId, p),
        );
        put.match(
          onData: (_) => _replaceAttachment(
            emit,
            localId,
            UploadedAttachment.ready(localId: localId, fileId: ticket.fileId, config: event.config),
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
    // The idempotency key is assigned ONCE, when the send is queued, and persisted
    // with the queue row (phase 026) - a retry after a reconnect reuses it.
    final clientMessageId = const Uuid().v4();

    emit(state.copyWith(sendInProgress: true));

    await executeLogic(
      () async {
        final result = await _messageRepository.sendMessage(
          config: SendMessageConfig(
            chatId: chatId,
            clientMessageId: clientMessageId,
            fileId: ready.fileId,
            localPath: ready.config.path,
            text: event.text.isEmpty ? null : event.text, // body is optional WITH an attachment
          ),
        );
        final updated = this.state;
        if (updated is! Initialized) return;
        result.match(
          onData: (message) {
            emit(updated.copyWith(sendInProgress: false));
            // The echo is the same whether this was the first send or a retry of the
            // same client_message_id - the server never creates a duplicate.
            _messageSentController.add(message);
          },
          onError: (exception) {
            emit(updated.copyWith(sendInProgress: false));
            _errorsController.add(exception);
          },
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        final updated = this.state;
        if (updated is Initialized) emit(updated.copyWith(sendInProgress: false));
        _errorsController.add(RepositoryException.unknown);
      },
    );
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
      attachments: [for (final a in state.attachments) if (_localIdOf(a) == localId) next else a],
    ));
  }

  void _fail(Emitter<UploadState> emit, String localId, BaseRepositoryException exception) {
    _replaceAttachment(emit, localId, UploadedAttachment.failed(localId: localId, exception: exception));
    _errorsController.add(exception);
  }
}
```

> **`executeLogic` — позиционный первый аргумент** (`executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})`), `onError` — именованный. Это дословный канон [05-presentation-layer.md](05-presentation-layer.md) §2: репозитории уже залогировали ошибку через `LogRepository` ([04-data-layer.md](04-data-layer.md)), BLoC лишь переводит её в UX. `result.match(onData:, onError:)` — **никогда** `result.data!`. **Без `onError` `executeLogic` молча глотает** (ни emit, ни rethrow) — на обеих ветках выше он передан.

---

## 7. Страница: прогресс, вложение в UI, исход отправки

Страница — `StatefulWidget` + `BaseStatePage<T>` ([05-presentation-layer.md](05-presentation-layer.md) §4–5): BLoC в `initState`, side-эффект-подписки в `initState` и отмена в `dispose`, тело — через `state.when(...)`. Навигируемая страница **обязана** иметь свой BLoC (правило описано в [05-presentation-layer.md](05-presentation-layer.md); номерной Инвариант 3a — в [08-conventions-and-constitution.md](08-conventions-and-constitution.md)).

`lib/presentation/pages/upload_page/upload_page.dart` (ключевые куски):

```dart
@override
void initState() {
  _bloc = UploadBloc()..add(UploadEvent.initialize(chatId: widget.chatId));
  // Snackbars carry LOCALIZED copy, never a raw exception (AlertDialogHelper, doc 05 sec. 8).
  // The domain code -> string lookup happens HERE because AppLocalizations is
  // context-bound: _copyFor reads context.l10n (ARB, EN + UK, identical key sets).
  // `attachment_gone` is terminal - inform, offer no retry.
  _errorSub = _bloc.errors.listen((e) => AlertDialogHelper.showSnackBar(context, _copyFor(context, e)));
  // One outcome only: the echo. A repeat of the same client_message_id returns the
  // same message, so there is no "already sent" branch to render.
  _sentSub = _bloc.messageSent.listen((message) => Navigator.of(context).pop(message));
  super.initState();
}

@override
void dispose() {
  _errorSub.cancel();
  _sentSub.cancel();
  _bloc.close();
  super.dispose();
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

> **Превью изображений — В СКОУПЕ с фичи 020.** Вложение-**изображение**, у которого есть реальный локальный файл (`MessageAttachment.localPath`), рендерится инлайн-эскизом с переходом в полноэкранный просмотр (`AppImageAttachmentWidget`; при нечитаемом файле — грациозный откат на чип, никогда «битая картинка»). Любой другой тип — и изображение без локального файла — остаётся чипом с иконкой типа (`AppFileChipWidget`). Прежняя формулировка «type-icon chips only» из `docs/design/spec/overview.md` **отменена** ревизией владельца (2026-07-26). Скачанные с сервера байты дают `localPath` тем же путём (`downloadBegin` → `GET` → файл на устройстве). На всех пяти платформах (iOS/Android/Windows/Linux/macOS) обе формы выглядят и ведут себя одинаково.

---

## 8. Удаление вложения до отправки (клиентское)

Удалить ещё **не** отправленное вложение из набора — чисто клиентская операция: событие `RemoveAttachment` убирает запись из `attachments` в state, никаких сетевых вызовов. Если аплоад файла ещё идёт (`AttachmentUploading`), отмена снимает его из списка; уже загруженный, но не привязанный к сообщению `file_id` остаётся на сервере осиротевшим — **контракт §7 закрывает это сам:** загрузки, не привязанные к сообщению за сутки, зачищаются при старте сервера (строка и байты). Клиенту здесь делать нечего — команды «отменить загрузку» в контракте нет.

> **Инвариант.** Пока сообщение не отправлено (шаг 3), вложение существует только в клиентском state как `file_id`. Никакого специального серверного «отката» загрузки на клиенте не делается. В NOX нет понятий квоты/расхода/возврата — удаление до отправки бесплатно и локально.

---

## 9. Чеклист

- [ ] **Picker** — `FilePickerService` поверх `file_selector` (`file_picker` **запрещён** — конфликт `win32` с `package_info_plus`); только метаданные (`PickedFile`), байты не читаются; `mime` — `MimeTypes.forFileName`, категория — `FileType.fromExtension`; нативные диалоги на всех пяти платформах.
- [ ] **Предполётная проверка** — `picked.sizeBytes` против `ServerLimits.maxAttachmentBytes` (рукопожатие §3; до фазы 027 — `contractDefaults`, 100 MB) **до** `uploadBegin`: `payload_too_large` по §2.1 неповторяем, его предотвращают.
- [ ] **Шаг 1 (`file.uploadBegin`)** — команда по сокету `{name, size, mime}` → `UploadTicket{fileId, uploadUrl, uploadToken, maxAttachmentBytes}`; `name` ≤ 255, `mime` ≤ 128, иначе `invalid_request`; держим только `file_id`.
- [ ] **Шаг 2 (`PUT`)** — сырые байты потоком по относительному `upload_url`, **ровно заявленный `size`** (больше → `413`, меньше → `400`); `onSendProgress` → прогресс-бар; токен одноразовый, TTL 10 минут — после обрыва **новый `uploadBegin`**, а не повтор `PUT`.
- [ ] **Шаг 3 (`message.send`)** — `{chat_id, client_message_id, body?, attachment: {file_id}}` по сокету → эхо `{message: Message}`; `body` опционален при наличии вложения; авторства в запросе нет; таймаут 10 с → локальный `error` + повтор тем же ключом.
- [ ] **Идемпотентность** — ключ `client_message_id` (UUID) назначается **при постановке в очередь** и персистится с ней (фаза 026); повтор возвращает **прежнее эхо** — различать «создано»/«уже было» нечем и не нужно; никаких `201`/`200` в цепочке нет.
- [ ] **Скачивание** — `file.downloadBegin` → `GET` с Range (докачка); `expires_at` персистится в `MessageAttachment` и гасит Save заранее; `attachment_gone` — терминальное состояние экрана файла (5.3) **без** кнопки повтора.
- [ ] **Мапперы** — `BaseMapper<E, M, dynamic, dynamic>` (4-арг generic из кода); коэрция (unix-секунды ↔ `DateTime`, `file_id` → `id`, категория из расширения) — в `toModel`/`toEntity`; применение эха/события — **merge, а не replace** (`localPath`/`status` не затирать).
- [ ] **Network-only** — цепочка без Sembast-DAO и `BehaviorSubject` ([04-data-layer.md](04-data-layer.md) §8); каждый метод в `execute<T>()` (лог через `LogRepository`; **три** ветки: `on BaseRepositoryException` — пропуск неразбавленным, `on DioException` — коэрция по типу/статусу, catch-all → `unknown`); конверт разворачивать `unwrapEnvelope(...)`, коды провода — `RepositoryException.fromWireCode` (неизвестный → `internal`).
- [ ] **BLoC** — `@freezed sealed` State/Event (bare-имена `Initializing`/`Initialized`/`Error`); `executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})` (позиционный первый арг, **всегда** с `onError`); прогресс per-attachment в state (гранулярные ребилды); навигация/снэкбары через `PublishSubject`, не через state; `result.match`, никогда `result.data!`.
- [ ] **Страница** — `BaseStatePage<T>`, BLoC + side-эффект-подписки в `initState`/`dispose`, `state.when`; изображение с локальным файлом — инлайн-эскиз + полноэкранный просмотр (фича 020), остальное — чип с иконкой типа; исход отправки — возврат в чат; снэкбары — локализованный текст из ARB, не сырое исключение.
- [ ] **Сеть/транспорт** — команды по WebSocket-конверту v0 (фаза 027), REST только под байты файлов; `ApiClient`/`baseClient` — из [14-networking-and-auth.md](14-networking-and-auth.md), **не переизобретать**; per-request Bearer-токенов в модели NOX нет.
- [ ] **Удаление до отправки** — `RemoveAttachment` чисто клиентский (убрать из state, без сети); осиротевшие загрузки зачищает сервер сам (не привязанные за сутки — при старте, §7).
- [ ] **Что реально открыто:** аутентификация этапа 2 (спаривание/подпись, §8.1) и граница E2EE (Q1 — задевает `body`, не `attachment`); файловая цепочка §7 **закрыта** и реализуется в фазе 028 (DI-флип по [016](../../../specs/016-remote-datasource-seam/contracts/di-binding.md)).

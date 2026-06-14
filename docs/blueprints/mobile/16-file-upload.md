# 16 — Загрузка вложения в чат (picker → multipart upload → attach to message)

> **Назначение:** зафиксировать клиентский контракт загрузки вложения в сообщение чата в `nox_app` — выбор файла/изображения через picker, multipart-upload через Dio с прогрессом, и прикрепление загруженного файла к сообщению чата. Вложение в UI рендерится как чип с иконкой типа файла (без превью содержимого — по дизайну NOX). Конкретный контракт endpoint'ов — **пример-плейсхолдер** (бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт). Worked-аналог `Item` из блюпринта здесь — пара `Attachment` (один загруженный файл) + `Message` (сообщение, к которому файл прикреплён). Сетевой слой (Dio `ApiClient`, signing + access/refresh-токены) **не переизобретается** — берётся из [14-networking-and-auth.md](14-networking-and-auth.md).
> **Когда читать:** перед реализацией экрана/панели вложений в чате (file/image picker → upload → attach), перед поднятием `UploadRepository` / `AttachmentRepository` в `lib/data/`, и при добавлении нового типа вложения (`document`/`image`).
> **Связанные документы:** [04-data-layer.md](04-data-layer.md) (`ApiClient`, `BaseApiRepository`, `BaseRepositoryHelper.execute`, `ResponseEntity<T>`/`EntityConverter<E>`, мапперы, REST-слой, network-only POST), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозиториев, per-call конфиги), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, `BaseBloc.executeLogic`, side-эффект-стримы, `state.when`), [14-networking-and-auth.md](14-networking-and-auth.md) (сетевой слой, signing + access/refresh-токены, security-заголовки — не переизобретать), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, регистрация репозиториев), [07-pagination.md](07-pagination.md) (список чатов — куда возвращается сообщение с вложением), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`file_picker`, `image_picker`, `dio`).

---

## 0. Идея: два шага — upload, затем attach

Отправка вложения в NOX — это **не** один общий POST. Это два вызова, каждый со своим контрактом и своими побочными эффектами:

1. **Upload** (`POST <upload-endpoint>` — *пример-плейсхолдер; бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт*) — клиент загружает выбранный файл (multipart) и получает на него `attachment_id`. Пробрасывается прогресс аплоада для прогресс-бара.
2. **Attach to message** (`POST <message-endpoint>` — *пример-плейсхолдер*) — отправка сообщения чата, ссылающегося на ранее загруженный `attachment_id`. Идемпотентно по natural-key `(chat_id, client_message_id)`: первый вызов → `201`, повтор того же `client_message_id` → `200` без повторной отправки (где идемпотентность имеет смысл — клиент генерирует `client_message_id` локально).

```
[picker] выбрать document/image
   │
   ▼
1. UploadRepository.uploadFile(...)  → POST <upload-endpoint>    → AttachmentModel{ attachmentId, ... }
   │  (держим attachmentId для шага 2)
   ▼
2. AttachmentRepository.sendAttachment(...) → POST <message-endpoint> → (MessageModel, bool isCreated)
        201 Created + Location  → новое сообщение с вложением
        200 OK (без Location)   → существующее сообщение (тот же client_message_id),
                                  без повторной отправки
```

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `nox_app` (worked example). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив).

> **Picker даёт файл, не репозиторий.** Picker'ы (file/image) живут в presentation-слое; репозиторий принимает уже готовые байты/путь и тип вложения. Вложение всегда загружается как файл — `document` или `image`.

---

## 1. Контракт и инварианты (что соблюдать дословно)

> Конкретные endpoint'ы, заголовки, статусы и поля ниже — **примеры-плейсхолдеры** (бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт). Дословно соблюдать нужно **паттерн** (picker → multipart → attach, network-only, `RepositoryResult<T>`), а не конкретные имена полей.

- **Оба шага требуют аутентификации** (`Authorization: Bearer <access_token>`, [14-networking-and-auth.md](14-networking-and-auth.md) §4). Refresh→rotate→retry на `401` — забота auth-слоя из доки 14, **не** этого экрана.
- **Подпись запроса (signing + security-заголовки) — забота interceptor'а доки 14**, не репозиториев этого документа. Сноска: шаг 1 (`upload`) — **единственный** `multipart/form-data` endpoint, и подпись `multipart/form-data` может отличаться от обычного JSON-пайплайна; шаг 2 — обычный JSON-пайплайн с полным набором security-заголовков. Конкретику подписи multipart-запроса финализировать вместе с контрактом бэкенда NOX (см. [14-networking-and-auth.md](14-networking-and-auth.md) §4 FLAG).
- **`attachment_id` — единственное поле из шага 1, которое нужно держать для шага 2.** (Конкретное имя поля — пример; заменить на реальный контракт.)
- **Идемпотентность по natural-key.** `(chat_id, client_message_id)` — повторная отправка того же `client_message_id` не создаёт дубль сообщения. Клиент генерирует `client_message_id` локально (например, UUID) и различает исходы по HTTP-статусу (`201` vs `200`) или наличию заголовка `Location`. (Конкретная форма ключа/статусов — пример-плейсхолдер.)
- **Все методы репозиториев возвращают `RepositoryResult<T>`** ([03-domain-layer.md](03-domain-layer.md)); конкретные доменные коды (`notFound` на `404`, и т.п.) возвращаются **явным** `return RepositoryResult.error(...)` в callback'е `execute`, а не из catch-веток (канон [04-data-layer.md](04-data-layer.md) §5). Маркерный тип ошибки — `BaseRepositoryException`; общие коды — из enum `RepositoryException` ([03-domain-layer.md](03-domain-layer.md)).
- **Это network-only-фича** (one-shot POST'ы) — без Sembast-DAO и `BehaviorSubject` (carve-out [04-data-layer.md](04-data-layer.md) §8). Отправленное сообщение затем подхватывается списком сообщений/чатов ([07-pagination.md](07-pagination.md)).

---

## 2. Выбор файла: `file_picker` / `image_picker`

Picker'ы живут в presentation-слое (или в тонком helper'е), но **не** в репозитории — репозиторий принимает уже готовые байты/путь. Пакеты — `file_picker` (документы/произвольные файлы) и `image_picker` (камера/галерея) (см. [01-stack-and-tooling.md](01-stack-and-tooling.md)). Размер/MIME-капы проверяются сервером (шаг 1, см. §3) — клиент валидирует их же **до** аплоада ради UX (мгновенный отказ вместо round-trip). Капы — плейсхолдеры (см. §3), так что клиентская пре-флайт-проверка опциональна и сверяется с реальным контрактом NOX.

`lib/presentation/pages/upload_page/helpers/source_picker_helper.dart`:

```dart
import 'dart:io';

import 'package:collection/collection.dart'; // singleOrNull (IterableExtension)
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nox_app/domain/model/upload/attachment_type.dart';

/// Тонкая обёртка над picker'ами.
/// Возвращает (файл, его тип вложения) или null (отмена).
class SourcePickerHelper {
  final _imagePicker = ImagePicker();

  /// Документ (pdf / docx). Cap 50 MB сверяется сервером; клиент-side — ради UX.
  Future<(File, AttachmentType)?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
      withData: false, // читаем поток с диска, не держим в памяти
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return null;
    return (File(path), AttachmentType.document);
  }

  /// Изображение (jpeg / png / webp). Cap 20 MB.
  Future<(File, AttachmentType)?> pickImage({required ImageSource source}) async {
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) return null;
    return (File(picked.path), AttachmentType.image);
  }
}
```

> На десктопе (Windows/Linux/macOS — целевые платформы NOX, см. [00-architecture-overview.md](00-architecture-overview.md)) `file_picker` использует нативные системные диалоги; камера через `image_picker` доступна на мобильных платформах, на десктопе остаётся выбор файла из галереи/ФС. Конкретные ограничения per-platform сверять с пакетами на этапе реализации.

> Капы/MIME-таблица ниже (§3) — **примеры-плейсхолдеры** (бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт). Конкретные расширения/лимиты сверяются с реальным контрактом бэкенда NOX.

---

## 3. Контракт endpoint'ов (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт)

> Всё в этом разделе — **пример-плейсхолдер**: endpoint'ы, заголовки, статусы, имена и форма полей приведены как иллюстрация паттерна. Финальный контракт фиксируется вместе с выбором бэкенда/протокола NOX.

### Шаг 1 — Upload (`POST <upload-endpoint>`)

`multipart/form-data`. Form-поля: `attachment_type` (`document`/`image`), `file` (payload). Капы (превышение → `413`, MIME-несоответствие → `415`):

| `attachment_type` | Cap | Допустимые MIME |
|---|---|---|
| `document` | 50 MB | `application/pdf`, `…wordprocessingml.document` |
| `image` | 20 MB | `image/jpeg`, `image/png`, `image/webp` |

Ответ (`200 OK`), `data`-объект:

```json
{
  "attachment_id": "att_456",
  "attachment_type": "image",
  "mime_type": "image/jpeg",
  "size_bytes": 238942,
  "checksum_md5": "a7f5f35426b927411fc9231b56382173"
}
```

Ключевое поле — **`attachment_id`**: его держат для шага 2.

### Шаг 2 — Attach to message (`POST <message-endpoint>`)

JSON. Request:

```json
{
  "chat_id": "chat_001",
  "client_message_id": "550e8400-e29b-41d4-a716-446655440000",
  "text": "",
  "attachment_id": "att_456"
}
```

- `chat_id` — обязателен (id чата, в который уходит сообщение).
- `client_message_id` — обязателен; клиент генерирует локально (например, UUID); по нему сервер дедуплицирует отправку.
- `text` — опционален, trimmed (пусто → хранится `''`); сообщение может нести только вложение без текста.
- `attachment_id` — id ранее загруженного файла (шаг 1). Несуществующий/чужой → `404` с `details.reason`.
- **Исходы по natural-key:** первый вызов нового `client_message_id` → **`201 Created`** + `Location: <message-endpoint>/{message_id}/` + Message-конверт; повтор того же `client_message_id` в том же чате → **`200 OK`** + существующий Message-конверт, **без** `Location` и без повторной отправки.

Message-конверт (`data`, оба исхода):

```json
{
  "id": "msg_001",
  "chat_id": "chat_001",
  "sender_id": "usr_123",
  "created_at": "2024-10-27T03:33:20.000Z",
  "text": "",
  "attachment": {
    "attachment_id": "att_456",
    "attachment_type": "image",
    "mime_type": "image/jpeg",
    "size_bytes": 238942,
    "file_name": "photo.jpg"
  }
}
```

| Шаг | Endpoint | Эффект |
|---|---|---|
| 1 upload | `POST <upload-endpoint>` | загрузка файла → `attachment_id` (multipart, с прогрессом) |
| 2 attach | `POST <message-endpoint>` | отправка сообщения с вложением на пути `201`; на пути `200` (повтор `client_message_id`) — без повторной отправки |

---

## 4. Доменный слой: модели, конфиги, контракты

Доменные модели — Freezed без `fromJson` ([03-domain-layer.md](03-domain-layer.md)); JSON живёт в entity-слое (§5). Enum `AttachmentType` — рядом с моделью.

`lib/domain/model/upload/attachment_type.dart`:

```dart
/// Тип вложения. Сериализуется как .name на проводе (см. mapper).
enum AttachmentType { document, image }
```

`lib/domain/model/upload/attachment_model.dart` (результат шага 1):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/upload/attachment_type.dart';

part 'attachment_model.freezed.dart';

@freezed
abstract class AttachmentModel with _$AttachmentModel {
  const factory AttachmentModel({
    required String attachmentId,
    required AttachmentType attachmentType,
    required String mimeType,
    required int sizeBytes,
    required String checksumMd5,
  }) = _AttachmentModel;
}
```

Per-call конфиги — по одному на вызов (маркер `RepositoryConfig`, [03-domain-layer.md](03-domain-layer.md)).

`lib/domain/repository/upload/upload_config.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/upload/attachment_type.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'upload_config.freezed.dart';

@freezed
abstract class UploadConfig with _$UploadConfig implements RepositoryConfig {
  /// Файл с диска (document/image) — отдаём путь, читаем потоком.
  const factory UploadConfig.fromPath({
    required AttachmentType attachmentType,
    required String path,
    required String fileName,
  }) = _UploadConfigFromPath;

  /// Синтетический файл из байтов (например, изображение из памяти).
  const factory UploadConfig.fromBytes({
    required AttachmentType attachmentType,
    required Uint8List bytes,
    required String fileName,
  }) = _UploadConfigFromBytes;
}
```

`lib/domain/repository/chat/send_attachment_config.dart`:

```dart
@freezed
abstract class SendAttachmentConfig with _$SendAttachmentConfig implements RepositoryConfig {
  const factory SendAttachmentConfig({
    required String chatId,
    required String clientMessageId, // генерируется клиентом (UUID); ключ дедупликации
    required String attachmentId,
    @Default('') String text,
  }) = _SendAttachmentConfig;
}
```

Контракты репозиториев (реализуются в `lib/data/`):

`lib/domain/repository/upload/upload_repository.dart`:

```dart
import 'package:nox_app/domain/model/upload/attachment_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/upload/upload_config.dart';

abstract class UploadRepository {
  /// Шаг 1: загрузить ОДИН файл. onProgress — для прогресс-бара (0.0..1.0).
  Future<RepositoryResult<AttachmentModel>> uploadFile({
    required UploadConfig config,
    void Function(double progress)? onProgress,
  });
}
```

`lib/domain/repository/chat/attachment_repository.dart`:

```dart
abstract class AttachmentRepository {
  /// Шаг 2: отправить сообщение с вложением.
  /// Возвращает (сообщение, isCreated): isCreated=true для 201, false для 200 (повтор client_message_id).
  Future<RepositoryResult<(MessageModel, bool)>> sendAttachment({required SendAttachmentConfig config});
}
```

> **Зачем `(MessageModel, bool)` на attach.** Сервер различает «отправлено» (`201`) и «уже было» (`200`) **только** статусом/`Location`. Репозиторий обязан вернуть это различие наверх (кортеж `(MessageModel, bool isCreated)`), а **не** прятать его — UX «сообщение отправлено» vs «уже отправлено ранее» зависит от исхода (§7).

> **`MessageModel` / `MessageEntity` — конкретный аналог worked-example `Item`** для чат-фичи (модель `lib/domain/model/chat/message_model.dart`, entity `lib/data/entity/chat/message_entity.dart`), а **не** типы из [07-pagination.md](07-pagination.md) (там список построен на абстрактном `ItemModel`). Ссылки на `07` — про **механику** списка (куда уходит отправленное сообщение в открытый список чатов NOX), а не про определение `MessageModel`; сами типы вводятся чат-фичей (форма entity зеркалит конверт сообщения из §3 — `id`/`chat_id`/`sender_id`/`created_at`/`text`/`attachment`).

---

## 5. Слой данных: entities, мапперы, REST, репозитории

### 5.1 Entities + `ResponseEntity<T>`

Entities — `@freezed` + `json_serializable`, только базовые типы; enum как `.name`, `DateTime` как ISO-8601 String ([04-data-layer.md](04-data-layer.md) §1). Каждый entity, ходящий через `ResponseEntity<T>`, регистрируется в **обеих** цепочках `EntityConverter` ([04-data-layer.md](04-data-layer.md) §3). (Имена полей ниже — пример-плейсхолдер; заменить на реальный контракт.)

`lib/data/entity/upload/attachment_entity.dart`:

```dart
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment_entity.freezed.dart';
part 'attachment_entity.g.dart';

@freezed
abstract class AttachmentEntity with _$AttachmentEntity {
  const factory AttachmentEntity({
    @JsonKey(name: 'attachment_id') required String attachmentId,
    @JsonKey(name: 'attachment_type') required String attachmentType,
    @JsonKey(name: 'mime_type') required String mimeType,
    @JsonKey(name: 'size_bytes') required int sizeBytes,
    @JsonKey(name: 'checksum_md5') required String checksumMd5,
  }) = _AttachmentEntity;

  factory AttachmentEntity.fromJson(Map<String, dynamic> json) => _$AttachmentEntityFromJson(json);
}
```

`MessageEntity` строится так же (snake_case `@JsonKey`, `created_at` — String, маппится в `DateTime` в маппере). `MessageEntity` зеркалит §3-конверт (`attachment` — вложенный entity).

### 5.2 Мапперы (вся коэрция здесь)

`BaseMapper` — 4-аргументный generic из кода (`lib/data/mapper/base_mapper.dart`): `abstract class BaseMapper<E, M, AdResult, AdParam>` с `toModel({required E entity, AdResult Function(AdParam entity)? ad})` и `toEntity({required M model, AdResult Function(AdParam entity)? ad})`. Конкретный маппер без вспомогательного контекста подставляет `dynamic, dynamic` в `AdResult/AdParam` и игнорирует `ad` ([04-data-layer.md](04-data-layer.md) §2).

`lib/data/mapper/upload/attachment_mapper.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/upload/attachment_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/upload/attachment_model.dart';
import 'package:nox_app/domain/model/upload/attachment_type.dart';

@lazySingleton
class AttachmentMapper extends BaseMapper<AttachmentEntity, AttachmentModel, dynamic, dynamic> {
  @override
  AttachmentModel toModel({required AttachmentEntity entity, dynamic Function(dynamic entity)? ad}) => AttachmentModel(
        attachmentId: entity.attachmentId,
        attachmentType: AttachmentType.values.byName(entity.attachmentType),
        mimeType: entity.mimeType,
        sizeBytes: entity.sizeBytes,
        checksumMd5: entity.checksumMd5,
      );

  @override
  AttachmentEntity toEntity({required AttachmentModel model, dynamic Function(dynamic entity)? ad}) => AttachmentEntity(
        attachmentId: model.attachmentId,
        attachmentType: model.attachmentType.name,
        mimeType: model.mimeType,
        sizeBytes: model.sizeBytes,
        checksumMd5: model.checksumMd5,
      );
}
```

`MessageMapper` (тоже `BaseMapper<MessageEntity, MessageModel, dynamic, dynamic>`) коэрсит `attachment_type`-строку (snake_case → `AttachmentType`) и `created_at` (ISO-8601 String → `DateTime.parse(...).toUtc()`).

### 5.3 REST-слой: multipart upload (шаг 1)

Upload — **единственный** multipart API. API-класс расширяет `BaseApiRepository` ([04-data-layer.md](04-data-layer.md) §7б) и шлёт `FormData` через `baseClient`. `onSendProgress` Dio пробрасывается наверх для прогресс-бара. На non-2xx Dio бросает `DioException` — его **не** ловят на уровне API (канон [04-data-layer.md](04-data-layer.md) §7г). Путь endpoint'а ниже — пример-плейсхолдер; заменить на реальный контракт бэкенда NOX.

`lib/data/remote/api/upload/post_upload_file_api.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/upload/attachment_entity.dart';
import 'package:nox_app/data/remote/api/base/base_api_repository.dart';
import 'package:nox_app/domain/repository/upload/upload_config.dart';

@lazySingleton
class PostUploadFileApi extends BaseApiRepository {
  Future<ResponseEntity<AttachmentEntity>> execute({
    required UploadConfig config,
    void Function(double progress)? onProgress,
  }) async {
    final MultipartFile filePart = await config.map(
      fromPath: (c) => MultipartFile.fromFile(c.path, filename: c.fileName),
      fromBytes: (c) async => MultipartFile.fromBytes(c.bytes, filename: c.fileName),
    );
    final attachmentType = config.map(fromPath: (c) => c.attachmentType, fromBytes: (c) => c.attachmentType);

    final formData = FormData.fromMap({
      'attachment_type': attachmentType.name, // 'document' | 'image'
      'file': filePart,
    });

    final response = await baseClient.post(
      'v1/attachments/upload/', // пример-плейсхолдер; заменить на реальный endpoint
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) onProgress(sent / total);
      },
    );
    return ResponseEntity<AttachmentEntity>.fromJson(response.data);
  }
}
```

### 5.4 REST-слой: attach to message (шаг 2, JSON)

JSON-API-класс — каноническая форма ([04-data-layer.md](04-data-layer.md) §7г): build path → POST через `baseClient` → `ResponseEntity<T>.fromJson`. На attach **status-line и `Location` нужны выше** (различить `201`/`200`) — поэтому API возвращает не голый entity, а пару `(ResponseEntity<MessageEntity>, int statusCode)`. Путь endpoint'а и поля — пример-плейсхолдер; заменить на реальный контракт.

`lib/data/remote/api/chat/post_send_attachment_api.dart`:

```dart
@lazySingleton
class PostSendAttachmentApi extends BaseApiRepository {
  Future<(ResponseEntity<MessageEntity>, int)> execute({required SendAttachmentConfig config}) async {
    final response = await baseClient.post(
      'v1/messages/', // пример-плейсхолдер; заменить на реальный endpoint
      data: {
        'chat_id': config.chatId,
        'client_message_id': config.clientMessageId,
        'text': config.text,
        'attachment_id': config.attachmentId,
      },
    );
    final entity = ResponseEntity<MessageEntity>.fromJson(response.data);
    return (entity, response.statusCode ?? 0); // 201 vs 200 — load-bearing
  }
}
```

### 5.5 Репозитории (network-only)

Network-only POST'ы: **без** DAO/`BehaviorSubject` (carve-out [04-data-layer.md](04-data-layer.md) §8). Каждый метод обёрнут в `execute<T>()` (mixin `BaseRepositoryHelper`) — он логирует необработанные исключения через `LogRepository` и коэрсит `DioException → RepositoryException.internal`, любой другой `catch → RepositoryException.unknown`; **конкретные** доменные коды (`notFound`, и т.п.) — явным `return RepositoryResult.error(...)` в callback'е после проверки `response.statusCode` ([04-data-layer.md](04-data-layer.md) §5, §8). (Dio/transport-специфика `execute` — пример; транспорт NOX ещё не выбран, см. [04-data-layer.md](04-data-layer.md).)

`lib/data/repository/upload/upload_repository_impl.dart`:

```dart
@LazySingleton(as: UploadRepository, env: [Environment.dev, Environment.prod, Environment.test])
class UploadRepositoryImpl with BaseRepositoryHelper implements UploadRepository {
  UploadRepositoryImpl(this._api, this._mapper);

  final PostUploadFileApi _api;
  final AttachmentMapper _mapper;

  @override
  Future<RepositoryResult<AttachmentModel>> uploadFile({
    required UploadConfig config,
    void Function(double progress)? onProgress,
  }) {
    return execute<AttachmentModel>(() async {
      final response = await _api.execute(config: config, onProgress: onProgress);
      final entity = response.data;
      if (entity == null) {
        // Пустое тело при 2xx — аномалия. Сырой throw -> catch-all -> unknown.
        throw StateError('Empty upload response payload');
      }
      return RepositoryResult<AttachmentModel>.success(data: _mapper.toModel(entity: entity));
    });
  }
}
```

`lib/data/repository/chat/attachment_repository_impl.dart` (фрагмент шага 2):

```dart
@override
Future<RepositoryResult<(MessageModel, bool)>> sendAttachment({required SendAttachmentConfig config}) {
  return execute<(MessageModel, bool)>(() async {
    final (response, statusCode) = await _sendAttachmentApi.execute(config: config);
    final entity = response.data;
    if (entity == null) throw StateError('Empty send-attachment payload');
    // 201 => только что отправлено; 200 => тот же client_message_id уже существовал.
    final isCreated = statusCode == 201;
    return RepositoryResult<(MessageModel, bool)>.success(
      data: (_messageMapper.toModel(entity: entity), isCreated),
    );
  });
}
```

> **Маппинг ошибок в доменный код.** `404 not_found` (чужой/несуществующий `attachment_id`) и прочие feature-ошибки приходят как `DioException` с `response.statusCode`/телом (конкретные статусы/коды — пример-плейсхолдер; заменить на реальный контракт). Если нужен **точный** доменный код (чтобы экран показал внятную причину, а не общий «что-то пошло не так»), извлеки его в callback'е **до** того, как `DioException` уйдёт в catch-ветку: оберни `_sendAttachmentApi.execute` в локальный `try { ... } on DioException catch (e) { ... }` внутри `execute`, разбери `e.response?.statusCode` + `data.error`/`details.reason` и верни конкретный `RepositoryException.<code>` явным `return`. Точный набор feature-кодов добавляется в enum [03-domain-layer.md](03-domain-layer.md) (общий enum — `RepositoryException`, расширяется только через `BaseRepositoryException`-маркер) — **согласовать состав enum, не плодить молча**.

DI: `@lazySingleton` на API/мапперах, `@LazySingleton(as: ..., env:[dev,prod,test])` на репозиториях; единый прогон `build_runner` сгенерит `configure_dependencies.config.dart` ([02-dependency-injection.md](02-dependency-injection.md), [12-dev-commands.md](12-dev-commands.md)).

---

## 6. BLoC панели вложения (Freezed, executeLogic позиционный)

Экран ведёт пользователя по двум шагам (выбрать файл → загрузить → отправить) и держит весь конвейер в одном BLoC. State — `@freezed sealed` union; Event — `@freezed sealed` union; обёртка асинхронной логики — `BaseBloc.executeLogic` с **позиционным** первым аргументом ([05-presentation-layer.md](05-presentation-layer.md) §2). Навигация и снэкбары — через `PublishSubject`-стримы, **не** через state. Варианты состояния названы каноническими bare-именами `Initializing`/`Initialized`/`Error` (как в shipped-коде; префиксные `<Feature>Initializing` — допустимый вариант против коллизий, см. [05-presentation-layer.md](05-presentation-layer.md) §3).

### 6.1 Event

`lib/presentation/pages/upload_page/bloc/upload_event.dart`:

```dart
part of 'upload_bloc.dart';

@freezed
sealed class UploadEvent with _$UploadEvent {
  const factory UploadEvent.initialize({required String chatId}) = Initialize;

  /// Пользователь выбрал файл (document/image) — поставить в очередь + загрузить.
  const factory UploadEvent.addAttachment({required UploadConfig config}) = AddAttachment;

  /// Удалить ещё не отправленное вложение.
  const factory UploadEvent.removeAttachment({required String localId}) = RemoveAttachment;

  /// Шаг 2: отправить сообщение с вложением.
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

/// Одно вложение: статус аплоада + (после успеха) его attachment_id.
@freezed
sealed class UploadedAttachment with _$UploadedAttachment {
  const factory UploadedAttachment.uploading({required String localId, required double progress}) = AttachmentUploading;
  const factory UploadedAttachment.ready({required String localId, required AttachmentModel file}) = AttachmentReady;
  const factory UploadedAttachment.failed({required String localId, required BaseRepositoryException exception}) = AttachmentFailed;
}

extension InitializedExt on Initialized {
  List<String> get readyAttachmentIds =>
      attachments.whereType<AttachmentReady>().map((a) => a.file.attachmentId).toList();

  /// Можно отправлять: ≥1 готовое вложение и не идёт отправка.
  bool get canSend =>
      readyAttachmentIds.isNotEmpty &&
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
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/upload/attachment_model.dart';
import 'package:nox_app/domain/repository/chat/attachment_repository.dart';
import 'package:nox_app/domain/repository/chat/send_attachment_config.dart';
import 'package:nox_app/domain/repository/upload/upload_config.dart';
import 'package:nox_app/domain/repository/upload/upload_repository.dart';
import 'package:nox_app/general/text_constants.dart';
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

  final _uploadRepository = getIt<UploadRepository>();
  final _attachmentRepository = getIt<AttachmentRepository>();

  final _errorMessagesController = PublishSubject<String>();
  final _messageSentController = PublishSubject<(MessageModel, bool)>(); // (сообщение, isCreated)

  Stream<String> get errorMessages => _errorMessagesController.stream;

  Stream<(MessageModel, bool)> get messageSent => _messageSentController.stream;

  @override
  Future<void> close() async {
    await _errorMessagesController.close();
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
        final result = await _uploadRepository.uploadFile(
          config: event.config,
          onProgress: (p) => _patchProgress(emit, localId, p), // живые апдейты прогресса
        );
        result.match(
          onData: (file) => _replaceAttachment(emit, localId, UploadedAttachment.ready(localId: localId, file: file)),
          onError: (exception) {
            _replaceAttachment(emit, localId, UploadedAttachment.failed(localId: localId, exception: exception));
            _errorMessagesController.add(_translate(exception));
          },
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        _replaceAttachment(emit, localId, UploadedAttachment.failed(localId: localId, exception: _unknown()));
        _errorMessagesController.add(TextConstants.errorGeneralMessage);
      },
    );
  }

  FutureOr<void> _onSendRequested(SendRequested event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized || !state.canSend) return;
    final chatId = state.chatId;
    final attachmentId = state.readyAttachmentIds.first;
    final clientMessageId = const Uuid().v4(); // ключ дедупликации, генерируется клиентом

    emit(state.copyWith(sendInProgress: true));

    await executeLogic(
      () async {
        final result = await _attachmentRepository.sendAttachment(
          config: SendAttachmentConfig(
            chatId: chatId,
            clientMessageId: clientMessageId,
            attachmentId: attachmentId,
            text: event.text,
          ),
        );
        final updated = this.state;
        if (updated is! Initialized) return;
        result.match(
          onData: (data) {
            emit(updated.copyWith(sendInProgress: false));
            // (сообщение, isCreated): true=201 «отправлено», false=200 «уже отправлено ранее».
            _messageSentController.add(data);
          },
          onError: (exception) {
            emit(updated.copyWith(sendInProgress: false));
            _errorMessagesController.add(_translate(exception));
          },
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        final updated = this.state;
        if (updated is Initialized) emit(updated.copyWith(sendInProgress: false));
        _errorMessagesController.add(TextConstants.errorGeneralMessage);
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

  String _translate(BaseRepositoryException exception) {
    // Перевод доменного кода в строку для пользователя
    // (полная таблица — 05 §3.3). notFound -> ..., иначе общий.
    return TextConstants.errorGeneralMessage;
  }
}
```

> **`executeLogic` — позиционный первый аргумент** (`executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})`), `onError` — именованный. Это дословный канон [05-presentation-layer.md](05-presentation-layer.md) §2: репозитории уже залогировали ошибку через `LogRepository` ([04-data-layer.md](04-data-layer.md)), BLoC лишь переводит её в UX. `result.match(onData:, onError:)` — **никогда** `result.data!`.

---

## 7. Страница: прогресс, чип вложения, исход 201/200

Страница — `StatefulWidget` + `BaseStatePage<T>` ([05-presentation-layer.md](05-presentation-layer.md) §4–5): BLoC в `initState`, side-эффект-подписки в `initState` и отмена в `dispose`, тело — через `state.when(...)`. Навигируемая страница **обязана** иметь свой BLoC (правило описано в [05-presentation-layer.md](05-presentation-layer.md); номерной Инвариант 3a — в [08-conventions-and-constitution.md](08-conventions-and-constitution.md)).

`lib/presentation/pages/upload_page/upload_page.dart` (ключевые куски):

```dart
@override
void initState() {
  _bloc = UploadBloc()..add(UploadEvent.initialize(chatId: widget.chatId));
  // Снэкбары: переведённый текст, НИКОГДА сырое исключение (AlertDialogHelper, 05 §5.8).
  _errorSub = _bloc.errorMessages.listen((msg) => AlertDialogHelper.showSnackBar(context, msg));
  // Исход отправки: 201 — «отправлено» + возврат в чат;
  // 200 — «уже отправлено ранее».
  _sentSub = _bloc.messageSent.listen((data) {
    final (message, isCreated) = data;
    AlertDialogHelper.showSnackBar(
      context,
      isCreated ? TextConstants.uploadMessageSent : TextConstants.uploadMessageAlreadySent,
    );
    Navigator.of(context).pop(message);
  });
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

Чип вложения в UI (по дизайну NOX — иконка типа файла, без превью содержимого):

```dart
// внутри state.when(initialized: (s) { ... })
// Каждое вложение — чип: иконка по attachmentType (document/image) + имя файла, БЕЗ превью.
// Для AttachmentUploading — прогресс-бар по a.progress; для AttachmentFailed — иконка ошибки + retry.
// Кнопка «Отправить» активна по s.canSend; пока s.isAnyUploading — ждём аплоады.
```

> **Превью не рендерим.** По дизайну NOX вложение показывается как чип с иконкой типа файла (`document`/`image`), без рендеринга содержимого — ни эскиза изображения, ни первой страницы документа. Это сознательное правило этого блюпринта для NOX (продуктовая модель: «file content previews — type-icon chips only»). На всех пяти платформах (iOS/Android/Windows/Linux/macOS) чип выглядит и ведёт себя одинаково.

---

## 8. Удаление вложения до отправки (клиентское)

Удалить ещё **не** отправленное вложение из набора — чисто клиентская операция: событие `RemoveAttachment` убирает запись из `attachments` в state, никаких сетевых вызовов. Если аплоад файла ещё идёт (`AttachmentUploading`), отмена снимает его из списка; уже загруженный, но не отправленный `attachment_id` на сервере остаётся осиротевшим — его уборка (TTL/GC неприкреплённых вложений) — забота бэкенда NOX (пример-плейсхолдер; уточнить в реальном контракте), клиенту здесь делать нечего.

> **Инвариант.** Пока сообщение не отправлено (шаг 2), вложение существует только в клиентском state как `attachment_id`. Никакого специального серверного «отката» загрузки на клиенте не делается. В NOX нет понятий квоты/расхода/возврата — удаление до отправки бесплатно и локально.

---

## 9. Чеклист

- [ ] **Picker** — `file_picker` (document/docx/pdf, cap 50 MB) / `image_picker` (jpeg/png/webp, cap 20 MB); опциональная клиент-side валидация капов **до** аплоада ради UX (капы/расширения — пример-плейсхолдер, сверить с реальным контрактом NOX); нативные диалоги на всех пяти платформах.
- [ ] **Шаг 1 (upload)** — `PostUploadFileApi` шлёт `FormData` (`attachment_type` + `file`) через `baseClient`, `onSendProgress` → прогресс-бар; `UploadRepository.uploadFile → RepositoryResult<AttachmentModel>`; держим только `attachment_id`.
- [ ] **Шаг 2 (attach)** — `PostSendAttachmentApi` возвращает `(ResponseEntity<MessageEntity>, statusCode)`; `AttachmentRepository.sendAttachment → RepositoryResult<(MessageModel, bool isCreated)>`; `isCreated = statusCode == 201` (200 — повтор `client_message_id`, **без** повторной отправки).
- [ ] **Идемпотентность** — натуральный ключ `(chat_id, client_message_id)`; `client_message_id` генерирует клиент (`const Uuid().v4()`); клиент различает исход по `201`/`200` (или `Location`); повтор того же `client_message_id` **безопасен** (то же `MessageModel`, без дубля). Конкретная форма ключа/статусов — пример-плейсхолдер.
- [ ] **Маппер** — `AttachmentMapper extends BaseMapper<AttachmentEntity, AttachmentModel, dynamic, dynamic>` (4-арг generic из кода); вся коэрция (`.name` ↔ enum, ISO ↔ `DateTime`) — в `toModel`/`toEntity`; параметр `ad` не используется (`dynamic`).
- [ ] **Network-only** — upload/attach без Sembast-DAO и `BehaviorSubject` ([04-data-layer.md](04-data-layer.md) §8); каждый метод в `execute<T>()` (логирование через `LogRepository` + `DioException→RepositoryException.internal`/else→`RepositoryException.unknown`); конкретные коды (`notFound`/…) — явным `return RepositoryResult.error(...)` в callback'е; состав feature-enum'а **согласовать** ([03-domain-layer.md](03-domain-layer.md)).
- [ ] **BLoC** — `@freezed sealed` State/Event (bare-имена `Initializing`/`Initialized`/`Error`); `executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})` (позиционный первый арг); прогресс per-attachment в state (гранулярные ребилды); навигация/снэкбары через `PublishSubject`, не через state; `result.match`, никогда `result.data!`.
- [ ] **Страница** — `BaseStatePage<T>`, BLoC + side-эффект-подписки в `initState`/`dispose`, `state.when`; вложение — чип с иконкой типа файла, **без превью** (дизайн NOX); исход отправки — снэкбар «отправлено»/«уже отправлено ранее» + возврат в чат; снэкбары — переведённый текст, не сырое исключение.
- [ ] **Сеть/auth** — `ApiClient`/`baseClient`, signing + security-заголовки + access/refresh-токены — из [14-networking-and-auth.md](14-networking-and-auth.md), **не переизобретать**; multipart-подпись шага 1 — финализировать вместе с контрактом бэкенда NOX (см. 14 §4 FLAG).
- [ ] **Удаление до отправки** — `RemoveAttachment` чисто клиентский (убрать из state, без сети); уборка осиротевших `attachment_id` — забота бэкенда NOX (пример-плейсхолдер).
- [ ] **FLAG (бэкенд NOX не выбран):** точный контракт endpoint'ов (пути, поля, статусы, набор `error`-кодов, заголовки multipart-подписи) — **пример-плейсхолдер**; финализируется вместе с выбором бэкенда/протокола NOX; в коде — `TODO(nox-backend)`.

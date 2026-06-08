# 16 — Загрузка контента (3-step: upload → estimate → create record)

> **Назначение:** зафиксировать клиентский контракт 3-шаговой загрузки пользовательского контента в `speech_ai_mobile` — выбор файла/изображения, multipart-upload каждого источника (`POST /api/v1/records/files/upload/`), read-only пре-флайт-оценка квоты (`POST /api/v1/records/length_check/`) и идемпотентное создание записи с атомарным списанием квоты (`POST /api/v1/records/`). Контракт endpoint'ов — **cross-project-решение** (`mobile ↔ client_backend`), здесь приведена текущая форма из `docs/spec/backend_mobile_client_0.2.md`. Worked-аналог `Item` из блюпринта здесь — пара `DataFile` (один загруженный source-файл) + `Record` (созданная запись). Сетевой слой (Dio `ApiClient`, HMAC + access/refresh JWT) **не переизобретается** — берётся из [14-networking-and-auth.md](14-networking-and-auth.md).
> **Когда читать:** перед реализацией экрана загрузки контента (file/image picker → upload → estimate → create), перед поднятием `UploadRepository` / `RecordRepository` в `lib/data/`, и при добавлении нового `data_type` источника (`link`/`text`/`document`/`image`).
> **Связанные документы:** [04-data-layer.md](04-data-layer.md) (`ApiClient`, `BaseApiRepository`, `BaseRepositoryHelper.execute`, `ResponseEntity<T>`/`EntityConverter<E>`, мапперы, REST-слой, network-only POST), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, `RepositoryException`, контракты репозиториев, per-call конфиги), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, `BaseBloc.executeLogic`, side-эффект-стримы, `state.when`), [14-networking-and-auth.md](14-networking-and-auth.md) (сетевой слой, HMAC + access/refresh JWT, security-заголовки — не переизобретать), [02-dependency-injection.md](02-dependency-injection.md) (`configureDependencies`, регистрация репозиториев), [07-pagination.md](07-pagination.md) (records-list, куда уходит созданная запись), [01-stack-and-tooling.md](01-stack-and-tooling.md) (`file_picker`, `image_picker`, `dio`).

---

## 0. Идея: три последовательных шага, не один POST

Создание записи в Speech AI — это **не** одиночный multipart-POST. Это конвейер из трёх вызовов, каждый из которых — отдельный запрос со своим контрактом и своими побочными эффектами:

1. **Upload** (`POST /api/v1/records/files/upload/`) — клиент загружает **каждый** источник по отдельности (multipart) и получает на него `data_file_id`. Повторяется по числу источников (1..50).
2. **Estimate / length_check** (`POST /api/v1/records/length_check/`) — read-only пре-флайт: «сколько секунд это займёт и хватит ли квоты». **Квота НЕ списывается.** Чистая функция от `(data_file_id, language_id, текущее состояние квоты)`.
3. **Create record** (`POST /api/v1/records/`) — создание записи по набору `data_file_id`'ов с **атомарным** списанием квоты. Идемпотентно по natural-key `(owner_id, sources_signature)`: первый вызов → `201`, повтор того же набора → `200` без повторного списания.

```
[picker] выбрать link/text/document/image
   │  (каждый источник)
   ▼
1. UploadRepository.uploadFile(...)  → POST /records/files/upload/   → DataFileModel{ dataFileId, ... }
   │  (накопить массив dataFileIds: 1..50)
   ▼
2. RecordRepository.lengthCheck(...) → POST /records/length_check/   → EstimateModel{ estimatedSeconds, canProcess, quota }
   │  (read-only; квота НЕ списана; гейт UX перед create)
   ▼
3. RecordRepository.createRecord(...) → POST /records/              → (RecordModel, bool isCreated)
        201 Created + Location  → новая запись + атомарный debit квоты + broker dispatch
        200 OK (без Location)   → существующая запись (тот же набор), БЕЗ повторного списания
```

> **Единый пакет.** Все пути — `lib/...` внутри одного пакета `speech_ai_mobile` (worked example). Импорты — полные `package:speech_ai_mobile/...`, относительные `../` запрещены (кроме `part`-директив).

> **Источники — это всегда файлы.** Даже `link` и `text` загружаются как маленькие UTF-8-файлы на шаге 1 (link — однострочный файл с URL, text — UTF-8-текст). Сервер сам читает `data_type` каждого источника из `data_files_v1` — клиент **не** передаёт `data_type` в шаг 3.

---

## 1. Контракт и инварианты (что соблюдать дословно)

- **Все три шага требуют аутентификации** (`Authorization: Bearer <access_jwt>`, [14-networking-and-auth.md](14-networking-and-auth.md) §4). Refresh→rotate→retry на `401` — забота auth-слоя из доки 14, **не** этого экрана.
- **Подпись запроса (HMAC + security-заголовки) — забота interceptor'а доки 14**, не репозиториев этого документа. Сноска: шаг 1 (`upload`) — **единственный** `multipart/form-data` endpoint, и спека **не** перечисляет `x-request-signature` среди его обязательных заголовков; шаги 2 и 3 — обычный JSON-пайплайн с полным набором security-заголовков. Конкретику подписи multipart-запроса — **сверить с владельцем бэкенда** перед реализацией (см. [14-networking-and-auth.md](14-networking-and-auth.md) §4 FLAG).
- **`data_file_id` = 1:1 Appwrite Storage `fileId` = `data_files_v1.$id`.** Это единственное поле из шага 1, которое нужно держать для шагов 2/3.
- **`length_check` оценивает один файл за вызов**, `create` принимает массив. Расчёт `estimated_seconds` на шагах 2 и 3 — **один и тот же read-path** (читает сохранённое при upload `effective_content_chars`), поэтому успешный `length_check` высоко-предиктивен для `201` на create.
- **Квота списывается только на шаге 3** и только на пути `201` (первое создание набора). Шаг 2 квоту не трогает; повтор шага 3 (`200`) квоту не трогает.
- **Идемпотентность по natural-key.** `sources_signature = sha256_hex(utf8(join(sort_asc(data_file_ids), ",")))` — один и тот же **набор** файлов в любом порядке → одна и та же запись. Клиент различает исходы по HTTP-статусу (`201` vs `200`) или наличию заголовка `Location`. **`409` в v1 НЕ возвращается** — не ветвиться на него.
- **Все методы репозиториев возвращают `RepositoryResult<T>`** ([03-domain-layer.md](03-domain-layer.md)); конкретные доменные коды (`notFound` на `404`, `quotaExceeded` на `400 quota_exceeded`) возвращаются **явным** `return RepositoryResult.error(...)` в callback'е `execute`, а не из catch-веток (канон [04-data-layer.md](04-data-layer.md) §5).
- **Это network-only-фича** (one-shot POST'ы) — без Sembast-DAO и `BehaviorSubject` (carve-out [04-data-layer.md](04-data-layer.md) §8). Созданная запись затем подхватывается records-list ([07-pagination.md](07-pagination.md)).

---

## 2. Выбор источника: `file_picker` / `image_picker`

Picker'ы живут в presentation-слое (или в тонком helper'е), но **не** в репозитории — репозиторий принимает уже готовые байты/путь. Пакеты — `file_picker` (документы/произвольные файлы) и `image_picker` (камера/галерея) (см. [01-stack-and-tooling.md](01-stack-and-tooling.md)). Размер/MIME-капы проверяются сервером (шаг 1, см. §3) — клиент валидирует их же **до** аплоада ради UX (мгновенный отказ вместо round-trip).

`lib/presentation/pages/upload_page/helpers/source_picker_helper.dart`:

```dart
import 'dart:io';

import 'package:collection/collection.dart'; // singleOrNull (IterableExtension)
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_ai_mobile/domain/model/upload/data_type.dart';

/// Тонкая обёртка над picker'ами. Возвращает (файл, его data_type) или null (отмена).
class SourcePickerHelper {
  final _imagePicker = ImagePicker();

  /// Документ (pdf / docx). Cap 50 MB сверяется сервером; клиент-side — ради UX.
  Future<(File, DataType)?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
      withData: false, // читаем поток с диска, не держим в памяти
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return null;
    return (File(path), DataType.document);
  }

  /// Изображение (jpeg / png / webp). Cap 20 MB.
  Future<(File, DataType)?> pickImage({required ImageSource source}) async {
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) return null;
    return (File(picked.path), DataType.image);
  }
}
```

> `link` и `text` обычно **не** через picker, а из текстового поля экрана: клиент собирает однострочный URL (`link`) или сырой текст (`text`) в UTF-8-байты и подаёт их как «файл» (см. `UploadConfig.fromText` в §4). Сервер примет их как `text/plain`.

---

## 3. Контракт endpoint'ов (текущая форма из спеки)

### Шаг 1 — Upload (`POST /api/v1/records/files/upload/`)

`multipart/form-data`. Form-поля: `data_type` (`link`/`text`/`document`/`image`), `file` (payload). Капы (превышение → `413`, MIME-несоответствие → `415`):

| `data_type` | Cap | Допустимые MIME |
|---|---|---|
| `link` | 10 KB | `text/plain` |
| `text` | 1 MB | `text/plain`, `text/markdown` |
| `document` | 50 MB | `application/pdf`, `…wordprocessingml.document` |
| `image` | 20 MB | `image/jpeg`, `image/png`, `image/webp` |

Ответ (`200 OK`), `data`-объект:

```json
{
  "data_file_id": "file_456",
  "data_type": "text",
  "mime_type": "text/plain",
  "size_bytes": 238942,
  "checksum_md5": "a7f5f35426b927411fc9231b56382173"
}
```

Ключевое поле — **`data_file_id`**. Внутреннее `effective_content_chars` сервер вычисляет и сохраняет при upload, но **в ответ не возвращает** — его читают только шаги 2 и 3.

### Шаг 2 — Length check / estimate (`POST /api/v1/records/length_check/`)

JSON, оценивает **один** файл. Request: `{ "data_file_id": "file_456", "language_id": "en" }` (оба обязательны, непустые; `language_id` — внутренний DB id, не ISO). Ответ (`200 OK`), `data`:

```json
{
  "estimated_seconds": 110,
  "can_process": true,
  "quota": {
    "plan": "free",
    "daily_remaining_seconds": 1500,
    "daily_total_seconds": 1500,
    "daily_hard_cap_seconds": 1500,
    "max_per_request_seconds": 1500,
    "daily_reset_at_utc": "2026-05-30T00:00:00.000Z"
  },
  "reason": null
}
```

- `estimated_seconds` (int) = `max(1, ceil(effective_content_chars * 60 / 1000))`.
- `can_process` (bool) — `false`, если сработал один из трёх quota-guard'ов.
- `reason` (enum-string | null) — при `can_process: false` одно из `exceeds_max_per_request` / `exceeds_daily_remaining` / `exceeds_daily_hard_cap`.
- `shortfall_seconds` (int) — присутствует **только** при `can_process: false`; = `estimated_seconds − релевантный лимит`.
- **Квота НЕ списывается.** Несуществующий/чужой `data_file_id` → `404 not_found`.

### Шаг 3 — Create record (`POST /api/v1/records/`)

JSON. Request:

```json
{
  "title": "My sample record",
  "voice_id": "voice_001",
  "language_id": "lang_001",
  "data_file_ids": ["file_456", "file_457"]
}
```

- `title` — опционален, trimmed 1..128 (пусто → хранится `''`; авто-генерация заголовка из первой строки — **клиентский** контракт, server-side fallback не делается).
- `voice_id` / `language_id` — обязательны (внутренние DB id).
- `data_file_ids` — массив **1..50**. Нарушения состава → `400` с `details.reason`: пустой → `sources_empty`, >50 → `sources_too_many`, дубликаты → `sources_duplicate`. Отсутствующий/чужой ID → `404` с `details.missing_ids: [...]`.
- **Атомарное списание квоты** = SUM per-source `estimated_seconds` через `deductSecondsAtomic` (3-retry optimistic loop). При quota/hard-cap-сбое → `400` (`text_too_short` / `text_too_long` / `quota_exceeded`); при исчерпании ретраев → `503 conflict_retry_exhausted`.
- **Исходы по natural-key:** первый вызов нового набора → **`201 Created`** + `Location: /api/v1/records/{record_id}/` + Record-конверт (только здесь — все side-effect'ы); повтор того же набора у того же пользователя → **`200 OK`** + существующий Record-конверт, **без** `Location`, без новых side-effect'ов и **без повторного списания квоты**. `voice_id`/`language_id` повтора к существующей записи **не** применяются (другой голос для того же набора → `POST /api/v1/records/{record_id}/tracks/`).

Record-конверт (`data`, оба исхода):

```json
{
  "id": "rec_001",
  "owner_id": "usr_123",
  "title": "My sample record",
  "created_at": "2024-10-27T03:33:20.000Z",
  "updated_at": "2024-10-27T03:33:20.000Z",
  "options": { "active_track_id": null, "is_bookmarked": false, "is_share_enabled": false, "share_url": null },
  "data": {
    "sources_count": 2,
    "cover_file_id": "file_456",
    "sources": [
      { "data_file_id": "file_456", "order_index": 0, "data_type": "text" },
      { "data_file_id": "file_457", "order_index": 1, "data_type": "image" }
    ]
  },
  "tracks": [
    { "id": "track_001", "voice_id": "voice_001", "language_id": "lang_001",
      "status": "init", "error_code": null, "files": null,
      "playback": { "duration_ms": 0, "duration_progress_ms": 0 } }
  ]
}
```

Initial track создаётся со `status: "init"`, `files: null`, нулевым playback.

| Шаг | Endpoint | Квота |
|---|---|---|
| 2 estimate | `POST /api/v1/records/length_check/` | **НЕ списывается** (read-only, идемпотентен, без I/O) |
| 3 create | `POST /api/v1/records/` | **Списывается атомарно** на пути `201`; на пути `200` (повтор) — **нет** |

---

## 4. Доменный слой: модели, конфиги, контракты

Доменные модели — Freezed без `fromJson` ([03-domain-layer.md](03-domain-layer.md)); JSON живёт в entity-слое (§5). Enum `DataType` — рядом с моделью.

`lib/domain/model/upload/data_type.dart`:

```dart
/// data_type источника. Сериализуется как .name на проводе (см. mapper).
enum DataType { link, text, document, image }
```

`lib/domain/model/upload/data_file_model.dart` (результат шага 1):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/model/upload/data_type.dart';

part 'data_file_model.freezed.dart';

@freezed
abstract class DataFileModel with _$DataFileModel {
  const factory DataFileModel({
    required String dataFileId,
    required DataType dataType,
    required String mimeType,
    required int sizeBytes,
    required String checksumMd5,
  }) = _DataFileModel;
}
```

`lib/domain/model/upload/estimate_model.dart` + `quota_model.dart` (результат шага 2):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'estimate_model.freezed.dart';

@freezed
abstract class EstimateModel with _$EstimateModel {
  const factory EstimateModel({
    required int estimatedSeconds,
    required bool canProcess,
    required QuotaModel quota,
    EstimateReason? reason,
    int? shortfallSeconds, // присутствует только при canProcess == false
  }) = _EstimateModel;
}

enum EstimateReason { exceedsMaxPerRequest, exceedsDailyRemaining, exceedsDailyHardCap }
```

```dart
@freezed
abstract class QuotaModel with _$QuotaModel {
  const factory QuotaModel({
    required String plan, // 'free' | 'premium'
    required int dailyRemainingSeconds,
    required int dailyTotalSeconds,
    required int dailyHardCapSeconds,
    required int maxPerRequestSeconds,
    required DateTime dailyResetAtUtc,
  }) = _QuotaModel;
}
```

Per-call конфиги — по одному на вызов (маркер `RepositoryConfig`, [03-domain-layer.md](03-domain-layer.md)).

`lib/domain/repository/upload/upload_config.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/model/upload/data_type.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_config.dart';

part 'upload_config.freezed.dart';

@freezed
abstract class UploadConfig with _$UploadConfig implements RepositoryConfig {
  /// Файл с диска (document/image) — отдаём путь, читаем потоком.
  const factory UploadConfig.fromPath({
    required DataType dataType,
    required String path,
    required String fileName,
  }) = _UploadConfigFromPath;

  /// link/text — синтетический файл из байтов (UTF-8).
  const factory UploadConfig.fromBytes({
    required DataType dataType,
    required Uint8List bytes,
    required String fileName,
  }) = _UploadConfigFromBytes;

  /// Удобный конструктор для link/text из строки.
  factory UploadConfig.fromText({
    required DataType dataType,
    required String content,
    required String fileName,
  }) =>
      UploadConfig.fromBytes(dataType: dataType, bytes: Uint8List.fromList(utf8.encode(content)), fileName: fileName);
}
```

`lib/domain/repository/record/length_check_config.dart` и `create_record_config.dart`:

```dart
@freezed
abstract class LengthCheckConfig with _$LengthCheckConfig implements RepositoryConfig {
  const factory LengthCheckConfig({
    required String dataFileId,
    required String languageId,
  }) = _LengthCheckConfig;
}
```

```dart
@freezed
abstract class CreateRecordConfig with _$CreateRecordConfig implements RepositoryConfig {
  const factory CreateRecordConfig({
    required String voiceId,
    required String languageId,
    required List<String> dataFileIds, // 1..50, без дублей
    @Default('') String title,
  }) = _CreateRecordConfig;
}
```

Контракты репозиториев (реализуются в `lib/data/`):

`lib/domain/repository/upload/upload_repository.dart`:

```dart
import 'package:speech_ai_mobile/domain/model/upload/data_file_model.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';
import 'package:speech_ai_mobile/domain/repository/upload/upload_config.dart';

abstract class UploadRepository {
  /// Шаг 1: загрузить ОДИН источник. onProgress — для прогресс-бара (0.0..1.0).
  Future<RepositoryResult<DataFileModel>> uploadFile({
    required UploadConfig config,
    void Function(double progress)? onProgress,
  });
}
```

`lib/domain/repository/record/record_repository.dart`:

```dart
abstract class RecordRepository {
  /// Шаг 2: read-only оценка одного файла (квота НЕ списывается).
  Future<RepositoryResult<EstimateModel>> lengthCheck({required LengthCheckConfig config});

  /// Шаг 3: создать запись (атомарный debit на пути 201).
  /// Возвращает (запись, isCreated): isCreated=true для 201, false для 200 (повтор набора).
  Future<RepositoryResult<(RecordModel, bool)>> createRecord({required CreateRecordConfig config});
}
```

> **Зачем `(RecordModel, bool)` на create.** Сервер различает «создано» (`201`) и «уже было» (`200`) **только** статусом/`Location`. Репозиторий обязан вернуть это различие наверх (record-кортеж `(RecordModel, bool isCreated)`), а **не** прятать его — UX «запись создана» vs «открыта существующая» зависит от исхода (§7).

> **`RecordModel` / `RecordEntity` — конкретный аналог worked-example `Item`** для records-фичи (модель `lib/domain/model/record/record_model.dart`, entity `lib/data/entity/record/record_entity.dart`), а **не** типы из [07-pagination.md](07-pagination.md) (там список построен на абстрактном `ItemModel`). Ссылки на `07` — про **механику** records-list (offset-пагинация, куда уходит созданная запись), а не про определение `RecordModel`; сами типы вводятся фичей records (форма entity зеркалит конверт записи из §3 — `id`/`owner_id`/`title`/`created_at`/`updated_at`/`sources`/`tracks`).

---

## 5. Слой данных: entities, мапперы, REST, репозитории

### 5.1 Entities + `ResponseEntity<T>`

Entities — `@freezed` + `json_serializable`, только базовые типы; enum как `.name`, `DateTime` как ISO-8601 String ([04-data-layer.md](04-data-layer.md) §1). Каждый entity, ходящий через `ResponseEntity<T>`, регистрируется в **обеих** цепочках `EntityConverter` ([04-data-layer.md](04-data-layer.md) §3).

`lib/data/entity/upload/data_file_entity.dart`:

```dart
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'data_file_entity.freezed.dart';
part 'data_file_entity.g.dart';

@freezed
abstract class DataFileEntity with _$DataFileEntity {
  const factory DataFileEntity({
    @JsonKey(name: 'data_file_id') required String dataFileId,
    @JsonKey(name: 'data_type') required String dataType,
    @JsonKey(name: 'mime_type') required String mimeType,
    @JsonKey(name: 'size_bytes') required int sizeBytes,
    @JsonKey(name: 'checksum_md5') required String checksumMd5,
  }) = _DataFileEntity;

  factory DataFileEntity.fromJson(Map<String, dynamic> json) => _$DataFileEntityFromJson(json);
}
```

`EstimateEntity` / `QuotaEntity` / `RecordEntity` строятся так же (snake_case `@JsonKey`, `daily_reset_at_utc` / `created_at` — String, маппятся в `DateTime` в маппере). `RecordEntity` зеркалит §3-конверт (`options`/`data`/`tracks` — вложенные entity).

### 5.2 Мапперы (вся коэрция здесь)

`lib/data/mapper/upload/data_file_mapper.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:speech_ai_mobile/data/entity/upload/data_file_entity.dart';
import 'package:speech_ai_mobile/data/mapper/base_mapper.dart';
import 'package:speech_ai_mobile/domain/model/upload/data_file_model.dart';
import 'package:speech_ai_mobile/domain/model/upload/data_type.dart';

@lazySingleton
class DataFileMapper extends BaseMapper<DataFileEntity, DataFileModel> {
  @override
  DataFileModel toModel({required DataFileEntity entity}) => DataFileModel(
        dataFileId: entity.dataFileId,
        dataType: DataType.values.byName(entity.dataType),
        mimeType: entity.mimeType,
        sizeBytes: entity.sizeBytes,
        checksumMd5: entity.checksumMd5,
      );

  @override
  DataFileEntity toEntity({required DataFileModel model}) => DataFileEntity(
        dataFileId: model.dataFileId,
        dataType: model.dataType.name,
        mimeType: model.mimeType,
        sizeBytes: model.sizeBytes,
        checksumMd5: model.checksumMd5,
      );
}
```

`EstimateMapper` коэрсит `reason`-строку (snake_case → `EstimateReason`), `daily_reset_at_utc` (ISO-8601 String → `DateTime.parse(...).toUtc()`).

### 5.3 REST-слой: multipart upload (шаг 1)

Upload — **единственный** multipart API. API-класс расширяет `BaseApiRepository` ([04-data-layer.md](04-data-layer.md) §7б) и шлёт `FormData` через `baseClient`. `onSendProgress` Dio пробрасывается наверх для прогресс-бара. На non-2xx Dio бросает `DioException` — его **не** ловят на уровне API (канон [04-data-layer.md](04-data-layer.md) §7г).

`lib/data/remote/api/upload/post_upload_file_api.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:speech_ai_mobile/data/entity/base/response_entity.dart';
import 'package:speech_ai_mobile/data/entity/upload/data_file_entity.dart';
import 'package:speech_ai_mobile/data/remote/api/base/base_api_repository.dart';
import 'package:speech_ai_mobile/domain/repository/upload/upload_config.dart';

@lazySingleton
class PostUploadFileApi extends BaseApiRepository {
  Future<ResponseEntity<DataFileEntity>> execute({
    required UploadConfig config,
    void Function(double progress)? onProgress,
  }) async {
    final MultipartFile filePart = await config.map(
      fromPath: (c) => MultipartFile.fromFile(c.path, filename: c.fileName),
      fromBytes: (c) async => MultipartFile.fromBytes(c.bytes, filename: c.fileName),
    );
    final dataType = config.map(fromPath: (c) => c.dataType, fromBytes: (c) => c.dataType);

    final formData = FormData.fromMap({
      'data_type': dataType.name, // 'link' | 'text' | 'document' | 'image'
      'file': filePart,
    });

    final response = await baseClient.post(
      'v1/records/files/upload/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) onProgress(sent / total);
      },
    );
    return ResponseEntity<DataFileEntity>.fromJson(response.data);
  }
}
```

### 5.4 REST-слой: length_check + create (шаги 2/3, JSON)

JSON-API-классы — каноническая форма ([04-data-layer.md](04-data-layer.md) §7г): build path → POST через `baseClient` → `ResponseEntity<T>.fromJson`. На create **status-line и `Location` нужны выше** (различить `201`/`200`) — поэтому API возвращает не голый entity, а пару `(ResponseEntity<RecordEntity>, int statusCode)`.

`lib/data/remote/api/record/post_length_check_api.dart`:

```dart
@lazySingleton
class PostLengthCheckApi extends BaseApiRepository {
  Future<ResponseEntity<EstimateEntity>> execute({required LengthCheckConfig config}) async {
    final response = await baseClient.post(
      'v1/records/length_check/',
      data: {'data_file_id': config.dataFileId, 'language_id': config.languageId},
    );
    return ResponseEntity<EstimateEntity>.fromJson(response.data);
  }
}
```

`lib/data/remote/api/record/post_create_record_api.dart`:

```dart
@lazySingleton
class PostCreateRecordApi extends BaseApiRepository {
  Future<(ResponseEntity<RecordEntity>, int)> execute({required CreateRecordConfig config}) async {
    final response = await baseClient.post(
      'v1/records/',
      data: {
        'title': config.title,
        'voice_id': config.voiceId,
        'language_id': config.languageId,
        'data_file_ids': config.dataFileIds,
      },
    );
    final entity = ResponseEntity<RecordEntity>.fromJson(response.data);
    return (entity, response.statusCode ?? 0); // 201 vs 200 — load-bearing
  }
}
```

### 5.5 Репозитории (network-only)

Network-only POST'ы: **без** DAO/`BehaviorSubject` (carve-out [04-data-layer.md](04-data-layer.md) §8). Каждый метод обёрнут в `execute<T>()` — он логирует необработанные исключения и коэрсит `DioException → internal`, любой другой `catch → unknown`; **конкретные** доменные коды (`notFound`, `quotaExceeded`) — явным `return RepositoryResult.error(...)` в callback'е после проверки `response.statusCode` ([04-data-layer.md](04-data-layer.md) §5, §8).

`lib/data/repository/upload/upload_repository_impl.dart`:

```dart
@LazySingleton(as: UploadRepository, env: [Environment.dev, Environment.prod, Environment.test])
class UploadRepositoryImpl with BaseRepositoryHelper implements UploadRepository {
  UploadRepositoryImpl(this._api, this._mapper);

  final PostUploadFileApi _api;
  final DataFileMapper _mapper;

  @override
  Future<RepositoryResult<DataFileModel>> uploadFile({
    required UploadConfig config,
    void Function(double progress)? onProgress,
  }) {
    return execute<DataFileModel>(() async {
      final response = await _api.execute(config: config, onProgress: onProgress);
      final entity = response.data;
      if (entity == null) {
        // Пустое тело при 2xx — аномалия. Сырой throw -> catch-all -> unknown.
        throw StateError('Empty upload response payload');
      }
      return RepositoryResult<DataFileModel>.success(data: _mapper.toModel(entity: entity));
    });
  }
}
```

`lib/data/repository/record/record_repository_impl.dart` (фрагменты шагов 2/3):

```dart
@override
Future<RepositoryResult<EstimateModel>> lengthCheck({required LengthCheckConfig config}) {
  return execute<EstimateModel>(() async {
    final response = await _lengthCheckApi.execute(config: config);
    final entity = response.data;
    if (entity == null) throw StateError('Empty length_check payload');
    return RepositoryResult<EstimateModel>.success(data: _estimateMapper.toModel(entity: entity));
  });
}

@override
Future<RepositoryResult<(RecordModel, bool)>> createRecord({required CreateRecordConfig config}) {
  return execute<(RecordModel, bool)>(() async {
    final (response, statusCode) = await _createRecordApi.execute(config: config);
    final entity = response.data;
    if (entity == null) throw StateError('Empty create-record payload');
    // 201 => только что создано (квота списана); 200 => тот же набор уже существовал.
    final isCreated = statusCode == 201;
    return RepositoryResult<(RecordModel, bool)>.success(
      data: (_recordMapper.toModel(entity: entity), isCreated),
    );
  });
}
```

> **Маппинг квота-/состав-ошибок в доменный код.** `400 quota_exceeded` / `text_too_long` / `text_too_short`, `404 not_found` (чужой/несуществующий `data_file_id`), `503 conflict_retry_exhausted` приходят как `DioException` с `response.statusCode`/телом. Если нужен **точный** доменный код (чтобы экран показал «не хватает квоты», а не общий «что-то пошло не так»), извлеки его в callback'е **до** того, как `DioException` уйдёт в catch-ветку: оберни `_createRecordApi.execute` в локальный `try { ... } on DioException catch (e) { ... }` внутри `execute`, разбери `e.response?.statusCode` + `data.error`/`details.reason` и верни конкретный `RepositoryException.<code>` явным `return`. Точный набор feature-кодов (`quotaExceeded`/`textTooLong`/`sourcesTooMany`/…) добавляется в enum [03-domain-layer.md](03-domain-layer.md) — **согласовать состав enum, не плодить молча**.

DI: `@lazySingleton` на API/мапперах, `@LazySingleton(as: ..., env:[dev,prod,test])` на репозиториях — `./script_auto_generate.sh` сгенерит `configure_dependencies.config.dart` ([02-dependency-injection.md](02-dependency-injection.md), [12-dev-commands.md](12-dev-commands.md)).

---

## 6. BLoC экрана загрузки (Freezed, executeLogic позиционный)

Экран ведёт пользователя по трём шагам и держит весь конвейер в одном BLoC. State — `@freezed sealed` union; Event — `@freezed sealed` union; обёртка асинхронной логики — `BaseBloc.executeLogic` с **позиционным** первым аргументом ([05-presentation-layer.md](05-presentation-layer.md) §2). Навигация и снэкбары — через `PublishSubject`-стримы, **не** через state.

### 6.1 Event

`lib/presentation/pages/upload_page/bloc/upload_event.dart`:

```dart
part of 'upload_bloc.dart';

@freezed
sealed class UploadEvent with _$UploadEvent {
  const factory UploadEvent.initialize() = Initialize;

  /// Пользователь выбрал источник (document/image/link/text) — поставить в очередь + загрузить.
  const factory UploadEvent.addSource({required UploadConfig config}) = AddSource;

  /// Удалить ещё не подтверждённый источник из набора.
  const factory UploadEvent.removeSource({required String dataFileId}) = RemoveSource;

  /// Выбор голоса/языка для будущего трека.
  const factory UploadEvent.selectVoiceLanguage({required String voiceId, required String languageId}) = SelectVoiceLanguage;

  /// Шаг 2: пересчитать оценку по текущему набору + языку.
  const factory UploadEvent.estimateRequested() = EstimateRequested;

  /// Шаг 3: создать запись.
  const factory UploadEvent.createRequested({@Default('') String title}) = CreateRequested;
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
    @Default(<UploadedSource>[]) List<UploadedSource> sources, // загруженные/в процессе
    String? voiceId,
    String? languageId,
    EstimateModel? estimate, // результат шага 2 (null до estimate)
    @Default(false) bool estimateInProgress,
    @Default(false) bool createInProgress,
  }) = Initialized;

  const factory UploadState.error({BaseRepositoryException? exception}) = Error;
}

/// Один источник в наборе: статус аплоада + (после успеха) его data_file_id.
@freezed
sealed class UploadedSource with _$UploadedSource {
  const factory UploadedSource.uploading({required String localId, required double progress}) = SourceUploading;
  const factory UploadedSource.ready({required String localId, required DataFileModel file}) = SourceReady;
  const factory UploadedSource.failed({required String localId, required BaseRepositoryException exception}) = SourceFailed;
}

extension InitializedExt on Initialized {
  List<String> get readyFileIds =>
      sources.whereType<SourceReady>().map((s) => s.file.dataFileId).toList();

  /// Можно создавать: ≥1 готовый источник, выбраны голос+язык, не идёт create,
  /// и (если оценка уже есть) она пропускает квоту.
  bool get canCreate =>
      readyFileIds.isNotEmpty &&
      voiceId != null &&
      languageId != null &&
      !createInProgress &&
      (estimate?.canProcess ?? true);

  bool get isAnyUploading => sources.any((s) => s is SourceUploading);
}
```

> **Прогресс аплоада — в state, гранулярно.** Каждый источник несёт свой `progress` (`SourceUploading.progress` 0.0..1.0). Глубокое value-equality Freezed ([05-presentation-layer.md](05-presentation-layer.md) §3.2) даёт точечные ребилды прогресс-бара без перерисовки всего экрана.

### 6.3 BLoC — handlers

`lib/presentation/pages/upload_page/bloc/upload_bloc.dart`:

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:speech_ai_mobile/di/configure_dependencies.dart';
import 'package:speech_ai_mobile/domain/exception/base_repository_exception.dart';
import 'package:speech_ai_mobile/domain/model/record/record_model.dart';
import 'package:speech_ai_mobile/domain/model/upload/data_file_model.dart';
import 'package:speech_ai_mobile/domain/model/upload/estimate_model.dart';
import 'package:speech_ai_mobile/domain/repository/record/create_record_config.dart';
import 'package:speech_ai_mobile/domain/repository/record/length_check_config.dart';
import 'package:speech_ai_mobile/domain/repository/record/record_repository.dart';
import 'package:speech_ai_mobile/domain/repository/upload/upload_config.dart';
import 'package:speech_ai_mobile/domain/repository/upload/upload_repository.dart';
import 'package:speech_ai_mobile/general/text_constants.dart';
import 'package:speech_ai_mobile/presentation/base/base_bloc.dart';

part 'upload_event.dart';
part 'upload_state.dart';
part 'upload_bloc.freezed.dart';

class UploadBloc extends BaseBloc<UploadEvent, UploadState> {
  UploadBloc() : super(const UploadState.initializing()) {
    on<Initialize>(_onInitialize);
    on<AddSource>(_onAddSource);
    on<RemoveSource>(_onRemoveSource);
    on<SelectVoiceLanguage>(_onSelectVoiceLanguage);
    on<EstimateRequested>(_onEstimateRequested);
    on<CreateRequested>(_onCreateRequested);
  }

  final _uploadRepository = getIt<UploadRepository>();
  final _recordRepository = getIt<RecordRepository>();

  final _errorMessagesController = PublishSubject<String>();
  final _recordCreatedController = PublishSubject<(RecordModel, bool)>(); // (запись, isCreated)

  Stream<String> get errorMessages => _errorMessagesController.stream;

  Stream<(RecordModel, bool)> get recordCreated => _recordCreatedController.stream;

  @override
  Future<void> close() async {
    await _errorMessagesController.close();
    await _recordCreatedController.close();
    await super.close();
  }

  void _onInitialize(Initialize event, Emitter<UploadState> emit) {
    emit(const UploadState.initialized());
  }

  FutureOr<void> _onAddSource(AddSource event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized) return;
    if (state.readyFileIds.length >= 50) {
      _errorMessagesController.add(TextConstants.uploadTooManySources);
      return;
    }

    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    emit(state.copyWith(
      sources: [...state.sources, UploadedSource.uploading(localId: localId, progress: 0)],
    ));

    await executeLogic(
      () async {
        final result = await _uploadRepository.uploadFile(
          config: event.config,
          onProgress: (p) => _patchProgress(localId, p), // живые апдейты прогресса
        );
        result.match(
          onData: (file) => _replaceSource(localId, UploadedSource.ready(localId: localId, file: file)),
          onError: (exception) {
            _replaceSource(localId, UploadedSource.failed(localId: localId, exception: exception));
            _errorMessagesController.add(_translate(exception));
          },
        );
        // Новый источник делает прежнюю оценку устаревшей.
        _invalidateEstimate();
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        _replaceSource(localId, UploadedSource.failed(localId: localId, exception: _unknown()));
        _errorMessagesController.add(TextConstants.errorGeneralMessage);
      },
    );
  }

  FutureOr<void> _onEstimateRequested(EstimateRequested event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized) return;
    final fileIds = state.readyFileIds;
    final languageId = state.languageId;
    if (fileIds.isEmpty || languageId == null || state.estimateInProgress) return;

    emit(state.copyWith(estimateInProgress: true));

    await executeLogic(
      () async {
        // length_check оценивает ОДИН файл; для UX-гейта берём первый/репрезентативный
        // источник (полная сумма по набору считается атомарно на create, шаг 3).
        final result = await _recordRepository.lengthCheck(
          config: LengthCheckConfig(dataFileId: fileIds.first, languageId: languageId),
        );
        final updated = this.state;
        if (updated is! Initialized) return;
        result.match(
          onData: (estimate) => emit(updated.copyWith(estimate: estimate, estimateInProgress: false)),
          onError: (exception) {
            emit(updated.copyWith(estimateInProgress: false));
            _errorMessagesController.add(_translate(exception));
          },
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        final updated = this.state;
        if (updated is Initialized) emit(updated.copyWith(estimateInProgress: false));
        _errorMessagesController.add(TextConstants.errorGeneralMessage);
      },
    );
  }

  FutureOr<void> _onCreateRequested(CreateRequested event, Emitter<UploadState> emit) async {
    final state = this.state;
    if (state is! Initialized || !state.canCreate) return;
    final voiceId = state.voiceId!;
    final languageId = state.languageId!;
    final fileIds = state.readyFileIds;

    emit(state.copyWith(createInProgress: true));

    await executeLogic(
      () async {
        final result = await _recordRepository.createRecord(
          config: CreateRecordConfig(
            voiceId: voiceId,
            languageId: languageId,
            dataFileIds: fileIds,
            title: event.title,
          ),
        );
        final updated = this.state;
        if (updated is! Initialized) return;
        result.match(
          onData: (data) {
            emit(updated.copyWith(createInProgress: false));
            // (запись, isCreated): true=201 «создана», false=200 «уже существовала».
            _recordCreatedController.add(data);
          },
          onError: (exception) {
            emit(updated.copyWith(createInProgress: false));
            _errorMessagesController.add(_translate(exception));
          },
        );
      },
      onError: (String? error, dynamic exception, StackTrace stackTrace) {
        final updated = this.state;
        if (updated is Initialized) emit(updated.copyWith(createInProgress: false));
        _errorMessagesController.add(TextConstants.errorGeneralMessage);
      },
    );
  }

  // --- helpers (мутация source-списка / инвалидация оценки) ---

  void _patchProgress(String localId, double progress) {
    final state = this.state;
    if (state is! Initialized) return;
    _replaceSource(localId, UploadedSource.uploading(localId: localId, progress: progress));
  }

  void _replaceSource(String localId, UploadedSource next) {
    final state = this.state;
    if (state is! Initialized) return;
    emit(state.copyWith(
      sources: [for (final s in state.sources) if (_localIdOf(s) == localId) next else s],
    ));
  }

  void _invalidateEstimate() {
    final state = this.state;
    if (state is Initialized && state.estimate != null) emit(state.copyWith(estimate: null));
  }

  String _translate(BaseRepositoryException exception) {
    // Перевод доменного кода в строку для пользователя (полная таблица — 05 §3.3).
    // quotaExceeded -> TextConstants.uploadQuotaExceeded, notFound -> ..., иначе общий.
    return TextConstants.errorGeneralMessage;
  }
}
```

> **`executeLogic` — позиционный первый аргумент** (`executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})`), `onError` — именованный. Это дословный канон [05-presentation-layer.md](05-presentation-layer.md) §2: репозитории уже залогировали ошибку через `LogRepository` ([04-data-layer.md](04-data-layer.md)), BLoC лишь переводит её в UX. `result.match(onData:, onError:)` — **никогда** `result.data!`.

---

## 7. Страница: прогресс, гейт по квоте, исход 201/200

Страница — `StatefulWidget` + `BaseStatePage<T>` ([05-presentation-layer.md](05-presentation-layer.md) §4–5): BLoC в `initState`, side-эффект-подписки в `initState` и отмена в `dispose`, тело — через `state.when(...)`.

`lib/presentation/pages/upload_page/upload_page.dart` (ключевые куски):

```dart
@override
void initState() {
  _bloc = UploadBloc()..add(const UploadEvent.initialize());
  // Снэкбары: переведённый текст, НИКОГДА сырое исключение (AlertDialogHelper, 05 §5.8).
  _errorSub = _bloc.errorMessages.listen((msg) => AlertDialogHelper.showSnackBar(context, msg));
  // Исход создания: 201 — «запись создана» + переход в плеер; 200 — «открыта существующая».
  _createdSub = _bloc.recordCreated.listen((data) {
    final (record, isCreated) = data;
    AlertDialogHelper.showSnackBar(
      context,
      isCreated ? TextConstants.uploadRecordCreated : TextConstants.uploadRecordExisting,
    );
    Navigator.of(context).pushReplacement(RecordPlayerPage.route(recordId: record.id));
  });
  super.initState();
}

@override
void dispose() {
  _errorSub.cancel();
  _createdSub.cancel();
  _bloc.close();
  super.dispose();
}
```

Гейт по квоте в UI (только то, что отдал `length_check`):

```dart
// внутри state.when(initialized: (s) { ... })
if (s.estimate != null && !s.estimate!.canProcess) {
  // Показать причину: reason + shortfall_seconds («не хватает N сек до дневного лимита»),
  // кнопку «Создать» дизейблим (s.canCreate == false), CTA — апгрейд для plan == 'free'.
}
// Кнопка «Создать запись» активна по s.canCreate; пока s.isAnyUploading — ждём аплоады.
```

> **Квота-гейт — UX, не контроль.** `length_check.can_process` — подсказка перед `create`. Финальное решение — за сервером на шаге 3: даже при `can_process: true` create может вернуть `400 quota_exceeded` (квота изменилась между шагами) — обработать в `_onCreateRequested` через тот же `_translate`. Не доверять клиентской оценке как авторизации.

---

## 8. Refund-on-delete (упоминание; реализация — в доке про records)

Удаление трека/записи **не** в статусе `ready` (то есть `init`/`processing`/`error`) возвращает списанную квоту: `DELETE /api/v1/records/{id}/tracks/{tid}/` и каскад `DELETE /api/v1/records/{id}/` на сервере вызывают `refundSecondsAtomic` **после** удаления строки трека. Refund — **серверный** и failure-tolerant (никогда не валит delete). Клиенту в этом документе делать нечего: на стороне приложения это обычный `DELETE`-вызов соответствующего `RecordRepository`-метода (контракт — в доке про records / [07-pagination.md](07-pagination.md)), без специальной refund-логики на клиенте.

> **Инвариант квоты.** Сумма списания, вычисленная при `create` (шаг 3) через серверный estimator, — **окончательная**. Фактическая длительность аудио от worker'а на квоту **не** влияет. Возврат — только при пользовательском delete не-`ready` трека. Клиент не пересчитывает и не «доначисляет» квоту сам.

---

## 9. Чеклист

- [ ] **Picker** — `file_picker` (document/docx/pdf, cap 50 MB) / `image_picker` (jpeg/png/webp, cap 20 MB); `link`/`text` — из текстового поля в UTF-8-байты (`UploadConfig.fromText`); клиент-side валидация капов **до** аплоада ради UX.
- [ ] **Шаг 1 (upload)** — `PostUploadFileApi` шлёт `FormData` (`data_type` + `file`) через `baseClient`, `onSendProgress` → прогресс-бар; повтор по каждому источнику (1..50); `UploadRepository.uploadFile → RepositoryResult<DataFileModel>`; держим только `data_file_id`.
- [ ] **Шаг 2 (length_check)** — `PostLengthCheckApi` (JSON, один файл); `RecordRepository.lengthCheck → RepositoryResult<EstimateModel>`; **квота НЕ списывается**; результат — гейт UX (`can_process`/`reason`/`shortfall_seconds`), не авторизация.
- [ ] **Шаг 3 (create)** — `PostCreateRecordApi` возвращает `(ResponseEntity<RecordEntity>, statusCode)`; `RecordRepository.createRecord → RepositoryResult<(RecordModel, bool isCreated)>`; `isCreated = statusCode == 201` (201 списал квоту, 200 — повтор набора, **без** списания); **не** ветвиться на `409` (в v1 нет).
- [ ] **Идемпотентность** — натуральный ключ `(owner_id, sources_signature)` считает сервер; клиент различает исход по `201`/`200` (или `Location`); повтор того же набора **безопасен** (то же `RecordModel`, без двойного debit).
- [ ] **Network-only** — upload/length_check/create без Sembast-DAO и `BehaviorSubject` ([04-data-layer.md](04-data-layer.md) §8); каждый метод в `execute<T>()` (логирование + `DioException→internal`/else→`unknown`); конкретные коды (`quotaExceeded`/`notFound`/…) — явным `return RepositoryResult.error(...)` в callback'е; состав feature-enum'а **согласовать** ([03-domain-layer.md](03-domain-layer.md)).
- [ ] **BLoC** — `@freezed sealed` State/Event; `executeLogic(() async {...}, onError: (String? error, dynamic exception, StackTrace stackTrace) {...})` (позиционный первый арг); прогресс per-source в state (гранулярные ребилды); навигация/снэкбары через `PublishSubject`, не через state; `result.match`, никогда `result.data!`.
- [ ] **Страница** — `BaseStatePage<T>`, BLoC + side-эффект-подписки в `initState`/`dispose`, `state.when`; квота-гейт по `estimate.canProcess`; исход создания — снэкбар «создана»/«уже существовала» + переход в плеер; снэкбары — переведённый текст, не сырое исключение.
- [ ] **Сеть/auth** — `ApiClient`/`baseClient`, HMAC + security-заголовки + access/refresh JWT — из [14-networking-and-auth.md](14-networking-and-auth.md), **не переизобретать**; multipart-подпись шага 1 — **сверить с владельцем бэкенда**.
- [ ] **Refund-on-delete** — серверный, failure-tolerant; клиент делает обычный `DELETE`, без refund-логики; create-time debit — окончательный, длительность аудио от worker'а на квоту не влияет.
- [ ] **FLAG (cross-project):** точный контракт endpoint'ов (поля, статусы, набор `reason`/`error`-кодов, заголовки multipart-подписи) — источник правды `docs/spec/backend_mobile_client_0.2.md` + владелец бэкенда; перед реализацией сверить, в коде — `TODO(cross-project)`.

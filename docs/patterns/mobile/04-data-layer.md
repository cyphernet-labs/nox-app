# 04 — Слой данных

> **Назначение:** дать копипаст-готовые шаблоны слоя данных (`lib/data/`) — сущности (entities), генерик-конверт `ResponseEntity<T>` + ручной реестр `EntityConverter<E>`, мапперы, типизированные исключения, реактивные Sembast-DAO, REST-слой (Dio `ApiClient` + `RequestBuilder`/`RequestBuilderHelper` + API-классы) и реализации репозиториев. Слой данных **реализует** контракты из `03-domain-layer.md`.
> **Когда читать:** когда поднимаешь папку `lib/data/` или подключаешь конкретный `ItemRepositoryImpl` к его DAO + мапперу + REST-клиенту. Это авторитетный дом всех шаблонов слоя данных.
> **Связанные документы:** `03-domain-layer.md` (контракты, которые здесь реализуются), `05-presentation-layer.md` (потребляет репозитории), `02-dependency-injection.md` (`AppDatabase`, env-scoped провайдеры, `getIt`), `06-theming.md`, `07-pagination.md` (network-only пагинация), `08-conventions-and-constitution.md` (правила именования и инвариантов), `10-code-templates.md` (индекс шаблонов), `12-dev-commands.md` (build_runner).

---

## Обзор и зона ответственности

Слой данных отвечает за:

- **Entities (DTO)** — `@freezed` + `json_serializable`, **только базовые типы** (`String`/`int`/`double`/`bool` + их `List`). Enum хранится как `.name` (String), `DateTime` — как ISO-8601 String. Любая коэрция отложена в маппер.
- **`ResponseEntity<T>` + `EntityConverter<E>`** — генерик-конверт REST-ответа (бэкенд отдаёт единый envelope `{data, timestamp, trace_id, meta}` — *пример контракта, заменить на реальный backend NOX*) + ручной реестр типов, резолвящий генерик `T` в конкретный entity.
- **Мапперы** — двунаправленная конвертация `Entity <-> Model` (`BaseMapper`), где происходит ВСЯ коэрция типов (enum, `DateTime`, nullable-нормализация). Композиция дочерних мапперов через конструктор.
- **Обработка ошибок** — единственный механизм `BaseRepositoryHelper.execute<TD>()`: тонкий guarded try/catch, который **обязательно** логирует через `LogRepository` и возвращает `RepositoryResult.error(...)`. Маппинг коэрсный: `DioException` → `RepositoryException.internal`, любой другой `catch` → `RepositoryException.unknown`. Никакой типизированной иерархии (`ApiException` / `DaoException` / `BaseDomainExceptionHelper` отсутствуют — таково правило этого блюпринта). Конкретный доменный код возвращает сам callback явным `return RepositoryResult.error(...)`.
- **DAO (Sembast)** — реактивное локальное хранилище: `onSnapshots()`/`onSnapshot()`, атомарные `db.transaction()`, env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory).
- **Репозитории** — реализуют контракты домена; кэш-first реактивная форма (подписка на DAO-поток + один `BehaviorSubject<RepositoryResult<...>>`). **Явный carve-out:** пагинированные серверные списки и one-shot POST — **network-only** (без DAO и subject), см. `07-pagination.md`.

Направление зависимостей: `data` **реализует** контракты `domain`. `domain` не импортирует `data`. Конвертация между базово-типизированными entities и богатыми доменными моделями живёт исключительно в мапперах.

> **Единый пакет.** Все пути — `lib/data/...` внутри одного пакета `nox_app`. Никаких `data/lib/src/...` или path-зависимостей: слои — это папки одного `lib/`. Импорты — полные `package:nox_app/...`, без относительных `../`, кроме директив `part`.

### Раскладка папок слоя данных

```
lib/data/
  entity/
    base/response_entity.dart
    base/entity_converter.dart
    item/item_entity.dart
    item/items_entity.dart
  mapper/
    base_mapper.dart
    item/item_mapper.dart
  exception/
    base_repository_helper.dart
  local/
    app_database.dart            # см. 02-dependency-injection.md (env-scoped провайдеры)
    item/item_dao.dart
  remote/
    api/base/api_client.dart
    api/base/base_api_repository.dart
    api/item/get_items_api.dart
    request_builder/base/request_builder.dart
    request_builder/base/request_builder_helper.dart
    request_builder/item/get_items_api_request_builder.dart
  repository/
    item/item_repository_impl.dart
```

> `path_provider` — обязательная зависимость `pubspec.yaml`: файловый бэкенд Sembast (`databaseFactoryIo`) резолвит путь к базе через `getApplicationDocumentsDirectory()`.

---

## 1. Сущности (entities / DTO)

Entities — `@freezed` **и** `json_serializable`: имеют обе `part`-директивы (`.freezed.dart` и `.g.dart`) и фабрику `fromJson`. Поля используют **только базовые типы**: `String`, `int`, `double`, `bool` и их `List`. Никаких enum-как-enum, никаких `DateTime`, никакого `BigInt`. `status`-enum хранится как его `name` (String); `created_at` — как ISO-8601 String. Nullable там, где API отдаёт nullable. **Вся** коэрция выполняется в маппере (§2).

`lib/data/entity/item/item_entity.dart`:

```dart
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'item_entity.freezed.dart';
part 'item_entity.g.dart';

@freezed
abstract class ItemEntity with _$ItemEntity {
  const factory ItemEntity({
    required String id,
    required String name,
    String? description,
    required String status, // ItemStatus enum name
    required String createdAt, // ISO-8601 string
    @Default(<String>[]) List<String> tags,
  }) = _ItemEntity;

  factory ItemEntity.fromJson(Map<String, dynamic> json) => _$ItemEntityFromJson(json);
}
```

### Entity-обёртка для списочного DAO

Когда DAO хранит коллекцию как одну запись (single-record store), добавь entity-обёртку. Она же удобна как форма ответа на серверный список-эндпойнт (поле `count` = серверный `total`).

`lib/data/entity/item/items_entity.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';

part 'items_entity.freezed.dart';
part 'items_entity.g.dart';

@freezed
abstract class ItemsEntity with _$ItemsEntity {
  const factory ItemsEntity({
    @Default(<ItemEntity>[]) List<ItemEntity> items,
    @Default(0) int count,
  }) = _ItemsEntity;

  factory ItemsEntity.fromJson(Map<String, dynamic> json) => _$ItemsEntityFromJson(json);
}
```

> **Гарантия round-trip:** `toEntity(model: toModel(entity: e))` должно воспроизвести `e` точно, и наоборот. Базовые типы entity-слоя делают это детерминированным — все «лоссы» (enum → дефолт, нормализация пустой строки в `null`) живут в маппере и обязаны быть симметричны.

---

## 2. `ResponseEntity<T>` — генерик-конверт REST-ответа

Каждый JSON-ответ бэкенда обёрнут в единый envelope `{data, timestamp, trace_id, meta}` (*пример контракта, заменить на реальный backend NOX*: бэкенд/протокол NOX ещё не выбран). `ResponseEntity<T>` — генерик-обёртка над ним; аннотация `@EntityConverter()` резолвит генерик `T` в `fromJson`/`toJson` конкретного entity.

`lib/data/entity/base/response_entity.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/base/entity_converter.dart';

part 'response_entity.freezed.dart';
part 'response_entity.g.dart';

@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({
    @Default(false) bool success,
    String? error,
    @EntityConverter() T? data,
  }) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
```

> Поля `success` / `error` / `data` подгоняются под реальный envelope бэкенда NOX (*пример контракта, заменить на реальный backend NOX*; протокол ещё не выбран). На деле envelope-пример кладёт полезную нагрузку в `data`, а служебное — в `timestamp` / `trace_id` / `meta`; если они нужны на клиенте, добавь соответствующие nullable-поля. Механизм, который надо сохранить, — генерик `T?`, резолвимый `JsonConverter`'ом.

---

## 3. `EntityConverter<E>` — ручной реестр типов

Это единственный кусок **ручной бухгалтерии** в архитектуре. `EntityConverter<E>` — `JsonConverter`, диспетчеризующий генерик `T` из `ResponseEntity<T>` в нужный entity. **Каждый entity, доступный через `ResponseEntity<T>`, ОБЯЗАН быть зарегистрирован в ОБОИХ цепочках — `fromJson` и `toJson`** — иначе бросается `ArgumentError('No converter found')`.

`lib/data/entity/base/entity_converter.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
// ... import every registered entity ...

bool _isType<E, T>() => <E>[] is List<T>;

class EntityConverter<E> implements JsonConverter<E?, dynamic> {
  const EntityConverter();

  @override
  E? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is bool && _isType<E, bool>() || _isType<E, bool?>()) {
      return json;
    }
    if (json is Map<String, dynamic>) {
      final map = json;

      if (_isType<E, ItemEntity>() || _isType<E, ItemEntity?>()) {
        return ItemEntity.fromJson(map) as E;
      }
      if (_isType<E, ItemsEntity>() || _isType<E, ItemsEntity?>()) {
        return ItemsEntity.fromJson(map) as E;
      }
      // ... one branch per registered entity ...
    }

    throw ArgumentError('No converter found for type $E');
  }

  @override
  dynamic toJson(E? object) {
    if (object == null) return null;

    if (object is ItemEntity) return object.toJson();
    if (object is ItemsEntity) return object.toJson();
    // ... one branch per registered entity ...

    throw ArgumentError('No converter found for type $E');
  }
}
```

> **Правило сопровождения (зафиксировано в `08-conventions-and-constitution.md`):** любой новый entity, используемый через `ResponseEntity<T>`, ОБЯЗАН быть добавлен в обе цепочки диспетчеризации `entity_converter.dart` — `fromJson` и `toJson`. Этот реестр **сопровождается руками**, не кодогенерится. Забыл ветку → рантайм-`ArgumentError` на первом же ответе с этим типом.

---

## 4. Мапперы

`BaseMapper<E, M, AdResult, AdParam>` даёт `toModel` / `toEntity` плюс списочные варианты. Мапперы композируют дочерние мапперы через конструктор. Все — `@lazySingleton`.

- `E` = Entity, `M` = Model (доменная модель).
- `AdResult` / `AdParam` — опциональный резолвер «дополнительных данных» (additional data), когда мапперу нужен контекст, которого нет на самом entity (например, разрезолвить связанную запись). Для простых мапперов оба типизируй как `dynamic` и игнорируй параметр `ad`.

`lib/data/mapper/base_mapper.dart`:

```dart
abstract class BaseMapper<E, M, AdResult, AdParam> {
  M toModel({required E entity, AdResult Function(AdParam entity)? ad});

  E toEntity({required M model, AdResult Function(AdParam entity)? ad});

  List<M> toListModel({required List<E> entities, AdResult Function(AdParam entity)? ad}) {
    if (ad == null) {
      return List.from(entities.map((e) => toModel(entity: e)));
    } else {
      return List.from(entities.map((e) => toModel(entity: e, ad: ad)));
    }
  }

  List<E> toListEntity({required List<M> models, AdResult Function(AdParam entity)? ad}) {
    if (ad == null) {
      return List.from(models.map((e) => toEntity(model: e)));
    } else {
      return List.from(models.map((e) => toEntity(model: e, ad: ad)));
    }
  }
}
```

Конкретный `ItemMapper` — выполняет лоссless round-trip `ItemEntity <-> domain.ItemModel`. `status` String парсится через `values.firstWhere(... orElse: ...)`; `createdAt` — через `DateTime.parse` / `toIso8601String`; пустой `imageUrl`-стиль нормализуется в `null`.

`lib/data/mapper/item/item_mapper.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/item/item_model.dart';

@lazySingleton
class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic> {
  @override
  ItemModel toModel({required ItemEntity entity, dynamic Function(dynamic entity)? ad}) {
    final description = entity.description;
    return ItemModel(
      id: entity.id,
      name: entity.name,
      description: (description == null || description.isEmpty) ? null : description,
      status: ItemStatus.values.firstWhere(
        (s) => s.name == entity.status,
        orElse: () => ItemStatus.draft,
      ),
      createdAt: DateTime.parse(entity.createdAt),
      tags: entity.tags,
    );
  }

  @override
  ItemEntity toEntity({required ItemModel model, dynamic Function(dynamic entity)? ad}) {
    return ItemEntity(
      id: model.id,
      name: model.name,
      description: model.description,
      status: model.status.name,
      createdAt: model.createdAt.toIso8601String(),
      tags: model.tags,
    );
  }
}
```

> **Композиция дочерних мапперов.** Когда entity вкладывает другой (например, `ItemEntity` держит `List<TagEntity>`), инжектируй дочерний маппер через конструктор и используй `_tagMapper.toListModel(entities: entity.tags)`:
>
> ```dart
> @lazySingleton
> class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic> {
>   ItemMapper(this._tagMapper);
>   final TagMapper _tagMapper;
>   // ... используй _tagMapper.toListModel(...) / toListEntity(...) внутри toModel/toEntity
> }
> ```

---

## 5. Обработка ошибок — `BaseRepositoryHelper.execute<T>()`

Слой данных **НЕ** заводит собственную иерархию типизированных исключений (правило этого блюпринта — `ApiException` / `DaoException` / `BaseDomainExceptionHelper` намеренно отсутствуют). Единственный механизм — тонкий mixin `BaseRepositoryHelper.execute<TD>()`: он оборачивает асинхронную операцию репозитория в guarded try/catch, **обязательно** логирует через `LogRepository` и возвращает завершённый `RepositoryResult<TD>`. Доменные коды — это `RepositoryException`-enum из [03-domain-layer.md](03-domain-layer.md).

`lib/data/exception/base_repository_helper.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

mixin BaseRepositoryHelper {
  Future<RepositoryResult<TD>> execute<TD>(Function executionFunction) async {
    try {
      return await executionFunction();
    } on DioException catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.internal);
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.unknown);
    }
  }
}
```

Ключевое:

- **`executionFunction` возвращает уже-обёрнутый `RepositoryResult<TD>`** (не «голые» данные). Каждый call-site внутри `execute` сам строит результат: `return RepositoryResult.success(data: …)` на успехе, или `return RepositoryResult.error(exception: RepositoryException.<code>)` для конкретного доменного кода. `execute` лишь перехватывает **необработанные** исключения.
- **Две catch-ветки:** `DioException` → `RepositoryException.internal` (сбой транспорта/HTTP); любой другой `catch` → `RepositoryException.unknown`. Никаких `ApiException` / `DaoException` / `BaseDomainExceptionHelper` — минимальная обработка, конкретику решает сам callback.
- **Логирование ОБЯЗАТЕЛЬНО** в каждой ветке (через `logRepository` — алиас из `lib/di/global_aliases.dart`, см. [02-dependency-injection.md](02-dependency-injection.md)), ПЕРЕД возвратом. Никакого сырого `print`.
- Импл подмешивает **`with BaseRepositoryHelper`** (без `on`-ограничения) и оборачивает каждый публичный метод в `execute<T>()`.

> **Конкретные доменные коды — в callback'е, не в catch.** Если нужен код точнее, чем `internal`/`unknown` (например `notFound` при cache-miss, `unauthenticated` при 401), верни его **внутри** `executionFunction` явным `return RepositoryResult.error(exception: RepositoryException.<code>)` (проверив `response.statusCode` или отсутствие записи). Пример — `fetchItem` в §8. `RepositoryException` (`unknown` / `unauthenticated` / `notFound` / `internal` / `connection`) определён в [03-domain-layer.md](03-domain-layer.md).

---

## 6. Sembast DAO (реактивный)

> **Локальная БД — Sembast (OQ-1 закрыт 2026-06-08).** Документная NoSQL, **schema-less** (хранит JSON-maps → миграций как класса нет: новые/отсутствующие поля гасятся дефолтами в маппере), чистый Dart без codegen, реактивные стримы (`onSnapshots`). Набор: `sembast` + `shared_preferences` (флаги/`themeMode`) + `flutter_secure_storage` (секреты, *например refresh-токен — бэкенд/протокол NOX ещё не выбран*). **Единый подход на все платформы, включая web:** mobile/desktop — `sembast_io` (`databaseFactoryIo`), Test — `databaseFactoryMemory`, **web (будущий клиент)** — `sembast_web` (`databaseFactoryWeb`, IndexedDB/WASM); код DAO/репозиториев не меняется — за абстракцией `AppDatabase` подменяется только фабрика. Отвергнуты: ObjectBox/Realm (нет web), Drift/PowerSync (реляционные), Isar (web только через community-форк + типизированная схема требует миграций). Контракты репозиториев (`03-domain-layer.md`) и потребители от БД не зависят.

DAO используют `StoreRef<String, Map<String, dynamic>>`, отдают реактивные потоки через `onSnapshots()` / `onSnapshot()`, поддерживают атомарные записи через `db.transaction()` и **бросают сырые исключения** при сбое хранилища (никакого типизированного `DaoException` — его в проекте нет; raw-исключение ловит catch-all ветка `execute` → `RepositoryException.unknown`). Cache-miss / not-found — это **не** забота DAO: DAO просто отдаёт `null` / пустой список, а проверку отсутствия и `RepositoryException.notFound` решает callback репозитория (§8). Битые записи отдают пустой список / `null`, а не убивают поток.

Шаблон ниже моделирует single-record «коллекционный» store (одна запись держит список `ItemsEntity`). Вариант с ключом-на-запись — в конце секции.

`lib/data/local/item/item_dao.dart`:

```dart
import 'package:collection/collection.dart';
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/data/local/app_database.dart';

@lazySingleton
class ItemDao {
  ItemDao(this._appDatabase);

  final AppDatabase _appDatabase;
  final _store = StoreRef<String, Map<String, dynamic>>.main();
  static const _storeKey = 'item_';

  /// Reactive stream of the full item list.
  /// Malformed records yield an empty list rather than killing the stream.
  Future<Stream<List<ItemEntity>>> watch() async {
    try {
      final db = await _appDatabase.db;
      return _store.query().onSnapshots(db).map((snapshots) {
        if (snapshots.isEmpty) return <ItemEntity>[];
        final snapshot = snapshots.firstWhereOrNull((e) => e.key == _storeKey);
        if (snapshot != null) {
          try {
            return ItemsEntity.fromJson(snapshot.value).items;
          } catch (_) {
            return <ItemEntity>[];
          }
        }
        return <ItemEntity>[];
      });
    } catch (_) {
      return Stream.value(<ItemEntity>[]);
    }
  }

  /// One-shot read.
  Future<List<ItemEntity>> getData() async {
    try {
      final db = await _appDatabase.db;
      final data = await _store.record(_storeKey).get(db);
      return data != null ? ItemsEntity.fromJson(data).items : <ItemEntity>[];
    } catch (e) {
      // Raw throw on storage failure: execute()'s catch-all maps it to
      // RepositoryException.unknown (no typed DaoException exists).
      throw StateError('Failed to get item data: $e');
    }
  }

  /// Replace the whole list.
  Future<void> saveData({required List<ItemEntity> items}) async {
    try {
      final db = await _appDatabase.db;
      final json = ItemsEntity(items: items, count: items.length).toJson();
      await _store.record(_storeKey).put(db, json);
    } catch (e) {
      throw StateError('Failed to save item data: $e');
    }
  }

  /// Upsert a single item by id within a transaction.
  Future<void> upsert({required ItemEntity item}) async {
    try {
      final db = await _appDatabase.db;
      await db.transaction((txn) async {
        final raw = await _store.record(_storeKey).get(txn);
        final current = raw != null ? ItemsEntity.fromJson(raw).items : <ItemEntity>[];
        final next = [
          ...current.where((e) => e.id != item.id),
          item,
        ];
        final json = ItemsEntity(items: next, count: next.length).toJson();
        await _store.record(_storeKey).put(txn, json);
      });
    } catch (e) {
      throw StateError('Failed to upsert item: $e');
    }
  }

  /// Remove a single item by id within a transaction.
  Future<void> removeById({required String id}) async {
    try {
      final db = await _appDatabase.db;
      await db.transaction((txn) async {
        final raw = await _store.record(_storeKey).get(txn);
        if (raw == null) return;
        final current = ItemsEntity.fromJson(raw).items;
        final next = current.where((e) => e.id != id).toList();
        final json = ItemsEntity(items: next, count: next.length).toJson();
        await _store.record(_storeKey).put(txn, json);
      });
    } catch (e) {
      throw StateError('Failed to remove item: $e');
    }
  }

  /// Wipe the store.
  Future<void> cleanData() async {
    try {
      final db = await _appDatabase.db;
      await _store.record(_storeKey).delete(db);
    } catch (e) {
      throw StateError('Failed to clean item data: $e');
    }
  }
}
```

**Вариант DAO с ключом-на-запись (per-ID records).** Когда каждый item — отдельная запись, префиксуй ключ (`'item_$id'`), используй `_store.record(key).onSnapshot(db)` (singular) для стриминга одной записи и трактуй битые данные как `null`, чтобы долгоживущие watch-потоки оставались живыми. Атомарный read-modify-write — канонический примитив мутации:

```dart
Future<void> mutate({
  required String key,
  required ItemEntity Function(ItemEntity current) mutator,
}) async {
  try {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      final raw = await _store.record(key).get(txn);
      if (raw == null) {
        // Raw throw: execute()'s catch-all maps it to RepositoryException.unknown.
        // For a precise notFound code, check absence in the repository callback instead.
        throw StateError('Record not found');
      }
      final updated = mutator(ItemEntity.fromJson(raw));
      await _store.record(key).put(txn, updated.toJson());
    });
  } catch (_) {
    rethrow;
  }
}
```

> **`AppDatabase` (env-scoped).** Сама база — `abstract AppDatabase` с тремя реализациями, привязанными к `Environment` через `@LazySingleton(as: AppDatabase, env: [...])`: `AppDatabaseDev`/`AppDatabaseProd` на `databaseFactoryIo` (файл под app-documents directory), `AppDatabaseTest` на `databaseFactoryMemory` (эфемерная in-memory). Полный шаблон провайдеров и почему env-список «load-bearing» — в `02-dependency-injection.md`. Здесь DAO просто инжектирует `AppDatabase` и не знает, какой env активен.

---

## 7. REST-слой

### 7а. Dio `ApiClient`

Два экземпляра Dio: `baseClient` (основной API, авторизованный через interceptor) и `searchClient` (опциональный второй хост, без auth). Auth-interceptor читает токен **асинхронно** из `AppConfigRepository` на каждом запросе — расширяй interceptor, а не добавляй заголовки по-API. (Конкретная модель токенов — Bearer / access-refresh — это *пример: бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт*; сохраняется именно паттерн асинхронного чтения токена в interceptor'е.)

`lib/data/remote/api/base/api_client.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

class ApiClient {
  static Dio initBase({String? contentType}) {
    final appConfigRepository = getIt<AppConfigRepository>();
    final baseOptions = BaseOptions(
      baseUrl: '${appConfigRepository.config.apiUrl}/api/',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: contentType ?? 'application/json',
      responseType: ResponseType.json,
    );
    final dio = Dio(baseOptions);

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await appConfigRepository.getUserAuthIdToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) => handler.next(response),
      onError: (e, handler) => handler.next(e),
    ));
    return dio;
  }

  static Dio initSearch({String? contentType}) {
    final appConfigRepository = getIt<AppConfigRepository>();
    final baseOptions = BaseOptions(
      baseUrl: '${appConfigRepository.config.searchApiUrl}/api/',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: contentType ?? 'application/json',
      responseType: ResponseType.json,
    );
    // initSearch() — второй Dio, без auth-interceptor: второй хост не требует Bearer-токена.
    return Dio(baseOptions);
  }
}
```

> На non-2xx Dio бросает `DioException`, который **пробрасывается до** `BaseRepositoryHelper.execute()` и попадает в его ветку `on DioException` → `RepositoryException.internal`. API-класс **не** маппит ошибку в типизированный `ApiException` (его в проекте нет).

> **Хук наблюдаемости.** Подключай HTTP-трекинг наблюдаемости в эти interceptor'ы (`onRequest`/`onResponse`/`onError`). Если второго хоста нет — выкинь `searchClient` и `initSearch()`.
>
> **HMAC/безопасность (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт).** Если бэкенд NOX потребует подписанные запросы (*пример*: `x-request-timestamp` + HMAC-SHA256 + security-заголовки), эти заголовки — тоже зона interceptor'а: добавь отдельный `InterceptorsWrapper`, считающий подпись по каноническому формату (*в этом примере* серверный канонический verb — это `ApiRequestMethod.<lowercase>`, не `GET`/`POST`). Это **архитектурный контракт** — конкретную схему подписи и security-заголовки определяй вместе с реальным бэкендом NOX перед реализацией, не выбирай молча.

### 7б. `BaseApiRepository`

`lib/data/remote/api/base/base_api_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  Dio get baseClient => ApiClient.initBase();

  Dio get searchClient => ApiClient.initSearch();
}
```

### 7в. `RequestBuilder` + `RequestBuilderHelper`

`RequestBuilder<T>` строит `body`/`path`/`headers` из доменного конфига; `RequestBuilderHelper<T>` — mixin, резолвящий конкретный builder из `getIt` и форвардящий вызовы (API-класс остаётся свободным от ручной разводки билдеров).

`lib/data/remote/request_builder/base/request_builder.dart`:

```dart
abstract class RequestBuilder<T> {
  Future<Map<String, dynamic>> buildBody(T config) async => {};

  Future<String> buildPath(T config, String basePath, {Map<String, String>? params}) async {
    if (params == null || params.isEmpty) {
      return basePath;
    }
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$basePath?$query';
  }

  Future<Map<String, String>> buildHeaders(T config) async => {};
}
```

`lib/data/remote/request_builder/base/request_builder_helper.dart`:

```dart
import 'package:nox_app/data/remote/request_builder/base/request_builder.dart';
import 'package:nox_app/di/configure_dependencies.dart';

mixin RequestBuilderHelper<T extends RequestBuilder> {
  Future<Map<String, dynamic>> buildBody(dynamic config) async => getIt<T>().buildBody(config);

  Future<String> buildPath(dynamic config, String basePath) async => getIt<T>().buildPath(config, basePath);

  Future<Map<String, String>> buildHeaders(dynamic config) async => getIt<T>().buildHeaders(config);
}
```

### 7г. API-класс + его request builder

Именование API: `{verb}_{resource}_api.dart`. Класс расширяет `BaseApiRepository` и подмешивает `RequestBuilderHelper<TheBuilder>`. Форма: построить path → вызвать Dio → завернуть `response.data` в `ResponseEntity<T>.fromJson`. На non-2xx Dio бросает `DioException` — его **не** перехватывают и **не** маппят на типизированный `ApiException`: исключение пробрасывается до `BaseRepositoryHelper.execute()`, где ветка `on DioException` отдаёт `RepositoryException.internal`.

`lib/data/remote/request_builder/item/get_items_api_request_builder.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/request_builder/base/request_builder.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

@lazySingleton
class GetItemsApiRequestBuilder extends RequestBuilder<GetItemsConfig> {
  @override
  Future<Map<String, String>> buildHeaders(GetItemsConfig config) async {
    return {'Content-Type': 'application/json'};
  }

  @override
  Future<String> buildPath(GetItemsConfig config, String basePath, {Map<String, String>? params}) {
    final Map<String, String> queryParams = params ?? {};

    final search = config.search;
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    queryParams['page'] = config.page.toString();
    queryParams['page_size'] = GetItemsConfig.pageSize.toString();

    return super.buildPath(config, basePath, params: queryParams);
  }
}
```

`lib/data/remote/api/item/get_items_api.dart`:

```dart
import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/data/remote/api/base/base_api_repository.dart';
import 'package:nox_app/data/remote/request_builder/base/request_builder_helper.dart';
import 'package:nox_app/data/remote/request_builder/item/get_items_api_request_builder.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

@lazySingleton
class GetItemsApi extends BaseApiRepository with RequestBuilderHelper<GetItemsApiRequestBuilder> {
  Future<ResponseEntity<ItemsEntity>> execute({required GetItemsConfig config}) async {
    // No try/catch: on non-2xx Dio throws DioException, which propagates
    // up to BaseRepositoryHelper.execute() -> RepositoryException.internal.
    final path = await buildPath(config, 'v1/items');
    final response = await baseClient.get(path);
    return ResponseEntity<ItemsEntity>.fromJson(response.data);
  }
}
```

> **REST-поток:** `RequestBuilder` превращает доменный конфиг в `body`/`path`/`headers` → `RequestBuilderHelper` резолвит builder из `getIt` → API-класс шлёт через `baseClient`, оборачивает `response.data` в `ResponseEntity<T>.fromJson` (генерик `T` резолвится `EntityConverter`'ом) → на non-2xx Dio бросает `DioException`, который не перехватывается на уровне API. Репозиторий оборачивает вызов в `execute<T>()`, где ветка `on DioException` логирует и отдаёт `RepositoryResult.error(exception: RepositoryException.internal)`.

---

## 8. Реализация репозитория (кэш-first реактивная)

Флагманский паттерн для user-scoped watchable-ресурсов. `ItemRepositoryImpl` реализует **ровно** контракт `ItemRepository` из §4.2 `03-domain-layer.md` (`watchItem`/`fetchItem`/`getItems`/`createItem`/`updateItem`/`deleteItem`/`clean`) и:

- несёт `@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])` — **env-список load-bearing** (Sembast-база env-scoped; пропуск env оставит репозиторий без биндинга базы в этом окружении);
- подмешивает `with BaseRepositoryHelper` (без `on`-ограничения) и оборачивает **каждый** вызов в `execute<TD>()` (обязательное логирование необработанных исключений + коэрсный маппинг `DioException`→`internal` / else→`unknown`); callback **сам возвращает уже-обёрнутый** `RepositoryResult<TD>` — `return RepositoryResult.success(data: …)` на успехе или `return RepositoryResult.error(exception: RepositoryException.<code>)` для конкретного доменного кода;
- подписывается на DAO-поток **один раз** в конструкторе (`_initSubscription`), маппит entities и кормит ОДИН `BehaviorSubject<RepositoryResult<List<ItemModel>>>` — кэш-источник, из которого `watchItem({id})` отдаёт реактивный поток одного ресурса по id;
- читает `RepositoryResult` через `result.hasData`, **никогда** не `result.data!` за пределами проверенной ветки;
- `@disposeMethod` отменяет подписку и закрывает subject.

`lib/data/repository/item/item_repository_impl.dart`:

```dart
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/item/item_dao.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/data/remote/api/item/get_items_api.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_item_config.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._itemDao, this._itemMapper, this._getItemsApi) {
    _initSubscription();
  }

  final ItemDao _itemDao;
  final ItemMapper _itemMapper;
  final GetItemsApi _getItemsApi;

  final _itemsStreamController = BehaviorSubject<RepositoryResult<List<ItemModel>>>();
  StreamSubscription<List<ItemEntity>>? _itemsSubscription;

  /// Subscribe ONCE to the DAO stream and feed mapped results into the subject.
  Future<void> _initSubscription() async {
    try {
      final stream = await _itemDao.watch();
      _itemsSubscription = stream.listen((entities) {
        _itemsStreamController.add(
          RepositoryResult<List<ItemModel>>.success(
            data: _itemMapper.toListModel(entities: entities),
          ),
        );
      });
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      _itemsStreamController.add(
        RepositoryResult<List<ItemModel>>.error(exception: RepositoryException.internal),
      );
    }
  }

  // --- Streaming read (cache-first, single resource) -------------------------

  @override
  Stream<RepositoryResult<ItemModel>> watchItem({required String id}) async* {
    // Cache-miss -> trigger a REST fetch; saveData re-emits via the DAO stream.
    if (!_itemsStreamController.hasValue) {
      await _refreshFromNetwork();
    }
    // Derive a single-resource stream from the shared cache subject.
    yield* _itemsStreamController.stream.map((result) {
      return result.match(
        onData: (items) {
          final item = items.firstWhereOrNull((e) => e.id == id);
          return item == null
              ? RepositoryResult<ItemModel>.error(exception: RepositoryException.notFound)
              : RepositoryResult<ItemModel>.success(data: item);
        },
        onError: (exception) => RepositoryResult<ItemModel>.error(exception: exception),
      );
    });
  }

  @override
  Future<RepositoryResult<ItemModel>> fetchItem({required GetItemConfig config}) {
    return execute<ItemModel>(() async {
      var entities = await _itemDao.getData();
      var entity = entities.firstWhereOrNull((e) => e.id == config.id);

      // Cache miss -> network refresh, then re-read from cache.
      if (entity == null) {
        await _refreshFromNetwork();
        entities = await _itemDao.getData();
        entity = entities.firstWhereOrNull((e) => e.id == config.id);
      }

      // Still absent after refresh: return the precise domain code DIRECTLY
      // (no typed DaoException — absence is handled in the callback).
      if (entity == null) {
        return RepositoryResult<ItemModel>.error(exception: RepositoryException.notFound);
      }
      return RepositoryResult<ItemModel>.success(data: _itemMapper.toModel(entity: entity));
    });
  }

  /// Network fetch + saveData; the DAO onSnapshots() stream re-emits to the subject.
  /// An empty payload throws raw -> execute()'s catch-all maps it to unknown.
  Future<void> _refreshFromNetwork() async {
    final response = await _getItemsApi.execute(config: GetItemsConfig.firstPage());
    final page = response.data;
    if (page == null) {
      throw StateError('Empty response payload');
    }
    await _itemDao.saveData(items: page.items);
  }

  // --- Paginated server-owned list (network-only carve-out) ------------------

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    // NETWORK-ONLY: no DAO, no BehaviorSubject. See 07-pagination.md.
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _getItemsApi.execute(config: config);
      final page = response.data;
      if (page == null) {
        throw StateError('Empty response payload');
      }
      final models = _itemMapper.toListModel(entities: page.items);
      final metadata = PageMetadata(
        nextPage: page.items.length < GetItemsConfig.pageSize ? null : config.page + 1,
        total: page.count,
      );
      return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
    });
  }

  // --- Mutations -------------------------------------------------------------

  @override
  Future<RepositoryResult<ItemModel>> createItem({required ItemModel item}) {
    return execute<ItemModel>(() async {
      await _itemDao.upsert(item: _itemMapper.toEntity(model: item));
      return RepositoryResult<ItemModel>.success(data: item);
    });
  }

  @override
  Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item}) {
    return execute<ItemModel>(() async {
      await _itemDao.upsert(item: _itemMapper.toEntity(model: item));
      return RepositoryResult<ItemModel>.success(data: item);
    });
  }

  @override
  Future<RepositoryResult<void>> deleteItem({required String id}) {
    return execute<void>(() async {
      await _itemDao.removeById(id: id);
      return RepositoryResult<void>.success(data: null);
    });
  }

  @override
  Future<void> clean() async {
    await _itemDao.cleanData();
  }

  @disposeMethod
  Future<void> dispose() async {
    await _itemsSubscription?.cancel();
    await _itemsStreamController.close();
  }
}
```

**Заметки**

- `watchItem({id})` реплеит последнее значение из общего `BehaviorSubject` (кэш-список) и форвардит живые обновления, фильтруя список по `id` через `result.match(onData:, onError:)`. Единственная подписка на DAO создаётся один раз в конструкторе. Для строго keyed/per-ID потоков используй map контроллеров-по-ключу и init-lock против гонок параллельной подписки.
- Чтение `RepositoryResult` — **только через `hasData`/`match`** в ветке, проверившей наличие данных; никогда `result.data!` «вслепую» (см. `03-domain-layer.md`).
- callback `execute<TD>()` **сам возвращает уже-обёрнутый** `RepositoryResult<TD>` — `return RepositoryResult.success(data: …)` на успехе. Для конкретного доменного кода (например `notFound` при cache-miss, как в `fetchItem`) верни его прямо в callback'е: `return RepositoryResult.error(exception: RepositoryException.<code>)`. `execute` лишь перехватывает **необработанные** исключения: `DioException`→`internal`, любой другой `catch`→`unknown`. Атомарная мутация по ключу:

```dart
Future<RepositoryResult<void>> _mutateItem({
  required String id,
  required ItemEntity Function(ItemEntity current) mutator,
}) {
  return execute<void>(() async {
    // _itemDao.mutate бросает сырое StateError('Record not found') при отсутствии записи —
    // его ловит catch-all ветка execute() -> RepositoryException.unknown.
    // Нужен точный notFound? Проверь отсутствие записи в callback'е и верни
    // RepositoryResult.error(exception: RepositoryException.notFound) явно.
    await _itemDao.mutate(key: 'item_$id', mutator: mutator);
    return RepositoryResult<void>.success(data: null);
  });
}
```

### Когда НЕ использовать кэш-first: network-only carve-out

**Пагинированные серверные списки и one-shot POST — явное исключение из реактивного паттерна.** Они **network-only**: без DAO, без `BehaviorSubject`, без подписки. Это и есть метод `getItems({required GetItemsConfig config})` из контракта — он реализован прямо в `ItemRepositoryImpl` выше (секция «Paginated server-owned list»): репозиторий просто бьёт по REST и возвращает `RepositoryResult<(List<ItemModel>, PageMetadata)>`. Никакого отдельного `getItemsPage`/`watchItems` для списка — пагинированный список это **`getItems`**.

```dart
// Paginated server-owned list: network-only, NO DAO, NO BehaviorSubject.
@override
Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
  return execute<(List<ItemModel>, PageMetadata)>(() async {
    final response = await _getItemsApi.execute(config: config);
    final page = response.data;
    if (page == null) {
      throw StateError('Empty response payload');
    }
    final models = _itemMapper.toListModel(entities: page.items);
    final metadata = PageMetadata(
      nextPage: page.items.length < GetItemsConfig.pageSize ? null : config.page + 1,
      total: page.count,
    );
    return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
  });
}
```

> Первая реальная фича — **список чатов** (открытое общее пространство) — именно такая: это серверный, network-only пагинированный список, потому она идёт по network-only ветке (`getItems`). Дефолтный флавор пагинации — OFFSET (`page` + `page_size` + `count`), альтернатива — CURSOR; конкретный контракт пагинации списка чатов финализируется позже вместе с бэкендом NOX. Полный контракт пагинации (дефолтный OFFSET-флавор `PageMetadata{int? nextPage, int total}`, альтернативный CURSOR, `PagingStateExt.applyPage`, проброс `result.exception` в `pagingState.error`) — в `07-pagination.md`. Не заводи DAO/subject для серверных пагинированных списков.

---

## Сводка разводки DI

| Артефакт | Файл | DI-аннотация |
|---|---|---|
| `ItemEntity` / `ItemsEntity` | `entity/item/item_entity.dart`, `items_entity.dart` | `@freezed` (без DI) |
| `ResponseEntity<T>` | `entity/base/response_entity.dart` | `@freezed` (без DI) |
| `EntityConverter<E>` | `entity/base/entity_converter.dart` | `JsonConverter` (ручной реестр) |
| `BaseMapper` | `mapper/base_mapper.dart` | базовый класс (без DI) |
| `ItemMapper` | `mapper/item/item_mapper.dart` | `@lazySingleton` |
| `BaseRepositoryHelper` | `exception/base_repository_helper.dart` | mixin |
| `AppDatabaseDev/Prod/Test` | `local/app_database.dart` | `@LazySingleton(as: AppDatabase, env: [...])` (см. `02-dependency-injection.md`) |
| `ItemDao` | `local/item/item_dao.dart` | `@lazySingleton` |
| `ApiClient` / `BaseApiRepository` | `remote/api/base/...` | статик-фабрики / абстрактный базовый |
| `RequestBuilder` / `RequestBuilderHelper` | `remote/request_builder/base/...` | базовый / mixin |
| `GetItemsApiRequestBuilder` | `remote/request_builder/item/get_items_api_request_builder.dart` | `@lazySingleton` |
| `GetItemsApi` | `remote/api/item/get_items_api.dart` | `@lazySingleton` |
| `ItemRepositoryImpl` | `repository/item/item_repository_impl.dart` | `@LazySingleton(as: ItemRepository, env: [dev, prod, test])` |

После добавления/правки любого аннотированного класса — **один** прогон кодогенерации в корне единого пакета (см. `12-dev-commands.md`):

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

---

## Чеклист

- [ ] `ItemEntity` использует **только базовые типы** (`status` как String-`name`, `createdAt` как ISO-8601 String, пустые строки нормализуются в `null` в маппере); `ItemsEntity`-обёртка присутствует, если DAO хранит список в одной записи.
- [ ] Все `part`-директивы стоят: entities имеют `.freezed.dart` **и** `.g.dart`; BLoC-типы — только `.freezed.dart` (entity-слой — единственное место с `.g.dart`/`fromJson`).
- [ ] `ResponseEntity<T>` envelope + `EntityConverter<E>` реестр на месте; **каждый** новый entity, проходящий через `ResponseEntity<T>`, добавлен в ОБЕ цепочки (`fromJson` + `toJson`) `entity_converter.dart`.
- [ ] `ItemMapper` расширяет `BaseMapper`, round-trip `ItemModel <-> ItemEntity` лоссless (enum через `name`/`firstWhere(orElse:)`, `DateTime` через `parse`/`toIso8601String`); дочерние мапперы инжектируются конструктором.
- [ ] Никаких `DaoException` / `ApiException` / `BaseDomainExceptionHelper` (их в проекте нет); единственный механизм — `mixin BaseRepositoryHelper` с `execute<TD>(Function executionFunction)`; импл подмешивает **только** `with BaseRepositoryHelper` (без `on`-ограничения).
- [ ] `BaseRepositoryHelper.execute<T>()` имеет **ровно две** `catch`-ветки — `on DioException` → `RepositoryException.internal`, общий `catch` → `RepositoryException.unknown`; **обязательно** логирует через `LogRepository` в каждой ветке (никакого `print`) перед возвратом `RepositoryResult.error(...)`. Callback `executionFunction` сам возвращает уже-обёрнутый `RepositoryResult` (`success(data: …)` / `error(exception: …)`); конкретный доменный код (`notFound` при cache-miss) — внутри callback'а, не в catch.
- [ ] `AppDatabase` env-scoped (`Dev`/`Prod` = `databaseFactoryIo`, `Test` = `databaseFactoryMemory`); `path_provider` — зависимость пакета; env-список в репозитории полный.
- [ ] `ItemDao` использует `StoreRef<String, Map<String, dynamic>>`, реактивные `onSnapshots()`/`onSnapshot()`, атомарные `db.transaction()` для upsert/removeById/`mutate`, битые записи → пустой список/`null`, **бросает сырые исключения** на сбое хранилища (никакого `DaoException`); cache-miss/not-found отдаёт `null`/пустой список (код `notFound` решает callback репозитория).
- [ ] `ItemRepositoryImpl` реализует **ровно** контракт `ItemRepository` (`watchItem({id})`/`fetchItem({GetItemConfig config})`/`getItems({GetItemsConfig config}) -> (List, PageMetadata)`/`createItem`/`updateItem`/`deleteItem`/`clean() -> Future<void>`) — никаких `watchItems()`/`saveItem()`/`getItemsPage()`/`fetchItem(String id)`; несёт **полный** env-список `@LazySingleton`, подписывается на DAO-поток **один раз** в конструкторе, кормит ОДИН `BehaviorSubject`, читает через `hasData`/`match` (не `result.data!`), `@disposeMethod` отменяет подписку + закрывает subject.
- [ ] REST: `ApiClient.initBase()` (auth-interceptor, токен из `AppConfigRepository` асинхронно на каждом запросе) + опциональный `ApiClient.initSearch()` (второй Dio, без auth, `config.searchApiUrl`); `BaseApiRepository`; `RequestBuilder` + `RequestBuilderHelper`; API-класс на endpoint оборачивает `response.data` в `ResponseEntity<T>.fromJson`; на non-2xx Dio бросает `DioException`, который **не** перехватывается на уровне API и пробрасывается до `execute()` → `RepositoryException.internal` (никакого `ApiException`).
- [ ] **Carve-out соблюдён:** пагинированные серверные списки + one-shot POST — network-only (без DAO, без subject), возвращают `RepositoryResult<(List<Model>, PageMetadata)>` (см. `07-pagination.md`).
- [ ] `build_runner` перезапущен один раз в корне пакета после изменений аннотаций.

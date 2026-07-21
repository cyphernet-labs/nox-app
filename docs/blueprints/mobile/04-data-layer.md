# 04 — Слой данных

> **Назначение:** дать копипаст-готовые шаблоны слоя данных (`lib/data/`) — сущности (entities), генерик-конверт `ResponseEntity<T>` + ручной реестр `EntityConverter<E>`, мапперы, типизированные исключения, реактивные Sembast-DAO, REST-слой (Dio `ApiClient` + `RequestBuilder`/`RequestBuilderHelper` + API-классы) и реализации репозиториев. Слой данных **реализует** контракты из `03-domain-layer.md`.
> **Когда читать:** когда поднимаешь папку `lib/data/` или подключаешь конкретный `ItemRepositoryImpl` к его DAO + мапперу + REST-клиенту. Это авторитетный дом всех шаблонов слоя данных.
> **Связанные документы:** `03-domain-layer.md` (контракты, которые здесь реализуются), `05-presentation-layer.md` (потребляет репозитории), `02-dependency-injection.md` (`AppDatabase`, env-scoped провайдеры, `getIt`), `06-theming.md`, `07-pagination.md` (network-only пагинация), `08-conventions-and-constitution.md` (правила именования и инвариантов), `10-code-templates.md` (индекс шаблонов), `12-dev-commands.md` (build_runner).

> **`watchX()` как change-signal (Feature 014).** Реактивные Sembast-`watch()`-стримы репозитория (`watchChats`/`watchMessages`) используются презентацией как **сигнал об изменении** кэша, а не как источник проекции: их значение игнорируется, а BLoC перечитывает уже загруженный префикс через тот же `getX` (см. `07-pagination.md`). Мутации, меняющие несколько сущностей (напр. `sendMessage` → сообщение + строка чата), выполняются в data-слое, поэтому реактивный список обновляется без связей между BLoC. См. `specs/014-reactive-data-refresh/`.

> **Reactive-канал не только над Sembast (Feature 015).** Тот же паттерн change-signal применим к не-Sembast источникам: `SessionRepository.watchLabel()` — это broadcast-`StreamController<String?>` над `shared_preferences`-меткой (не реактивной самой по себе). Он эмитит текущую метку при подписке (seed-then-live, как `watch()`-`async*`), затем каждое переименование (`updateLabel`) и `null` при `clear` (logout). Единый источник identity (технический идентификатор + label) резолвится чистой `resolveIdentity(SessionModel?)`; переименование меняет только label, идентификатор remain-invariant (own-detection в треде опирается на идентификатор). Живые surfaces (desktop rail-аватар) подписываются и обновляются без рестарта. См. `specs/015-identity-unification/`.

> **RemoteDataSource seam (Feature 016).** Сетевая граница каждой data-фичи — абстрактный интерфейс `*RemoteDataSource` (`lib/data/remote/datasource/`: `ChatRemoteDataSource`/`ChatFilesRemoteDataSource`/`MessageRemoteDataSource`/`ItemRemoteDataSource`). Репо зависят **от интерфейса**, не от конкретного мока (dependency inversion). Мок-реализации (`Mock*RemoteDataSource`) делегируют неизменным `*Api`-генераторам и биндятся `@LazySingleton(as: Interface, env:[dev,prod,test])` — мок покрывает и `prod`, т.к. prod-флейвор бутается `Environment.prod`, а real-impl ещё нет. **Флип на бэкенд** (когда появится): зарегистрировать `RealXRemoteDataSource` на `[Environment.prod]`, сузить мок до `[dev,test]`, `make generate` — репо/DAO/мапперы/`RepositoryResult`/`PageMetadata`/UI не трогаются. `RepositoryResult`+catch-all `execute()` и HTTP→exception-маппинг (S3) остаются контрактом поверх seam. См. `specs/016-remote-datasource-seam/`.

---

## Обзор и зона ответственности

Слой данных отвечает за:

- **Entities (DTO)** — `@freezed` + `json_serializable`, **только базовые типы** (`String`/`int`/`double`/`bool` + их `List`). Enum хранится как `.name` (String), `DateTime` — как ISO-8601 String. Любая коэрция отложена в маппер.
- **`ResponseEntity<T>` + `EntityConverter<E>`** — генерик-конверт REST-ответа (бэкенд отдаёт единый envelope `{data, timestamp, trace_id, meta}` — *пример контракта, заменить на реальный backend NOX*) + ручной реестр типов, резолвящий генерик `T` в конкретный entity.
- **Мапперы** — двунаправленная конвертация `Entity <-> Model` (`BaseMapper`), где происходит ВСЯ коэрция типов (enum, `DateTime`, nullable-нормализация). Композиция дочерних мапперов через конструктор.
- **Обработка ошибок** — единственный механизм `BaseRepositoryHelper.execute<TD>()`: тонкий guarded try/catch, который **обязательно** логирует через `LogRepository` и возвращает `RepositoryResult.error(...)`. Маппинг коэрсный: `DioException` → `RepositoryException.internal`, любой другой `catch` → `RepositoryException.unknown`. **Нет типизированной транспортной иерархии** (`ApiException` / `DaoException` / `BaseDomainExceptionHelper` намеренно отсутствуют — правило этого блюпринта), но есть **маркер** `BaseRepositoryException`, который реализует каждая доменная ошибка: общий enum `RepositoryException` и любые feature-специфичные enum'ы реализуют этот маркер (см. §5 и `03-domain-layer.md`). Конкретный доменный код возвращает сам callback явным `return RepositoryResult.error(...)`.
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
    api_client.dart              # SKELETON: тонкий @lazySingleton Dio-обёртка (см. §7а)
    api/item/get_items_api.dart  # SKELETON: mock-источник (FR-013)
    # --- TARGET-форма REST-слоя (приходит с реальным бэкендом NOX) ---
    # api/base/base_api_repository.dart
    # request_builder/base/request_builder.dart
    # request_builder/base/request_builder_helper.dart
    # request_builder/item/get_items_api_request_builder.dart
  repository/
    app_config/app_config_repository_impl.dart
    item/item_repository_impl.dart
    log_repository_impl.dart
```

> **SKELETON vs полный блюпринт.** В скелете Feature-001 реально присутствуют только закомментированные «SKELETON»-файлы выше: тонкий `ApiClient` (`remote/api_client.dart`), mock-`GetItemsApi` (`remote/api/item/get_items_api.dart`) и network-only `ItemRepositoryImpl`. Папка `remote/request_builder/`, `BaseApiRepository` и per-feature DAO-обвязка — это **TARGET-форма**, к которой слой растёт по мере появления реального бэкенда NOX и первой кэшируемой фичи (см. §6, §7, §8). Блюпринт даёт обе формы; пометки SKELETON/TARGET показывают, что уже построено, а что — канон-к-построению.

> `path_provider` — обязательная зависимость `pubspec.yaml`: файловый бэкенд Sembast (`databaseFactoryIo`) резолвит путь к базе через `getApplicationDocumentsDirectory()`.

---

## 1. Сущности (entities / DTO)

Entities — `@freezed` **и** `json_serializable`: имеют обе `part`-директивы (`.freezed.dart` и `.g.dart`) и фабрику `fromJson`. Поля используют **только базовые типы**: `String`, `int`, `double`, `bool` и их `List`. Никаких enum-как-enum, никаких `DateTime`, никакого `BigInt`. `status`-enum хранится как его `name` (String); `created_at` — как ISO-8601 String. Nullable там, где API отдаёт nullable. **Вся** коэрция выполняется в маппере (§4).

> **`Item` — нейтральный blueprint-шаблон, не реальная сущность.** `ItemEntity` / `ItemModel` / `ItemRepository` по всему документу — это обобщённый плейсхолдер, демонстрирующий форму слоя; они НЕ описывают конкретный домен. Контракт реальных сущностей (поля, форма envelope, статусы) **бэкенд/протокол NOX ещё не выбран** и появится вместе с первой фичей реализации. Настоящие модели (например сущность чата для первой реальной фичи — списка чатов) появляются как результат **первой фичи реализации**, а не вписываются в blueprint — здесь фиксируется только паттерн, по которому они строятся.

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
    required String status, // ItemStatus enum name
    required String createdAt, // ISO-8601 string
    required String? description,
  }) = _ItemEntity;

  factory ItemEntity.fromJson(Map<String, dynamic> json) => _$ItemEntityFromJson(json);
}
```

> Вложенные коллекции (например `List<TagEntity>` через `@Default(<TagEntity>[])`) — иллюстративное расширение, **не** часть скелетного `ItemEntity`: в коде у него ровно эти пять полей. Любое такое поле остаётся базово-типизированным entity и резолвится дочерним маппером (§4).

### Entity-обёртка страницы (page wrapper)

Серверный список-эндпойнт отдаёт **срез страницы плюс offset-метаданные**: `items` + `page` + `page_size` + `total`. Это и есть форма ответа `GetItemsApi` (через network-only `getItems`, §8). Та же обёртка пригодна как single-record store, если DAO решит держать список в одной записи (альтернативный вариант DAO, §6).

`lib/data/entity/item/items_entity.dart`:

```dart
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';

part 'items_entity.freezed.dart';
part 'items_entity.g.dart';

/// Page wrapper: a page slice plus server offset metadata. JSON key names are an
/// example — backend/protocol not chosen; replace with the real contract.
@freezed
abstract class ItemsEntity with _$ItemsEntity {
  const factory ItemsEntity({
    @Default(<ItemEntity>[]) List<ItemEntity> items,
    @JsonKey(name: 'page') required int page,
    @JsonKey(name: 'page_size') required int pageSize,
    @JsonKey(name: 'total') required int total,
  }) = _ItemsEntity;

  factory ItemsEntity.fromJson(Map<String, dynamic> json) => _$ItemsEntityFromJson(json);
}
```

> Имена JSON-ключей (`page` / `page_size` / `total`) — **пример; бэкенд/протокол NOX ещё не выбран**, заменить на реальный контракт. Load-bearing — это форма обёртки (срез + offset-метаданные), а не конкретные имена. Канон вычисления `PageMetadata` из этой обёртки (`hasMore = (page * pageSize) < total`) — в §8.

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

/// Unified backend envelope (example — backend/protocol not chosen; replace with
/// the real contract). The load-bearing mechanism is the generic `T?` resolved
/// by EntityConverter.
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({@Default(false) bool success, String? error, @EntityConverter() T? data}) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
```

> Поля `success` / `error` / `data` подгоняются под реальный envelope бэкенда NOX (*пример контракта, заменить на реальный backend NOX*; протокол ещё не выбран). На деле envelope-пример кладёт полезную нагрузку в `data`, а служебное — в `timestamp` / `trace_id` / `meta`; если они нужны на клиенте, добавь соответствующие nullable-поля. Механизм, который надо сохранить, — генерик `T?`, резолвимый `JsonConverter`'ом.

---

## 3. `EntityConverter<E>` — ручной реестр типов

Это единственный кусок **ручной бухгалтерии** в архитектуре. `EntityConverter<E>` — `JsonConverter`, диспетчеризующий генерик `T` из `ResponseEntity<T>` в нужный entity. **Каждый entity, доступный через `ResponseEntity<T>`, ОБЯЗАН быть зарегистрирован в ОБОИХ цепочках — `fromJson` и `toJson`** — иначе бросается `ArgumentError('No converter found')`.

В скелете Feature-001 реестр **пуст**: entity-ветки регистрируются вместе со своей фичей (US2 — `ItemEntity` / `ItemsEntity`). Ниже показана заполненная форма реестра — канон сопровождения; в коде сейчас на месте только `bool`-ветка и места под per-feature регистрацию.

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
    if ((json is bool && _isType<E, bool>()) || _isType<E, bool?>()) {
      return json as E;
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

Конкретный `ItemMapper` — выполняет round-trip `ItemEntity <-> domain.ItemModel`. `status` String парсится через `values.firstWhere(... orElse: ...)`; `createdAt` коэрцируется **защитно и в UTC** — `DateTime.tryParse(...)?.toUtc() ?? DateTime.now().toUtc()` на входе и `model.createdAt.toUtc().toIso8601String()` на выходе (битая дата не валит маппинг). `ItemStatus` импортируется из `domain/model/item/item_status.dart` (enum живёт в отдельном файле).

`lib/data/mapper/item/item_mapper.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

/// The single place where String<->enum and String<->DateTime coercion happens.
@lazySingleton
class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic> {
  @override
  ItemModel toModel({required ItemEntity entity, dynamic Function(dynamic entity)? ad}) {
    return ItemModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      status: ItemStatus.values.firstWhere((e) => e.name == entity.status, orElse: () => ItemStatus.draft),
      createdAt: DateTime.tryParse(entity.createdAt)?.toUtc() ?? DateTime.now().toUtc(),
    );
  }

  @override
  ItemEntity toEntity({required ItemModel model, dynamic Function(dynamic entity)? ad}) {
    return ItemEntity(
      id: model.id,
      name: model.name,
      description: model.description,
      status: model.status.name,
      createdAt: model.createdAt.toUtc().toIso8601String(),
    );
  }
}
```

> **Round-trip с оговоркой по дате.** Защитная коэрция даты не строго лоссless: невалидная ISO-строка коэрцируется в `DateTime.now().toUtc()` (а не падает). Это сознательный выбор — устойчивость к битым данным важнее буквального round-trip. Для остальных полей (id/name/status/description) round-trip симметричен. Пустую строку при необходимости нормализуй в `null` в `toModel` (`(description?.isEmpty ?? true) ? null : description`) — в скелетном `ItemModel` это не требуется (`description` пробрасывается как есть).

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

Слой данных **НЕ** заводит типизированную **транспортную** иерархию исключений (правило этого блюпринта — `ApiException` / `DaoException` / `BaseDomainExceptionHelper` намеренно отсутствуют). Но доменная модель ошибок **есть и типизирована маркером**: абстрактный `BaseRepositoryException` реализует каждая доменная ошибка, а общий enum `RepositoryException implements BaseRepositoryException` — это и есть набор кодов. `RepositoryResult.error` всегда несёт подтип `BaseRepositoryException`, не «голый» `Exception`/framework- error. Feature-специфичные исключения — это **отдельные enum'ы, реализующие тот же маркер** (см. [03-domain-layer.md](03-domain-layer.md)). Единственный механизм коэрции framework-ошибок в этот enum — тонкий mixin `BaseRepositoryHelper.execute<TD>()`: он оборачивает асинхронную операцию репозитория в guarded try/catch, **обязательно** логирует через `LogRepository` и возвращает завершённый `RepositoryResult<TD>`.

`lib/data/exception/base_repository_helper.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Wraps a repository operation in try/catch, ALWAYS logs via LogRepository,
/// and coarsely maps framework errors to a domain RepositoryException.
/// Exactly two catch branches; no typed Dao/ApiException hierarchy.
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

> `DioException` — пример транспортной ошибки: ветка `on DioException` существует в коде, но **транспорт NOX ещё не выбран**. Когда бэкенд/протокол определят, набор «транспортных» исключений в первой catch-ветке скорректируют под реальный клиент; load-bearing — это сам паттерн «две ветки → коэрсный маппинг в `RepositoryException`», а не конкретно `DioException`.

Ключевое:

- **`executionFunction` возвращает уже-обёрнутый `RepositoryResult<TD>`** (не «голые» данные). Каждый call-site внутри `execute` сам строит результат: `return RepositoryResult.success(data: …)` на успехе, или `return RepositoryResult.error(exception: RepositoryException.<code>)` для конкретного доменного кода. `execute` лишь перехватывает **необработанные** исключения.
- **Две catch-ветки:** `DioException` (пример транспорта) → `RepositoryException.internal`; любой другой `catch` → `RepositoryException.unknown`. Никаких `ApiException` / `DaoException` / `BaseDomainExceptionHelper` — минимальная обработка, конкретику решает сам callback.
- **Логирование ОБЯЗАТЕЛЬНО** в каждой ветке (через `logRepository` — алиас из `lib/di/global_aliases.dart`, см. [02-dependency-injection.md](02-dependency-injection.md)), ПЕРЕД возвратом. Никакого сырого `print`.
- Импл подмешивает **`with BaseRepositoryHelper`** (без `on`-ограничения) и оборачивает каждый публичный метод в `execute<T>()`.

> **Конкретные доменные коды — в callback'е, не в catch.** Если нужен код точнее, чем `internal`/`unknown` (например `notFound` при cache-miss, `unauthenticated` при 401), верни его **внутри** `executionFunction` явным `return RepositoryResult.error(exception: RepositoryException.<code>)` (проверив `response.statusCode` или отсутствие записи). Пример — `fetchItem` в §8 (полная форма). `RepositoryException` (`unknown` / `internal` / `authentication` / `connection` / `unauthenticated` / `notFound`) определён в [03-domain-layer.md](03-domain-layer.md) и реализует маркер `BaseRepositoryException`.

---

## 6. Sembast DAO (реактивный)

> **Локальная БД — Sembast (OQ-1 закрыт 2026-06-08).** Документная NoSQL, **schema-less** (хранит JSON-maps → миграций как класса нет: новые/отсутствующие поля гасятся дефолтами в маппере), чистый Dart без codegen, реактивные стримы (`onSnapshots`). Набор: `sembast` + `shared_preferences` (флаги/`themeMode`) + `flutter_secure_storage` (секреты, *например refresh-токен — бэкенд/протокол NOX ещё не выбран*). **Единый подход на все платформы, включая web:** mobile/desktop — `sembast_io` (`databaseFactoryIo`), Test — `databaseFactoryMemory`, **web (будущий клиент)** — `sembast_web` (`databaseFactoryWeb`, IndexedDB/WASM); код DAO/репозиториев не меняется — за абстракцией `AppDatabase` подменяется только фабрика. Отвергнуты: ObjectBox/Realm (нет web), Drift/PowerSync (реляционные), Isar (web только через community-форк + типизированная схема требует миграций). Контракты репозиториев (`03-domain-layer.md`) и потребители от БД не зависят.

DAO используют `StoreRef<String, Map<String, dynamic>>`, отдают реактивные потоки через `onSnapshots()` / `onSnapshot()` и поддерживают атомарные записи через `db.transaction()`. **Типизированного `DaoException` нет** — при сбое хранилища исключения самого Sembast **пробрасываются наружу** (DAO их не оборачивает в свой тип), а ловит их catch-all ветка `execute()` репозитория → `RepositoryException.unknown`. Cache-miss / not-found — это **не** забота DAO: DAO просто отдаёт `null` / пустой список, а проверку отсутствия и `RepositoryException.notFound` решает callback репозитория (полная форма, §8). Битые записи **пропускаются** при декодировании (`_tryDecode` → `null`), а не убивают поток.

**Первичный шаблон — per-ID records store** (как в реальном коде): `stringMapStoreFactory.store('items')`, ключ записи = `item.id`, отдельный `getById(String id)`, реактивный `watch()` как `Stream<List<ItemEntity>> async*` (не `Future<Stream>`). Это форма по умолчанию для кэшируемого ресурса. Single-record «коллекционный» store (одна запись держит весь список через `ItemsEntity`) — **альтернативный вариант** в конце секции.

`lib/data/local/item/item_dao.dart`:

```dart
import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

/// Sembast store for the cacheable single `Item` entity — the reference
/// cache-first DAO for the skeleton.
///
/// Network-only carve-out (data-model §2.4): the paginated `getItems` list is a
/// server-owned list and goes through the network-only branch, so it does NOT
/// use this DAO. The DAO exists for the `watch()` (reactive cache) path and gets
/// wired up with the first genuinely cacheable feature. A broken record is
/// skipped rather than killing the stream; a storage failure throws raw and is
/// mapped to RepositoryException.unknown by the repository's catch-all execute().
@lazySingleton
class ItemDao {
  ItemDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StoreRef<String, Map<String, dynamic>> _store = stringMapStoreFactory.store('items');

  /// Reactive stream of all cached records (keyed by id). Broken records are
  /// dropped, so a single corrupt entry never tears down the stream.
  Stream<List<ItemEntity>> watch() async* {
    final db = await _appDatabase.db;
    yield* _store.query().onSnapshots(db).map(_decode);
  }

  /// One-shot read of every cached record.
  Future<List<ItemEntity>> getData() async {
    final db = await _appDatabase.db;
    return _decode(await _store.query().getSnapshots(db));
  }

  /// One-shot read of a single record by id; null if absent or corrupt.
  Future<ItemEntity?> getById(String id) async {
    final db = await _appDatabase.db;
    final value = await _store.record(id).get(db);
    return value == null ? null : _tryDecode(value);
  }

  /// Atomically write/replace a batch of records.
  Future<void> saveData(List<ItemEntity> items) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final item in items) {
        await _store.record(item.id).put(txn, item.toJson());
      }
    });
  }

  /// Atomic upsert of a single record.
  Future<void> upsert(ItemEntity item) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(item.id).put(txn, item.toJson());
    });
  }

  /// Delete a single record by id.
  Future<void> removeById(String id) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.record(id).delete(txn);
    });
  }

  /// Drop every record in the store.
  Future<void> cleanData() async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      await _store.delete(txn);
    });
  }

  List<ItemEntity> _decode(List<RecordSnapshot<String, Map<String, dynamic>>> snapshots) {
    final result = <ItemEntity>[];
    for (final snapshot in snapshots) {
      final entity = _tryDecode(snapshot.value);
      if (entity != null) result.add(entity);
    }
    return result;
  }

  /// A corrupt record decodes to null (skipped) instead of throwing.
  ItemEntity? _tryDecode(Map<String, dynamic> value) {
    try {
      return ItemEntity.fromJson(value);
    } catch (_) {
      return null;
    }
  }
}
```

> **Сигнатуры — позиционные, без обёртки в `StateError`.** `saveData(List<ItemEntity>)` / `upsert(ItemEntity)` / `removeById(String)` принимают позиционный аргумент; `cleanData()` чистит store целиком в транзакции. DAO **не** оборачивает сбои хранилища в `StateError` — исключения Sembast летят наружу и попадают в catch-all `execute()` репозитория. `_tryDecode` гасит битую запись в `null`, а `_decode` её пропускает: один сбойный документ не валит долгоживущий `watch()`-поток.

**Альтернативный вариант DAO — single-record «коллекционный» store.** Когда весь список удобнее хранить одной записью (`ItemsEntity`-в-одной-записи), используй `StoreRef<String, Map<String, dynamic>>.main()` с фиксированным ключом и singular `_store.record(key).onSnapshot(db)` для стриминга. Атомарный read-modify-write — канонический примитив мутации:

```dart
// Single-record collection store (alternative): one record holds the whole list.
final _store = StoreRef<String, Map<String, dynamic>>.main();
static const _storeKey = 'item_';

Future<void> mutate({
  required ItemEntity Function(ItemEntity current) mutator,
  required String id,
}) async {
  final db = await _appDatabase.db;
  await db.transaction((txn) async {
    final raw = await _store.record(_storeKey).get(txn);
    final current = raw != null ? ItemsEntity.fromJson(raw).items : <ItemEntity>[];
    final target = current.firstWhere((e) => e.id == id);
    final updated = mutator(target);
    final next = [...current.where((e) => e.id != id), updated];
    await _store.record(_storeKey).put(txn, ItemsEntity(items: next, page: 1, pageSize: next.length, total: next.length).toJson());
  });
}
```

> В коллекционном варианте `notFound` всё равно решает **callback репозитория**: для точного кода проверь отсутствие записи в callback'е и верни `RepositoryResult.error(exception: RepositoryException.notFound)` явно, а не полагайся на сырое исключение из `firstWhere`.

> **`AppDatabase` (env-scoped).** Сама база — `abstract AppDatabase` (интерфейс: `Future<Database> get db;` + `Future<void> clearEntireDatabase();`) с тремя реализациями, привязанными к `Environment` через `@LazySingleton(as: AppDatabase, env: [...])`: `AppDatabaseDev`/`AppDatabaseProd` на `databaseFactoryIo` (файл под app-documents directory; mobile/desktop, web — будущий `databaseFactoryWeb`), `AppDatabaseTest` на `databaseFactoryMemory` (эфемерная in-memory). Сброс БД — единый `clearEntireDatabase()` (удаляет файл/in-memory и обнуляет хэндл); per-DAO `cleanData()` чистит свой store. Полный шаблон провайдеров и почему env-список «load-bearing» — в `02-dependency-injection.md`. Здесь DAO просто инжектирует `AppDatabase` и не знает, какой env активен.

---

## 7. REST-слой

### 7а. Dio `ApiClient`

**SKELETON (реальный код).** Один host, один экземпляр Dio. Сейчас `ApiClient` — тонкий `@lazySingleton` с единственным полем `dio` (только таймауты). Base URL, auth-interceptor, HMAC/security-заголовки и источник токена — **пример/TBD: бэкенд/протокол NOX ещё не выбран**.

`lib/data/remote/api_client.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

/// Thin Dio wrapper. Base URL, auth interceptor, HMAC/security headers and the
/// token source are example/TBD (backend & protocol not chosen) — see
/// contracts/build-flavors.md and blueprint 14-networking-and-auth.md.
@lazySingleton
class ApiClient {
  ApiClient() : dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)));

  final Dio dio;
}
```

**TARGET-форма (приходит с реальным бэкендом NOX).** Когда бэкенд выберут, `ApiClient` дорастает до фабрики, навешивающей auth-interceptor, который читает токен **асинхронно** из `AppConfigRepository` на каждом запросе (расширяй interceptor, а не добавляй заголовки по-API). Модель токенов (Bearer / access-refresh) и геттеры `config.apiUrl` / `getUserAuthIdToken` — **пример; в текущем `AppConfigRepository` их ещё нет**:

```dart
// TARGET (example/TBD — backend not chosen). File would live at
// remote/api/base/api_client.dart alongside BaseApiRepository.
import 'package:dio/dio.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

class ApiClient {
  static Dio initBase({String? contentType}) {
    final appConfigRepository = getIt<AppConfigRepository>();
    final baseOptions = BaseOptions(
      baseUrl: '${appConfigRepository.config.apiUrl}/api/', // example/TBD: config.apiUrl not yet present
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: contentType ?? 'application/json',
      responseType: ResponseType.json,
    );
    final dio = Dio(baseOptions);

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await appConfigRepository.getUserAuthIdToken; // example/TBD: token source not yet present
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
}
```

> На non-2xx Dio бросает `DioException`, который **пробрасывается до** `BaseRepositoryHelper.execute()` и попадает в его ветку `on DioException` → `RepositoryException.internal`. API-класс **не** маппит ошибку в типизированный `ApiException` (его в проекте нет).

> **Хук наблюдаемости.** Подключай HTTP-трекинг наблюдаемости в эти interceptor'ы (`onRequest`/`onResponse`/`onError`).
>
> **HMAC/безопасность (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт).** Если бэкенд NOX потребует подписанные запросы (*пример*: `x-request-timestamp` + HMAC-SHA256 + security-заголовки), эти заголовки — тоже зона interceptor'а: добавь отдельный `InterceptorsWrapper`, считающий подпись по каноническому формату (*в этом примере* серверный канонический verb — это `ApiRequestMethod.<lowercase>`, не `GET`/`POST`). Точная формула строки подписи (включая хеш тела запроса) — в [14-networking-and-auth.md](14-networking-and-auth.md) §4 (тоже размеченный пример). Это **архитектурный контракт** — конкретную схему подписи и security-заголовки определяй вместе с реальным бэкендом NOX перед реализацией, не выбирай молча.

### 7б. `BaseApiRepository` (TARGET)

> **TARGET-форма.** `BaseApiRepository` появляется вместе с request-builder-обвязкой и реальным бэкендом NOX; в скелете его ещё нет (API-классы пока не наследуют общий базовый, а mock-`GetItemsApi` — обычный `@lazySingleton`).

`lib/data/remote/api/base/base_api_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  Dio get baseClient => ApiClient.initBase();
}
```

> **Свежий `Dio` на каждый доступ к `baseClient` — намеренное правило этого блюпринта, не дефект.** Геттер вызывает `ApiClient.initBase()` при каждом обращении, поэтому новый экземпляр создаётся на запрос. Токен всё равно читается асинхронно в interceptor'е **на каждый** запрос (§7а), так что свежесть авторизации обеспечена interceptor'ом, а не переиспользованием клиента. Это сознательное решение — не «оптимизируй» в singleton-Dio без согласования.

### 7в. `RequestBuilder` + `RequestBuilderHelper` (TARGET)

> **TARGET-форма.** Папки `remote/request_builder/` в скелете ещё нет — она приходит с реальным бэкендом NOX. Ниже — канон-к-построению.

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

**SKELETON (реальный код).** `GetItemsApi` — `@lazySingleton` **mock-источник** (верификационный harness, FR-013): отдаёт 47 фейковых `ItemEntity` с задержкой 150 мс и **сам строит** `ResponseEntity<ItemsEntity>` напрямую (без Dio, без request-builder'а). Это и есть текущее состояние REST-слоя по `getItems`.

`lib/data/remote/api/item/get_items_api.dart`:

```dart
import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/entity/item/items_entity.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

/// Skeleton MOCK source for the Item harness (no real backend — FR-013). The
/// real impl wraps a Dio request builder around `ResponseEntity<ItemsEntity>`
/// (path `v1/items`, query `page`/`page_size`/`search`) — example/TBD until the
/// NOX backend is chosen.
@lazySingleton
class GetItemsApi {
  static const int _mockTotal = 47;

  Future<ResponseEntity<ItemsEntity>> execute({required GetItemsConfig config}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    const pageSize = GetItemsConfig.pageSize;
    final start = (config.page - 1) * pageSize; // 1-based page (defaultPage = 1)
    final now = DateTime.now().toUtc().toIso8601String();
    final items = <ItemEntity>[
      for (var i = start; i < start + pageSize && i < _mockTotal; i++)
        ItemEntity(id: 'item_$i', name: 'Item #$i', status: 'active', createdAt: now, description: null),
    ];
    return ResponseEntity<ItemsEntity>(
      success: true,
      data: ItemsEntity(items: items, page: config.page, pageSize: pageSize, total: _mockTotal),
    );
  }
}
```

**TARGET-форма (приходит с реальным бэкендом NOX).** Именование API: `{verb}_{resource}_api.dart`. Класс расширяет `BaseApiRepository` и подмешивает `RequestBuilderHelper<TheBuilder>`. Форма: построить path → вызвать Dio → завернуть `response.data` в `ResponseEntity<T>.fromJson`. На non-2xx Dio бросает `DioException` — его **не** перехватывают и **не** маппят на типизированный `ApiException`: исключение пробрасывается до `BaseRepositoryHelper.execute()`, где ветка `on DioException` отдаёт `RepositoryException.internal`.

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
      queryParams['search'] = search; // wire param matches GetItemsConfig.search
    }
    queryParams['page'] = config.page.toString(); // 1-based (GetItemsConfig.defaultPage = 1)
    queryParams['page_size'] = GetItemsConfig.pageSize.toString();

    return super.buildPath(config, basePath, params: queryParams);
  }
}
```

```dart
// TARGET get_items_api.dart (Dio + request-builder form; example/TBD — backend not chosen).
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
    final path = await buildPath(config, 'v1/items'); // path 'v1/items' is an example — endpoint TBD with NOX backend
    final response = await baseClient.get(path);
    return ResponseEntity<ItemsEntity>.fromJson(response.data);
  }
}
```

> **REST-поток (TARGET):** `RequestBuilder` превращает доменный конфиг в `body`/`path`/`headers` → `RequestBuilderHelper` резолвит builder из `getIt` → API-класс шлёт через `baseClient`, оборачивает `response.data` в `ResponseEntity<T>.fromJson` (генерик `T` резолвится `EntityConverter`'ом) → на non-2xx Dio бросает `DioException`, который не перехватывается на уровне API. Репозиторий оборачивает вызов в `execute<T>()`, где ветка `on DioException` логирует и отдаёт `RepositoryResult.error(exception: RepositoryException.internal)`. В скелете весь этот поток сжат в mock-`GetItemsApi` выше; форма ответа (`ResponseEntity<ItemsEntity>` со срезом + offset-метаданными) сохраняется и в mock'е, и в TARGET.

---

## 8. Реализация репозитория

### 8.0. SKELETON — network-only `ItemRepositoryImpl` (реальный код)

В скелете Feature-001 `ItemRepository` сознательно **узкий**: контракт `03-domain-layer.md` для harness'а экспонирует **только** `getItems(...)` (network-only carve-out) + `clean()`; полный кэш-first CRUD (`watchItem`/`fetchItem`/`createItem`/`updateItem`/`deleteItem` + `ItemDao` + `BehaviorSubject`) — это **полная форма блюпринта** (§8.1), которая приходит с первой кэшируемой фичей. Так что реальный `ItemRepositoryImpl` инжектирует только маппер + (mock-)API, без DAO, без subject, без `dispose`:

`lib/data/repository/item/item_repository_impl.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/data/remote/api/item/get_items_api.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

/// Network-only paginated list (no DAO/subject — carve-out). Skeleton source is
/// a mock (FR-013). Wraps every call in BaseRepositoryHelper.execute (logs via
/// LogRepository, maps errors to RepositoryException).
@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._itemMapper, this._getItemsApi);

  final ItemMapper _itemMapper;
  final GetItemsApi _getItemsApi;

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _getItemsApi.execute(config: config);
      final entity = response.data;
      if (entity == null) {
        return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
      }
      final models = _itemMapper.toListModel(entities: entity.items);
      final hasMore = (entity.page * entity.pageSize) < entity.total;
      final metadata = PageMetadata(total: entity.total, nextPage: hasMore ? entity.page + 1 : null);
      return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
    });
  }

  @override
  Future<void> clean() async {}
}
```

Скелетные инварианты, которые надо держать и в полной форме:

- **`@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])`** — env-список load-bearing (Sembast-база env-scoped; пропуск env оставит репозиторий без биндинга базы в этом окружении), даже у network-only-репозитория.
- **`with BaseRepositoryHelper`** (без `on`-ограничения) + каждый публичный метод обёрнут в `execute<TD>()`; callback **сам возвращает уже-обёрнутый** `RepositoryResult<TD>`.
- **Пустой payload → `RepositoryException.unknown` прямо в callback'е** (так в коде: `if (entity == null) return ...error(unknown)` — без `throw StateError`). Логирования здесь нет: `unknown` — нормальный доменный исход; необработанные исключения логирует и коэрцирует сам `execute`.
- **`PageMetadata` из обёртки страницы:** `hasMore = (page * pageSize) < total`; `nextPage = hasMore ? page + 1 : null`; `total = entity.total`. Это канон для всех серверных пагинированных списков (см. подсекцию «network-only carve-out» ниже и `07-pagination.md`) — никакой эвристики «по длине страницы».
- **`clean()`** в скелете — no-op (`Future<void>.value()` через `async {}`); в полной форме он отменяет подписку и чистит DAO/subject.

### 8.1. Полная форма — кэш-first реактивный репозиторий (TARGET)

> **TARGET-форма (приходит с первой кэшируемой фичей).** Ниже — флагманский паттерн для user-scoped watchable-ресурсов. Это **канон-к-построению**, а не текущий скелет: `ItemDao`, `BehaviorSubject`, `watchItem`/`fetchItem`/CRUD и `GetItemConfig` (single-resource config) в коде пока **отсутствуют** — они появляются вместе с фичей, которой нужно кэширование. Network-only `getItems` (§8.0) остаётся в этой же полной форме без изменений.

Полная форма `ItemRepositoryImpl` реализует расширенный контракт `ItemRepository` (`watchItem`/`fetchItem`/`getItems`/`createItem`/`updateItem`/`deleteItem`/`clean`) и:

- несёт тот же `@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])` — **env-список load-bearing**;
- подмешивает `with BaseRepositoryHelper` и оборачивает **каждый** вызов в `execute<TD>()` (обязательное логирование необработанных исключений + коэрсный маппинг `DioException`→`internal` / else→`unknown`); callback **сам возвращает уже-обёрнутый** `RepositoryResult<TD>`;
- подписывается на DAO-поток **один раз** в конструкторе (`_initSubscription`), маппит entities и кормит ОДИН `BehaviorSubject<RepositoryResult<List<ItemModel>>>` — кэш-источник, из которого `watchItem({id})` отдаёт реактивный поток одного ресурса по id;
- читает `RepositoryResult` через `result.hasData`/`match`, **никогда** не `result.data!` за пределами проверенной ветки;
- `@disposeMethod` отменяет подписку и закрывает subject.

`lib/data/repository/item/item_repository_impl.dart` (TARGET):

```dart
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
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
import 'package:nox_app/domain/repository/item/get_item_config.dart'; // TARGET-only: single-resource config (not in skeleton)
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
    // A refresh failure becomes a RepositoryResult.error EMITTED INTO the stream
    // (not a raw async* error) so the subscriber sees it via match(onError:),
    // mirroring BaseRepositoryHelper.execute's coercive mapping.
    if (!_itemsStreamController.hasValue) {
      try {
        await _refreshFromNetwork();
      } catch (e, stackTrace) {
        logRepository.error(target: this, error: e, stackTrace: stackTrace);
        yield RepositoryResult<ItemModel>.error(
          exception: e is DioException ? RepositoryException.internal : RepositoryException.unknown,
        );
        return;
      }
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

      // tri-state cacheOnly (03 §5.4): cacheOnly == true means cache-only —
      // on a cache miss return notFound DIRECTLY, never hit the network.
      if (entity == null && config.cacheOnly == true) {
        return RepositoryResult<ItemModel>.error(exception: RepositoryException.notFound);
      }

      // Cache miss (cacheOnly null/false) -> network refresh, then re-read from cache.
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
    await _itemDao.saveData(page.items); // positional arg matches the per-ID DAO
  }

  // --- Paginated server-owned list (network-only carve-out) ------------------

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    // NETWORK-ONLY: no DAO, no BehaviorSubject. See 07-pagination.md.
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _getItemsApi.execute(config: config);
      final entity = response.data;
      if (entity == null) {
        return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
      }
      final models = _itemMapper.toListModel(entities: entity.items);
      final hasMore = (entity.page * entity.pageSize) < entity.total;
      final metadata = PageMetadata(total: entity.total, nextPage: hasMore ? entity.page + 1 : null);
      return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
    });
  }

  // --- Mutations -------------------------------------------------------------

  @override
  Future<RepositoryResult<ItemModel>> createItem({required ItemModel item}) {
    return execute<ItemModel>(() async {
      await _itemDao.upsert(_itemMapper.toEntity(model: item));
      return RepositoryResult<ItemModel>.success(data: item);
    });
  }

  @override
  Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item}) {
    return execute<ItemModel>(() async {
      await _itemDao.upsert(_itemMapper.toEntity(model: item));
      return RepositoryResult<ItemModel>.success(data: item);
    });
  }

  @override
  Future<RepositoryResult<void>> deleteItem({required String id}) {
    return execute<void>(() async {
      await _itemDao.removeById(id);
      return RepositoryResult<void>.success(data: null);
    });
  }

  @override
  Future<void> clean() async {
    // Full form: cancel the subscription, close the subject, wipe the store.
    await _itemsSubscription?.cancel();
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
- callback `execute<TD>()` **сам возвращает уже-обёрнутый** `RepositoryResult<TD>` — `return RepositoryResult.success(data: …)` на успехе. Для конкретного доменного кода (например `notFound` при cache-miss, как в `fetchItem`) верни его прямо в callback'е: `return RepositoryResult.error(exception: RepositoryException.<code>)`. `execute` лишь перехватывает **необработанные** исключения: `DioException`→`internal`, любой другой `catch`→`unknown`. Атомарная мутация по id через per-ID DAO:

```dart
Future<RepositoryResult<void>> _mutateItem({
  required String id,
  required ItemEntity Function(ItemEntity current) mutator,
}) {
  return execute<void>(() async {
    // Per-ID DAO: read the current record, mutate, upsert. Absence is a precise
    // domain code DECIDED HERE — return notFound directly, don't rely on a raw throw.
    final current = await _itemDao.getById(id);
    if (current == null) {
      return RepositoryResult<void>.error(exception: RepositoryException.notFound);
    }
    await _itemDao.upsert(mutator(current));
    return RepositoryResult<void>.success(data: null);
  });
}
```

### Когда НЕ использовать кэш-first: network-only carve-out

**Пагинированные серверные списки и one-shot POST — явное исключение из реактивного паттерна.** Они **network-only**: без DAO, без `BehaviorSubject`, без подписки. Это и есть метод `getItems({required GetItemsConfig config})` из контракта — он реализован прямо в `ItemRepositoryImpl` (и в скелетной §8.0, и в полной §8.1 форме одинаково): репозиторий просто бьёт по REST и возвращает `RepositoryResult<(List<ItemModel>, PageMetadata)>`. Никакого отдельного `getItemsPage`/`watchItems` для списка — пагинированный список это **`getItems`**.

```dart
// Paginated server-owned list: network-only, NO DAO, NO BehaviorSubject.
@override
Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
  return execute<(List<ItemModel>, PageMetadata)>(() async {
    final response = await _getItemsApi.execute(config: config);
    final entity = response.data;
    if (entity == null) {
      return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
    }
    final models = _itemMapper.toListModel(entities: entity.items);
    final hasMore = (entity.page * entity.pageSize) < entity.total;
    final metadata = PageMetadata(total: entity.total, nextPage: hasMore ? entity.page + 1 : null);
    return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
  });
}
```

> Первая реальная фича — **список чатов** (открытое общее пространство) — именно такая: это серверный, network-only пагинированный список, потому она идёт по network-only ветке (`getItems`). Дефолтный флавор пагинации — OFFSET (срез страницы + `page` + `page_size` + `total`), альтернатива — CURSOR; **конкретный контракт пагинации списка чатов финализируется позже вместе с бэкендом NOX** (бэкенд/протокол ещё не выбраны — имена ключей `page`/`page_size`/`total` пример/TBD). Канон вычисления `PageMetadata` (`hasMore = (page * pageSize) < total`, `nextPage = hasMore ? page + 1 : null`) — здесь, в §8; `07-pagination.md` описывает presentation-сторону поверх этого канона (дефолтный OFFSET-флавор `PageMetadata{int total, int? nextPage}`, альтернативный CURSOR, `PagingStateExt.applyPage`, проброс `result.exception` в `pagingState.error`). Не заводи DAO/subject для серверных пагинированных списков.

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
| `ApiClient` (SKELETON) | `remote/api_client.dart` | `@lazySingleton` (тонкий Dio-обёртка) |
| `GetItemsApi` (SKELETON, mock) | `remote/api/item/get_items_api.dart` | `@lazySingleton` |
| `ItemRepositoryImpl` | `repository/item/item_repository_impl.dart` | `@LazySingleton(as: ItemRepository, env: [dev, prod, test])` |
| `BaseApiRepository` (TARGET) | `remote/api/base/base_api_repository.dart` | абстрактный базовый (ещё нет в коде) |
| `RequestBuilder` / `RequestBuilderHelper` (TARGET) | `remote/request_builder/base/...` | базовый / mixin (ещё нет в коде) |
| `GetItemsApiRequestBuilder` (TARGET) | `remote/request_builder/item/get_items_api_request_builder.dart` | `@lazySingleton` (ещё нет в коде) |

После добавления/правки любого аннотированного класса — **один** прогон кодогенерации в корне единого пакета (см. `12-dev-commands.md`):

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

---

## Чеклист

- [ ] `ItemEntity` использует **только базовые типы**, ровно пять полей `id`/`name`/`status` (String-`name`)/`createdAt` (ISO-8601 String)/`description` (required-nullable); никаких `tags`/`DateTime`/enum-как-enum. `ItemsEntity` — page wrapper `{items, page, page_size, total}` с `@JsonKey` (имена ключей — пример/TBD).
- [ ] Все `part`-директивы стоят: entities имеют `.freezed.dart` **и** `.g.dart`; BLoC-типы и доменные модели (`ItemModel`) — только `.freezed.dart` (entity-слой — единственное место с `.g.dart`/`fromJson`).
- [ ] `ResponseEntity<T>` envelope (пример/TBD) + `EntityConverter<E>` реестр на месте; **каждый** новый entity, проходящий через `ResponseEntity<T>`, добавлен в ОБЕ цепочки (`fromJson` + `toJson`) `entity_converter.dart` (в скелете реестр пуст — ветки регистрируются per-feature).
- [ ] `ItemMapper` расширяет `BaseMapper` (4-арг, `dynamic, dynamic` для простого случая), коэрция enum через `name`/`firstWhere(orElse:)`, дата — защитно в UTC (`DateTime.tryParse(...)?.toUtc() ?? DateTime.now().toUtc()` / `.toUtc().toIso8601String()`); импортирует `item_status.dart`; дочерние мапперы инжектируются конструктором.
- [ ] **Нет** транспортной иерархии `DaoException` / `ApiException` / `BaseDomainExceptionHelper`; есть **маркер** `BaseRepositoryException`, который реализует `RepositoryException` (enum `{unknown, internal, authentication, connection, unauthenticated, notFound}`) и любые feature-enum'ы; `RepositoryResult.error` всегда несёт подтип маркера. Единственный коэрсный механизм — `mixin BaseRepositoryHelper` с `execute<TD>(Function executionFunction)`; импл подмешивает **только** `with BaseRepositoryHelper` (без `on`-ограничения).
- [ ] `BaseRepositoryHelper.execute<T>()` имеет **ровно две** `catch`-ветки — `on DioException` (пример транспорта) → `RepositoryException.internal`, общий `catch` → `RepositoryException.unknown`; **обязательно** логирует через `LogRepository` в каждой ветке (никакого `print`) перед возвратом `RepositoryResult.error(...)`. Callback `executionFunction` сам возвращает уже-обёрнутый `RepositoryResult`; конкретный доменный код (`notFound`/`unknown` при пустом payload) — внутри callback'а, не в catch.
- [ ] `AppDatabase` env-scoped (интерфейс `db` + `clearEntireDatabase()`; `Dev`/`Prod` = `databaseFactoryIo`, `Test` = `databaseFactoryMemory`); `path_provider` — зависимость пакета; env-список в репозитории полный.
- [ ] `ItemDao` (PRIMARY) — **per-ID records store** `stringMapStoreFactory.store('items')`, ключ = `item.id`: `watch()` как `Stream<List<ItemEntity>> async*`, `getById(String)`, позиционные `saveData(List)`/`upsert(ItemEntity)`/`removeById(String)`/`cleanData()`, `_decode`/`_tryDecode` пропускают битую запись (`null`). DAO **не** оборачивает сбои в `StateError` — исключения Sembast летят в catch-all `execute()`. Cache-miss/not-found решает callback репозитория. Single-record collection store — альтернативный вариант.
- [ ] **SKELETON `ItemRepositoryImpl`** реализует **узкий** контракт `ItemRepository` (`getItems({GetItemsConfig config}) -> (List, PageMetadata)` + `clean() -> Future<void>`): инжектирует только маппер + (mock-)API, без DAO/subject/dispose; пустой payload → `RepositoryException.unknown` в callback'е; `PageMetadata` через `hasMore = (page * pageSize) < total`, `nextPage = hasMore ? page + 1 : null`; `clean()` — no-op. **Полный** env-список `@LazySingleton`. Полная (TARGET) форма добавляет `watchItem`/`fetchItem`/CRUD + `ItemDao` + ОДИН `BehaviorSubject` (подписка раз в конструкторе) + `@disposeMethod`, читает через `hasData`/`match` (не `result.data!`).
- [ ] REST **SKELETON**: тонкий `@lazySingleton ApiClient` (`remote/api_client.dart`) + mock-`GetItemsApi` (FR-013) строит `ResponseEntity<ItemsEntity>` напрямую. **TARGET**: `ApiClient.initBase()` (auth-interceptor, токен из `AppConfigRepository` асинхронно — пример/TBD) + `BaseApiRepository` + `RequestBuilder`/`RequestBuilderHelper`; API-класс оборачивает `response.data` в `ResponseEntity<T>.fromJson`; на non-2xx Dio бросает `DioException`, не перехватываемый на уровне API → `execute()` → `RepositoryException.internal` (никакого `ApiException`). Wire-параметр поиска — `search` (не `q`); `page` 1-based (`defaultPage = 1`).
- [ ] **Carve-out соблюдён:** пагинированные серверные списки + one-shot POST — network-only (без DAO, без subject), возвращают `RepositoryResult<(List<Model>, PageMetadata)>` (см. `07-pagination.md`). Первая реальная фича — список чатов; контракт пагинации финализируется с бэкендом NOX.
- [ ] `build_runner` перезапущен один раз в корне пакета после изменений аннотаций.

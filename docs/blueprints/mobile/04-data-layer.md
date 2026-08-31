# 04 — Слой данных

> **Назначение:** дать копипаст-готовые шаблоны слоя данных (`lib/data/`) — сущности (entities), генерик-конверт `ResponseEntity<T>` + ручной реестр `EntityConverter<E>`, мапперы, типизированные исключения, реактивные Sembast-DAO, REST-слой (Dio `ApiClient` + `RequestBuilder`/`RequestBuilderHelper` + API-классы) и реализации репозиториев. Слой данных **реализует** контракты из `03-domain-layer.md`.
> **Когда читать:** когда поднимаешь папку `lib/data/` или подключаешь конкретный `ItemRepositoryImpl` к его DAO + мапперу + REST-клиенту. Это авторитетный дом всех шаблонов слоя данных.
> **Связанные документы:** `03-domain-layer.md` (контракты, которые здесь реализуются), `05-presentation-layer.md` (потребляет репозитории), `02-dependency-injection.md` (`AppDatabase`, env-scoped провайдеры, `getIt`), `06-theming.md`, `07-pagination.md` (страничный путь списка чатов + seq-курсорный путь истории сообщений), `08-conventions-and-constitution.md` (правила именования и инвариантов), `10-code-templates.md` (индекс шаблонов), `12-dev-commands.md` (build_runner).

> **`watchX()` как change-signal (Feature 014).** Реактивные Sembast-`watch()`-стримы репозитория (`watchChats`/`watchMessages`) используются презентацией как **сигнал об изменении** кэша, а не как источник проекции: их значение игнорируется, а BLoC перечитывает уже загруженный префикс через тот же `getX` (см. `07-pagination.md`). Мутации, меняющие несколько сущностей (напр. `sendMessage` → сообщение + строка чата), выполняются в data-слое, поэтому реактивный список обновляется без связей между BLoC. См. `specs/014-reactive-data-refresh/`.

> **Reactive-канал не только над Sembast (Feature 015).** Тот же паттерн change-signal применим к не-Sembast источникам: `SessionRepository.watchLabel()` — это broadcast-`StreamController<String?>` над `shared_preferences`-меткой (не реактивной самой по себе). Он эмитит текущую метку при подписке (seed-then-live, как `watch()`-`async*`), затем каждое переименование (`updateLabel`) и `null` при `clear` (logout). Единый источник identity (технический идентификатор + label) резолвится чистой `resolveIdentity(SessionModel?)`; переименование меняет только label, идентификатор remain-invariant (own-detection в треде опирается на идентификатор). Живые surfaces (desktop rail-аватар) подписываются и обновляются без рестарта. См. `specs/015-identity-unification/`.

> **RemoteDataSource seam (Feature 016).** Сетевая граница каждой data-фичи — абстрактный интерфейс `*RemoteDataSource` (`lib/data/remote/datasource/`: `ChatRemoteDataSource`/`MessageRemoteDataSource`/`ItemRemoteDataSource`). Репо зависят **от интерфейса**, не от конкретного мока (dependency inversion). Мок-реализации (`Mock*RemoteDataSource`) делегируют неизменным `*Api`-генераторам и биндятся `@LazySingleton(as: Interface, env:[...])`. **Флип на бэкенд состоялся фазой 026** вместе с транспортом: `RealChatRemoteDataSource`/`RealMessageRemoteDataSource` (`remote/datasource/real/`) зарегистрированы на `[Environment.dev]`, их моки сужены до `[Environment.prod, Environment.test]` — репо/DAO/мапперы/`RepositoryResult`/`PageMetadata`/UI не тронуты, ровно как обещал seam. У `ItemRemoteDataSource` (замороженный верификационный срез) real-impl нет, и его мок по-прежнему покрывает `[dev, prod, test]`. `RepositoryResult`+catch-all `execute()` и HTTP→exception-маппинг (S3) остаются контрактом поверх seam. См. `specs/016-remote-datasource-seam/`. _(Feature 017 ретайрил `ChatFilesRemoteDataSource`: файлы чата — не сетевой ресурс, а локальная деривация из уже персистентных вложений `MessageDao` (`MessageRepository.chatFiles(chatId)`, newest-first). У файлов нет собственной сетевой границы — они появляются вместе с сообщениями, а сообщения уже проходят через `MessageRemoteDataSource`.)_

---

## Обзор и зона ответственности

Слой данных отвечает за:

- **Entities (DTO)** — `@freezed` + `json_serializable`, **только базовые типы** (`String`/`int`/`double`/`bool` + их `List`). Enum хранится как `.name` (String), `DateTime` — как ISO-8601 String. Любая коэрция отложена в маппер.
- **`ResponseEntity<T>` + `EntityConverter<E>`** — генерик-конверт ответа (контракт v0: `success` зеркалит `ok` reply-кадра, `error` — объект `{code, message}` §2.1) + ручной реестр типов, резолвящий генерик `T` в конкретный entity.
- **Мапперы** — двунаправленная конвертация `Entity <-> Model` (`BaseMapper`), где происходит ВСЯ коэрция типов (enum, `DateTime`, nullable-нормализация). Композиция дочерних мапперов через конструктор.
- **Обработка ошибок** — единственный механизм `BaseRepositoryHelper.execute<TD>()`: тонкий guarded try/catch, который **обязательно** логирует через `LogRepository` и возвращает `RepositoryResult.error(...)`. Четыре ветки: `on BaseRepositoryException` (уже доменная ошибка — пробрасывается **как есть**, не понижается до `unknown`), `on SocketUnavailableException` → `RepositoryException.connection` (фаза 026: без неё мёртвый сокет попадает в catch-all как `unknown`, и весь кэш-фоллбэк, завязанный на `connection`, становится недостижимым кодом), `on DioException` (маппинг по типу/статусу через `_mapDioException`), общий `catch` → `RepositoryException.unknown`. Там же живёт `unwrapEnvelope<TD>(ResponseEntity<TD>, String what)` — разворачивание конверта: payload, иначе `RepositoryException.fromWireCode(error.code)`, иначе `StateError`. **Нет типизированной транспортной иерархии** (`ApiException` / `DaoException` / `BaseDomainExceptionHelper` намеренно отсутствуют — правило этого блюпринта), но есть **маркер** `BaseRepositoryException`, который реализует каждая доменная ошибка: общий enum `RepositoryException` и любые feature-специфичные enum'ы реализуют этот маркер (см. §5 и `03-domain-layer.md`). Конкретный доменный код возвращает сам callback явным `return RepositoryResult.error(...)`.
- **DAO (Sembast)** — реактивное локальное хранилище: `onSnapshots()`/`onSnapshot()`, атомарные `db.transaction()`, env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory).
- **Репозитории** — реализуют контракты домена; **кэш-first — форма по умолчанию**: либо прямая подписка на DAO-поток (продуктовые `ChatRepositoryImpl`/`MessageRepositoryImpl`, фича 013), либо один `BehaviorSubject<RepositoryResult<...>>` (канон реактивного **одиночного** ресурса, §8.1). **Carve-out «пагинированный серверный список = network-only» ретайрен для продуктовых фич:** список чатов и история сообщений — кэш-first с DAO. Network-only (без DAO и subject) остаётся только у **замороженного верификационного среза `Item`** и у того, что действительно не кэшируется (см. §8 и `07-pagination.md`).

Направление зависимостей: `data` **реализует** контракты `domain`. `domain` не импортирует `data`. Конвертация между базово-типизированными entities и богатыми доменными моделями живёт исключительно в мапперах.

> **Единый пакет.** Все пути — `lib/data/...` внутри одного пакета `nox_app`. Никаких `data/lib/src/...` или path-зависимостей: слои — это папки одного `lib/`. Импорты — полные `package:nox_app/...`, без относительных `../`, кроме директив `part`.

### Раскладка папок слоя данных

```
lib/data/
  entity/
    base/response_entity.dart
    base/entity_converter.dart
    base/error_wire_entity.dart  # контрактный {code, message} (§2.1)
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
    chat/outbox_dao.dart         # очередь исходящих; ключ записи = client_message_id (027)
  sync/
    live_session_starter.dart    # подъём живой сессии: сокет + фазы + первичный sync (026)
    sync_service.dart            # применение событий журнала в DAO (026)
    outbox_service.dart          # слив очереди исходящих — единственный отправитель (027)
  remote/
    api_client.dart              # тонкий @lazySingleton Dio-обёртка + initBase() (см. §7а)
    interceptor/auth_interceptor.dart   # Bearer-заголовок + 401 -> forced logout (019/S5)
    datasource/item_remote_data_source.dart      # сетевая граница фичи (016)
    datasource/mock/mock_item_remote_data_source.dart
    datasource/real/real_chat_remote_data_source.dart     # команды поверх WS-конверта, env: [dev] (026)
    datasource/real/real_message_remote_data_source.dart
    datasource/real/socket_envelope.dart
    socket/nox_socket_client.dart        # клиент конверта: корреляция, фазы, реконнект, keepalive (026)
    socket/socket_channel_factory.dart   # узкий порт сокета + IOWebSocketChannel(pingInterval: 25s)
    socket/server_frame.dart
    api/item/get_items_api.dart  # mock-генератор верификационного среза (FR-013)
    # --- TARGET-форма request-builder-обвязки REST (ещё не построена) ---
    # api/base/base_api_repository.dart
    # request_builder/base/request_builder.dart
    # request_builder/base/request_builder_helper.dart
    # request_builder/item/get_items_api_request_builder.dart
  repository/
    app_config/app_config_repository_impl.dart
    item/item_repository_impl.dart
    log_repository_impl.dart
```

> **SKELETON vs полный блюпринт.** Из перечисленного выше `remote/request_builder/` и `BaseApiRepository` — единственная **TARGET-форма**: в коде их нет. Всё остальное построено: тонкий `ApiClient` с `initBase()` + `AuthInterceptor` (019/S5), `Mock*RemoteDataSource` за интерфейсом (016) и — с фазы 026 — `Real*RemoteDataSource` (`remote/datasource/real/`) поверх сокет-клиента конверта (`remote/socket/`), зарегистрированные в окружении `dev` (флейвор `stage`), тогда как чат/сообщенческие моки сужены до `[prod, test]`; network-only `ItemRepositoryImpl` верификационного среза, а кэш-first DAO-обвязка реализована для продуктовых фич (`local/chat/chat_dao.dart`, `message_dao.dart`, `local/chat/outbox_dao.dart`, `local/sync/sync_dao.dart`, фичи 013–027). Пометки SKELETON/TARGET по тексту показывают, что уже построено, а что — канон-к-построению; **`Item`-срез заморожен** как верификационный harness и не является продуктовым каноном.

> `path_provider` — обязательная зависимость `pubspec.yaml`: файловый бэкенд Sembast (`databaseFactoryIo`) резолвит путь к базе через `getApplicationDocumentsDirectory()`.

---

## 1. Сущности (entities / DTO)

Entities — `@freezed` **и** `json_serializable`: имеют обе `part`-директивы (`.freezed.dart` и `.g.dart`) и фабрику `fromJson`. Поля используют **только базовые типы**: `String`, `int`, `double`, `bool` и их `List`. Никаких enum-как-enum, никаких `DateTime`, никакого `BigInt`. `status`-enum хранится как его `name` (String); `created_at` — как ISO-8601 String. Nullable там, где API отдаёт nullable. **Вся** коэрция выполняется в маппере (§4).

> **`Item` — нейтральный blueprint-шаблон, не реальная сущность.** `ItemEntity` / `ItemModel` / `ItemRepository` по всему документу — это обобщённый плейсхолдер, демонстрирующий форму слоя; они НЕ описывают конкретный домен, и срез **заморожен намеренно** (верификационный harness Feature-001, включая его offset-обёртку и путь `v1/items`). Контракт реальных сущностей зафиксирован **wire-контрактом v0** (`docs/client-backend/protocol/contract-draft.md`) и реализован в `lib/data/entity/chat/wire/` (`ChatWireEntity`/`ChatsWireEntity`/`MessageWireEntity`/`MessagesWireEntity`, фаза 025). Здесь фиксируется только паттерн, по которому такие сущности строятся.

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

Обёртка **замороженного верификационного среза `Item`** отдаёт **срез страницы плюс offset-метаданные**: `items` + `page` + `page_size` + `total`. Это форма ответа `GetItemsApi` (через network-only `getItems`, §8), **а не продуктовый канон**: контрактные обёртки v0 несут только `has_more` (`{chats, has_more}` / `{messages, has_more}`, §4–5 контракта) и `total` на проводе не существует. Та же обёртка пригодна как single-record store, если DAO решит держать список в одной записи (альтернативный вариант DAO, §6).

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

> Имена JSON-ключей (`page` / `page_size` / `total`) — **заморожены вместе с верификационным срезом `Item`**; докстринг в самом файле всё ещё несёт до-025-ную формулировку «backend not chosen» — это остаточный текст harness'а, а не действующее утверждение. Продуктовый провод описан контрактом v0: `{chats, has_more}` / `{messages, has_more}`, без `page`-математики и без `total` в ответе. Load-bearing здесь — не имена, а то, что **вся** страничная арифметика сворачивается в `PageMetadata` в репозитории: для `Item`-среза `hasMore = (page * pageSize) < total` (§8), для контрактных обёрток `hasMore` приходит готовым.

> **Гарантия round-trip:** `toEntity(model: toModel(entity: e))` должно воспроизвести `e` точно, и наоборот. Базовые типы entity-слоя делают это детерминированным — все «лоссы» (enum → дефолт, нормализация пустой строки в `null`) живут в маппере и обязаны быть симметричны.

---

## 2. `ResponseEntity<T>` — генерик-конверт REST-ответа

Конверт реален с фазы 025 (контракт v0): `success` зеркалит `ok` reply-кадра, `error` несёт объект `{code, message}` (§2.1), полезная нагрузка — в `data`. `ResponseEntity<T>` — генерик-обёртка над ним; аннотация `@EntityConverter()` резолвит генерик `T` в `fromJson`/`toJson` конкретного entity.

`lib/data/entity/base/response_entity.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/base/entity_converter.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';

part 'response_entity.freezed.dart';
part 'response_entity.g.dart';

/// Unified data-source envelope over contract v0 replies: success mirrors the
/// wire `ok`, [error] carries the contract `{code, message}` object of a
/// failed reply, and the generic `T?` payload is resolved by EntityConverter.
@freezed
abstract class ResponseEntity<T> with _$ResponseEntity<T> {
  const factory ResponseEntity({@Default(false) bool success, ErrorWireEntity? error, @EntityConverter() T? data}) = _ResponseEntity<T>;

  factory ResponseEntity.fromJson(Map<String, dynamic> json) => _$ResponseEntityFromJson(json);
}
```

> Ошибка конверта — типизированный `ErrorWireEntity {code, message}` (фаза 025); её код мапится в `RepositoryException.fromWireCode` (незнакомый код → `internal`, правило эволюции §2.1), а `BaseRepositoryHelper.unwrapEnvelope` бросает её сквозь `execute()` без переупаковки. Механизм, который надо сохранить, — генерик `T?`, резолвимый `JsonConverter`'ом.

---

## 3. `EntityConverter<E>` — ручной реестр типов

Это единственный кусок **ручной бухгалтерии** в архитектуре. `EntityConverter<E>` — `JsonConverter`, диспетчеризующий генерик `T` из `ResponseEntity<T>` в нужный entity. **Каждый entity, доступный через `ResponseEntity<T>`, ОБЯЗАН быть зарегистрирован в ОБОИХ цепочках — `fromJson` и `toJson`** — иначе бросается `ArgumentError('No converter found')`.

В скелете Feature-001 реестр был **пуст**; **наполнен фичей 018/S4**: зарегистрированы все wire-сущности, достижимые через `ResponseEntity<T>` — `ItemEntity`/`ItemsEntity` (референс) + `ChatWireEntity`/`ChatsWireEntity` + `MessageWireEntity`/`MessagesWireEntity` (`lib/data/entity/chat/wire/`), в обеих цепочках. Неизвестный тип по-прежнему бросает `ArgumentError`. С S4 chat-list и message-list на сетевой границе идут через конверт единообразно с Item (генератор мапит model→wire и возвращает `ResponseEntity<wire>`; репо разворачивает wire→model). Wire-форма — только сетевая граница; локальные Sembast-сущности не тронуты. С фазы 025 wire-сущности выровнены по **контракту v0** (обёртки `{chats, has_more}` / `{messages, has_more}`), так что это уже не example/TBD. Ниже — заполненная форма реестра (канон сопровождения).

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
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Wraps a repository operation in try/catch, ALWAYS logs via LogRepository,
/// and coarsely maps framework errors to a domain RepositoryException.
///
/// FOUR catch branches, in this order, and the order is the point.
mixin BaseRepositoryHelper {
  Future<RepositoryResult<TD>> execute<TD>(Function executionFunction) async {
    try {
      return await executionFunction();
    } on BaseRepositoryException catch (e, stackTrace) {
      // An already-mapped domain failure (e.g. a wire error code from
      // unwrapEnvelope) passes through undiluted - never downgraded to
      // `unknown` by the catch-all.
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: e);
    } on SocketUnavailableException catch (e, stackTrace) {
      // The live channel is down, or a command went unanswered. Without this
      // branch it lands in the catch-all as `unknown`, and every cache fallback
      // guarded on `connection` becomes unreachable code (feature 026).
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.connection);
    } on DioException catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: _mapDioException(e));
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      return RepositoryResult<TD>.error(exception: RepositoryException.unknown);
    }
  }

  /// Unwraps a data-source envelope: the payload when present, otherwise the
  /// contract §2.1 error code mapped onto [RepositoryException] (an unknown
  /// code degrades to `internal` per the evolution rule), otherwise a bare
  /// StateError (malformed envelope) that the catch-all maps to `unknown`.
  TD unwrapEnvelope<TD>(ResponseEntity<TD> response, String what) {
    final data = response.data;
    if (data != null) return data;
    final error = response.error;
    if (error != null) throw RepositoryException.fromWireCode(error.code);
    throw StateError('$what envelope has no data (success=${response.success})');
  }

  /// Maps a transport error to a domain [RepositoryException] by connection type and
  /// HTTP status — the HTTP path (blob upload/download, phase 028). Envelope errors
  /// take the other route: [unwrapEnvelope] throws the code-mapped exception and the
  /// `on BaseRepositoryException` branch re-emits it unchanged.
  RepositoryException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return RepositoryException.connection;
      case DioExceptionType.badResponse:
        switch (e.response?.statusCode) {
          case 401:
            return RepositoryException.unauthenticated;
          case 403:
            return RepositoryException.authentication;
          case 404:
            return RepositoryException.notFound;
          default:
            return RepositoryException.internal;
        }
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return RepositoryException.internal;
    }
  }
}
```

> `DioException` — транспортная ветка для REST-поверхности. Живой канал команд **построен**: контракт v0 идёт WebSocket-конвертом, и сам конверт вместе с сокет-клиентом пришёл фазой 026 (`remote/socket/`, `remote/datasource/real/`), а REST остаётся только для blob upload/download (`file.uploadBegin` → `PUT`, `file.downloadBegin` → `GET` с `Range`). Отдельно от этого: `wss:443` с key pinning — **целевая форма транспорта, ещё не построенная**. `WebSocketChannelFactory` открывает голый `IOWebSocketChannel.connect(url, pingInterval: 25s)` — ни `SecurityContext`, ни `badCertificateCallback`, ни сверки отпечатка в `lib/` нет; `LiveSessionStarter._socketUrl` лишь переводит `https` → `wss`, поэтому локальный `http://127.0.0.1:8080` из `config/stage.json` даёт `ws://`. Ветка `on BaseRepositoryException` — это путь доменных кодов, поднятых из конверта `unwrapEnvelope`; load-bearing здесь — «четыре ветки: уже-доменная ошибка сквозь, мёртвый сокет → `connection`, транспорт по типу/статусу, всё остальное → `unknown`». Сокет-ветка стала load-bearing именно в мире 026+: она и есть то, что делает кэш-фоллбэк достижимым.

Ключевое:

- **`executionFunction` возвращает уже-обёрнутый `RepositoryResult<TD>`** (не «голые» данные). Каждый call-site внутри `execute` сам строит результат: `return RepositoryResult.success(data: …)` на успехе, или `return RepositoryResult.error(exception: RepositoryException.<code>)` для конкретного доменного кода. `execute` лишь перехватывает **необработанные** исключения.
- **Три catch-ветки:** `BaseRepositoryException` → пробрасывается **как есть** (доменный код из `unwrapEnvelope` не размывается); `DioException` → `_mapDioException` (таймауты/`connectionError` → `connection`; 401 → `unauthenticated`; 403 → `authentication`; 404 → `notFound`; иначе `internal`); любой другой `catch` → `RepositoryException.unknown`. Никаких `ApiException` / `DaoException` / `BaseDomainExceptionHelper` — минимальная обработка, конкретику решает сам callback.
- **Разворачивание конверта — `unwrapEnvelope<TD>(response, what)`** того же mixin'а: вернуть `data`, иначе бросить `RepositoryException.fromWireCode(error.code)` (незнакомый код → `internal`), иначе `StateError` про кривой конверт. Бросок ловит первая ветка `execute` и отдаёт тот же доменный код наружу.
- **Логирование ОБЯЗАТЕЛЬНО** в каждой ветке (через `logRepository` — алиас из `lib/di/global_aliases.dart`, см. [02-dependency-injection.md](02-dependency-injection.md)), ПЕРЕД возвратом. Никакого сырого `print`.
- Импл подмешивает **`with BaseRepositoryHelper`** (без `on`-ограничения) и оборачивает каждый публичный метод в `execute<T>()`.

> **Конкретные доменные коды — в callback'е, не в catch.** Если нужен код точнее, чем `internal`/`unknown` (например `notFound` при cache-miss, `unauthenticated` при 401), верни его **внутри** `executionFunction` явным `return RepositoryResult.error(exception: RepositoryException.<code>)` (проверив `response.statusCode` или отсутствие записи). Пример — `fetchItem` в §8 (полная форма). `RepositoryException` (`unknown` / `internal` / `authentication` / `connection` / `unauthenticated` / `notFound` + контрактные коды §2.1 `invalidRequest` / `nameTaken` / `payloadTooLarge` / `attachmentGone` / `rateLimited` / `unsupportedSchema`, плюс статический `RepositoryException.fromWireCode(String)`) определён в [03-domain-layer.md](03-domain-layer.md) и реализует маркер `BaseRepositoryException`.

---

## 6. Sembast DAO (реактивный)

> **Локальная БД — Sembast (OQ-1 закрыт 2026-06-08).** Документная NoSQL, **schema-less** (хранит JSON-maps → миграций как класса нет: новые/отсутствующие поля гасятся дефолтами в маппере), чистый Dart без codegen, реактивные стримы (`onSnapshots`). Набор: `sembast` + `shared_preferences` (флаги/`themeMode`) + `flutter_secure_storage` (секреты: технический идентификатор `session.identifier`; ключ `auth_id_token` заведён под `Authorization`-токен, но **писателя ещё нет** — он приходит со stage-2 аутентификацией, стадия 1 контракта работает без auth). **Единый подход на все платформы, включая web:** mobile/desktop — `sembast_io` (`databaseFactoryIo`), Test — `databaseFactoryMemory`, **web (будущий клиент)** — `sembast_web` (`databaseFactoryWeb`, IndexedDB/WASM); код DAO/репозиториев не меняется — за абстракцией `AppDatabase` подменяется только фабрика. Отвергнуты: ObjectBox/Realm (нет web), Drift/PowerSync (реляционные), Isar (web только через community-форк + типизированная схема требует миграций). Контракты репозиториев (`03-domain-layer.md`) и потребители от БД не зависят.

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

> **Докстринг `ItemDao` — текст замороженного harness'а, не продуктовое правило.** Фраза «Network-only carve-out … the paginated `getItems` list … does NOT use this DAO» приведена дословно как в коде и относится **только** к `Item`-срезу. Продуктовые списки давно наоборот: у чатов и истории сообщений DAO есть (`ChatDao`/`MessageDao`, фича 013), и обе пагинации обслуживаются из кэша. Load-bearing в этом файле — форма DAO (per-ID store, `watch()`, `_tryDecode`), а не его комментарий про carve-out.

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

### 6а. Очередь исходящих — store, у которого ключ записи несёт смысл (027)

`local/chat/outbox_dao.dart` — единственный store, где выбор ключа записи **и есть** гарантия корректности, а не деталь: ключ равен `client_message_id` из контракта §5. Store не может держать две строки под одним ключом, поэтому повторная постановка того же сообщения физически не создаёт дубль — в открытом пространстве без удаления это неисправимо, и полагаться на проверку, о которой нужно помнить, здесь нельзя.

Три правила этого store, каждое — следствие того, что он переживает перезапуск:

1. **Порядок задаёт поле `ordinal`, а не время.** Оно назначается **внутри транзакции** постановки как `max + 1`. Сортировка по `createdAt` не годится: под замороженными в снимках часами у пачки сообщений время совпадает до миллисекунды, а счётчик в памяти обнуляется ровно тогда, когда порядок и нужно помнить.
2. **Фильтрация и сортировка — в Dart по декодированным сущностям.** Глобальный `field_rename: snake` пишет на диск `chat_id`, поэтому `Finder`/`Filter` по camelCase-ключу молча не находит ничего (та же гоча, что у `ChatDao`/`MessageDao`).
3. **Состояния `sending` в store нет.** Оно живёт ровно столько, сколько длится один `await` в сервисе; персистировать его — значит после падения процесса оставить на диске запись, помеченную как отправляемая, которую никто не отправляет.

Слив живёт рядом, в `data/sync/outbox_service.dart`, и это **единственный отправитель в приложении**. До 027 отправляли два места — композер и переотправка по реконнекту, — и мигание связи запускало их внахлёст. Проходы сериализованы цепочкой `Future _queue` (тот же приём, что в `SyncService`), идут строго по `ordinal` и по одной записи, а запись удаляется **только после** того, как репозиторий персистировал сообщение: обратный порядок оставляет окно, в котором сообщения нет нигде.

Отказ классифицируется, а не обрабатывается одинаково: `connection` / `rate_limited` / `internal` / нераспознанный — повторяемые (пауза `min(30s, 1s × 2^(attempts − 1))` ±20%, где `attempts` берётся **у записи**); прочие — окончательные, помечаются ошибкой, и проход идёт дальше. Иначе одно негодное сообщение держит за собой всю очередь, а слишком длинный текст короче с десятой попытки не станет.

Счётчиков у записи **два**, и это не избыточность: `attempts` считает любые неудачи и задаёт паузу, `refusals` — только те, на которые **сервер ответил**, и лишь он вправе исчерпать лимит автоповторов (десять). Оборванный канал — не отказ: сообщение сервер не видел, и наказывать его за сеть нельзя. Считай мы обрывы, поезд в тоннеле отложил бы совершенно здоровое сообщение за секунды. Ручной повтор обнуляет **оба** счётчика: касание значит «попробуй сейчас заново», а не «дай ещё одну попытку», иначе каждое следующее касание превращается в единственный выстрел, тут же возвращающий ошибку.

Пауза привязана к **записи**, а не хранится флагом: у неё должна кончаться причина. Отменили застрявшую голову — или её досчитало эхо сервера — и пауза, оставшись флагом, продолжала бы держать всю очередь на записи, которой больше нет.

Экран очередь **проецирует, а не хранит**: `ChatThreadBloc.outgoing` пересчитывается из `watchQueue(chatId:)`. Перечитывать сообщения из кэша нужно только на тике, где **какая-то запись исчезла**. Обычно это значит, что сервер её принял, и подмена «пузырь очереди → персистированная строка» обязана лечь одним `emit`, иначе пузырь на кадр пропадёт. Отмена вручную попадает под то же условие и вызывает лишнее чтение — сознательный размен: различить два повода исчезновения по самой очереди нельзя, а лишнее чтение кэша дешевле мигающего пузыря.

---

## 7. REST-слой

### 7а. Dio `ApiClient`

**Реальный код (seam 019/S5, для команд по-прежнему инертен).** Один host, один экземпляр Dio. `ApiClient` — `@lazySingleton`, инжектирующий `AppConfigRepository`; идемпотентный `initBase()` ставит base URL из `AppConfig.apiUrl` и **один раз** навешивает `AuthInterceptor`. Dio-seam инертен **для команд**: `AppConfig.apiUrl` с фазы 026 больше не `null` — в dev/stage он несёт адрес локального `noxd` (`--dart-define=app.apiUrl`), но из него строится **WS-URL** (`LiveSessionStarter`), а не Dio-база. Поэтому `initBase()` из кода приложения по-прежнему не вызывается (только тесты) и ни один data source не инжектирует `ApiClient` — эта разводка приходит с blob upload/download (фаза 028); живой канал контракта v0 — WS-конверт (фаза 026).

`lib/data/remote/api_client.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/interceptor/auth_interceptor.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// Thin Dio wrapper. [initBase] configures the base URL from [AppConfig.apiUrl] and
/// installs the [AuthInterceptor] (feature S5).
///
/// Inert for COMMANDS, and permanently so: contract v0 carries them over the
/// WebSocket envelope (feature 026), never over HTTP. REST exists only for blob
/// upload/download, so nothing calls [initBase] from app code and no data source
/// injects this client — that binding arrives with the file chain (phase 028).
@lazySingleton
class ApiClient {
  ApiClient(this._config)
    : dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)));

  final AppConfigRepository _config;
  final Dio dio;

  /// Idempotent: sets the base URL (when `apiUrl` is non-empty) and installs the auth
  /// interceptor exactly once (a second call is a no-op).
  void initBase() {
    final apiUrl = _config.config.apiUrl;
    if (apiUrl != null && apiUrl.isNotEmpty) {
      dio.options.baseUrl = apiUrl;
    }
    if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
      dio.interceptors.add(AuthInterceptor(_config));
    }
  }
}
```

Auth-заголовок — отдельный `AuthInterceptor` (`remote/interceptor/auth_interceptor.dart`), а не заголовки по-API: `onRequest` читает токен **асинхронно** на каждом запросе через `AppConfigRepository.getUserAuthIdToken()` (оба члена — `config.apiUrl` и `getUserAuthIdToken()` — в контракте репозитория **есть** с фичи 019) и ставит `Authorization: Bearer <token>` только для непустого значения; `onError` на 401 делает forced logout через **ленивый** алиас `authRepository` (это и разрывает DI-цикл `ApiClient → AuthInterceptor → AuthRepository → repositories`) и **всегда** пробрасывает ошибку дальше. Что здесь ещё открыто — не наличие seam'а, а **stage-2 аутентификация**: писателя `auth_id_token` нет, схема `Bearer` — плейсхолдер до утверждения модели pairing/авторизации.

```dart
// Real AuthInterceptor (feature 019/S5), abridged.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._config);

  final AppConfigRepository _config;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _config.getUserAuthIdToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // Lazy AuthRepository resolution breaks the DI cycle; the error always propagates.
    if (err.response?.statusCode == 401) {
      await authRepository.logout(forced: true);
    }
    handler.next(err);
  }
}
```

> На non-2xx Dio бросает `DioException`, который **пробрасывается до** `BaseRepositoryHelper.execute()` и там маппится `_mapDioException` по типу/статусу (401 → `unauthenticated`, 403 → `authentication`, 404 → `notFound`, таймауты/`connectionError` → `connection`, иначе `internal`). API-класс **не** маппит ошибку в типизированный `ApiException` (его в проекте нет).

> **Хук наблюдаемости.** Подключай HTTP-трекинг наблюдаемости в эти interceptor'ы (`onRequest`/`onResponse`/`onError`).
>
> **HMAC/подпись запросов — контрактом v0 НЕ требуется.** Транспортная защита — `wss:443` с key pinning, а REST-поверхность (blob upload/download) авторизуется одноразовыми 10-минутными токенами из `file.uploadBegin` / `file.downloadBegin`, а не подписью. Описанная дальше схема остаётся **гипотетическим примером** на случай, если такое требование появится: подписанные запросы (*пример*: `x-request-timestamp` + HMAC-SHA256 + security-заголовки) — тоже зона interceptor'а, отдельным `InterceptorsWrapper`, считающим подпись по каноническому формату (*в этом примере* серверный канонический verb — это `ApiRequestMethod.<lowercase>`, не `GET`/`POST`). Формула строки подписи (включая хеш тела запроса) — в [14-networking-and-auth.md](14-networking-and-auth.md) §4 (тоже размеченный пример). Не вводи подпись молча — это изменение контракта.

### 7б. `BaseApiRepository` (TARGET)

> **TARGET-форма.** `BaseApiRepository` появляется вместе с request-builder-обвязкой; в коде его нет (API-классы не наследуют общий базовый, а mock-`GetItemsApi` — обычный `@lazySingleton`). Он и не обязателен: контракт v0 идёт WS-конвертом (фаза 026), а REST-поверхность сводится к blob upload/download — если request-builder-обвязку и построят, то под неё. Сигнатура ниже — сама TARGET-форма: реальный `ApiClient.initBase()` — это **инстанс-метод `void`** на `@lazySingleton` (§7а), поэтому базовый класс придётся привязать к инжектированному `ApiClient`, а не к статической фабрике.

`lib/data/remote/api/base/base_api_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  Dio get baseClient => ApiClient.initBase();
}
```

> **Свежий `Dio` на каждый доступ к `baseClient` — намеренное правило этого блюпринта, не дефект.** В TARGET-наброске геттер вызывает `ApiClient.initBase()` при каждом обращении, поэтому новый экземпляр создаётся на запрос. Токен всё равно читается асинхронно в `AuthInterceptor` **на каждый** запрос (§7а), так что свежесть авторизации обеспечена interceptor'ом, а не переиспользованием клиента. _(Реальный `ApiClient` пошёл другим путём — один `@lazySingleton`-`Dio` с идемпотентным `initBase()`; если request-builder-обвязку будут строить, выбор между «свежий Dio на запрос» и singleton нужно принять явно, а не унаследовать молча.)_

### 7в. `RequestBuilder` + `RequestBuilderHelper` (TARGET)

> **TARGET-форма.** Папки `remote/request_builder/` в коде нет и не появилось с бэкендом: контракт v0 идёт WS-конвертом (фаза 026), REST — только blob upload/download. Ниже — канон-к-построению, если REST-поверхность вырастет.

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

**SKELETON (реальный код, заморожен).** `GetItemsApi` — `@lazySingleton` **mock-генератор** (верификационный harness, FR-013): отдаёт 47 фейковых `ItemEntity` с задержкой 150 мс и **сам строит** `ResponseEntity<ItemsEntity>` напрямую (без Dio, без request-builder'а). Репозиторий с фичи 016 **не вызывает его напрямую** — он зависит от интерфейса `ItemRemoteDataSource`, а `MockItemRemoteDataSource` делегирует этому генератору. Докстринг файла всё ещё несёт до-025-ную формулировку «until the NOX backend is chosen» — остаточный текст замороженного harness'а.

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
    final start = (config.page - 1) * pageSize;
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

**TARGET-форма (если REST-поверхность вырастет за пределы blob upload/download).** Именование API: `{verb}_{resource}_api.dart`. Класс расширяет `BaseApiRepository` и подмешивает `RequestBuilderHelper<TheBuilder>`. Форма: построить path → вызвать Dio → завернуть `response.data` в `ResponseEntity<T>.fromJson`. На non-2xx Dio бросает `DioException` — его **не** перехватывают и **не** маппят на типизированный `ApiException`: исключение пробрасывается до `BaseRepositoryHelper.execute()`, где ветка `on DioException` маппит его через `_mapDioException` (по типу/статусу).

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
// TARGET get_items_api.dart (Dio + request-builder form; not built).
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
    final path = await buildPath(config, 'v1/items'); // frozen Item verification slice, not a contract v0 endpoint
    final response = await baseClient.get(path);
    return ResponseEntity<ItemsEntity>.fromJson(response.data);
  }
}
```

> **REST-поток (TARGET):** `RequestBuilder` превращает доменный конфиг в `body`/`path`/`headers` → `RequestBuilderHelper` резолвит builder из `getIt` → API-класс шлёт через `baseClient`, оборачивает `response.data` в `ResponseEntity<T>.fromJson` (генерик `T` резолвится `EntityConverter`'ом) → на non-2xx Dio бросает `DioException`, который не перехватывается на уровне API. Репозиторий оборачивает вызов в `execute<T>()`, где ветка `on DioException` логирует и отдаёт `RepositoryResult.error(...)` с кодом из `_mapDioException`. В верификационном срезе весь этот поток сжат в mock-`GetItemsApi` выше; форма ответа (`ResponseEntity<ItemsEntity>` со срезом + offset-метаданными) сохраняется и в mock'е, и в TARGET — но это форма **`Item`-среза**, а не контрактных обёрток `{chats|messages, has_more}`.

---

## 8. Реализация репозитория

### 8.0. SKELETON — network-only `ItemRepositoryImpl` замороженного `Item`-среза (реальный код)

В скелете Feature-001 `ItemRepository` сознательно **узкий**: контракт `03-domain-layer.md` для harness'а экспонирует **только** `getItems(...)` (network-only — свойство этого замороженного harness'а, **не** продуктовое правило) + `clean()`; полный кэш-first CRUD (`watchItem`/`fetchItem`/`createItem`/`updateItem`/`deleteItem` + `ItemDao` + `BehaviorSubject`) — это **полная форма блюпринта** (§8.1), и для `Item` она так и не была построена: кэш-first пришёл фичей 013 к продуктовым репозиториям и в другой форме (прямая подписка на DAO-`watch()`, без промежуточного subject — §8.1). Так что реальный `ItemRepositoryImpl` инжектирует только маппер + `ItemRemoteDataSource` (интерфейс, а не конкретный мок — seam 016), без DAO, без subject, без `dispose`:

`lib/data/repository/item/item_repository_impl.dart`:

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/data/remote/datasource/item_remote_data_source.dart';
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
  ItemRepositoryImpl(this._itemMapper, this._itemRemote);

  final ItemMapper _itemMapper;
  final ItemRemoteDataSource _itemRemote;

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _itemRemote.getItems(config: config);
      final entity = response.data;
      if (entity == null) {
        return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
      }
      final models = _itemMapper.toListModel(entities: entity.items);
      final hasMore = (entity.page * entity.pageSize) < entity.total;
      final metadata = PageMetadata(hasMore: hasMore, nextPage: hasMore ? entity.page + 1 : null);
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
- **Пустой payload → `RepositoryException.unknown` прямо в callback'е** (так в замороженном `Item`-срезе: `if (entity == null) return ...error(unknown)` — без `throw StateError`). Логирования здесь нет: `unknown` — нормальный доменный исход; необработанные исключения логирует и коэрцирует сам `execute`. **Продуктовые репозитории** (`ChatRepositoryImpl`/`MessageRepositoryImpl`) разворачивают конверт через `unwrapEnvelope(response, 'chats'|'messages'|'send')`: он поднимает точный код §2.1 (`fromWireCode`) или `StateError`, и `execute` отдаёт его наружу — так `name_taken`/`payload_too_large` доходят до BLoC неразмытыми.
- **`PageMetadata` из обёртки страницы:** контрактные обёртки v0 (`{chats|messages, has_more}`) отдают `hasMore` готовым; verification-срез Item сворачивает offset-математику сам (`hasMore = (page * pageSize) < total`). В обоих случаях `nextPage = hasMore ? page + 1 : null` на страничном пути; `total` в `PageMetadata` не существует (фаза 025). Это канон для всех пагинированных списков — и кэш-first, и network-only (см. подсекцию «Когда network-only всё ещё уместен» ниже и `07-pagination.md`); никакой эвристики «по длине страницы».
- **`clean()`** в скелете — no-op (`Future<void>.value()` через `async {}`); в полной форме он отменяет подписку и чистит DAO/subject.

### 8.1. Полная форма — кэш-first реактивный репозиторий (TARGET)

> **TARGET-форма (для `Item`-среза — канон-к-построению).** Ниже — флагманский паттерн для user-scoped watchable-ресурсов. Применительно к `Item` это по-прежнему канон, а не код: `ItemDao` в репозитории **файл существует** (`local/item/item_dao.dart`, `@lazySingleton`), но им пользуется только собственный тест — сам `ItemRepositoryImpl` его не инжектирует, а `BehaviorSubject`, `watchItem`/`fetchItem`/CRUD и `GetItemConfig` (single-resource config) в коде отсутствуют. Кэш-first как таковой **построен** — фичей 013 для продуктовых репозиториев (`ChatRepositoryImpl` + `ChatDao`, `MessageRepositoryImpl` + `MessageDao`), но в другой форме: они подписываются на DAO-`watch()`-поток напрямую, без промежуточного `BehaviorSubject`, и один раз засеивают store из remote data source. Subject-вариант ниже остаётся каноном для реактивного **одиночного** ресурса. Network-only `getItems` **замороженного `Item`-среза** (§8.0) переносится в эту полную форму без изменений — как свойство harness'а, а не как образец для продуктового списка.

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
import 'package:nox_app/data/remote/datasource/item_remote_data_source.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_item_config.dart'; // TARGET-only: single-resource config (not in skeleton)
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._itemDao, this._itemMapper, this._itemRemote) {
    _initSubscription();
  }

  final ItemDao _itemDao;
  final ItemMapper _itemMapper;
  final ItemRemoteDataSource _itemRemote;

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
    final response = await _itemRemote.getItems(config: GetItemsConfig.firstPage());
    final page = response.data;
    if (page == null) {
      throw StateError('Empty response payload');
    }
    await _itemDao.saveData(page.items); // positional arg matches the per-ID DAO
  }

  // --- Frozen Item slice: paginated list, network-only -----------------------

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    // NETWORK-ONLY here only because the frozen Item harness caches nothing:
    // no DAO, no BehaviorSubject. Product lists are cache-first (013).
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _itemRemote.getItems(config: config);
      final entity = response.data;
      if (entity == null) {
        return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
      }
      final models = _itemMapper.toListModel(entities: entity.items);
      final hasMore = (entity.page * entity.pageSize) < entity.total;
      final metadata = PageMetadata(hasMore: hasMore, nextPage: hasMore ? entity.page + 1 : null);
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

### Когда network-only всё ещё уместен (ретайренный carve-out)

**Старая формулировка «пагинированный серверный список = network-only» ретайрена.** Она была правилом до фичи 013; сегодня продуктовые пагинированные списки — **кэш-first**: и список чатов, и история сообщений засеиваются в Sembast один раз и дальше режутся из DAO. Network-only остаётся ровно у двух вещей: у **замороженного верификационного среза `Item`** (harness не кэширует ничего по построению) и у операций, которые кэшировать нечего — one-shot команды без локальной проекции. Кэш-first — форма **по умолчанию**; network-only теперь нужно обосновывать, а не наоборот.

Что от carve-out'а осталось неизменным — **форма контракта**: метод `getItems({required GetItemsConfig config})` возвращает `RepositoryResult<(List<ItemModel>, PageMetadata)>` и реализован прямо в `ItemRepositoryImpl` (в скелетной §8.0 и в полной §8.1 форме одинаково). Никакого отдельного `getItemsPage`/`watchItems` для списка — пагинированный список это **`getItems`**, независимо от того, кэш-first он или network-only.

```dart
// Frozen Item slice: paginated list, network-only - NO DAO, NO BehaviorSubject.
@override
Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
  return execute<(List<ItemModel>, PageMetadata)>(() async {
    final response = await _itemRemote.getItems(config: config);
    final entity = response.data;
    if (entity == null) {
      return RepositoryResult<(List<ItemModel>, PageMetadata)>.error(exception: RepositoryException.unknown);
    }
    final models = _itemMapper.toListModel(entities: entity.items);
    final hasMore = (entity.page * entity.pageSize) < entity.total;
    final metadata = PageMetadata(hasMore: hasMore, nextPage: hasMore ? entity.page + 1 : null);
    return RepositoryResult<(List<ItemModel>, PageMetadata)>.success(data: (models, metadata));
  });
}
```

> **Как это разошлось с реальностью для чатов.** Список чатов планировался как network-only, но фичей 013 он стал **кэш-first**: `ChatRepositoryImpl` один раз засеивает Sembast-store из `ChatRemoteDataSource` (проходя страницы, пока `has_more` не упадёт), а дальше отдаёт срезы, поиск и `PageMetadata` локально — из DAO. То же у истории сообщений. Carve-out как правило снят; network-only остаётся в силе для замороженного `Item`-среза и для того, что действительно не кэшируется; форма возврата (`RepositoryResult<(List<Model>, PageMetadata)>`, никакого отдельного `getItemsPage`/`watchItems`) одинакова на обеих ветках. Контракт пагинации списка чатов **зафиксирован контрактом v0 (фаза 025)**: страничный запрос (`page`/`page_size`) с ответом `{chats, has_more}`; история сообщений — курсорный путь `before_seq`/`limit` с ответом `{messages, has_more}`. Канон вычисления `PageMetadata{hasMore, nextPage?}` — здесь, в §8 (`hasMore` с провода или сворачиванием offset-математики verification-среза; `nextPage = hasMore ? page + 1 : null` на страничном пути); `07-pagination.md` описывает presentation-сторону поверх этого канона (страничный флавор, реальный seq-курсорный путь треда в его §4.2, `PagingStateExt.applyPage`, проброс `result.exception` в `pagingState.error`). Правило теперь обратное прежнему: для продуктового пагинированного списка **заводи DAO** и кэш-first-путь, а network-only оставляй только там, где кэшировать нечего.

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
| `ApiClient` | `remote/api_client.dart` | `@lazySingleton` (Dio + `initBase()`, инжектирует `AppConfigRepository`) |
| `AuthInterceptor` | `remote/interceptor/auth_interceptor.dart` | без DI — создаётся в `ApiClient.initBase()` |
| `ItemRemoteDataSource` / `MockItemRemoteDataSource` | `remote/datasource/item_remote_data_source.dart`, `datasource/mock/...` | `@LazySingleton(as: ItemRemoteDataSource, env: [dev, prod, test])` |
| `GetItemsApi` (mock-генератор, заморожен) | `remote/api/item/get_items_api.dart` | `@lazySingleton` |
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

- [ ] `ItemEntity` использует **только базовые типы**, ровно пять полей `id`/`name`/`status` (String-`name`)/`createdAt` (ISO-8601 String)/`description` (required-nullable); никаких `tags`/`DateTime`/enum-как-enum. `ItemsEntity` — page wrapper `{items, page, page_size, total}` с `@JsonKey` (verification-срез; ПРОДУКТОВЫЕ обёртки фиксированы контрактом v0: `{chats, has_more}` / `{messages, has_more}` — фаза 025, живые фикстуры в `test/fixtures/wire/`).
- [ ] Все `part`-директивы стоят: entities имеют `.freezed.dart` **и** `.g.dart`; BLoC-типы и доменные модели (`ItemModel`) — только `.freezed.dart` (entity-слой — единственное место с `.g.dart`/`fromJson`).
- [ ] `ResponseEntity<T>` = `{success (зеркало wire-`ok`), ErrorWireEntity? error {code, message}, @EntityConverter() T? data}` + `EntityConverter<E>` реестр на месте; **каждый** новый entity, проходящий через `ResponseEntity<T>`, добавлен в ОБЕ цепочки (`fromJson` + `toJson`) `entity_converter.dart` (реестр наполнен с 018/S4: Item + chat/message wire-сущности; неизвестный тип → `ArgumentError`).
- [ ] `ItemMapper` расширяет `BaseMapper` (4-арг, `dynamic, dynamic` для простого случая), коэрция enum через `name`/`firstWhere(orElse:)`, дата — защитно в UTC (`DateTime.tryParse(...)?.toUtc() ?? DateTime.now().toUtc()` / `.toUtc().toIso8601String()`); импортирует `item_status.dart`; дочерние мапперы инжектируются конструктором.
- [ ] **Нет** транспортной иерархии `DaoException` / `ApiException` / `BaseDomainExceptionHelper`; есть **маркер** `BaseRepositoryException`, который реализует `RepositoryException` (enum `{unknown, internal, authentication, connection, unauthenticated, notFound, invalidRequest, nameTaken, payloadTooLarge, attachmentGone, rateLimited, unsupportedSchema}` + статический `fromWireCode(String)`, незнакомый код → `internal`) и любые feature-enum'ы; `RepositoryResult.error` всегда несёт подтип маркера. Единственный коэрсный механизм — `mixin BaseRepositoryHelper` с `execute<TD>(Function executionFunction)`; импл подмешивает **только** `with BaseRepositoryHelper` (без `on`-ограничения).
- [ ] `BaseRepositoryHelper.execute<T>()` имеет **ровно три** `catch`-ветки — `on BaseRepositoryException` (пробрасывается как есть, не понижается до `unknown`), `on DioException` → `_mapDioException` (таймауты/`connectionError` → `connection`; 401 → `unauthenticated`; 403 → `authentication`; 404 → `notFound`; иначе `internal`), общий `catch` → `RepositoryException.unknown`; **обязательно** логирует через `LogRepository` в каждой ветке (никакого `print`) перед возвратом `RepositoryResult.error(...)`. Тот же mixin даёт `unwrapEnvelope<TD>(ResponseEntity<TD>, String what)`: payload, иначе `fromWireCode(error.code)`, иначе `StateError`. Callback `executionFunction` сам возвращает уже-обёрнутый `RepositoryResult`; конкретный доменный код (`notFound`/`unknown` при пустом payload) — внутри callback'а, не в catch.
- [ ] `AppDatabase` env-scoped (интерфейс `db` + `clearEntireDatabase()`; `Dev`/`Prod` = `databaseFactoryIo`, `Test` = `databaseFactoryMemory`); `path_provider` — зависимость пакета; env-список в репозитории полный.
- [ ] `ItemDao` (PRIMARY) — **per-ID records store** `stringMapStoreFactory.store('items')`, ключ = `item.id`: `watch()` как `Stream<List<ItemEntity>> async*`, `getById(String)`, позиционные `saveData(List)`/`upsert(ItemEntity)`/`removeById(String)`/`cleanData()`, `_decode`/`_tryDecode` пропускают битую запись (`null`). DAO **не** оборачивает сбои в `StateError` — исключения Sembast летят в catch-all `execute()`. Cache-miss/not-found решает callback репозитория. Single-record collection store — альтернативный вариант.
- [ ] **`ItemRepositoryImpl` (замороженный верификационный срез)** реализует **узкий** контракт `ItemRepository` (`getItems({GetItemsConfig config}) -> (List, PageMetadata)` + `clean() -> Future<void>`): инжектирует только маппер + `ItemRemoteDataSource` (интерфейс, seam 016), без DAO/subject/dispose; пустой payload → `RepositoryException.unknown` в callback'е; `PageMetadata` сворачивается из offset-обёртки среза (`hasMore = (page * pageSize) < total`, `nextPage = hasMore ? page + 1 : null`) — **в самой `PageMetadata` полей `total`/`pageSize` нет**, только `{hasMore, nextPage?}`; `clean()` — no-op. **Полный** env-список `@LazySingleton`. Полная (TARGET) форма добавляет `watchItem`/`fetchItem`/CRUD + `ItemDao` + ОДИН `BehaviorSubject` (подписка раз в конструкторе) + `@disposeMethod`, читает через `hasData`/`match` (не `result.data!`).
- [ ] REST **построенное**: `@lazySingleton ApiClient` (`remote/api_client.dart`) с идемпотентным `initBase()` (base URL из `AppConfig.apiUrl` + однократная установка `AuthInterceptor`, который асинхронно читает `AppConfigRepository.getUserAuthIdToken()` и на 401 делает forced logout через ленивый алиас) — Dio-seam инертен **для команд**: `initBase()` из кода приложения не зовётся, data sources его не инжектируют (разводка — blob upload/download фазы 028); `AppConfig.apiUrl` с фазы 026 непустой в dev/stage, но питает WS-транспорт, а не Dio. Транспорт контракта v0 — WS-конверт (фаза 026); REST остаётся за blob upload/download. **TARGET (не построено)**: `BaseApiRepository` + `RequestBuilder`/`RequestBuilderHelper`; API-класс оборачивает `response.data` в `ResponseEntity<T>.fromJson`; на non-2xx Dio бросает `DioException`, не перехватываемый на уровне API → `execute()` → `_mapDioException` (никакого `ApiException`). В замороженном `Item`-срезе wire-параметр поиска — `search` (не `q`); `page` 1-based (`defaultPage = 1`).
- [ ] **Кэш-first — форма по умолчанию; carve-out «пагинированный список = network-only» ретайрен.** Список чатов и история сообщений — кэш-first (013): один seed в Sembast, дальше срезы/поиск/`PageMetadata` из DAO. Network-only (без DAO, без subject) допустим только там, где кэшировать нечего: замороженный `Item`-срез и one-shot команды без локальной проекции — и это обосновывается, а не предполагается. Форма возврата на обеих ветках одна — `RepositoryResult<(List<Model>, PageMetadata)>`, без отдельного `getItemsPage`/`watchItems` (см. `07-pagination.md`). Контракт пагинации зафиксирован v0: `{chats, has_more}` по `page`/`page_size`, `{messages, has_more}` по `before_seq`/`limit`.
- [ ] **Очередь исходящих построена (027)**: store `outbox` (`local/chat/outbox_dao.dart`), где **ключ записи = `client_message_id`** контракта — повторная постановка физически не даёт дубля; `ordinal` назначается `max + 1` **внутри одной транзакции** с записью (сортировка по времени не годится); фильтрация и сортировка — в Dart по декодированным сущностям, не `Finder`'ом по camelCase-ключу (`field_rename: snake`); в `OutboxStatus` ровно `{pending, error}` — состояния `sending` на диске **нет**. `data/sync/outbox_service.dart` — **единственный отправитель**: проходы сериализованы цепочкой `Future _queue`, идут по `ordinal` по одной записи, запись удаляется **только после** персиста сообщения репозиторием; отказ классифицируется — `connection`/`rateLimited`/`internal`/`unknown`/нераспознанный повторяемы (пауза `min(30s, 1s × 2^(attempts − 1))` ±20%, где `attempts` берётся у записи), прочие окончательны (`error`, проход идёт дальше). Экран очередь **проецирует**, а не хранит (`ChatThreadBloc.outgoing` из `watchQueue(chatId:)`).
- [ ] `build_runner` перезапущен один раз в корне пакета после изменений аннотаций.

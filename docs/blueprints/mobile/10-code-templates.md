# 10 — Каталог шаблонов кода

> **Назначение:** единый copy-paste-ready справочник шаблонов для каждого артефакта скелета (модель → enum → конвертер → контракт → конфиг → entity → mapper → DAO → repository → BLoC → page → тема → DI). Каждый шаблон дан в двух формах: рабочий пример на нейтральной фиче `Item` и пустой скелет `<Feature>` / `<Model>`. Это чистый каталог — обоснования и правила живут в слоевых документах, сюда вынесена только готовая к вставке форма.
> **Когда читать:** когда вы скаффолдите конкретную фичу (первая реальная — список чатов: открытый список чатов общего пространства, серверный network-only пагинированный список) или любой сквозной артефакт (конвертер, `ThemeExtension`, DI-регистрация) и хотите канонический, проектно-верный код, который остаётся переименовать и вставить.
> **Связанные документы:** `03-domain-layer.md` (RepositoryResult, configs, exceptions, модели), `04-data-layer.md` (entities, mappers, DAO, ResponseEntity/EntityConverter, repo impl, Dio), `05-presentation-layer.md` (BLoC-трио, страницы, BaseStatePage, общие виджеты), `06-theming.md` (ThemeExtension, токены), `07-pagination.md` (полный контракт пагинации, `PagingStateExt.applyPage`), `02-dependency-injection.md` (единый `configureDependencies(env)`), `08-conventions-and-constitution.md` (нейминг/импорты/правила), `11-scaffolding-plan.md` (порядок скаффолдинга), `12-dev-commands.md` (команды и codegen).

---

## Как пользоваться этим файлом

- **Рабочий пример** использует одну нейтральную фичу `Item`: `ItemModel`, `ItemEntity`, `ItemRepository`, `ItemRepositoryImpl`, `ItemMapper`, `ItemDao`, `ItemListPage`, `ItemListBloc`, `ItemListEvent`, `ItemListState`, `GetItemsConfig`.
- ⚠ **`Item`-шаблоны — НЕЙТРАЛЬНЫЙ пример формы, не источник полей.** Их поля (`name`, `description`, `status`, …) выдуманы под демонстрацию слоёв. Реальные сущности NOX (`Chat`, `Message`, технический `identifier` / публичный `label` и т. п.) проектируются **по контракту бэкенда NOX** — а он ещё не выбран (TBD): набор полей, их имена, обязательность и типы берутся из реального контракта, а не копируются из `Item`. Из шаблонов переиспользуется только структура артефактов (model → entity → mapper → DAO → repository → BLoC), но не их данные.
- Для **пустого скелета** подставляйте плейсхолдеры: `<Feature>` — PascalCase имя фичи (`Chat`, `Message`), `<Model>` — PascalCase имя модели (часто совпадает с `<Feature>`), `<feature>` / `<model>` — `snake_case` формы для путей файлов и barrel-экспортов в слоях `domain`/`data` (группировка по сущности). В презентации привязка идёт к **страницам**, не к абстрактным «фичам»: один экран = одна плоская папка `lib/presentation/pages/<page>_page/`, плейсхолдер `<page>` — `snake_case` имя страницы (`item_list`, `item_details`), а bloc-файлы внутри — `<page>_bloc.dart` / `<page>_event.dart` / `<page>_state.dart` (без инфикса `_page_`).
- Имя Dart-пакета фиксировано: `nox_app`. Все импорты идут через `package:nox_app/...`. Владелец может переименовать пакет — это отмечено один раз в `README.md`, в шаблонах ниже имя зашито.
- Слои — это **папки в одном `lib/`**: `lib/data`, `lib/domain`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`. Никаких трёх пакетов и path-зависимостей (NOX — один standalone-пакет, не монорепо). `lib/resource` — задекларированный слой-резерв (сейчас только `.gitkeep`); тема живёт **не** в нём, а в `lib/design/theme/` (см. §16). Зависимости однонаправленны: `presentation → domain`, `data → domain`; `domain` не импортирует ничего из приложения.
- После вставки любого Freezed / json_serializable / injectable-артефакта запустите codegen `fvm dart run build_runner build --delete-conflicting-outputs` (Makefile-обёртка — `make generate`), отформатируйте затронутые файлы (`fvm dart format -l 140 <paths>`) и прогоните `fvm flutter analyze` (см. `12-dev-commands.md`).
- Генерируемые файлы (`*.freezed.dart`, `*.g.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и **никогда** не редактируются руками.

> **Соглашение по умолчанию для пагинации — OFFSET.** В шаблонах ниже список-конфиг и метаданные страницы используют offset-форму (`page` + `pageSize` + `total`): offset — флейвор по умолчанию, cursor (`CursorPaginationMetadata { String? nextCursor }`) задокументирован как альтернатива в `07-pagination.md`. `page` (1-based, default 1) и `page_size` — query-параметры запроса; ответ эхом возвращает `page` / `page_size` / `total`, а `nextPage` вычисляется клиентски в репозитории. Конкретный контракт пагинации списка чатов финализируется позже вместе с бэкендом NOX (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт); не смешивайте формы в одной фиче.

---

## 1. Доменная модель — `ItemModel` (`@freezed`, без JSON)

**Целевой путь:** `lib/domain/model/<feature>/<model>_model.dart`
**Рабочий пример:** `lib/domain/model/item/item_model.dart`

Доменные модели — `@freezed` **только с `.freezed.dart`** (никакого `.g.dart`, никакого `fromJson`). JSON живёт в entity-слое (§6). Производная/бизнес-логика — в **extension-геттерах**, никогда в теле `@freezed`.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

part 'item_model.freezed.dart';

@freezed
abstract class ItemModel with _$ItemModel {
  const factory ItemModel({
    required String id,
    required String name,
    required String? description,
    required ItemStatus status,
    required DateTime createdAt,
  }) = _ItemModel;
}

extension ItemModelExt on ItemModel {
  bool get isArchived => status == ItemStatus.archived;

  String get displayName => name.trim().isEmpty ? 'Untitled' : name;
}
```

Правила:
- `@freezed abstract class` с миксином `_$ItemModel` и `const factory` (`abstract` — потому что одна вариация, value-object; см. §13 про `sealed` для union-типов).
- Все поля `required`; nullable-поля явно типизированы `Type?` (всё равно `required`).
- Никаких `BigInt`-money, пакета `decimal`, FFI — деньги/крипта вне скоупа.
- Производные значения — в `extension`, не в теле модели.

Пустой скелет:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/<feature>/<feature>_status.dart';

part '<model>_model.freezed.dart';

@freezed
abstract class <Model>Model with _$<Model>Model {
  const factory <Model>Model({
    required String id,
    // ... поля; nullable как Type?, всё required
  }) = _<Model>Model;
}

extension <Model>ModelExt on <Model>Model {
  // производные геттеры
}
```

Barrel-реэкспорт моделей:

**Целевой путь:** `lib/domain/model/models.dart`

```dart
export 'item/item_model.dart';
export 'item/item_status.dart';
// ... остальные экспорты моделей и enum'ов
```

---

## 2. Enum статуса + рецепт `JsonConverter<T, S>` (в data/entity-слое)

### 2a. Enum статуса (домен)

**Целевой путь:** `lib/domain/model/<feature>/<feature>_status.dart`
**Рабочий пример:** `lib/domain/model/item/item_status.dart`

```dart
enum ItemStatus {
  draft,
  active,
  archived,
}
```

Enum живёт в домене и используется доменной моделью как богатый тип. На границе с JSON он кодируется как `.name` String — **вся коэрция происходит в mapper'е** (§8), а не в модели и не в entity.

### 2b. Рецепт `JsonConverter<T, S>` (опционально, для entity-слоя)

> Доменная модель не сериализуется, поэтому конвертеры на доменных полях не нужны. Если нестандартная коэрция требуется на уровне **entity** (например, поле приходит как число, а удобнее работать со String, или нужна форма, отличная от дефолтного json_serializable), кладите конвертер в data-слой и аннотируйте им поле **entity**. `T` — тип в Dart-land, `S` — JSON-сериализуемый тип.

**Целевой путь:** `lib/data/entity/base/<custom>_converter.dart`

Generic-рецепт:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

/// Converts between an in-Dart type [T] and a JSON-serializable type [S].
class CustomTypeConverter<T, S> implements JsonConverter<T, S> {
  const CustomTypeConverter();

  /// S (JSON) -> T (Dart).
  @override
  T fromJson(S json) => throw UnimplementedError();

  /// T (Dart) -> S (JSON).
  @override
  S toJson(T object) => throw UnimplementedError();
}
```

Рабочий пример — конвертер enum ⇄ String, если потребовался на entity-поле:

**Целевой путь:** `lib/data/entity/base/item_status_converter.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

class ItemStatusConverter implements JsonConverter<ItemStatus, String> {
  const ItemStatusConverter();

  @override
  ItemStatus fromJson(String json) {
    return ItemStatus.values.firstWhere(
      (e) => e.name == json,
      orElse: () => ItemStatus.draft,
    );
  }

  @override
  String toJson(ItemStatus object) => object.name;
}
```

Применение — аннотировать поле entity (`// ignore_for_file: invalid_annotation_target` в начале файла, как в §6):

```dart
@freezed
abstract class ItemEntity with _$ItemEntity {
  const factory ItemEntity({
    @ItemStatusConverter() required ItemStatus status,
  }) = _ItemEntity;

  factory ItemEntity.fromJson(Map<String, dynamic> json) => _$ItemEntityFromJson(json);
}
```

> По умолчанию (как в §6) entity хранит `status` просто как `String`, а enum ⇄ String делает mapper — это предпочтительный путь. Конвертер на entity-поле — опция для случаев, когда форма в DAO/JSON должна остаться типизированной. Не помещайте такие конвертеры в `lib/domain/` — домен не знает про JSON.

---

## 3. `RepositoryResult<T>` + `match()` + маркеры + enum исключений

Базовая инфраструктура домена. Вставляется **один раз на проект**, переиспользуется каждой фичей.

### 3a. `RepositoryResult<T>` (`@freezed`, success/error)

**Целевой путь:** `lib/domain/repository/base/repository_result.dart`

`RepositoryResult<T>` — `@freezed` с **взаимоисключающими** `success` / `error` фабриками (data XOR exception; никаких «обоих nullable»). Только `.freezed.dart`, без `.g.dart` — результат не сериализуется.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';

part 'repository_result.freezed.dart';

@freezed
sealed class RepositoryResult<T> with _$RepositoryResult<T> {
  const RepositoryResult._();

  const factory RepositoryResult.success({required T data}) = RepositoryResultSuccess<T>;

  const factory RepositoryResult.error({required BaseRepositoryException exception}) = RepositoryResultError<T>;

  bool get hasData => this is RepositoryResultSuccess<T>;

  /// Non-null data on a success result; null on error. Prefer [match].
  T? get data => switch (this) {
        RepositoryResultSuccess(:final data) => data,
        _ => null,
      };

  /// The exception on an error result; null on success.
  BaseRepositoryException? get exception => switch (this) {
        RepositoryResultError(:final exception) => exception,
        _ => null,
      };
}
```

### 3b. Trimmed `match<R>()` extension

**Целевой путь:** `lib/domain/repository/base/repository_result_handling.dart`

Урезанный `match` — ровно две ветки (никаких `onPartial` / `onEmpty`, потому что результат строго XOR):

```dart
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

extension RepositoryResultMatch<T> on RepositoryResult<T> {
  R match<R>({
    required R Function(T data) onData,
    required R Function(BaseRepositoryException exception) onError,
  }) =>
      switch (this) {
        RepositoryResultSuccess(:final data) => onData(data),
        RepositoryResultError(:final exception) => onError(exception),
      };
}
```

> Никогда не используйте `result.data!`. В BLoC'ах потребляйте через `match(onData:, onError:)`; для булевой проверки — `result.hasData`.

### 3c. Маркер `RepositoryConfig`

**Целевой путь:** `lib/domain/repository/base/repository_config.dart`

```dart
abstract class RepositoryConfig {}
```

### 3d. Маркер `BaseRepositoryException`

**Целевой путь:** `lib/domain/exception/base_repository_exception.dart`

```dart
abstract class BaseRepositoryException {}
```

### 3e. Enum `RepositoryException`

**Целевой путь:** `lib/domain/exception/repository_exception.dart`

```dart
import 'package:nox_app/domain/exception/base_repository_exception.dart';

enum RepositoryException implements BaseRepositoryException {
  unknown,
  internal,
  authentication,
  connection,
  unauthenticated,
  notFound,
}
```

Фиче-специфичные исключения реализуют тот же маркер (BLoC `switch`-ит по конкретному типу, чтобы выбрать сообщение пользователю):

```dart
// lib/domain/repository/<feature>/<feature>_repository_exception.dart  (пример)
import 'package:nox_app/domain/exception/base_repository_exception.dart';

enum ChatsRepositoryException implements BaseRepositoryException {
  quotaExceeded,
}
```

Barrel базового слоя:

**Целевой путь:** `lib/domain/repository/base/base.dart`

```dart
export 'repository_config.dart';
export 'repository_result.dart';
export 'repository_result_handling.dart';
```

---

## 4. Контракт репозитория — `ItemRepository`

**Целевой путь:** `lib/domain/repository/<feature>/<feature>_repository.dart`
**Рабочий пример:** `lib/domain/repository/item/item_repository.dart`

```dart
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_item_config.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';

abstract class ItemRepository {
  /// Cache-first single resource. Replays the last value, then live updates.
  Stream<RepositoryResult<ItemModel>> watchItem({required String id});

  /// One-shot single resource (cache-first; pushes onto the watch stream).
  Future<RepositoryResult<ItemModel>> fetchItem({required GetItemConfig config});

  /// Paginated server-owned list (network-only). Returns the page slice paired
  /// with offset metadata (nextPage + total).
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config});

  Future<RepositoryResult<ItemModel>> createItem({required ItemModel item});

  Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item});

  Future<RepositoryResult<void>> deleteItem({required String id});

  /// Resets cache/subjects (called on logout).
  Future<void> clean();
}
```

Правила формы методов:
- `fetch*()` / `create*()` / `update*()` / `delete*()` → `Future<RepositoryResult<T>>` (one-shot single).
- `get*()` → параметризованный/списковый (`getItems` принимает `{required GetItemsConfig config}` и возвращает срез + offset-метаданные).
- `watch*()` → `Stream<RepositoryResult<T>>` (live, поверх `BehaviorSubject` в impl).
- Никаких `saveItem` — пишем через `createItem` / `updateItem`. Никаких `fetchItems` для списка — каноническое имя `getItems`.
- Одиночные методы ключуются по `id`; списковые принимают `{required GetXxxConfig config}` (см. §5); create/update берут полную модель.
- Пагинированный список возвращает `RepositoryResult<(List<T>, PageMetadata)>` — кортеж со срезом страницы и offset-метаданными (см. §6c про `PageMetadata` и `07-pagination.md`).
- Возвраты **всегда** обёрнуты в `RepositoryResult<T>` — никогда голый `Future<T>` (кроме `clean()`, который возвращает `Future<void>`).

> **Сверка со скелетом.** Контракт выше — **полная** референс-форма. Реальный `lib/domain/repository/item/item_repository.dart` в скелете Feature-001 урезан до network-only-среза (паттерн «первая реальная фича / список чатов»): только `getItems({required GetItemsConfig config})` + `clean()`. Cache-first `watchItem`/`fetchItem` и CRUD (`createItem`/`updateItem`/`deleteItem`) — это полный пример блюпринта; они прибывают с фичей, которой нужен кэш.

---

## 5. Конфиги — `GetItemConfig` / `GetItemsConfig` (`@freezed`)

Конфиги — `@freezed`, реализуют `RepositoryConfig`, несут именованные фабрики `firstPage` / `nextPage` и константы пагинации.

### 5a. Списковый конфиг — `GetItemsConfig` (OFFSET по умолчанию)

**Целевой путь:** `lib/domain/repository/<feature>/get_<feature>s_config.dart`
**Рабочий пример:** `lib/domain/repository/item/get_items_config.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_items_config.freezed.dart';

@freezed
abstract class GetItemsConfig with _$GetItemsConfig implements RepositoryConfig {
  const GetItemsConfig._();

  const factory GetItemsConfig({required int page, String? search}) = _GetItemsConfig;

  factory GetItemsConfig.firstPage({String? search}) => GetItemsConfig(page: defaultPage, search: search);

  factory GetItemsConfig.nextPage({required int page, String? search}) => GetItemsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1; // 1-based
}
```

> `defaultPage` — **1** (1-based). Никогда `GetItemsConfig(page: 0, pageSize: 50)`; никаких магических чисел страницы в BLoC — первая страница выражается только фабрикой `Get<Name>sConfig.firstPage()`. `pageSize` — статическая константа (20), не поле конфига; `page` — единственное обязательное поле, `search` опционален.

### 5b. Одиночный конфиг — `GetItemConfig`

**Целевой путь:** `lib/domain/repository/<feature>/get_<feature>_config.dart`
**Целевая форма (в скелете отсутствует):** `lib/domain/repository/item/get_item_config.dart`

> **Сверка со скелетом.** `GetItemConfig` / `get_item_config.dart` — часть **полной** референс-формы (одиночный cache-first `fetchItem`/`watchItem`); в скелете Feature-001 их **нет**: урезанный `ItemRepository` несёт только `getItems(...)` + `clean()` (см. §4), поэтому одиночный конфиг прибывает с фичей, которой нужен кэш. Шаблон ниже — целевой образец, не существующий файл.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_item_config.freezed.dart';

@freezed
abstract class GetItemConfig with _$GetItemConfig implements RepositoryConfig {
  const factory GetItemConfig({required String id, required bool? cacheOnly}) = _GetItemConfig;
}
```

Семантика `cacheOnly` (единая по кодовой базе):
- `true` → читать только кэш; вернуть `notFound`, если пусто (сеть не трогается).
- `null` или `false` → cache-first: вернуть кэш, если есть, иначе сходить в сеть.

---

## 6. Entity + `PageMetadata` (только базовые типы)

### 6a. `ItemEntity` (basic types only)

**Целевой путь:** `lib/data/entity/<feature>/<model>_entity.dart`
**Рабочий пример:** `lib/data/entity/item/item_entity.dart`

Entity — `@freezed` **и** json_serializable: оба парта (`.freezed.dart` + `.g.dart`) и `fromJson`. Поля — **только базовые типы**: enum как String, `DateTime` как ISO-8601 String. Никаких enum'ов, `DateTime`, кастомных типов в полях — вся коэрция в mapper (§8).

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
    required String status, // enum encoded as String
    required String createdAt, // DateTime encoded as ISO-8601 String
    required String? description,
  }) = _ItemEntity;

  factory ItemEntity.fromJson(Map<String, dynamic> json) => _$ItemEntityFromJson(json);
}
```

### 6b. `ItemsEntity` — обёртка страницы

**Целевой путь:** `lib/data/entity/<feature>/<model>s_entity.dart`
**Рабочий пример:** `lib/data/entity/item/items_entity.dart`

Обёртка несёт срез страницы плюс серверные offset-метаданные (`page` / `page_size` / `total`). Имена JSON-ключей подгоняются под реальный envelope бэкенда NOX (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт); `nextPage` вычисляется клиентски в репозитории (§11c, канон — `04-data-layer.md` §8).

```dart
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';

part 'items_entity.freezed.dart';
part 'items_entity.g.dart';

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

### 6c. `PageMetadata` — offset-метаданные домена (OFFSET по умолчанию)

**Целевой путь:** `lib/domain/repository/base/page_metadata.dart`

Доменный тип метаданных страницы, который репозиторий возвращает рядом со срезом. `@freezed`, **без JSON** (только `.freezed.dart`). Форма по умолчанию — OFFSET: `nextPage == null` ⇒ последняя страница. Cursor-альтернатива `CursorPaginationMetadata` лежит в **той же папке** и используется ТОЛЬКО в cursor-секции. JSON-парсинг — это data-слой: ответ списка приходит как `ResponseEntity<ItemsEntity>` (`items` + `page` + `page_size` + `total`, §6b), а `PageMetadata` репозиторий собирает клиентски — `hasMore = (entity.page * entity.pageSize) < entity.total`, `nextPage = hasMore ? entity.page + 1 : null`, `total = entity.total` (канон — `04-data-layer.md` §8, рабочий пример — §11c).

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_metadata.freezed.dart';

/// Offset-style page metadata (default flavor for the NOX chats list).
/// nextPage == null => last page.
@freezed
abstract class PageMetadata with _$PageMetadata {
  const factory PageMetadata({
    /// Total item count across all pages (drives «X of Y» counters / admin analytics).
    required int total,

    /// 1-based index of the next page (computed client-side); null on the last page.
    int? nextPage,
  }) = _PageMetadata;
}

/// Cursor-style alternative — use ONLY when the endpoint is cursor-based.
/// See 07-pagination.md. Do not mix with PageMetadata in one feature.
@freezed
abstract class CursorPaginationMetadata with _$CursorPaginationMetadata {
  const factory CursorPaginationMetadata({String? nextCursor}) = _CursorPaginationMetadata;
}
```

---

## 7. `ResponseEntity<T>` + реестр `EntityConverter<E>`

Предполагается, что бэкенд NOX оборачивает каждый JSON-ответ в единый envelope (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт; см. `04-data-layer.md` §2–3). `ResponseEntity<T>` — generic-обёртка над ним с полями `success` / `error` / `data`; `@EntityConverter()` резолвит generic `T` в конкретный `fromJson`/`toJson` entity.

### 7a. `ResponseEntity<T>`

**Целевой путь:** `lib/data/entity/base/response_entity.dart`

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

> Поля — ровно `success` (bool, `@Default(false)`), `error` (`String?`), `data` (`@EntityConverter() T?`) — это правило данного блюпринта. Load-bearing-механизм, который надо сохранить, — generic `T?`, резолвимый `JsonConverter`'ом (`@EntityConverter()`); конкретный набор полей конверта (нужны ли `timestamp`/`trace_id`/`meta` и в какой форме приходит ошибка) подгоняется под реальный контракт бэкенда NOX (пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт). Добавляйте служебные поля nullable по мере надобности (см. `04-data-layer.md` §2).

### 7b. `EntityConverter<E>` — реестр типов, поддерживаемый руками

Единственное место **ручного учёта**. `EntityConverter<E>` — `JsonConverter`, диспетчеризующий generic `T` из `ResponseEntity<T>` в нужный entity. **Каждый entity, достижимый через `ResponseEntity<T>`, ОБЯЗАН быть зарегистрирован в обеих цепочках** (`fromJson` и `toJson`), иначе `ArgumentError('No converter found')`.

**Целевой путь:** `lib/data/entity/base/entity_converter.dart`

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

> **Правило сопровождения:** любой новый entity, используемый через `ResponseEntity<T>`, добавляется в **обе** цепочки в `entity_converter.dart`. Реестр поддерживается руками, не кодогенерируется.

> **Сверка со скелетом.** В скелете Feature-001 `entity_converter.dart` стартует **пустым** (без `ItemEntity`/`ItemsEntity`-веток — комментарии в коде помечают «registered per feature, see US2»): network-only `Item`-слайс инстанцирует `ItemsEntity` напрямую в моке, не проходя через реестр. Ветки entity добавляются по мере появления фич, как показано в шаблоне выше — конфликта нет, реестр всё равно ручной.

---

## 8. `BaseMapper<E, M, AdResult, AdParam>` + `ItemMapper`

### 8a. `BaseMapper` (вставить один раз на проект)

**Целевой путь:** `lib/data/mapper/base_mapper.dart`

```dart
import 'dart:core';

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

### 8b. `ItemMapper` (вся коэрция enum/DateTime)

**Целевой путь:** `lib/data/mapper/<feature>/<model>_mapper.dart`
**Рабочий пример:** `lib/data/mapper/item/item_mapper.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/base_mapper.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

@lazySingleton
class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic> {
  @override
  ItemModel toModel({required ItemEntity entity, dynamic Function(dynamic entity)? ad}) {
    return ItemModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      status: ItemStatus.values.firstWhere(
        (e) => e.name == entity.status,
        orElse: () => ItemStatus.draft,
      ),
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

Правила:
- Наследует `BaseMapper<Entity, Model, dynamic, dynamic>` (`dynamic, dynamic`, когда доп-контекст не нужен).
- `@lazySingleton`; вложенные мапперы инжектируются через конструктор (`_childMapper.toListModel(entities: entity.children)`).
- Это **единственное** место, где происходит `String ⇄ enum`, `String ⇄ DateTime` и любая числовая коэрция.

---

## 9. DAO Sembast (реактивный) + `AppDatabase`

> Слой данных **не** заводит типизированную иерархию исключений (`ApiException` / `DaoException` / `BaseDomainExceptionHelper` намеренно отсутствуют — правило данного блюпринта, см. [04-data-layer.md](04-data-layer.md) §5). DAO **не** оборачивает ошибки в типизированный `DaoException`: при сбое хранилища он бросает **сырое** исключение Sembast (его поймает catch-all-ветка `execute` → `RepositoryException.unknown`), а отсутствие записи / ошибку парсинга отдаёт как `null`. Решение «cache-miss → `notFound`» принимает **callback репозитория**, проверяя `null` и явно возвращая `RepositoryResult.error(exception: RepositoryException.notFound)` (см. §11c), а не DAO.

### 9a. `AppDatabase` — env-scoped (Dev/Prod = IO, Test = memory)

**Целевой путь:** `lib/data/local/app_database.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

abstract class AppDatabase {
  Future<Database> get db;

  Future<void> clearEntireDatabase();
}

@LazySingleton(as: AppDatabase, env: [Environment.prod])
class AppDatabaseProd implements AppDatabase {
  static const String _dbName = 'app.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await _initDb();

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return databaseFactoryIo.openDatabase('${dir.path}/$_dbName');
  }

  @override
  Future<void> clearEntireDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    await databaseFactoryIo.deleteDatabase('${dir.path}/$_dbName');
    _database = null;
  }
}

@LazySingleton(as: AppDatabase, env: [Environment.dev])
class AppDatabaseDev implements AppDatabase {
  static const String _dbName = 'app_dev.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await _initDb();

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    return databaseFactoryIo.openDatabase('${dir.path}/$_dbName');
  }

  @override
  Future<void> clearEntireDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    await databaseFactoryIo.deleteDatabase('${dir.path}/$_dbName');
    _database = null;
  }
}

@LazySingleton(as: AppDatabase, env: [Environment.test])
class AppDatabaseTest implements AppDatabase {
  static const String _dbName = 'app_test.db';

  Database? _database;

  @override
  Future<Database> get db async => _database ??= await databaseFactoryMemory.openDatabase(_dbName);

  @override
  Future<void> clearEntireDatabase() async {
    await databaseFactoryMemory.deleteDatabase(_dbName);
    _database = null;
  }
}
```

> Маппинг flavor → env (см. `09-build-and-secrets-infra.md`): `prod → Environment.prod`, `stage → Environment.dev`. Тест-env (`Environment.test`) активируется только в тест-бутстрапе. Все три impl связаны через `@LazySingleton(as: AppDatabase, env: [...])` — список env load-bearing, никогда не опускать.

### 9b. Реактивный `ItemDao` (watch / onSnapshots / transaction / mutate)

**Целевой путь:** `lib/data/local/<feature>/<feature>_dao.dart`
**Рабочий пример:** `lib/data/local/item/item_dao.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:sembast/sembast.dart';

@lazySingleton
class ItemDao {
  ItemDao(this._appDatabase);

  final AppDatabase _appDatabase;
  final _store = StoreRef<String, Map<String, dynamic>>.main();
  static const _storeKeyPart = 'item_';

  String _key(String id) => '$_storeKeyPart$id';

  Finder get _itemsFinder => Finder(filter: Filter.custom((r) => (r.key as String).startsWith(_storeKeyPart)));

  /// Reactive watch of a single record by id; emits null on absence/parse error.
  Future<Stream<ItemEntity?>> watch({required String id}) async {
    final db = await _appDatabase.db;
    return _store.record(_key(id)).onSnapshot(db).map((snapshot) {
      if (snapshot?.value == null) return null;
      try {
        return ItemEntity.fromJson(snapshot!.value);
      } catch (_) {
        return null;
      }
    });
  }

  /// Reactive watch of the whole store; emits the full list on every change.
  Future<Stream<List<ItemEntity>>> watchAll() async {
    final db = await _appDatabase.db;
    return _store.query(finder: _itemsFinder).onSnapshots(db).map((snapshots) {
      return snapshots
          .map((s) {
            try {
              return ItemEntity.fromJson(s.value);
            } catch (_) {
              return null;
            }
          })
          .whereType<ItemEntity>()
          .toList();
    });
  }

  Future<List<ItemEntity>> getAll() async {
    final db = await _appDatabase.db;
    final records = await _store.find(db, finder: _itemsFinder);
    return records.map((r) => ItemEntity.fromJson(r.value)).toList();
  }

  /// Single record by id; returns null on absence — the repository callback
  /// turns that into RepositoryException.notFound (no typed DaoException).
  Future<ItemEntity?> getData({required String id}) async {
    final db = await _appDatabase.db;
    final data = await _store.record(_key(id)).get(db);
    if (data == null) return null;
    return ItemEntity.fromJson(data);
  }

  Future<void> saveData(ItemEntity item) async {
    final db = await _appDatabase.db;
    await _store.record(_key(item.id)).put(db, item.toJson());
  }

  Future<void> saveAll(List<ItemEntity> items) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      for (final item in items) {
        await _store.record(_key(item.id)).put(txn, item.toJson());
      }
    });
  }

  /// Atomic read-transform-write; no-op when the record is absent.
  Future<void> mutate({required String id, required ItemEntity Function(ItemEntity current) mutator}) async {
    final db = await _appDatabase.db;
    await db.transaction((txn) async {
      final raw = await _store.record(_key(id)).get(txn);
      if (raw == null) return;
      final updated = mutator(ItemEntity.fromJson(raw));
      await _store.record(_key(id)).put(txn, updated.toJson());
    });
  }

  Future<void> deleteData({required String id}) async {
    final db = await _appDatabase.db;
    await _store.record(_key(id)).delete(db);
  }

  Future<void> cleanData() async {
    final db = await _appDatabase.db;
    await _store.delete(db, finder: _itemsFinder);
  }
}
```

Правила DAO:
- `@lazySingleton`, инжектит `AppDatabase`, использует `StoreRef<String, Map<String, dynamic>>.main()`.
- Single-record фичи используют константный `_storeKey`; multi-record — префикс `_storeKeyPart` + `_key(id)`.
- `watch()` → `Stream<Entity?>` через `onSnapshot`; `watchAll()` → `Stream<List<Entity>>` через `onSnapshots`; мутации — через `db.transaction()`.
- **Никакого типизированного `DaoException`** (слой данных без иерархии исключений — см. §9-преамбулу и [04-data-layer.md](04-data-layer.md) §5): сбой хранилища пробрасывается **сырым** исключением Sembast (его ловит catch-all-ветка `execute` → `RepositoryException.unknown`); отсутствие записи отдаётся как `null` (`getData`) или молчаливый no-op (`mutate`), а cache-miss → `notFound` решает callback репозитория.

> **Сверка со скелетом.** Путь шаблона (`lib/data/local/<feature>/<feature>_dao.dart`, подпапка `item/`) совпадает с реальным `lib/data/local/item/item_dao.dart`. Сам класс в скелете отличается store-factory и набором методов: он использует `stringMapStoreFactory.store('items')` (не `StoreRef.main()` + `_storeKeyPart`/`_key(id)`), ключует записи прямо по `item.id`, и даёт метод-сет `watch()` / `getData()` / `getById(id)` / `saveData(List<ItemEntity>)` / `upsert` / `removeById` / `cleanData` (плюс приватные `_decode` / `_tryDecode`, где битая запись молча отбрасывается). Это полностью эквивалентная реактивная форма; richer-вариант выше (`watchAll`/`mutate`/`Finder`) — каноническая ссылка для multi-record-кэша. `ItemDao` **не используется** network-only `Item`-слайсом (пагинированный список идёт мимо DAO) и подключается с первой по-настоящему кэшируемой фичей.

---

## 10. Обработка ошибок слоя данных — без типизированной иерархии исключений

> **Правило данного блюпринта:** слой данных **не** заводит собственную иерархию типизированных исключений — `ApiException`, `DaoException` и `BaseDomainExceptionHelper` намеренно отсутствуют. Единственный механизм — тонкий mixin `BaseRepositoryHelper.execute<TD>()` (см. §11): он оборачивает операцию репозитория в guarded try/catch, **обязательно** логирует через `LogRepository` и грубо мапит framework-ошибки в доменный `RepositoryException` (`DioException` → `internal`, любое другое исключение → `unknown`). Конкретные доменные коды (`notFound` при cache-miss, `unauthenticated` при 401 и т. д.) callback возвращает сам — явным `return RepositoryResult.error(exception: RepositoryException.<code>)`. Полное описание — в [04-data-layer.md](04-data-layer.md) §5; шаблон `RepositoryException`-enum — в §3e выше.

---

## 11. `BaseRepositoryHelper.execute` (с обязательным `LogRepository`) + `ItemRepositoryImpl`

### 11a. `LogRepository` — единственный канал логирования (обязателен)

> `BaseRepositoryHelper.execute` **всегда** логирует ошибку через `LogRepository` — единый канал, никакого голого `print`. Контракт интерфейса — **ровно** `debug` / `error`, без `info` / `warning` / `reportToExternal` (полная реализация — в `04-data-layer.md`):

**Целевой путь:** `lib/domain/repository/log_repository.dart`

```dart
abstract class LogRepository {
  void debug({Object? target, required String message});

  void error({Object? target, required Object error, StackTrace? stackTrace});
}
```

### 11b. `BaseRepositoryHelper` (вставить один раз на проект)

**Целевой путь:** `lib/data/exception/base_repository_helper.dart`

Mixin оборачивает операцию в try/catch, **обязательно логирует через `LogRepository`** и грубо мапит framework-ошибки в доменный `RepositoryException`. `executionFunction` возвращает **уже-обёрнутый** `RepositoryResult<TD>` (callback заканчивается `return RepositoryResult.success(data: …)` или `return RepositoryResult.error(exception: RepositoryException.<code>)`). Никакого `on BaseDomainExceptionHelper`, никакого `ApiException` / `DaoException` — ровно две catch-ветки.

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

> Маппинг **грубый**: `DioException` → `RepositoryException.internal` (сбой транспорта/HTTP), любое другое исключение → `RepositoryException.unknown`. Конкретный код (`notFound`, `unauthenticated`, …) появляется только тогда, когда callback **сам** его вернул. `target: this` — стандартный аргумент `LogRepository.error` (см. §11a / `04-data-layer.md`).

### 11c. `ItemRepositoryImpl` — DAO-stream-subscribed `BehaviorSubject`

**Целевой путь:** `lib/data/repository/<feature>/<model>_repository_impl.dart`
**Рабочий пример:** `lib/data/repository/item/item_repository_impl.dart`

Флагман для user-scoped watchable-ресурса: `@LazySingleton(as: ItemRepository, env: [dev, prod, test])`, `with BaseRepositoryHelper`, **одна подписка на DAO-стрим** (`onSnapshots`), питающая один `BehaviorSubject<RepositoryResult<...>>`. Пагинированный список — **network-only**, без DAO и без subject (carve-out из `04-data-layer.md`).

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
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_item_config.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';

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
  /// Single subscription in the constructor — never per watchItem(id) call.
  Future<void> _initSubscription() async {
    try {
      final stream = await _itemDao.watchAll();
      _itemsSubscription = stream.listen((entities) {
        _itemsStreamController.add(
          RepositoryResult<List<ItemModel>>.success(data: _itemMapper.toListModel(entities: entities)),
        );
      });
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
      _itemsStreamController.add(RepositoryResult<List<ItemModel>>.error(exception: RepositoryException.internal));
    }
  }

  @override
  Stream<RepositoryResult<ItemModel>> watchItem({required String id}) async* {
    // Cache-miss -> trigger a REST fetch; saveAll re-emits via the DAO stream.
    // A refresh failure becomes a RepositoryResult.error EMITTED INTO the stream
    // (not a raw async* error) so the subscriber sees it via match(onError:),
    // mirroring BaseRepositoryHelper.execute's coercive mapping (канон 04-data-layer.md §8).
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
    // Derive a single-resource stream from the shared cache subject; filter by id.
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
      // cache-first read: DAO returns the whole list (no typed DaoException).
      var entities = await _itemDao.getAll();
      var entity = entities.firstWhereOrNull((e) => e.id == config.id);

      // tri-state cacheOnly (03 §5.4): cacheOnly == true means cache-only —
      // on a cache miss return notFound DIRECTLY, never hit the network.
      if (entity == null && config.cacheOnly == true) {
        return RepositoryResult<ItemModel>.error(exception: RepositoryException.notFound);
      }

      // Cache hit returns UNCONDITIONALLY (cache-first for any cacheOnly value).
      if (entity != null) {
        return RepositoryResult<ItemModel>.success(data: _itemMapper.toModel(entity: entity));
      }

      // Cache miss (cacheOnly null/false) -> network refresh, then re-read from cache.
      await _refreshFromNetwork();
      entities = await _itemDao.getAll();
      entity = entities.firstWhereOrNull((e) => e.id == config.id);

      // Still absent after refresh: return the precise domain code DIRECTLY.
      return entity == null
          ? RepositoryResult<ItemModel>.error(exception: RepositoryException.notFound)
          : RepositoryResult<ItemModel>.success(data: _itemMapper.toModel(entity: entity));
    });
  }

  /// Network fetch + saveAll; the DAO onSnapshots() stream re-emits to the subject.
  /// An empty payload throws raw -> execute()'s catch-all maps it to unknown.
  Future<void> _refreshFromNetwork() async {
    final response = await _getItemsApi.execute(config: GetItemsConfig.firstPage());
    final page = response.data;
    if (page == null) {
      throw StateError('Empty response payload');
    }
    await _itemDao.saveAll(page.items);
  }

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    // Paginated server-owned list: network-only, NO DAO, NO BehaviorSubject.
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _getItemsApi.execute(config: config);
      final page = response.data;
      if (page == null) {
        throw StateError('Empty response payload'); // execute maps this to RepositoryException.unknown (04-data-layer.md §8)
      }
      final models = _itemMapper.toListModel(entities: page.items);
      // Response echoes page/page_size/total; page math is computed client-side (1-based).
      final hasMore = (page.page * page.pageSize) < page.total;
      final nextPage = hasMore ? page.page + 1 : null;
      final metadata = PageMetadata(nextPage: nextPage, total: page.total);
      return RepositoryResult.success(data: (models, metadata));
    });
  }

  @override
  Future<RepositoryResult<ItemModel>> createItem({required ItemModel item}) {
    return execute<ItemModel>(() async {
      await _itemDao.saveData(_itemMapper.toEntity(model: item));
      return RepositoryResult.success(data: item);
    });
  }

  @override
  Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item}) {
    return execute<ItemModel>(() async {
      await _itemDao.mutate(id: item.id, mutator: (_) => _itemMapper.toEntity(model: item));
      return RepositoryResult.success(data: item);
    });
  }

  @override
  Future<RepositoryResult<void>> deleteItem({required String id}) {
    return execute<void>(() async {
      await _itemDao.deleteData(id: id);
      return const RepositoryResult.success(data: null);
    });
  }

  @override
  Future<void> clean() async {
    // Clearing the DAO makes the live watchAll() stream re-emit an empty list
    // onto the shared subject — no manual subject teardown (subscription lives
    // for the singleton's lifetime, torn down only in dispose()).
    // clean() runs outside execute(), so log a storage failure instead of
    // letting the raw cleanData() exception escape uncaught.
    try {
      await _itemDao.cleanData();
    } catch (e, stackTrace) {
      logRepository.error(target: this, error: e, stackTrace: stackTrace);
    }
  }

  @disposeMethod
  Future<void> dispose() async {
    await _itemsSubscription?.cancel();
    await _itemsStreamController.close();
  }
}
```

Правила impl:
- `@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])` — биндинг на доменный контракт; список env load-bearing (Sembast env-scoped), не опускать.
- `with BaseRepositoryHelper` (без `BaseDomainExceptionHelper`); каждое тело метода, возвращающего `RepositoryResult<T>`, — в `execute<T>(() async { ... })` и заканчивается `return RepositoryResult.success/error(...)` (исключение — `clean()`: возвращает `Future<void>`, мимо `execute`).
- Watchable-ресурс подписывается на DAO-стрим **один раз в конструкторе** (`_initSubscription` поверх `watchAll()`) и питает один `BehaviorSubject<RepositoryResult<List<ItemModel>>>` — кэш-источник списка; `watchItem({id})` реплеит из него и фильтрует по `id` через `result.match` + `firstWhereOrNull` (канон 04-data-layer.md §8), никаких подписок по первому `id`. `clean()` чистит DAO (live-стрим переэмитит пустой список на subject); идёт мимо `execute`, поэтому сбой `cleanData()` оборачивается в try/catch с `logRepository.error` (best-effort, как в каноне 04-data-layer.md §8) — сырое исключение не улетает наверх. Подписка живёт всё время синглтона, гасится только в `dispose()`.
- Пагинированный список — network-only: без DAO, без subject; `PageMetadata` вычисляется клиентски — `hasMore = (page.page * page.pageSize) < page.total`, `nextPage = hasMore ? page.page + 1 : null`, `total = page.total`; бэкенд эхом возвращает `page` / `page_size` / `total`.
- `@disposeMethod` гарантирует отмену подписки и закрытие subject при teardown DI.

> **Сверка со скелетом.** Шаблон выше — **полная** референс-форма (cache-first `watchItem`/`fetchItem` поверх `ItemDao` + `BehaviorSubject` + full CRUD); она прибывает с фичей, которой нужен кэш. Скелет Feature-001 — намеренно урезанный **network-only** срез: реальный `lib/data/repository/item/item_repository_impl.dart` инжектит **только** `ItemMapper` + `GetItemsApi` (без `ItemDao`, без subject, без `_initSubscription`) — ctor `ItemRepositoryImpl(this._itemMapper, this._getItemsApi)`; реализует **только** `getItems(...)` (тело — как в `getItems` выше: `(page.page * page.pageSize) < page.total` ⇒ `nextPage`) + `clean()`, который сейчас пустой no-op `{}`. Контракт домена в скелете тоже урезан до `getItems` + `clean()` (см. §4). Источник данных за `GetItemsApi` — мок (бэкенд не выбран).

---

## 12. Dio `ApiClient` + `RequestBuilder<T>` + `RequestBuilderHelper` + `GetItemsApi`

### 12a. `ApiClient` (Dio + auth-интерсептор)

**Целевой путь:** `lib/data/remote/api/base/api_client.dart`

```dart
import 'package:dio/dio.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

class ApiClient {
  static Dio initBase({String? contentType}) {
    final appConfigRepository = getIt<AppConfigRepository>();
    final dio = Dio(
      BaseOptions(
        baseUrl: '${appConfigRepository.config.apiUrl}/api/',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: contentType ?? 'application/json',
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
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
      ),
    );
    return dio;
  }
}
```

> На non-2xx Dio бросает `DioException` — он пробрасывается до `DioException`-ветки `execute` (→ `RepositoryException.internal`). API-класс **не** мапит в типизированный `ApiException` (его нет — см. §10): никакого `_mapDioException`. Сохраняем паттерн `RequestBuilder`/`RequestBuilderHelper`.

> Конкретный контракт авторизации в интерсепторе (`Authorization: Bearer <token>`, `getUserAuthIdToken`, модель access/refresh-токенов и любые security-заголовки, например HMAC-подпись) — это **пример** (бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт). У NOX **один** бэкенд-хост (ещё не выбран), поэтому `ApiClient` несёт **единственный** Dio/host (`initBase` / `baseClient`); никакого второго хоста нет. Паттерн (Dio + auth-интерсептор) сохраняется как есть; меняются только конкретные заголовки, `baseUrl` и схема токенов под реальный бэкенд NOX.

> **Сверка со скелетом.** Шаблон выше — целевая форма со static-фабрикой по пути `lib/data/remote/api/base/api_client.dart`. В скелете Feature-001 `ApiClient` пока **тонкая** `@lazySingleton`-обёртка над `Dio` по плоскому пути `lib/data/remote/api_client.dart` (ctor `ApiClient() : dio = Dio(BaseOptions(connectTimeout: ..., receiveTimeout: ...))`, без `baseUrl`, без auth-интерсептора, без static-фабрик) — base URL / auth / security-заголовки помечены example/TBD прямо в docstring класса. Он апгрейдится до static-factory-формы выше с первой реальной сетевой фичей.

### 12b. `BaseApiRepository` + `RequestBuilder<T>` + `RequestBuilderHelper`

**Целевой путь:** `lib/data/remote/api/base/base_api_repository.dart`

```dart
import 'package:dio/dio.dart' as dio;
import 'package:nox_app/data/remote/api/base/api_client.dart';

abstract class BaseApiRepository {
  /// The single NOX backend host (example/TBD — baseUrl/auth/signing finalized
  /// with the chosen NOX backend). One host only; there is no second client.
  dio.Dio get baseClient => ApiClient.initBase();
}
```

**Целевой путь:** `lib/data/remote/request_builder/base/request_builder.dart`

```dart
abstract class RequestBuilder<T> {
  Future<Map<String, dynamic>> buildBody(T config) async => {};

  Future<String> buildPath(T config, String basePath, {Map<String, String>? params}) async {
    if (params == null || params.isEmpty) {
      return basePath;
    }
    return '$basePath?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  Future<Map<String, String>> buildHeaders(T config) async => {};
}
```

**Целевой путь:** `lib/data/remote/request_builder/base/request_builder_helper.dart`

```dart
import 'package:nox_app/data/remote/request_builder/base/request_builder.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

mixin RequestBuilderHelper<T extends RequestBuilder> {
  Future<Map<String, dynamic>> buildBody(RepositoryConfig config) async => getIt<T>().buildBody(config);

  Future<String> buildPath(RepositoryConfig config, String basePath) async => getIt<T>().buildPath(config, basePath);

  Future<Map<String, String>> buildHeaders(RepositoryConfig config) async => getIt<T>().buildHeaders(config);
}
```

### 12c. `GetItemsApi` + request builder (обёртка в `ResponseEntity`)

**Целевой путь:** `lib/data/remote/api/<feature>/get_<feature>s_api.dart`
**Рабочий пример:** `lib/data/remote/api/item/get_items_api.dart`

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
    final path = await buildPath(config, 'v1/items');
    final response = await baseClient.get(path);
    return ResponseEntity<ItemsEntity>.fromJson(response.data);
  }
}
```

**Целевой путь:** `lib/data/remote/request_builder/<feature>/get_<feature>s_api_request_builder.dart`
**Рабочий пример:** `lib/data/remote/request_builder/item/get_items_api_request_builder.dart`

```dart
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/request_builder/base/request_builder.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

@lazySingleton
class GetItemsApiRequestBuilder extends RequestBuilder<GetItemsConfig> {
  @override
  Future<String> buildPath(GetItemsConfig config, String basePath, {Map<String, String>? params}) async {
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

> Конкретный путь эндпоинта (`v1/items`), имена query-параметров (`page` / `page_size` / `search`) и форма ответа — это **пример** (бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт). Для первой реальной фичи — списка чатов — путь, параметры и пагинация финализируются позже вместе с бэкендом NOX; паттерн `GetItemsApi` + request builder + обёртка в `ResponseEntity` остаётся неизменным.

> **Сверка со скелетом.** Шаблон выше (`GetItemsApi extends BaseApiRepository with RequestBuilderHelper` + отдельный `GetItemsApiRequestBuilder`) — целевая форма реальной сетевой фичи. В скелете Feature-001 `lib/data/remote/api/item/get_items_api.dart` — самодостаточный `@lazySingleton`-**мок** (без `BaseApiRepository`, без `RequestBuilderHelper`, без `buildPath`): он синтезирует страницы `ItemEntity` (всего 47 записей) и возвращает `ResponseEntity<ItemsEntity>(success: true, data: ...)`. Дерева `lib/data/remote/request_builder/` и `base_api_repository.dart` в коде **пока нет** — RequestBuilder-обвязка прибывает с первой реальной сетевой фичей (список чатов), потому что бэкенд NOX не выбран.

---

## 13. BLoC-трио (`@freezed`) — `ItemListEvent` / `ItemListState` / `ItemListBloc`

> Этот раздел **полностью заменяет** ручные sealed-`Equatable` события/состояния из старого скелета. BLoC = Freezed: `@freezed sealed` union'ы для State и Event, тонкий `BaseBloc<E, S>` с `executeLogic`, производная логика — в extension-геттерах, `copyWith` для переходов. Никакого `fromJson` на BLoC-типах (только `.freezed.dart`). Канонические имена под-состояний — `Initializing` / `Initialized` / `Error`, как `const factory` конструкторы. Пагинация — `infinite_scroll_pagination ^5.1.1` v5 stateless: `PagingState` живёт **в стейте**, не в `PagingController`; полный контракт и `PagingStateExt.applyPage` — в `07-pagination.md`. **Каждая навигируемая страница владеет собственным BLoC — даже logic-less (минимальный trio или value-BLoC а-ля `AppRootBloc`; Принцип 5.1 в [08](08-conventions-and-constitution.md)); переиспользуемые виджеты BLoC не требуют.**

### 13a. `BaseBloc<E, S>` (вставить один раз на проект)

**Целевой путь:** `lib/presentation/base/base_bloc.dart`

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

abstract class BaseBloc<E, S> extends Bloc<E, S> {
  BaseBloc(super.initialState);

  FutureOr<void> executeLogic(
    FutureOr<void> Function() logic, {
    FutureOr<void> Function(String? error, dynamic exception, StackTrace stackTrace)? onError,
  }) async {
    try {
      await logic();
    } catch (e, s) {
      await onError?.call('$e, $s', e, s);
    }
  }
}
```

> `executeLogic` без `onError` **молча проглатывает** исключение (никакого emit, никакого rethrow) — осознанная асимметрия. Для загрузки списка всегда передавайте `onError`, эмитящий `Error`-состояние (см. §13d).

### 13b. `ItemListEvent` (`@freezed sealed` union)

**Целевой путь:** `lib/presentation/pages/<page>_page/bloc/<page>_event.dart`
**Рабочий пример:** `lib/presentation/pages/item_list_page/bloc/item_list_event.dart`

```dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListEvent with _$ItemListEvent {
  /// Triggered once from initState via `..add(const ItemListEvent.initialize())`.
  const factory ItemListEvent.initialize() = Initialize;

  /// Load a page. `reset: true` clears the list and reloads from page one.
  const factory ItemListEvent.loadItems({@Default(false) bool reset}) = LoadItems;

  /// Pull-to-refresh; the completer resolves when the refresh finishes.
  const factory ItemListEvent.refreshRequested({required Completer<void> completer}) = RefreshRequested;

  /// Search box text changed (debounced + restartable in the bloc).
  const factory ItemListEvent.updateSearchQuery({required String query}) = UpdateSearchQuery;

  /// User tapped a row — drives a navigation side effect.
  const factory ItemListEvent.showItemDetails({required ItemModel item}) = ShowItemDetails;
}
```

### 13c. `ItemListState` (`@freezed sealed` union + extension-геттеры)

**Целевой путь:** `lib/presentation/pages/<page>_page/bloc/<page>_state.dart`
**Рабочий пример:** `lib/presentation/pages/item_list_page/bloc/item_list_state.dart`

```dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListState with _$ItemListState {
  const factory ItemListState.initializing() = Initializing;

  const factory ItemListState.initialized({
    required PagingState<String, ItemModel> pagingState,
    @Default(<ItemModel>[]) List<ItemModel> items,
    @Default(GetItemsConfig.defaultPage) int nextPage,
    @Default(false) bool isLastPage,
    @Default(0) int total,
    @Default(false) bool loadingInProgress,
    @Default(false) bool refreshInProgress,
    @Default('') String searchQuery,
  }) = Initialized;

  const factory ItemListState.error({BaseRepositoryException? exception}) = Error;
}

extension ItemListStateExt on ItemListState {
  /// Flat item list (single source of truth for the UI is the `items` field).
  List<ItemModel> get pagedItems => switch (this) {
        Initialized(:final items) => items,
        _ => const [],
      };

  bool get hasMore => switch (this) {
        Initialized(:final isLastPage) => !isLastPage,
        _ => false,
      };
}
```

> Производные значения (`pagedItems`, `hasMore`) — в `extension`, не в теле `@freezed`. Каноническая форма (одна-элемент-на-страницу, `K = String = item id`) держит плоский список в поле `items`; `pagingState.pages` остаётся page-of-pages для `PagedListView`.
> **Имена вариантов union — BARE** (`Initializing` / `Initialized` / `Error`), как в реальном `item_list_state.dart`; `switch`-ится по голым `Initializing()` / `Initialized()` / `Error()`. Префиксные имена (`ItemListInitializing` / `ItemListInitialized` / `ItemListError`) — допустимый вариант для избежания коллизий имён, если в одном файле сходятся несколько union-ов; в этом блюпринте канон — bare, поэтому все примеры приведены к bare-форме.

### 13d. `ItemListBloc` (extends `BaseBloc`, `applyPage`, `PublishSubject` side-effects, restartable search)

**Целевой путь:** `lib/presentation/pages/<page>_page/bloc/<page>_bloc.dart`
**Рабочий пример:** `lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart`

```dart
import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

part 'item_list_bloc.freezed.dart';
part 'item_list_event.dart';
part 'item_list_state.dart';

class ItemListBloc extends BaseBloc<ItemListEvent, ItemListState> {
  ItemListBloc() : super(const ItemListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadItems>(_onLoadItems, transformer: sequential());
    on<RefreshRequested>(_onRefreshRequested, transformer: droppable());
    on<UpdateSearchQuery>(_onUpdateSearchQuery, transformer: restartable());
    on<ShowItemDetails>(_onShowItemDetails);
  }

  final _itemRepository = getIt<ItemRepository>();

  /// One-shot navigation side effects — listened by the page via a BlocListener-like stream.
  final _showItemDetails = PublishSubject<ItemModel>();

  Stream<ItemModel> get showItemDetails => _showItemDetails.stream;

  @override
  Future<void> close() {
    _showItemDetails.close();
    return super.close();
  }

  FutureOr<void> _onInitialize(Initialize event, Emitter<ItemListState> emit) async {
    emit(ItemListState.initialized(pagingState: PagingState<String, ItemModel>(), searchQuery: ''));
    add(const ItemListEvent.loadItems(reset: true));
  }

  FutureOr<void> _onLoadItems(LoadItems event, Emitter<ItemListState> emit) async {
    final state = this.state;
    if (state is! Initialized) return;
    if (state.loadingInProgress) return;

    final isReset = event.reset;
    if (!isReset && !(state.pagingState.hasNextPage)) return;

    final nextPageKey = isReset ? GetItemsConfig.defaultPage : state.nextPage;
    final existingList = isReset ? <ItemModel>[] : state.items;
    final basePagingState = isReset
        ? PagingState<String, ItemModel>(isLoading: true)
        : state.pagingState.copyWith(isLoading: true, error: null);

    emit(state.copyWith(loadingInProgress: true, items: existingList, pagingState: basePagingState));

    await executeLogic(
      () async {
        final config = isReset
            ? GetItemsConfig.firstPage(search: state.searchQuery)
            : GetItemsConfig.nextPage(page: nextPageKey, search: state.searchQuery);

        final result = await _itemRepository.getItems(config: config);

        final live = this.state;
        if (live is! Initialized) return;

        result.match<void>(
          onData: (data) {
            final (items, PageMetadata metadata) = data;
            final r = basePagingState.applyPage(
              existingList: existingList,
              response: (items, metadata),
              keyExtractor: (e) => e.id,
            );
            emit(live.copyWith(
              items: r.updatedList,
              pagingState: r.pagingState,
              nextPage: r.nextPage ?? live.nextPage, // null => страниц больше нет, координату не двигаем
              isLastPage: metadata.nextPage == null,
              total: metadata.total,
              loadingInProgress: false,
            ));
          },
          onError: (exception) {
            emit(live.copyWith(pagingState: live.pagingState.copyWith(isLoading: false, error: exception), loadingInProgress: false));
          },
        );
      },
      onError: (error, exception, stackTrace) {
        final live = this.state;
        if (live is Initialized) {
          emit(live.copyWith(loadingInProgress: false, pagingState: live.pagingState.copyWith(isLoading: false)));
        }
      },
    );
  }

  FutureOr<void> _onRefreshRequested(RefreshRequested event, Emitter<ItemListState> emit) async {
    final state = this.state;
    if (state is! Initialized) {
      event.completer.complete();
      return;
    }
    emit(state.copyWith(refreshInProgress: true));
    add(const ItemListEvent.loadItems(reset: true));
    // Resolve the pull-to-refresh completer once the reset load settles.
    await stream.firstWhere((s) => s is Initialized && !s.loadingInProgress).timeout(
          const Duration(seconds: 30),
          onTimeout: () => this.state,
        );
    final settled = this.state;
    if (settled is Initialized) {
      emit(settled.copyWith(refreshInProgress: false));
    }
    event.completer.complete();
  }

  FutureOr<void> _onUpdateSearchQuery(UpdateSearchQuery event, Emitter<ItemListState> emit) async {
    await Future<void>.delayed(const Duration(milliseconds: 300)); // restartable() cancels stale debounces
    final state = this.state;
    if (state is! Initialized) return;
    if (state.searchQuery == event.query) return;
    emit(state.copyWith(searchQuery: event.query));
    add(const ItemListEvent.loadItems(reset: true));
  }

  FutureOr<void> _onShowItemDetails(ShowItemDetails event, Emitter<ItemListState> emit) async {
    _showItemDetails.add(event.item);
  }
}
```

Правила BLoC:
- `extends BaseBloc<Event, State>`; `super(const ItemListState.initializing())`; `on<Variant>(_handler)` на каждый вариант.
- Репозитории — через `getIt<ItemRepository>()`; одноразовые side-effects (навигация) — через `PublishSubject`, закрываемый в `close()`.
- Загрузка страницы — через `executeLogic(..., onError: ...)`; после каждого `await` пере-читать `this.state`.
- Поиск — `restartable()` (stale debounce отменяется); load — `sequential()` (строго по очереди, без гонок страниц); refresh — `droppable()` (повторный pull в полёте игнорируется). Пагинация — через `PagingStateExt.applyPage` (см. §14 и `07-pagination.md`).
- Никаких `result.data!` — только `match(onData:, onError:)`.

> **Сверка со скелетом.** Трио выше — **полная** референс-форма (поиск + pull-to-refresh + навигация по тапу). Скелет Feature-001 — намеренно урезанный срез верификационной харни: реальный `ItemListEvent` = `{ initialize(), loadItems({@Default(false) bool reset}) }` (без `refreshRequested` / `updateSearchQuery` / `showItemDetails`); реальный `ItemListState.initialized(...)` без `refreshInProgress` / `searchQuery`, `nextPage` остаётся non-nullable `@Default(GetItemsConfig.defaultPage) int nextPage`; `ItemListBloc` регистрирует только `Initialize` + `LoadItems` (`sequential()`), без `PublishSubject`-side-effects. Расширения (поиск/refresh/навигация) добавляются по той же форме, что в шаблоне, когда фича их требует.

---

## 14. `PagingStateExt.applyPage` (v5 stateless, generic over `K`)

**Целевой путь:** `lib/presentation/pagination/paging_state_ext.dart`

Переиспользуемое расширение, инкапсулирующее сборку `PagingState` v5 (page-of-pages + keys + `hasNextPage`). Generic over `K`: одна каноническая форма, принимает `(List<T>, PageMetadata)` и возвращает запись `(updatedList, pagingState, nextPage)`. OFFSET-форма по умолчанию: `K = String` (id элемента, один-элемент-на-страницу), `hasNextPage` выводится из `meta.nextPage != null`. Полный контракт — в `07-pagination.md`.

```dart
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';

extension PagingStateExt<K, T> on PagingState<K, T> {
  /// Appends a freshly fetched page into v5 paging state and returns the flat
  /// list + the updated PagingState + the next page (null on the last page).
  ({List<T> updatedList, PagingState<K, T> pagingState, int? nextPage}) applyPage({
    required List<T> existingList,
    required (List<T>, PageMetadata) response,
    required K Function(T) keyExtractor,
  }) {
    final (incoming, meta) = response;
    final updatedList = [...existingList, ...incoming];
    final isLastPage = meta.nextPage == null;
    final pages = updatedList.map((e) => [e]).toList();
    final keys = updatedList.map(keyExtractor).toList();
    final isNoItems = updatedList.isEmpty && isLastPage;
    final newPagingState = isNoItems
        ? copyWith(pages: <List<T>>[], keys: <K>[], hasNextPage: false, isLoading: false)
        : copyWith(pages: pages, keys: keys, hasNextPage: !isLastPage, isLoading: false);
    return (updatedList: updatedList, pagingState: newPagingState, nextPage: meta.nextPage);
  }
}
```

> Вызов: `final r = state.pagingState.applyPage(existingList: state.items, response: (items, meta), keyExtractor: (e) => e.id);` — затем `emit(copyWith(items: r.updatedList, pagingState: r.pagingState, nextPage: r.nextPage))` (см. §13d). Cursor-секция в `07-pagination.md` показывает тот же helper с `CursorPaginationMetadata`, возвращающий `nextCursor`. Ошибку отдавайте в `pagingState.error` (`copyWith(error: exception, isLoading: false)`) — v5 error-builder'ы (`PagedChildBuilderDelegate.firstPageErrorIndicatorBuilder` / `newPageErrorIndicatorBuilder`) рендерят из этого поля.

---

## 15. Страница — `ItemListPage` (`BaseStatePage`, `PagedListView.separated`, `BlocSelector`)

### 15a. `BaseStatePage<T>` (вставить один раз на проект)

**Целевой путь:** `lib/presentation/pages/base/base_state_page.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

abstract class BaseStatePage<T extends StatefulWidget> extends State<T> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _useDrawerValue = false;

  bool get useDrawer => _useDrawerValue;

  set useDrawer(bool value) {
    if (value != _useDrawerValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _useDrawerValue = value);
      });
    }
  }

  void closeDrawer() {
    if (useDrawer) {
      scaffoldKey.currentState?.closeDrawer();
    }
  }

  /// Platform-aware AppBar factory. Override per page; return null for no AppBar.
  /// Default: a thin status-bar spacer on iOS; null on Android and on desktop
  /// (Windows / macOS / Linux). Width-driven adaptive chrome (NavigationBar <->
  /// NavigationRail) lives in the shell, not here — see 00/05.
  PreferredSizeWidget? buildAppBar() {
    if (Platform.isIOS) {
      return PreferredSize(
        preferredSize: Size.fromHeight(AppSpacingTokens.s28),
        child: SizedBox(height: AppSpacingTokens.s28),
      );
    }
    return null;
  }
}
```

### 15b. `ItemListPage`

**Целевой путь:** `lib/presentation/pages/<page>_page/<page>_page.dart`
**Рабочий пример:** `lib/presentation/pages/item_list_page/item_list_page.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/item_details_page/item_details_page.dart';
import 'package:nox_app/presentation/pages/item_list_page/bloc/item_list_bloc.dart';
import 'package:nox_app/presentation/widgets/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/app_progress_widget.dart';
import 'package:nox_app/presentation/widgets/app_refresh_indicator_widget.dart';

class ItemListPage extends StatefulWidget {
  const ItemListPage({super.key});

  static const routeName = '/items';

  static Route route() {
    return MaterialPageRoute(
      builder: (_) => const ItemListPage(),
      settings: const RouteSettings(name: routeName),
    );
  }

  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends BaseStatePage<ItemListPage> {
  late final ItemListBloc _bloc;
  StreamSubscription<ItemModel>? _detailsSubscription;

  @override
  void initState() {
    _bloc = ItemListBloc()..add(const ItemListEvent.initialize());
    _detailsSubscription = _bloc.showItemDetails.listen((item) {
      if (mounted) {
        Navigator.of(context).push(ItemDetailsPage.route(itemId: item.id));
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _detailsSubscription?.cancel();
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ItemListBloc>.value(
      value: _bloc,
      child: Scaffold(
        key: scaffoldKey,
        appBar: buildAppBar(),
        body: SafeArea(
          child: BlocBuilder<ItemListBloc, ItemListState>(
            builder: (context, state) {
              return switch (state) {
                Initializing() => const AppProgressWidget(),
                Error() => AppErrorWidget(onTryAgain: () => _bloc.add(const ItemListEvent.initialize())),
                Initialized() => _buildList(context, state),
              };
            },
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, Initialized state) {
    return AppRefreshIndicatorWidget(
      onRefresh: () {
        final completer = Completer<void>();
        _bloc.add(ItemListEvent.refreshRequested(completer: completer));
        return completer.future;
      },
      child: PagedListView<String, ItemModel>.separated(
        state: state.pagingState,
        fetchNextPage: () => _bloc.add(const ItemListEvent.loadItems()),
        builderDelegate: PagedChildBuilderDelegate<ItemModel>(
          itemBuilder: (context, item, index) => ListTile(
            key: ValueKey(item.id),
            title: Text(item.name),
            subtitle: Text(item.id),
            onTap: () => _bloc.add(ItemListEvent.showItemDetails(item: item)),
          ),
          firstPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
          newPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
          noItemsFoundIndicatorBuilder: (_) => const AppEmptyContentWidget(),
          firstPageErrorIndicatorBuilder: (_) => AppErrorWidget(onTryAgain: () => _bloc.add(const ItemListEvent.loadItems(reset: true))),
          newPageErrorIndicatorBuilder: (_) => AppErrorWidget(onTryAgain: () => _bloc.add(const ItemListEvent.loadItems())),
        ),
        separatorBuilder: (context, index) => const Divider(height: 1),
      ),
    );
  }
}
```

Правила страницы:
- `StatefulWidget` с `const` ctor, `static const routeName`, `static Route route()` → `MaterialPageRoute` с `RouteSettings(name: routeName)`.
- State наследует `BaseStatePage<ItemListPage>`; BLoC создаётся в `initState()` с `..add(const ItemListEvent.initialize())`, закрывается в `dispose()`.
- Рендер — `switch (state)` по Freezed-вариантам (`Initializing` / `Error` / `Initialized`).
- Список — `PagedListView<String, T>.separated` (v5 stateless, `K = String = item id`: `state: pagingState`, `fetchNextPage` диспетчит событие, не фетчит). Pull-to-refresh — `AppRefreshIndicatorWidget`, разрешающий completer.

> **Сверка со скелетом.** Шаблон выше — целевая форма навигируемой страницы (`routeName` + `route()` + собственный `Scaffold` + pull-to-refresh + навигация по тапу; Принцип 5.1 / инвариант 3a). Реальный `lib/presentation/pages/item_list_page/item_list_page.dart` в скелете Feature-001 — verification-харня на мок-данных, отрендеренная как тело таба Chats **внутри** `AppShell` (свой `Scaffold` не заводит, `routeName`/`route()` нет, без pull-to-refresh/навигации). Это допустимое упрощение скелета (placeholder-страницы пока stateless, у `AppShell` нет своего BLoC) до прихода реальных фич; целевая форма — шаблон выше.

### 15c. Страница с параметром — `ItemDetailsPage`

**Целевой путь:** `lib/presentation/pages/item_details_page/item_details_page.dart`

```dart
class ItemDetailsPage extends StatefulWidget {
  const ItemDetailsPage({super.key, required this.itemId});

  final String itemId;

  static const routeName = '/item-details';

  static Route route({required String itemId}) {
    return MaterialPageRoute(
      builder: (_) => ItemDetailsPage(itemId: itemId),
      settings: const RouteSettings(name: routeName),
    );
  }

  @override
  State<ItemDetailsPage> createState() => _ItemDetailsPageState();
}
```

> **Эта страница тоже навигируемая** (`routeName` + `route()`) ⇒ как и `ItemListPage`, **обязана иметь собственный BLoC** (Принцип 5.1): `ItemDetailsBloc extends BaseBloc<ItemDetailsEvent, ItemDetailsState>` с трио `Initializing` / `Initialized(item)` / `Error`, создаётся в `initState()` (`..add(const ItemDetailsEvent.initialize())`), закрывается в `dispose()`. Выше показан только `StatefulWidget`-скелет с `route()`-фабрикой (демонстрирует проброс параметра `itemId`); BLoC-обвязка — по тому же шаблону, что и §15b. Навигируемой страницы **без** BLoC быть не должно.

### 15d. `AppRefreshIndicatorWidget`

**Целевой путь:** `lib/presentation/widgets/app_refresh_indicator_widget.dart`

```dart
import 'package:flutter/material.dart';

class AppRefreshIndicatorWidget extends StatelessWidget {
  const AppRefreshIndicatorWidget({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}
```

---

## 16. `AppColors` (`ThemeExtension`) + Light/Dark + `AppTheme.light()/dark()`

> Тема = light + dark через `ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `context.appColors`, `themeMode` едет из `AppRootBloc`. Полная палитра и токены — в `06-theming.md`; здесь — минимальный заготовочный шаблон.

### 16a. `AppColors`

**Целевой путь:** `lib/design/theme/app_colors.dart`

```dart
import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surfaceMuted,
    required this.dividerSubtle,
  });

  final Color surfaceMuted;
  final Color dividerSubtle;

  @override
  AppColors copyWith({Color? surfaceMuted, Color? dividerSubtle}) {
    return AppColors(
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      dividerSubtle: dividerSubtle ?? this.dividerSubtle,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      dividerSubtle: Color.lerp(dividerSubtle, other.dividerSubtle, t)!,
    );
  }
}

class LightAppColors extends AppColors {
  const LightAppColors()
      : super(
          surfaceMuted: const Color(0xFFF2F2F2),
          dividerSubtle: const Color(0xFFBDBDBD),
        );
}

class DarkAppColors extends AppColors {
  const DarkAppColors()
      : super(
          surfaceMuted: const Color(0xFF2D2D2D),
          dividerSubtle: const Color(0xFF000000),
        );
}

extension AppColorsExtension on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
```

### 16b. `AppTheme.light()/dark()`

**Целевой путь:** `lib/design/theme/app_theme.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData.light().copyWith(
      extensions: const <ThemeExtension<dynamic>>[LightAppColors()],
    );
  }

  static ThemeData dark() {
    return ThemeData.dark().copyWith(
      extensions: const <ThemeExtension<dynamic>>[DarkAppColors()],
    );
  }
}
```

Использование: `context.appColors.dividerSubtle`. `themeMode` поставляется `AppRootBloc` (см. `05-presentation-layer.md` / `06-theming.md`).

---

## 17. Сквозные артефакты — DI, aliases, токены, флаги, строки

### 17a. DI-регистрации (через аннотации)

Большинство артефактов регистрируется аннотациями и подхватывается `build_runner`:
- DAO, mappers, API-классы, request builders, `LogRepository` impl → `@lazySingleton`.
- Repository impl → `@LazySingleton(as: Interface, env: [Environment.dev, Environment.prod, Environment.test])`.
- Env-специфичные классы (`AppDatabaseProd` / `AppDatabaseDev` / `AppDatabaseTest`) → `@LazySingleton(as: AppDatabase, env: [...])`.

После добавления/изменения аннотации перегенерируйте `*.config.dart`:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

> Makefile-обёртка `make generate` — опциональный шорткат над той же командой; первичная команда codegen — `fvm dart run build_runner build --delete-conflicting-outputs` (см. `12-dev-commands.md`).

### 17b. Единый bootstrap DI

**Целевой путь:** `lib/di/configure_dependencies.dart`

Единый `configureDependencies(String env)` + единый `@InjectableInit(initializerName: r'$initGetIt')` + единый сгенерированный `configure_dependencies.config.dart` (полное описание — в `02-dependency-injection.md`).

```dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.config.dart';

final getIt = GetIt.instance;

@InjectableInit(initializerName: r'$initGetIt')
Future<void> configureDependencies(String env) async {
  getIt.$initGetIt(environment: env);
}
```

### 17c. `global_aliases.dart` (удобные геттеры)

**Целевой путь:** `lib/di/global_aliases.dart`

```dart
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

/// Cross-cutting
LogRepository get logRepository => getIt<LogRepository>();

/// Repositories
ItemRepository get itemRepository => getIt<ItemRepository>();
```

### 17d. `feature_flags.dart`

**Целевой путь:** `lib/general/feature_flags.dart`

```dart
/// Compile-time / config-time feature toggles. Keep flags additive and short-lived.
abstract final class FeatureFlags {
  const FeatureFlags._();

  static const bool enableSearch = true;

  static const bool enablePullToRefresh = true;
}
```

### 17e. `text_constants.dart`

**Целевой путь:** `lib/general/text_constants.dart`

```dart
/// All user-facing strings (English). No literal copy in widgets.
/// Migration-ready for ARB + flutter_localizations (separate i18n feature).
abstract final class TextConstants {
  const TextConstants._();

  static const String appName = 'NOX';

  // App shell destinations (FR-004)
  static const String chats = 'Chats';
  static const String settings = 'Settings';

  // Generic states
  static const String errorGeneralTitle = 'Something went wrong';
  static const String actionTryAgain = 'Try again';
  static const String noData = 'Nothing here yet';
  static const String comingSoon = 'Coming soon';
}
```

> UI-строки — **только английский** (язык продукта — English + Ukrainian; русский UI-языком не бывает). Строки в этом файле остаются английскими даже внутри русскоязычных доков.

> **Migration-ready.** Файл должен быть пригоден к будущему переносу на локализацию (ARB + `flutter_localizations`, отдельный таск — см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md) §7): одна `static const` на строку, параметризованные строки — методами (`static String greeting(String n) => 'Hello, $n';`), без рантайм-конкатенации; имена ключей стабильные и говорящие (станут ARB-ключами).

### 17f. Четыре класса токенов

> Цвета берутся **не** из статического токен-класса, а из `AppColors` `ThemeExtension` через `context.appColors` (см. §16). Класса `AppRadiusTokens` нет. Каноническая четвёрка статических токен-классов — `AppSpacingTokens` (responsive: `static double get sN => N * _scale`, где `_scale => (1.w + 1.h) / 2` через `flutter_screenutil`, **не** const-литералы; геттеры, а не `final`-поля, чтобы scale вычислялся лениво/desktop-aware), `AppTextStyleTokens` (color-injecting factory-методы, **не** const `TextStyle`), `AppOverlayStyleTokens`, `AppImagesTokens` (рукописный реестр путей ассетов). `AppColorsTokens` нет — цвет приходит только из `context.appColors`.

**Целевой путь:** `lib/design/app_spacing_tokens.dart`

```dart
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Responsive spacing scale. Each step is the design-px value scaled by
/// flutter_screenutil, so it adapts to the device.
abstract final class AppSpacingTokens {
  const AppSpacingTokens._();

  // Mean of width/height scale factors, so spacing stays balanced on extreme
  // aspect ratios (desktop/landscape), not just width-driven (blueprint 06 §4).
  static double get _scale => (1.w + 1.h) / 2;

  static double get s4 => 4 * _scale;
  static double get s8 => 8 * _scale;
  static double get s12 => 12 * _scale;
  static double get s16 => 16 * _scale;
  static double get s24 => 24 * _scale;
  static double get s28 => 28 * _scale;
  static double get s32 => 32 * _scale;
}
```

**Целевой путь:** `lib/design/app_text_style_tokens.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Typography scale. Color-injecting factory methods (NOT const TextStyle) —
/// callers pass the resolved color from `context.appColors`.
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();

  static TextStyle body({required Color color}) => TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w400, color: color);

  static TextStyle title({required Color color}) => TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600, color: color);

  static TextStyle caption({required Color color}) => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w400, color: color);
}
```

**Целевой путь:** `lib/design/app_overlay_style_tokens.dart`

```dart
import 'package:flutter/services.dart';

/// System UI overlay (status/nav bar) styles per brightness.
abstract final class AppOverlayStyleTokens {
  const AppOverlayStyleTokens._();

  static const SystemUiOverlayStyle light = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static const SystemUiOverlayStyle dark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
```

**Целевой путь:** `lib/design/app_images_tokens.dart`

```dart
/// Asset path registry. No literal asset strings in widgets.
abstract final class AppImagesTokens {
  const AppImagesTokens._();

  static const String _base = 'assets/png';

  static const String logo = '$_base/logo.png';
  static const String emptyState = '$_base/empty_state.png';
}
```

> **Два канала ассетов сосуществуют в коде.** Рядом с рукописным `AppImagesTokens` (`_base = 'assets/png'`) код держит сгенерированный `lib/design/gen/assets.gen.dart` (`flutter_gen`, gitignored, регенерится `build_runner`; ассет-директории — в `pubspec.yaml::flutter.assets`, бандлятся в APK/IPA/desktop-бандл). Использование flutter_gen: `Image.asset(Assets.png.logo.path)` / `Assets.png.logo.image()`. `flutter_gen` — намеренный канонический канал (type-safe, авто-синхронизация с `pubspec.yaml`); `AppImagesTokens` — convenience-реестр строковых путей. Оба присутствуют в `lib/design/`.

### 17g. `main.dart` (runZonedGuarded + allReady)

**Целевой путь:** `lib/main.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/presentation/app/app_root.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final flavor = AppFlavor.getFlavor();
      final env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev;

      await Future.wait<dynamic>([
        configureDependencies(env),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
      await getIt.allReady();
      await getIt<AppConfigRepository>().initialize(flavorType: flavor);

      runApp(const AppRoot());
    },
    (error, stack) {
      if (getIt.isRegistered<LogRepository>()) {
        getIt<LogRepository>().error(target: 'main', error: error, stackTrace: stack);
      }
    },
  );
}
```

> `AppFlavor.getFlavor()` читает `String.fromEnvironment('app.flavor')`; маппинг `AppFlavorType.prod → Environment.prod`, `AppFlavorType.stage → Environment.dev` — в `09-build-and-secrets-infra.md`.
> `setPreferredOrientations([portraitUp])` — лок ориентации для iOS/Android; десктоп (Windows / macOS / Linux) этот вызов игнорирует (одно окно, ориентацией не управляет). На все пять платформ значения flavor приходят через `--dart-define-from-file` (см. `09-build-and-secrets-infra.md`).
> Отдельного BLoC-обозревателя нет: логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует), а ошибки BLoC-обработчиков оборачиваются `BaseBloc.executeLogic` — поэтому отдельный `Bloc.observer` не нужен.

---

## Чеклист

После применения шаблонов этого документа у вас должно быть:

- [ ] Доменная модель `lib/domain/model/<feature>/<model>_model.dart` (+ enum-файл), реэкспортированная из `models.dart`, `@freezed` **без** `.g.dart`, логика в `extension`.
- [ ] Enum статуса в домене; любой нестандартный `JsonConverter` — в `lib/data/entity/`, **не** в `lib/domain/`.
- [ ] `RepositoryResult<T>` (`@freezed sealed`, success/error XOR) + урезанный `match(onData, onError)` + маркеры `RepositoryConfig` / `BaseRepositoryException` + enum `RepositoryException`. Ноль `result.data!` в коде.
- [ ] Контракт `lib/domain/repository/<feature>/<feature>_repository.dart`: все методы → `RepositoryResult<T>` / `Stream<RepositoryResult<T>>`; список → `(List<T>, PageMetadata)`.
- [ ] `GetItemsConfig` (`@freezed implements RepositoryConfig`, поля `page` + `search?`, фабрики `firstPage`/`nextPage`, статические `pageSize` = 20 / `defaultPage` = 1 — 1-based; никакого `page: 0`; никаких магических чисел страницы в BLoC — первая страница выражается только фабрикой `Get<Name>sConfig.firstPage()`) и `GetItemConfig` (`id` + `cacheOnly`).
- [ ] Entity `lib/data/entity/<feature>/<model>_entity.dart` (только базовые типы; enum как String, дата как ISO-8601 String) + обёртка `ItemsEntity` + доменный `PageMetadata` (OFFSET).
- [ ] `ResponseEntity<T>` + реестр `EntityConverter<E>` (новый entity — в **обе** цепочки).
- [ ] `BaseMapper<E, M, AdResult, AdParam>` + mapper `@lazySingleton`, вся коэрция enum/DateTime внутри него.
- [ ] Env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory) + реактивный DAO (`watch`/`onSnapshots`/`transaction`/`mutate`); **без типизированного `DaoException`** — сырой throw при сбое хранилища, `null`/no-op при отсутствии записи.
- [ ] Слой данных **без** типизированной иерархии исключений: нет `ApiException`, нет `DaoException`, нет `BaseDomainExceptionHelper` — единственный механизм — `BaseRepositoryHelper.execute` (грубый маппинг `DioException` → `internal`, прочее → `unknown`).
- [ ] `BaseRepositoryHelper.execute<TD>(Function executionFunction)` (`with BaseRepositoryHelper` только, без `on`-ограничения; две catch-ветки; callback возвращает уже-обёрнутый `RepositoryResult`) с **обязательным** `LogRepository.error` (никакого `print`) + impl `@LazySingleton(as: Interface, env:[dev,prod,test])` с DAO-stream-subscribed `BehaviorSubject` и `@disposeMethod`; пагинированный список — network-only.
- [ ] Dio `ApiClient` + `RequestBuilder<T>` + `RequestBuilderHelper` + `GetItemsApi` (обёртка в `ResponseEntity`).
- [ ] Freezed BLoC-трио: `<Feature>ListEvent` (`@freezed sealed`: `Initialize`/`LoadItems`/`RefreshRequested`/`UpdateSearchQuery`/`ShowItemDetails`), `<Feature>ListState` (`@freezed sealed`: `Initializing`/`Initialized{pagingState,items,nextPage,total,...}`/`Error`), `<Feature>ListBloc extends BaseBloc` с `applyPage`, `PublishSubject` side-effects, restartable-поиском. Никакого ручного `Equatable`.
- [ ] `PagingStateExt.applyPage` (v5 stateless, generic over `K`; OFFSET-дефолт `K = String = item id`, возвращает запись `(updatedList, pagingState, nextPage)`, принимает `(List<T>, PageMetadata)`); ошибки идут в `pagingState.error`.
- [ ] Страница `BaseStatePage<T>` с `routeName` + `route()`, BLoC в `initState`/`dispose`, `switch (state)`, `PagedListView.separated` + `AppRefreshIndicatorWidget`.
- [ ] `AppColors` `ThemeExtension` + Light/Dark + `AppTheme.light()/dark()`, доступ через `context.appColors`.
- [ ] Сквозное: единый `configureDependencies(env)` + `$initGetIt`, `global_aliases.dart`, `feature_flags.dart`, `text_constants.dart`, четыре класса токенов (`AppSpacingTokens` responsive / `AppTextStyleTokens` color-injecting / `AppOverlayStyleTokens` / `AppImagesTokens` с `_base = 'assets/png'`; сгенерированный `flutter_gen` `assets.gen.dart` сосуществует; цвета — через `context.appColors`, классов `AppRadiusTokens` / `AppColorsTokens` нет), `main.dart` в `runZonedGuarded` + `getIt.allReady()` (без `Bloc.observer` — отдельного BLoC-обозревателя нет).
- [ ] DI перегенерирован (`fvm dart run build_runner build --delete-conflicting-outputs`), `fvm flutter analyze` чист.

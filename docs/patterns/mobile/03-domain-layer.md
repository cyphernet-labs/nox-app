# 03 — Доменный слой

> **Назначение:** описать доменный слой (`lib/domain/`) единого Dart-пакета `speech_ai_mobile` так, чтобы по нему можно было собрать его с нуля и реализовать любую фичу: Freezed-модели без JSON, контракты репозиториев, обёртку `RepositoryResult<T>`, иерархию исключений и per-call конфиги. Доменный слой — чистый: он не зависит ни от чего, кроме аннотаций Freezed, и сам не импортирует ни `lib/data`, ни `lib/presentation`.
>
> **Когда читать:** когда создаёте доменный слой, добавляете новую доменную модель, объявляете контракт репозитория или подключаете инфраструктуру `RepositoryResult` / исключений / конфигов. Первая реальная фича, которую предстоит построить поверх этих шаблонов, — список записей (records list); шаблоны ниже даны на нейтральном примере `Item`, но списочные/пагинированные конфиги вынесены в `07-pagination.md`.
>
> **Связанные документы:** `00-architecture-overview.md` (раскладка пакета, направление зависимостей), `01-stack-and-tooling.md` (Freezed, build_runner, скрипты кодогенерации), `02-dependency-injection.md` (`configureDependencies`, `getIt`, окружения), `04-data-layer.md` (entity, DAO, mapper, реализации репозиториев, `BaseRepositoryHelper.execute`, `LogRepository`), `05-presentation-layer.md` (BLoC, потребляющий `RepositoryResult` через `match`), `07-pagination.md` (полный контракт пагинации, `PageMetadata`, `firstPage`/`nextPage`-конфиги), `10-code-templates.md` (сводные копипаст-шаблоны).

---

## 0. Что лежит в доменном слое

Доменный слой — это **слой бизнес-контрактов**. Здесь нет I/O, нет персистентности, нет HTTP, нет Flutter-виджетов. Это **папки** внутри единого `lib/`, а не отдельный пакет (см. `00-architecture-overview.md`): доменный код лежит в `lib/domain/`, импортируется как `package:speech_ai_mobile/domain/...` и **ничего из других слоёв не импортирует** (правило однонаправленных зависимостей: `presentation -> domain`, `data -> domain`, `domain` не импортирует ничего из приложения).

Доменный слой экспонирует:

- **Модели** — иммутабельные Freezed value-объекты (`*Model`), на языке которых разговаривает всё приложение. **Только `.freezed.dart`, без `.g.dart`, без `fromJson`** — JSON живёт в entity-слое (`04-data-layer.md`).
- **Контракты репозиториев** — абстрактные классы (`<Feature>Repository`), описывающие операции; реализуются в `lib/data/`.
- **Конфиги репозиториев** — Freezed-классы **по одному на вызов** (`GetItemsConfig`, `GetItemConfig`, …), реализующие маркер `RepositoryConfig`. Тоже только `.freezed.dart`, без `.g.dart`.
- **`RepositoryResult<T>`** — универсальная обёртка возврата (данные **ИЛИ** исключение, взаимоисключающе).
- **Иерархия исключений** — маркер `BaseRepositoryException` (однострочный, без JSON) + enum `RepositoryException` + при необходимости feature-specific enum'ы, реализующие тот же маркер.

Раскладка папок:

```
lib/domain/
├── model/                       # Freezed-модели, по папке на фичу
│   └── item/
│       ├── item_model.dart
│       └── item_status.dart      # мелкие enum'ы рядом с моделью
├── exception/
│   ├── base_repository_exception.dart
│   └── repository_exception.dart
└── repository/
    ├── base/                     # инфраструктура: result + marker'ы + match
    │   ├── repository_result.dart
    │   ├── repository_result_handling.dart
    │   └── repository_config.dart
    └── item/                     # по одной папке на контракт
        ├── item_repository.dart
        ├── get_item_config.dart
        └── get_items_config.dart
```

> **Чем это отличается от прежних подходов.** В исходных вариантах доменный слой был отдельным пакетом (`domain/lib/src/...`) с path-зависимостью на `data` и циклом `domain <-> data`. Здесь — **один пакет, слои = папки**, направление зависимостей строго `data -> domain` (домен не знает про data). Поэтому из доменного слоя выпилены `DataConverter` / `ExceptionConverter` / `JsonMappers` / кастомные `JsonConverter` / `fromJson` на доменных типах — всё это перенесено в entity-слой (`04-data-layer.md`). Доменные конфиги — **по одному классу на вызов**, а не sealed-union на фичу.

---

## 1. `RepositoryResult<T>` — универсальная обёртка возврата

Каждый метод репозитория возвращает `Future<RepositoryResult<T>>` или `Stream<RepositoryResult<T>>`. **Никогда** не голый `Future<T>`.

`RepositoryResult<T>` — это `@freezed sealed`-класс (по мандату Freezed), но с **взаимоисключающими** вариантами: либо `RepositoryResultSuccess<T>` (несёт `data`), либо `RepositoryResultError<T>` (несёт `exception`), и ровно один из них в наличии. Взаимоисключаемость гарантируется двумя именованными фабриками `RepositoryResult.success(data: …)` / `RepositoryResult.error(exception: …)` — **именованные обязательные параметры**. Никакого «partial»-состояния (когда заполнены оба поля) больше нет.

`lib/domain/repository/base/repository_result.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/exception/base_repository_exception.dart';

part 'repository_result.freezed.dart';

@freezed
sealed class RepositoryResult<T> with _$RepositoryResult<T> {
  const RepositoryResult._();

  /// Success path: payload present, no exception.
  const factory RepositoryResult.success({required T data}) = RepositoryResultSuccess<T>;

  /// Error path: exception present, no payload.
  const factory RepositoryResult.error({required BaseRepositoryException exception}) = RepositoryResultError<T>;

  /// `true` when this is a success carrying a payload.
  bool get hasData => this is RepositoryResultSuccess<T>;

  /// The payload, or `null` on the error path. Prefer `match()` over reading this.
  T? get data => switch (this) {
        RepositoryResultSuccess(:final data) => data,
        _ => null,
      };

  /// The exception, or `null` on the success path. Prefer `match()` over reading this.
  BaseRepositoryException? get exception => switch (this) {
        RepositoryResultError(:final exception) => exception,
        _ => null,
      };
}
```

Ключевые моменты:

- **Только `.freezed.dart`** — `RepositoryResult` не сериализуется в JSON (нет `.g.dart`, нет `fromJson`): он живёт целиком внутри процесса, IPC-границ нет.
- **Именованные взаимоисключающие фабрики.** `RepositoryResult.success(data: …)` создаёт success-вариант (`RepositoryResultSuccess<T>`), `RepositoryResult.error(exception: …)` — error-вариант (`RepositoryResultError<T>`). Параметры **именованные обязательные** (`required`). Заполнить оба поля одновременно невозможно.
- **Публичные варианты.** Варианты называются `RepositoryResultSuccess<T>` / `RepositoryResultError<T>` (публичные, без `_`-префикса) — на них можно `switch`'иться напрямую снаружи файла.
- `hasData` — безопасная булева проверка; предпочитайте её инлайновому `data != null`.
- `data` / `exception` — удобные геттеры для миграции старого кода, но **канонический способ потребления — `match()`** (раздел 2). Прямой `result.data!` запрещён — на error-пути он бросает.

> **Почему `@freezed sealed`, а не plain-класс.** Мандат проекта — BLoC и доменные value-объекты на Freezed. `RepositoryResult` — sealed-union из двух публичных вариантов (`RepositoryResultSuccess` / `RepositoryResultError`), что и даёт исчерпывающий `switch` в `match()` и компилятор-проверяемую взаимоисключаемость. Это сознательно заменяет прежний plain-класс с двумя nullable-полями (`base`) и прежний permissive-Freezed с обоими nullable-полями и `completed(...)`-фабрикой (`v1`).

### Безопасный доступ — никогда `result.data!`

`data` равно `null` на error-пути; голый `result.data!` там бросит. Используйте одну из двух безопасных форм:

```dart
// Предпочтительно: исчерпывающий разбор (раздел 2)
final label = result.match<String>(
  onData: (item) => 'Loaded: ${item.name}',
  onError: (ex) => 'Failed: $ex',
);

// Либо: guard через hasData перед чтением
if (result.hasData) {
  final item = result.data; // внутри guard поле непустое
  // ...
}
```

---

## 2. `repository_result_handling.dart` — расширение `match()`

`match()` превращает два возможных варианта `RepositoryResult<T>` в явные исчерпывающие ветки через `switch` по публичным вариантам. Это канонический способ потребить результат в BLoC и в любом вызывающем коде. Поскольку состояние **взаимоисключающее**, расширение **тримнутое**: только `onData` / `onError`, без `onPartial` / `onEmpty` (они были нужны прежнему permissive-варианту и здесь не имеют смысла).

`lib/domain/repository/base/repository_result_handling.dart`:
```dart
import 'package:speech_ai_mobile/domain/exception/base_repository_exception.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';

/// Type-safe, exhaustive pattern-match over a [RepositoryResult] payload.
///
/// `RepositoryResult` is mutually exclusive: it is EITHER [RepositoryResultSuccess]
/// (carries `data`) OR [RepositoryResultError] (carries `exception`), never both.
/// Reading `result.data!` directly throws on the error path; use [match] to express
/// each case explicitly. The `switch` over the public variants is exhaustive.
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

Контракт:

| Случай | Вариант | Несёт | Ветка |
|---|---|---|---|
| success | `RepositoryResultSuccess<T>` | `data` | `onData(data)` |
| error | `RepositoryResultError<T>` | `exception` | `onError(exception)` |

Типичное использование в BLoC (подробности — `05-presentation-layer.md`):

```dart
result.match<void>(
  onData: (items) => emit(state.copyWith(substate: const Initialized(), items: items)),
  onError: (exception) => emit(state.copyWith(substate: Error(exception: exception))),
);
```

> `switch` по публичным вариантам `RepositoryResultSuccess` / `RepositoryResultError` исчерпывающий — компилятор гарантирует, что обе ветки покрыты, без `?? RepositoryException.unknown`-страховок. На error-пути `exception` всегда непусто (фабрика `RepositoryResult.error` требует его как `required`), так что в `onError(exception)` он не-nullable напрямую из деструктуризации варианта.

---

## 3. Иерархия исключений

Два файла: однострочный маркер-интерфейс и enum стандартных режимов отказа. **Никаких JSON-методов на маркере** (это сознательно убирает прежний `fromJson`/`toJson`-контракт варианта `v1` — JSON-маппинг ошибок живёт в entity-слое, см. `04-data-layer.md`).

### 3.1 `BaseRepositoryException` (маркер)

`lib/domain/exception/base_repository_exception.dart`:
```dart
abstract class BaseRepositoryException {}
```

Всё пользовательское проходит через подтипы этого маркера. Маркер пуст — никаких методов, никакой сериализации.

### 3.2 `RepositoryException` (enum)

`lib/domain/exception/repository_exception.dart`:
```dart
import 'package:speech_ai_mobile/domain/exception/base_repository_exception.dart';

enum RepositoryException implements BaseRepositoryException {
  unknown,
  internal,
  authentication,
  connection,
  unauthenticated,
  notFound,
}
```

Семантика каждого значения (data-слой маппит сюда свои `ApiException` / `DaoException` — см. `04-data-layer.md`):

| Значение | Смысл |
|---|---|
| `unknown` | Обобщённая / немаппнутая ошибка (а также fallback по умолчанию). |
| `internal` | Невосстановимое внутреннее состояние или серверная ошибка (5xx). |
| `authentication` | Неверные учётные данные / провал аутентификации (неправильный логин/пароль). |
| `connection` | Сетевой/I-O сбой, таймаут, недостижимый сервер. |
| `unauthenticated` | Вызывающий не аутентифицирован (токен истёк, нужен повторный вход) — 401. |
| `notFound` | Запрошенный ресурс не существует — 404. |

### 3.3 Feature-specific исключения

Когда фиче нужны более тонкие сигналы — добавляйте **отдельный** enum, реализующий тот же маркер `BaseRepositoryException`. BLoC потом `switch`'ится по конкретному типу, чтобы выбрать пользовательское сообщение (см. `05-presentation-layer.md`).

```dart
// lib/domain/repository/payments/payments_repository_exception.dart  (пример)
import 'package:speech_ai_mobile/domain/exception/base_repository_exception.dart';

enum PaymentsRepositoryException implements BaseRepositoryException {
  providerNotConnected,
}
```

> Предпочтение: для общих режимов отказа расширяйте `RepositoryException`; отдельный enum заводите только когда фиче нужен **семантически свой** сигнал, которого нет в общем наборе (как `providerNotConnected` выше). Оба варианта одинаково проходят через `match()`, т.к. оба — `BaseRepositoryException`.

---

## 4. Контракт репозитория

Контракт — обычный абстрактный класс `<Feature>Repository`. Каждый метод возвращает обёрнутый результат. Имена методов следуют строгим префиксам.

### 4.1 Семантика префиксов методов

| Префикс | Возвращает | Смысл |
|---|---|---|
| `watch*()` | `Stream<RepositoryResult<T>>` | Живой стрим; в реализации backed `BehaviorSubject`. Реплеит последнее значение, затем live-обновления. |
| `fetch*()` | `Future<RepositoryResult<T>>` | Одноразовое чтение одиночного ресурса (часто пушит результат в `watch`-стрим того же ресурса). |
| `get*()` | `Future<RepositoryResult<T>>` | Параметризованное чтение / список (network-only для server-owned списков). |
| `create*` / `update*` | `Future<RepositoryResult<T>>` | Сайд-эффектные записи; возвращают итоговую модель. |
| `delete*` | `Future<RepositoryResult<void>>` | Сайд-эффектное удаление без payload. |
| `clean()` | `Future<void>` | Сброс кэша / subject'ов; вызывается на logout. |

Правила:

- Класс называется `<Feature>Repository`.
- Возврат — **всегда** `Future<RepositoryResult<T>>` или `Stream<RepositoryResult<T>>`, никогда голый `Future<T>`.
- **Watchable-ресурсы экспонируют пару:** `watchXxx()` (Stream, backed `BehaviorSubject`) + `fetchXxx()` (Future, пушит на тот же стрим). Это касается одиночных кэшируемых ресурсов и реактивных коллекций.
- **Carve-out (важно).** Пагинированные server-owned списки и одноразовые POST'ы — **network-only**: у них нет DAO/subject, только `get*` / `fetch*` / `create*`-метод, который ходит в сеть и возвращает результат напрямую. Не заводите `watch*`-пару для серверного пагинированного списка (см. `04-data-layer.md` про carve-out и `07-pagination.md` про контракт пагинации).
- Списочные методы возвращают слайс страницы в паре с метаданными пагинации: `(List<T>, PageMetadata)` (offset-flavor — дефолт для records-list client_backend). Полный контракт — `07-pagination.md`.
- `clean()` сбрасывает кэш/subject'ы (вызывается на logout).

### 4.2 Рабочий пример: `ItemRepository`

`lib/domain/repository/item/item_repository.dart`:
```dart
import 'package:speech_ai_mobile/domain/model/item/item_model.dart';
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';
import 'package:speech_ai_mobile/domain/repository/item/get_item_config.dart';
import 'package:speech_ai_mobile/domain/repository/item/get_items_config.dart';

abstract class ItemRepository {
  /// Cache-first single resource. Replays the last value, then live updates.
  /// Backed by a BehaviorSubject in the impl.
  Stream<RepositoryResult<ItemModel>> watchItem({required String id});

  /// One-shot read of the single resource (pushes onto the watch stream).
  Future<RepositoryResult<ItemModel>> fetchItem({required GetItemConfig config});

  /// Paginated server-owned list (NETWORK-ONLY — no DAO/subject).
  /// Returns the page slice paired with offset pagination metadata.
  /// Full pagination contract: see 07-pagination.md.
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config});

  /// Side-effecting create; returns the resulting model.
  Future<RepositoryResult<ItemModel>> createItem({required ItemModel item});

  /// Side-effecting update; returns the resulting model.
  Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item});

  /// Side-effecting delete; no payload.
  Future<RepositoryResult<void>> deleteItem({required String id});

  /// Reset cache / subjects (called on logout).
  Future<void> clean();
}
```

> `PageMetadata` — offset-flavor (`{int? nextPage, int total}`), потому что records-list client_backend пагинируется по offset (`page` + `page_size` + `count`). Курсорный flavor (`CursorPaginationMetadata{String? nextCursor}`) задокументирован как альтернатива в `07-pagination.md`. Сам тип `PageMetadata` объявлен в `lib/domain/repository/base/` и описан в `07-pagination.md`.

### 4.3 Пустой скелет

```dart
// lib/domain/repository/<feature>/<feature>_repository.dart
import 'package:speech_ai_mobile/domain/model/<feature>/<model>_model.dart';
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';
import 'package:speech_ai_mobile/domain/repository/<feature>/get_<model>_config.dart';
import 'package:speech_ai_mobile/domain/repository/<feature>/get_<model>s_config.dart';

abstract class <Feature>Repository {
  Stream<RepositoryResult<<Model>Model>> watch<Model>({required String id});

  Future<RepositoryResult<<Model>Model>> fetch<Model>({required Get<Model>Config config});

  Future<RepositoryResult<(List<<Model>Model>, PageMetadata)>> get<Model>s({required Get<Model>sConfig config});

  Future<RepositoryResult<<Model>Model>> create<Model>({required <Model>Model item});

  Future<RepositoryResult<<Model>Model>> update<Model>({required <Model>Model item});

  Future<RepositoryResult<void>> delete<Model>({required String id});

  Future<void> clean();
}
```

> Реализация контракта, проводка DAO/API, гард через `BaseRepositoryHelper.execute<T>()` и регистрация в DI — всё в `lib/data/` (`04-data-layer.md`). Сводный шаблон контракта продублирован в `10-code-templates.md`.

---

## 5. Конфиги репозиториев — один Freezed-класс на вызов

В отличие от прежних sealed-union-на-фичу (`<Feature>RepositoryConfigs`), здесь — **по одному `@freezed`-классу на каждый вызов** (`GetItemsConfig`, `GetItemConfig`, …). Каждый конфиг реализует однострочный маркер `RepositoryConfig`. Конфиги несут всё, что нужно вызову, плюс именованные фабрики под частые случаи и константы пагинации. **Только `.freezed.dart`, без `.g.dart`** — конфиги в JSON не сериализуются.

### 5.1 Маркер `RepositoryConfig`

`lib/domain/repository/base/repository_config.dart`:
```dart
abstract class RepositoryConfig {}
```

### 5.2 Списочный/пагинированный конфиг: `GetItemsConfig`

`lib/domain/repository/item/get_items_config.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_config.dart';

part 'get_items_config.freezed.dart';

@freezed
abstract class GetItemsConfig with _$GetItemsConfig implements RepositoryConfig {
  const GetItemsConfig._();

  const factory GetItemsConfig({
    required int page,
    String? search,
  }) = _GetItemsConfig;

  /// First page of the list. Used by PagingState fetch when pageKey is the default.
  factory GetItemsConfig.firstPage({String? search}) => GetItemsConfig(page: defaultPage, search: search);

  /// Subsequent page. `page` comes from PageMetadata.nextPage.
  factory GetItemsConfig.nextPage({required int page, String? search}) => GetItemsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
```

> Этот пример показывает базовую форму пагинированного конфига; **детальный** контракт `firstPage`/`nextPage` в связке с `PagingState` и `PageMetadata.nextPage` живёт в `07-pagination.md`. Не дублируйте пагинационную логику — следуйте `07-pagination.md`.

### 5.3 Конфиг одиночного ресурса: `GetItemConfig`

`lib/domain/repository/item/get_item_config.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_config.dart';

part 'get_item_config.freezed.dart';

@freezed
abstract class GetItemConfig with _$GetItemConfig implements RepositoryConfig {
  const factory GetItemConfig({
    required String id,
    required bool? cacheOnly,
  }) = _GetItemConfig;
}
```

### 5.4 Семантика `cacheOnly` (tri-state)

Поле `cacheOnly` несут конфиги одиночных кэшируемых ресурсов (`GetItemConfig`). Server-owned пагинированный список (`GetItemsConfig`) — network-only, поэтому `cacheOnly` в нём нет (только `page` + `search`). Там, где поле присутствует, оно трёхзначное:

| Значение | Поведение |
|---|---|
| `true` | Читать **только** кэш; если ресурса в кэше нет — вернуть `notFound`, в сеть не ходить. |
| `null` или `false` | Cache-first: вернуть кэш, если он есть, иначе сходить в сеть. |

### 5.5 Пустой скелет конфига

```dart
// lib/domain/repository/<feature>/get_<model>_config.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_config.dart';

part 'get_<model>_config.freezed.dart';

@freezed
abstract class Get<Model>Config with _$Get<Model>Config implements RepositoryConfig {
  const factory Get<Model>Config({
    required String id,
    required bool? cacheOnly,
  }) = _Get<Model>Config;
}
```

> **Чего НЕ делаем (сознательно отвергнуто из `v1`):** не объявляем JSON в домене (нет `fromJson`/`.g.dart` на конфигах), не используем `DataConverter`/`ExceptionConverter`, не делаем sealed-union-на-фичу (`<Feature>RepositoryConfigs` с `= NamedConfig`-редиректами). Один класс на вызов — проще, без union-разбора на стороне реализации.

---

## 6. Доменные модели

Доменные модели — Freezed-классы с **только** `.freezed.dart`-частью: **нет `.g.dart`, нет `fromJson`**. JSON живёт в entity-слое (`04-data-layer.md`). Производная/бизнес-логика выносится во **внешнее `extension`**, а не в тело `@freezed`-класса.

В отличие от entity-слоя (где разрешены только примитивы), доменные модели могут использовать богатые типы — enum'ы, вложенные модели, `DateTime`. Вся коэрция «примитив <-> богатый тип» происходит в **mapper'е** при переходе entity -> model (`04-data-layer.md`).

### 6.1 Рабочий пример: `ItemModel`

`lib/domain/model/item/item_model.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:speech_ai_mobile/domain/model/item/item_status.dart';

part 'item_model.freezed.dart';

@freezed
abstract class ItemModel with _$ItemModel {
  const factory ItemModel({
    required String id,
    required String name,
    String? description,
    String? imageUrl,
    @Default(ItemStatus.draft) ItemStatus status,
    @Default(<String>[]) List<String> tags,
  }) = _ItemModel;
}

extension ItemModelExt on ItemModel {
  bool get isPublished => status == ItemStatus.active;

  String get displayName => name.trim().isEmpty ? 'Untitled' : name;
}
```

Правила:

- `@freezed` + `with _$ItemModel` + `const factory`.
- **Ровно одна `part`-директива** — `'item_model.freezed.dart'`. Никакого `'*.g.dart'`, никакого `fromJson`-фабричного конструктора.
- Производная логика (`isPublished`, `displayName`) — **только** во внешнем `extension ItemModelExt on ItemModel`, **никогда** в теле `@freezed`-класса. Это держит сгенерированный класс чистым и не привязывает геттеры к Freezed-генерации.
- Полные `package:`-импорты, никаких относительных `../` (кроме `part`-директив).

### 6.2 Мелкие enum'ы / status-типы

Держите небольшие enum'ы в собственном файле `*_status.dart` / `*_type.dart` рядом с моделью:

`lib/domain/model/item/item_status.dart`:
```dart
enum ItemStatus { draft, active, archived }
```

### 6.3 Пустой скелет модели

```dart
// lib/domain/model/<feature>/<model>_model.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part '<model>_model.freezed.dart';

@freezed
abstract class <Model>Model with _$<Model>Model {
  const factory <Model>Model({
    required String id,
    // ... required / nullable / @Default(...) fields ...
  }) = _<Model>Model;
}

extension <Model>ModelExt on <Model>Model {
  // bool get isXxx => ...;
  // String get displayName => ...;
}
```

> После добавления/изменения любой модели, конфига или контракта запустите `./script_auto_generate.sh` (или `dart run build_runner build --delete-conflicting-outputs`) — он перегенерирует все `*.freezed.dart` (см. `01-stack-and-tooling.md` и `12-dev-commands.md`). Никаких `*.g.dart` для доменных типов не появится — это норма.

---

## 7. Как части соединяются (end-to-end)

```
Контракт (lib/domain)            Конфиг (lib/domain)         Результат (lib/domain)
ItemRepository                   GetItemConfig               RepositoryResult<ItemModel>
  watchItem(id) ──────────┐      GetItemsConfig                ├─ success(data: ItemModel)
  fetchItem(GetItemConfig)│                                    └─ error(exception: BaseRepositoryException)
  getItems(GetItemsConfig)│
  createItem(item)        │
  updateItem(item)        │
  deleteItem(id)          │
  clean()                 ▼
              ItemRepositoryImpl (lib/data/)  ──►  match() / hasData в BLoC (lib/presentation/)
              (BaseRepositoryHelper.execute + LogRepository)
```

Доменный слой задаёт **словарь** (модели, конфиги, исключения) и **контракт** (`ItemRepository`) плюс **форму возврата** (`RepositoryResult` + `match`). Data-слой исполняет контракт (мапит entity -> model, маппит `ApiException`/`DaoException` -> `RepositoryException`, логирует через обязательный `LogRepository`). Presentation-слой потребляет результат через `match()` / `hasData`.

---

## Чеклист

После применения этого документа должно существовать и проходить анализ:

- [ ] `lib/domain/exception/base_repository_exception.dart` — однострочный маркер `abstract class BaseRepositoryException {}` (без JSON-методов).
- [ ] `lib/domain/exception/repository_exception.dart` — enum `RepositoryException` (`unknown`, `internal`, `authentication`, `connection`, `unauthenticated`, `notFound`), реализующий маркер.
- [ ] `lib/domain/repository/base/repository_result.dart` — `@freezed sealed class RepositoryResult<T>` с публичными вариантами `RepositoryResultSuccess<T>` / `RepositoryResultError<T>`, **взаимоисключающими** именованными фабриками `success({required data})` / `error({required exception})`, геттером `hasData`, **только `.freezed.dart`** (нет `.g.dart`, нет `fromJson`).
- [ ] `lib/domain/repository/base/repository_result_handling.dart` — `extension RepositoryResultMatch` с тримнутым `match<R>({onData, onError})` через `switch` по публичным вариантам (без `onPartial`/`onEmpty`).
- [ ] `lib/domain/repository/base/repository_config.dart` — маркер `abstract class RepositoryConfig {}`.
- [ ] Нигде в коде нет прямого `result.data!` — весь доступ через `match()` или guard по `hasData`.
- [ ] Хотя бы один контракт `<Feature>Repository`, где каждое чтение/запись возвращает `RepositoryResult` / `Stream<RepositoryResult>`; watchable-ресурсы имеют пару `watchXxx()`/`fetchXxx()`; серверный пагинированный список — network-only (`getItems`, без `watch`-пары); записи — `createXxx`/`updateXxx`/`deleteXxx` (delete → `RepositoryResult<void>`); есть `clean()` → `Future<void>`.
- [ ] По одному `@freezed`-конфигу **на вызов** (`GetItemConfig`, `GetItemsConfig`), реализующему `RepositoryConfig`. У пагинированного `GetItemsConfig` — поля `{page, search?}`, фабрики `firstPage`/`nextPage` + константы `pageSize`/`defaultPage`, **без** `cacheOnly`. У одиночного `GetItemConfig` — tri-state `cacheOnly`. **Только `.freezed.dart`**.
- [ ] Хотя бы одна `@freezed`-модель (`ItemModel`) с одной `part '*.freezed.dart'`-директивой, **без** `fromJson`/`.g.dart`; производная логика — во внешнем `extension <Model>ModelExt`; мелкие enum'ы — в отдельном `*_status.dart` рядом.
- [ ] Доменный слой **ничего** не импортирует из `lib/data` / `lib/presentation`; импорты — полные `package:speech_ai_mobile/...`, без относительных `../` (кроме `part`).
- [ ] `./script_auto_generate.sh` перегенерирует все `*.freezed.dart` без ошибок; `dart analyze` по доменному слою чист.

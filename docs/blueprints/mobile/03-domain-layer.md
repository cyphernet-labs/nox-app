# 03 — Доменный слой

> **Назначение:** описать доменный слой (`lib/domain/`) единого Dart-пакета `nox_app` так, чтобы по нему можно было собрать его с нуля и реализовать любую фичу: Freezed-модели без JSON, контракты репозиториев, обёртку `RepositoryResult<T>`, иерархию исключений и per-call конфиги. Доменный слой — чистый: он не зависит ни от чего, кроме аннотаций Freezed, и сам не импортирует ни `lib/data`, ни `lib/presentation`. Единственное отступление в собранном коде — `repository/settings/settings_repository.dart` с точечным `import 'package:flutter/material.dart' show ThemeMode;`: тип темы взят из фреймворка вместо собственного доменного enum'а.
>
> **Когда читать:** когда создаёте доменный слой, добавляете новую доменную модель, объявляете контракт репозитория или подключаете инфраструктуру `RepositoryResult` / исключений / конфигов. Первая реальная фича, построенная поверх этих шаблонов, — список чатов (открытые общие пространства): пагинированный список, который в собранном коде реализован **cache-first** над локальным Sembast (`ChatRepository.getChats` + `watchChats`), а не network-only; network-only carve-out остался только у замороженного verification-среза `Item`. Шаблоны ниже даны на нейтральном примере `Item`, но списочные/пагинированные конфиги вынесены в `07-pagination.md`.
>
> **Связанные документы:** `00-architecture-overview.md` (раскладка пакета, направление зависимостей), `01-stack-and-tooling.md` (Freezed, build_runner, скрипты кодогенерации), `02-dependency-injection.md` (`configureDependencies`, `getIt`, окружения), `04-data-layer.md` (entity, DAO, mapper, реализации репозиториев, `BaseRepositoryHelper.execute`, `LogRepository`), `05-presentation-layer.md` (BLoC, потребляющий `RepositoryResult` через `match`), `07-pagination.md` (полный контракт пагинации, `PageMetadata`, `firstPage`/`nextPage`-конфиги), `10-code-templates.md` (сводные копипаст-шаблоны).

---

## 0. Что лежит в доменном слое

Доменный слой — это **слой бизнес-контрактов**. Здесь нет I/O, нет персистентности, нет HTTP, нет Flutter-виджетов. Это **папки** внутри единого `lib/`, а не отдельный пакет (см. `00-architecture-overview.md`): доменный код лежит в `lib/domain/`, импортируется как `package:nox_app/domain/...` и **ничего из других слоёв не импортирует** (правило однонаправленных зависимостей: `presentation -> domain`, `data -> domain`, `domain` не импортирует ничего из приложения).

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
│   ├── item/
│   │   ├── item_model.dart
│   │   └── item_status.dart      # мелкие enum'ы рядом с моделью
│   └── app_config/              # рантайм-конфиг, зависящий от flavor (см. 02, 09)
│       ├── app_config.dart       # plain-класс AppConfig({ required AppFlavorType flavor, String? apiUrl })
│       ├── app_flavor.dart       # AppFlavor.getFlavor() из --dart-define app.flavor
│       └── app_flavor_type.dart  # enum AppFlavorType { prod, stage }
├── exception/
│   ├── base_repository_exception.dart
│   └── repository_exception.dart
└── repository/
    ├── base/                     # инфраструктура: result + marker'ы + match + метаданные пагинации
    │   ├── base.dart             # barrel: re-export config + result + result_handling (удобство импорта)
    │   ├── repository_config.dart
    │   ├── repository_result.dart
    │   ├── repository_result_handling.dart
    │   └── page_metadata.dart    # PageMetadata{ hasMore, nextPage? } (контракт — 07-pagination.md)
    ├── log_repository.dart       # единственный канал логирования (FR-011); impl — в lib/data
    ├── app_config/
    │   └── app_config_repository.dart  # контракт flavor-конфига (реализация — lib/data, см. 02/09)
    └── item/                     # по одной папке на контракт
        ├── item_repository.dart
        └── get_items_config.dart # get_item_config.dart появится с кэшируемой фичей (§5.3)
```

> **О составе дерева.** Доменный слой кроме рабочего примера `Item` несёт три кросс-слойных контракта/модели, которые задают границу домена для остальных частей: `repository/log_repository.dart` — единственный канал логирования (FR-011: голый `print`/`debugPrint` в `lib/` запрещён, всё идёт через `LogRepository`; реализация `LoggerLogRepository` — в `lib/data`, см. `02-dependency-injection.md`); `model/app_config/{app_config,app_flavor,app_flavor_type}.dart` + `repository/app_config/app_config_repository.dart` — flavor-зависимый рантайм-конфиг (`AppConfig` несёт `flavor` + nullable `apiUrl`; `apiUrl` остаётся `null` до транспорта — WebSocket-конверт контракта v0 приходит фазой 027, DI-флип на реальные data source'ы — фазой 028; источник auth-токена ждёт stage-2-аутентификацию, она ещё не спроектирована; см. `02-dependency-injection.md` и `09-build-and-secrets-infra.md`); `repository/base/base.dart` — barrel-файл, реэкспортирующий `repository_config.dart` + `repository_result.dart` + `repository_result_handling.dart` ради одной строки импорта на стороне потребителя. Само дерево выше — **скелетная** раскладка блюпринта, а не опись сегодняшнего кода: в реальном `lib/domain/` рядом с `item/` уже живут `model/{app,chat,file,qr}`, `model/app_config/server_limits.dart`, `repository/{app,chat,settings,sync}` и папка `service/` (`ConnectivityService`, `FilePickerService`, …) — форма та же, состав шире.

> **Правило раскладки.** Доменный слой — **не** отдельный пакет: **один пакет, слои = папки**, направление зависимостей строго `data -> domain` (домен не знает про data); цикла `domain <-> data` быть не должно. В доменном слое **нет** `DataConverter` / `ExceptionConverter` / `JsonMappers` / кастомных `JsonConverter` / `fromJson` на доменных типах — всё это живёт в entity-слое (`04-data-layer.md`). Доменные конфиги — **по одному классу на вызов**, а не sealed-union на фичу.

---

## 1. `RepositoryResult<T>` — универсальная обёртка возврата

Каждый метод репозитория возвращает `Future<RepositoryResult<T>>` или `Stream<RepositoryResult<T>>`. **Никогда** не голый `Future<T>`.

`RepositoryResult<T>` — это `@freezed sealed`-класс (по мандату Freezed), но с **взаимоисключающими** вариантами: либо `RepositoryResultSuccess<T>` (несёт `data`), либо `RepositoryResultError<T>` (несёт `exception`), и ровно один из них в наличии. Взаимоисключаемость гарантируется двумя именованными фабриками `RepositoryResult.success(data: …)` / `RepositoryResult.error(exception: …)` — **именованные обязательные параметры**. Никакого «partial»-состояния (когда заполнены оба поля) больше нет.

`lib/domain/repository/base/repository_result.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';

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

> **Почему `@freezed sealed`, а не plain-класс.** Мандат проекта — BLoC и доменные value-объекты на Freezed. `RepositoryResult` — sealed-union из двух публичных вариантов (`RepositoryResultSuccess` / `RepositoryResultError`), что и даёт исчерпывающий `switch` в `match()` и компилятор-проверяемую взаимоисключаемость. Это сознательная замена plain-класса с двумя nullable-полями и permissive-Freezed с обоими nullable-полями и `completed(...)`-фабрикой: оба допускают «partial»-состояние с обоими заполненными полями, чего здесь быть не должно.

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
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

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

> Имена sub-state-вариантов — **bare** (`Initializing` / `Initialized` / `Error`), как в собранном коде (`05-presentation-layer.md`). Префиксные имена (`<Feature>Initializing`…) допустимы как вариант защиты от коллизий, но канон — bare.

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
import 'package:nox_app/domain/exception/base_repository_exception.dart';

enum RepositoryException implements BaseRepositoryException {
  unknown,
  internal,
  authentication,
  connection,
  unauthenticated,
  notFound,
  invalidRequest,
  nameTaken,
  payloadTooLarge,
  attachmentGone,
  rateLimited,
  unsupportedSchema;

  /// Maps a contract v0 §2.1 wire error code onto an enum value. Evolution rule:
  /// a code unknown to this client build degrades to [internal], never a crash.
  static RepositoryException fromWireCode(String code) => switch (code) {
        'invalid_request' => invalidRequest,
        'not_found' => notFound,
        'name_taken' => nameTaken,
        'payload_too_large' => payloadTooLarge,
        'attachment_gone' => attachmentGone,
        'rate_limited' => rateLimited,
        'unauthenticated' => unauthenticated,
        'unsupported_schema' => unsupportedSchema,
        'internal' => internal,
        _ => internal,
      };
}
```

Типизированной иерархии `ApiException` / `DaoException` **нет** — это сознательное решение (подтверждено комментарием в `repository_exception.dart`). Хвост значений зеркалит коды ошибок контракта v0 §2.1, чтобы отказ команды оставался различимым end-to-end; статический `RepositoryException.fromWireCode(String)` — единственная точка маппинга кода с провода, и незнакомый этой сборке код деградирует в `internal` (правило эволюции), а не роняет клиент.

Data-слой маппит необработанные ошибки прямо в этот enum внутри `BaseRepositoryHelper.execute`, у которого **три** catch-ветки: `on BaseRepositoryException` (уже смаппленный доменный отказ — например код с провода из `unwrapEnvelope` — проходит насквозь и **не** размывается в `unknown`), затем `on DioException` (таймауты/`connectionError` → `connection`, 401 → `unauthenticated`, 403 → `authentication`, 404 → `notFound`, прочее → `internal`), затем catch-all → `unknown`. Подробности — `04-data-layer.md` §5.

| Значение | Смысл |
|---|---|
| `unknown` | Обобщённая / немаппнутая ошибка (а также fallback по умолчанию). |
| `internal` | Невосстановимое внутреннее состояние или серверная ошибка (5xx); сюда же деградирует незнакомый код с провода. |
| `authentication` | Неверные учётные данные / провал аутентификации (неправильный логин/пароль). |
| `connection` | Сетевой/I-O сбой, таймаут, недостижимый сервер. |
| `unauthenticated` | Вызывающий не аутентифицирован (токен истёк, нужен повторный вход) — 401 / `unauthenticated`. |
| `notFound` | Запрошенный ресурс не существует — 404 / `not_found`. |
| `invalidRequest` | Запрос не прошёл валидацию сервера — `invalid_request`. |
| `nameTaken` | Имя чата или label уже занято — `name_taken`. |
| `payloadTooLarge` | Payload больше объявленных сервером лимитов — `payload_too_large`. |
| `attachmentGone` | Загруженный blob истёк или уже собран — `attachment_gone`. |
| `rateLimited` | Сервер притормозил клиента — `rate_limited`. |
| `unsupportedSchema` | Версия схемы конверта не поддерживается — `unsupported_schema`. |

### 3.3 Feature-specific исключения

Когда фиче нужны более тонкие сигналы — добавляйте **отдельный** enum, реализующий тот же маркер `BaseRepositoryException`. BLoC потом `switch`'ится по конкретному типу, чтобы выбрать пользовательское сообщение (см. `05-presentation-layer.md`).

```dart
// lib/domain/repository/payments/payments_repository_exception.dart  (пример)
import 'package:nox_app/domain/exception/base_repository_exception.dart';

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
| `watch*()` | `Stream<RepositoryResult<T>>` | Живой стрим; в реализации backed `BehaviorSubject`. Реплеит последнее значение, затем live-обновления. В собранном коде реактивные чат-каналы — исключение: `watchChats()`/`watchMessages()`/`watchChat()` отдают голый `Stream<List<T>>` (`Stream<ChatModel?>`) поверх Sembast `onSnapshot` как change-сигнал. |
| `fetch*()` | `Future<RepositoryResult<T>>` | Одноразовое чтение одиночного ресурса (часто пушит результат в `watch`-стрим того же ресурса). |
| `get*()` | `Future<RepositoryResult<T>>` | Параметризованное чтение / страница списка (у продуктовых списков — cache-first поверх Sembast; network-only остался у среза `Item`). |
| `create*` / `update*` | `Future<RepositoryResult<T>>` | Сайд-эффектные записи; возвращают итоговую модель. |
| `delete*` | `Future<RepositoryResult<void>>` | Сайд-эффектное удаление без payload. |
| `clean()` | `Future<void>` | Сброс кэша / subject'ов; вызывается на logout. |

Правила:

- Класс называется `<Feature>Repository`.
- Возврат — **всегда** `Future<RepositoryResult<T>>` или `Stream<RepositoryResult<T>>`, никогда голый `Future<T>`. Осознанные исключения в собранном коде: реактивные change-сигналы (`watchChats`/`watchMessages`) и fire-and-forget `Future<void>` (`clean`, `markChatRead`, `seedCreatedChat`) — они идут мимо `BaseRepositoryHelper.execute`, а значит гарантии «никогда не бросает» на них **не** распространяется, и вызывающий обязан ловить сам.
- **Watchable-ресурсы экспонируют пару:** `watchXxx()` (Stream, backed `BehaviorSubject`) + `fetchXxx()` (Future, пушит на тот же стрим). Это касается одиночных кэшируемых ресурсов и реактивных коллекций.
- **Carve-out (важно, и он сузился).** Network-only — то есть без DAO/subject, только `get*` / `fetch*` / `create*`, который ходит в сеть и возвращает результат напрямую — остаётся формой для одноразовых команд и для замороженного verification-среза `Item`. **Продуктовые пагинированные списки так НЕ устроены:** и `ChatRepository`, и `MessageRepository` — cache-first поверх Sembast (013) и экспонируют пагинированный `get*` **вместе** с реактивным `watch*` (`getChats` + `watchChats`/`watchChat`, `getMessages` + `watchMessages`); `watch*`-канал там отдаёт голый `Stream<List<T>>`-сигнал, а страницы всегда перечитываются через `get*`. См. `04-data-layer.md` про carve-out и `07-pagination.md` про контракт пагинации.
- Списочные методы возвращают слайс страницы в паре с метаданными пагинации: `(List<T>, PageMetadata)`. В контракте v0 путей ровно два: **paged** (чаты — `page` + `page_size`, ответ `{chats, has_more}`) и **seq-курсор** (история сообщений — `before_seq` + `limit`, ответ `{messages, has_more}`, батч по возрастанию `seq`, сервер молча зажимает `limit` до 100). Полный контракт — `07-pagination.md`.
- `clean()` сбрасывает кэш/subject'ы (вызывается на logout).

### 4.2 Рабочий пример: `ItemRepository`

Ниже — **полный** канонический контракт (cache-first watch/fetch + network-only список + CRUD); это эталон-цель блюпринта. В собранном скелете Feature-001 контракт сознательно урезан (см. примечание после кода).

`lib/domain/repository/item/item_repository.dart`:
```dart
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_item_config.dart'; // forward-looking — нет в коде скелета (см. §4.2)
import 'package:nox_app/domain/repository/item/get_items_config.dart';

abstract class ItemRepository {
  /// Cache-first single resource. Replays the last value, then live updates.
  /// Backed by a BehaviorSubject in the impl.
  Stream<RepositoryResult<ItemModel>> watchItem({required String id});

  /// One-shot read of the single resource (pushes onto the watch stream).
  Future<RepositoryResult<ItemModel>> fetchItem({required GetItemConfig config});

  /// Paginated server-owned list (NETWORK-ONLY — no DAO/subject; the frozen
  /// Item slice only, product lists are cache-first). Returns the page slice
  /// paired with PageMetadata. Full pagination contract: see 07-pagination.md.
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

> `PageMetadata` — **contract-shaped**: `{required bool hasMore, int? nextPage}` и **никакого `total`** (сервер тоталов на проводе не отдаёт). `hasMore` приходит с провода как `has_more`; `nextPage` — **1-based** индекс следующей страницы, он считается на клиенте (`hasMore ? page + 1 : null`) и заполняется только на paged-пути (чаты). Курсорный путь истории сообщений оставляет `nextPage` пустым и двигается по `before_seq`; тред держит `oldestLoadedSeq`, а не номера страниц. `CursorPaginationMetadata{String? nextCursor}` остаётся в `07-pagination.md` **только** как задокументированный вариант для гипотетического строкового курсора — в коде его нет. Сам тип `PageMetadata` объявлен в `lib/domain/repository/base/page_metadata.dart` и описан в `07-pagination.md`.

> **Сверка со скелетом (Feature-001).** Собранный `ItemRepository` — это **урезанный** verification-harness: он экспонирует **только** network-only список + `clean()`:
> ```dart
> abstract class ItemRepository {
>   Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config});
>   Future<void> clean();
> }
> ```
> Полный CRUD и cache-first `watchItem`/`fetchItem` (с `ItemDao` + `BehaviorSubject`) — это эталон-цель блюпринта. Кэширование в приложение уже пришло (013), но легло в `ChatRepository`/`MessageRepository`, а срез `Item` сознательно **заморожен** как verification-harness и остаётся list-only: он не product canon, а живой пример network-only-формы. Соответственно `get_item_config.dart` (см. §5.3) в коде сегодня **отсутствует** — импорт в примере выше forward-looking.

### 4.3 Пустой скелет

```dart
// lib/domain/repository/<feature>/<feature>_repository.dart
import 'package:nox_app/domain/model/<feature>/<model>_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/<feature>/get_<model>_config.dart';
import 'package:nox_app/domain/repository/<feature>/get_<model>s_config.dart';

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

Конфиги — **по одному `@freezed`-классу на каждый вызов** (`GetItemsConfig`, `GetItemConfig`, …), а не sealed-union-на-фичу (`<Feature>RepositoryConfigs`). Каждый конфиг реализует однострочный маркер `RepositoryConfig`. Конфиги несут всё, что нужно вызову, плюс именованные фабрики под частые случаи и константы пагинации. **Только `.freezed.dart`, без `.g.dart`** — конфиги в JSON не сериализуются.

### 5.1 Маркер `RepositoryConfig`

`lib/domain/repository/base/repository_config.dart`:
```dart
abstract class RepositoryConfig {}
```

### 5.2 Списочный/пагинированный конфиг: `GetItemsConfig`

`lib/domain/repository/item/get_items_config.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

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

> Это эталон-шаблон для cache-first одиночного ресурса. В собранном скелете Feature-001 `get_item_config.dart` **ещё нет** (в коде только `get_items_config.dart`) — он приходит вместе с первой кэшируемой фичей (`watchItem`/`fetchItem`, см. §4.2).

`lib/domain/repository/item/get_item_config.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

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

Поле `cacheOnly` несут конфиги одиночных кэшируемых ресурсов (`GetItemConfig`). Списочные конфиги его не несут: `GetItemsConfig` и `GetChatsConfig` — это `page` + `search`, а `GetMessagesConfig` — `chatId` + `beforeSeq` + `limit`; выбирать кэш или сеть — дело реализации репозитория, а не запроса страницы. Там, где поле присутствует, оно трёхзначное:

| Значение | Поведение |
|---|---|
| `true` | Читать **только** кэш; если ресурса в кэше нет — вернуть `notFound`, в сеть не ходить. |
| `null` или `false` | Cache-first: вернуть кэш, если он есть, иначе сходить в сеть. |

### 5.5 Пустой скелет конфига

```dart
// lib/domain/repository/<feature>/get_<model>_config.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/repository/base/repository_config.dart';

part 'get_<model>_config.freezed.dart';

@freezed
abstract class Get<Model>Config with _$Get<Model>Config implements RepositoryConfig {
  const factory Get<Model>Config({
    required String id,
    required bool? cacheOnly,
  }) = _Get<Model>Config;
}
```

> **Чего НЕ делаем (сознательно):** не объявляем JSON в домене (нет `fromJson`/`.g.dart` на конфигах), не используем `DataConverter`/`ExceptionConverter`, не делаем sealed-union-на-фичу (`<Feature>RepositoryConfigs` с `= NamedConfig`-редиректами). Один класс на вызов — проще, без union-разбора на стороне реализации.

---

## 6. Доменные модели

Доменные модели — Freezed-классы с **только** `.freezed.dart`-частью: **нет `.g.dart`, нет `fromJson`**. JSON живёт в entity-слое (`04-data-layer.md`). Производная/бизнес-логика выносится во **внешнее `extension`**, а не в тело `@freezed`-класса.

В отличие от entity-слоя (где разрешены только примитивы), доменные модели могут использовать богатые типы — enum'ы, вложенные модели, `DateTime`. Вся коэрция «примитив <-> богатый тип» происходит в **mapper'е** при переходе entity -> model (`04-data-layer.md`).

### 6.1 Рабочий пример: `ItemModel`

`lib/domain/model/item/item_model.dart` (форма из собранного скелета):
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

part 'item_model.freezed.dart';

/// Domain model — @freezed, no JSON (.freezed.dart only). Derived/business logic
/// lives in extension getters, never in the @freezed body.
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

- `@freezed` + `with _$ItemModel` + `const factory`.
- **Ровно одна `part`-директива** — `'item_model.freezed.dart'`. Никакого `'*.g.dart'`, никакого `fromJson`-фабричного конструктора.
- Производная логика (`isArchived`, `displayName`) — **только** во внешнем `extension ItemModelExt on ItemModel`, **никогда** в теле `@freezed`-класса. Это держит сгенерированный класс чистым и не привязывает геттеры к Freezed-генерации.
- Полные `package:`-импорты, никаких относительных `../` (кроме `part`-директив).
- Доменная модель может нести богатые типы (`enum ItemStatus`, `DateTime createdAt`); коэрция «примитив <-> богатый тип» — в mapper'е (`04-data-layer.md`). Поля бывают `required` (в т.ч. `required String? description` — обязательный, но nullable), nullable или с `@Default(...)` — выбирайте по семантике поля; пустой скелет (§6.3) показывает все три формы.

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

> После добавления/изменения любой модели, конфига или контракта запустите кодоген одним проходом — `fvm dart run build_runner build --delete-conflicting-outputs` (или `make generate`) — он перегенерирует все `*.freezed.dart` (см. `01-stack-and-tooling.md` и `12-dev-commands.md`). Никаких `*.g.dart` для доменных типов не появится — это норма.

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

Доменный слой задаёт **словарь** (модели, конфиги, исключения) и **контракт** (`ItemRepository`) плюс **форму возврата** (`RepositoryResult` + `match`). Data-слой исполняет контракт (мапит entity -> model, маппит необработанные ошибки -> `RepositoryException` внутри `BaseRepositoryHelper.execute` — три ветки: доменное исключение насквозь, `DioException` по типу/статусу, catch-all → `unknown`; логирует через обязательный `LogRepository`). Presentation-слой потребляет результат через `match()` / `hasData`.

> Диаграмма выше показывает **полный** контракт `ItemRepository` (эталон-цель). В коде у замороженного среза `Item` присутствуют только `getItems(GetItemsConfig)` + `clean()` (network-only carve-out); `watchItem`/`fetchItem`/CRUD и `GetItemConfig` в нём так и не появились — cache-first-форму смотрите на живых `ChatRepository`/`MessageRepository`, см. §4.2.

---

## Чеклист

После применения этого документа должно существовать и проходить анализ:

- [ ] `lib/domain/exception/base_repository_exception.dart` — однострочный маркер `abstract class BaseRepositoryException {}` (без JSON-методов).
- [ ] `lib/domain/exception/repository_exception.dart` — enum `RepositoryException` (`unknown`, `internal`, `authentication`, `connection`, `unauthenticated`, `notFound` + коды контракта v0 §2.1: `invalidRequest`, `nameTaken`, `payloadTooLarge`, `attachmentGone`, `rateLimited`, `unsupportedSchema`), реализующий маркер, плюс статический `fromWireCode(String)` (незнакомый код → `internal`).
- [ ] `lib/domain/repository/base/repository_result.dart` — `@freezed sealed class RepositoryResult<T>` с публичными вариантами `RepositoryResultSuccess<T>` / `RepositoryResultError<T>`, **взаимоисключающими** именованными фабриками `success({required data})` / `error({required exception})`, геттером `hasData`, **только `.freezed.dart`** (нет `.g.dart`, нет `fromJson`).
- [ ] `lib/domain/repository/base/repository_result_handling.dart` — `extension RepositoryResultMatch` с тримнутым `match<R>({onData, onError})` через `switch` по публичным вариантам (без `onPartial`/`onEmpty`).
- [ ] `lib/domain/repository/base/repository_config.dart` — маркер `abstract class RepositoryConfig {}`.
- [ ] Нигде в коде нет прямого `result.data!` — весь доступ через `match()` или guard по `hasData`.
- [ ] Хотя бы один контракт `<Feature>Repository`, где каждое чтение/запись возвращает `RepositoryResult` / `Stream<RepositoryResult>`; watchable-ресурсы имеют пару `watchXxx()`/`fetchXxx()`; продуктовый пагинированный список — cache-first, то есть `getXxx(config)` **вместе** с реактивным `watchXxx()` (как `ChatRepository`/`MessageRepository`), и только замороженный срез `Item` остаётся network-only (`getItems`, без `watch`-пары); записи — `createXxx`/`updateXxx`/`deleteXxx` (delete → `RepositoryResult<void>`); есть `clean()` → `Future<void>`.
- [ ] По одному `@freezed`-конфигу **на вызов**, реализующему `RepositoryConfig`. У пагинированного `GetItemsConfig` — поля `{page, search?}`, фабрики `firstPage`/`nextPage` + константы `pageSize = 20` / `defaultPage = 1`, **без** `cacheOnly`. У одиночного `GetItemConfig` (эталон-шаблон; в скелете ещё нет) — tri-state `cacheOnly`. **Только `.freezed.dart`**.
- [ ] `lib/domain/repository/base/page_metadata.dart` — `@freezed PageMetadata{ required bool hasMore, int? nextPage }`, **без** `total` (`hasMore` — с провода `has_more`; `nextPage` — 1-based, считается на клиенте и заполняется только на paged-пути, `null` на последней странице и на seq-курсорном пути истории); полный контракт — `07-pagination.md`.
- [ ] `lib/domain/repository/base/base.dart` — barrel, реэкспортирующий `repository_config.dart` + `repository_result.dart` + `repository_result_handling.dart`.
- [ ] `lib/domain/repository/log_repository.dart` — абстрактный `LogRepository` (`debug({Object? target, required String message})` / `error({Object? target, required Object error, StackTrace? stackTrace})`), единственный канал логирования (FR-011; реализация — `lib/data`, см. `02-dependency-injection.md`).
- [ ] `lib/domain/model/app_config/{app_config,app_flavor,app_flavor_type}.dart` + `lib/domain/repository/app_config/app_config_repository.dart` — flavor-зависимый рантайм-конфиг (`AppConfig({ required AppFlavorType flavor, String? apiUrl })`, `enum AppFlavorType { prod, stage }`; `apiUrl` = `null` до транспорта фазы 027, источник auth-токена ждёт stage-2-аутентификацию; см. `02`/`09`).
- [ ] Хотя бы одна `@freezed`-модель (`ItemModel`) с одной `part '*.freezed.dart'`-директивой, **без** `fromJson`/`.g.dart`; производная логика — во внешнем `extension <Model>ModelExt` (для `ItemModel` — `isArchived` / `displayName`); мелкие enum'ы — в отдельном `*_status.dart` рядом.
- [ ] Доменный слой **ничего** не импортирует из `lib/data` / `lib/presentation`; импорты — полные `package:nox_app/...`, без относительных `../` (кроме `part`).
- [ ] `fvm dart run build_runner build --delete-conflicting-outputs` (или `make generate`) перегенерирует все `*.freezed.dart` без ошибок; `fvm flutter analyze` по доменному слою чист.

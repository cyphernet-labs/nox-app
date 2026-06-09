# 08 — Конвенции и конституция

> **Назначение:** свести воедино конституцию (девять управляющих принципов) и операционные конвенции (нейминг, импорты, коммиты, форматирование, локализация, фиче-флаги, тестирование, золотые правила и «несущие» подводные камни), на которые опираются все остальные документы блюпринта. Это раздел, который кодируется в `CLAUDE.md` приложения и проверяется на каждом изменении.
> **Когда читать:** перед тем как создать или переместить любой файл, назвать любой класс, написать любой коммит; перед запуском форматтера; когда нужен авторитетный свод правил, на которые ссылаются шаблоны из остальных документов. Это финальный «контракт качества» блюпринта.
> **Связанные документы:** [00-architecture-overview.md](00-architecture-overview.md) (карта слоёв и принципы), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, доменные модели, конфиги), [04-data-layer.md](04-data-layer.md) (`Entity`/`Mapper`, `BaseRepositoryHelper`, DAO), [05-presentation-layer.md](05-presentation-layer.md) (BLoC-троица на Freezed, `AlertDialogHelper`), [06-theming.md](06-theming.md) (токены дизайна), [07-pagination.md](07-pagination.md) (пагинация v5), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (флейворы, секреты), [10-code-templates.md](10-code-templates.md) (готовые шаблоны), [11-scaffolding-plan.md](11-scaffolding-plan.md) (порядок сборки), [12-dev-commands.md](12-dev-commands.md) (команды разработки).

---

Этот документ — финальный свод. Конкретные copy-paste-ready шаблоны живут в по-слойных документах; здесь фиксируются **инварианты** (конституция) и **операционные правила** (конвенции). Конституция объявляет, что нерушимо; конвенции описывают, как именно это соблюдать в повседневной работе. Любое расхождение между шаблоном и этим документом трактуется в пользу этого документа, кроме случаев, где документ явно делегирует деталь по-слойному файлу.

---

## 1. Конституция — девять управляющих принципов

Это несущие инварианты архитектуры. Всё остальное — стиль. Каждый принцип формулируется так, чтобы его можно было проверить ревью одной строкой. Принципы пронумерованы и неизменны по нумерации (на них ссылаются по номеру из остальных документов).

### Принцип 1 — Один пакет, три слоя-папки, односторонние зависимости

Приложение — **один Dart-пакет** `nox_app` с одним `pubspec.yaml` и одним прогоном `build_runner`. Слои — это **папки** внутри `lib/`, а не отдельные пакеты:

```
lib/
├── data/          → реализации (entity, mapper, dao, api, repository impl)
├── domain/        → контракты и чистые модели (repository, model, exception, RepositoryResult)
├── presentation/  → UI, BLoC (base/base_bloc.dart), страницы, виджеты, навигация, helpers, extension
├── di/            → configure_dependencies.dart (+ .config.dart), global_aliases.dart
├── design/        → токены (App*Tokens) + theme/ (AppColors ThemeExtension)
├── general/       → constants, text_constants, feature_flags, formatters
└── resource/      → app_theme.dart и прочие ресурсы уровня приложения
```

Направление зависимостей **строго одностороннее**:

```
presentation ──▶ domain ◀── data
```

`presentation` никогда не импортирует `data`; `data` никогда не импортирует `presentation`; **`domain` не импортирует ничего** (ни Flutter, ни персистентность, ни HTTP). Однопакетная схема устраняет цикл `domain ⇄ data`, возможный при трёхпакетной раскладке: внутри одного пакета нет path-зависимостей и нет встречной ссылки `data → domain` ради DI-бутстрапа. DI — **одноуровневый**: единственная `configureDependencies(String env)`, единственная аннотация `@InjectableInit(initializerName: r'$initGetIt')` и единственный сгенерированный `configure_dependencies.config.dart` (см. [02-dependency-injection.md](02-dependency-injection.md)).

> **Однопакетные пути — правило блюпринта.** Все слой-пути однопакетные: `lib/domain/model/items/item_model.dart`, `lib/data/repository/item/item_repository_impl.dart`. Импорты — всегда `package:nox_app/...`. Описывать «три пакета», path-зависимости или цикл `domain ⇄ data` — нарушение.

### Принцип 2 — Каждый метод репозитория возвращает `RepositoryResult<T>`

Любой метод контракта репозитория возвращает `RepositoryResult<T>` (или `Stream<RepositoryResult<T>>`), и `.exception` всегда — подтип `BaseRepositoryException`, никогда не «сырой» `Exception` или фреймворковая ошибка. `RepositoryResult<T>` — **`@freezed`-тип** с дисциплиной data-XOR-exception (фабрики `RepositoryResult.success(data:)` и `RepositoryResult.error(exception:)` — взаимоисключающие; не «оба-nullable partial»). Доступ к содержимому — только через расширение `match<R>(onData:, onError:)` или геттер `hasData`; прямой `result.data!` запрещён. Полный шаблон — в [03-domain-layer.md](03-domain-layer.md).

### Принцип 3 — Трёхчастный data-model split: Entity ↔ Mapper ↔ Model

Граница между транспортом и доменом всегда трёхчастная:

```
API JSON ↔ Entity (@freezed + json_serializable) ↔ Mapper ↔ Model (@freezed, БЕЗ JSON)
```

- **Entity** (`*Entity`) — тонкий DTO, выровненный под схему: только базовые типы (`String`, `int`, `double`, `bool`, `List`, `Map<String, dynamic>`, `DateTime`-как-ISO-8601-`String`, и их nullable-варианты). Никаких enum, value-типов или конвертеров. Имеет `fromJson`/`toJson` (`.g.dart`).
- **Mapper** (`*Mapper`) — единственная граница обогащения: `String → enum`, `String → DateTime`, числовое форматирование/парсинг. Мапперы композируют дочерние мапперы через инъекцию в конструктор.
- **Model** (`*Model`) — доменная модель: `@freezed`, **только `.freezed.dart`, без `.g.dart`** (никакого JSON на доменной модели). Богатые типы (enum, `DateTime`, вложенные модели). **Бизнес-логика живёт в `extension`-геттерах**, а не в теле `@freezed`-класса.

Сверх трёхчастного split этот блюпринт сохраняет паттерн унифицированного контракта сетевого ответа: если бэкенд NOX возвращает единый конверт вида `{data, timestamp, trace_id, meta}` *(пример — бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт)*, то в data-слое применяются `ResponseEntity<T>` + вручную поддерживаемый реестр `EntityConverter<E>`. См. [04-data-layer.md](04-data-layer.md).

### Принцип 4 — Один объект-конфиг на один вызов API

Каждый параметризованный вызов получает ровно один объект-конфиг — `@freezed`-класс, реализующий маркер `RepositoryConfig`, и передаётся как `{required XxxConfig config}`. Никаких многоаргументных сигнатур и никаких zero-arg list-чтений. Канонический пример: `GetItemsConfig.firstPage()` / `GetItemsConfig.nextPage(page: …)`. Конфиг несёт `page` (+ опциональный `search`); `pageSize` (20) и `defaultPage` (1, 1-based) — статические константы конфига, а не поля (см. [07-pagination.md](07-pagination.md)). Шаблон одного `@freezed`-конфига на вызов (фабрики `firstPage`/`nextPage`, **без** sealed-union на фичу) — в [03-domain-layer.md](03-domain-layer.md).

### Принцип 5 — BLoC через Freezed-юнионы + `BaseBloc.executeLogic` + логика-в-расширениях

Управление состоянием — **BLoC на Freezed**. State и Event — `@freezed sealed`-юнионы (`sealed` для многовариантных юнионов, `abstract` для одновариантных value-объектов). Канонические подсостояния — `Initializing` / `Initialized` / `Error`, объявленные как `const factory`-конструкторы. Тонкий `BaseBloc<E, S>` оборачивает обработчики в `executeLogic` с единым `try/catch`. Вычисляемая/производная логика живёт в **`extension`-геттерах** над состоянием (не в теле `@freezed`). Переходы — через `copyWith`. BLoC-типы имеют **только `.freezed.dart`, никогда `.g.dart`** (никакого `fromJson` на типах BLoC). Побочные эффекты (навигация, snackbar) уходят через `PublishSubject`-стримы, а не через state.

> **Правило блюпринта: BLoC на Freezed, не на Equatable.** State/event — `@freezed`-юнионы (а **не** рукописные `sealed`-иерархии на `Equatable` с ручными `when()`/`copyWith()`). Имена подсостояний — `Initializing`/`Initialized`/`Error`. Полная BLoC-троица — в [05-presentation-layer.md](05-presentation-layer.md).

### Принцип 6 — Единый канал логирования + маппинг доменных исключений

Логирование — единственным каналом `LogRepository` (`debug`/`error`/`warning`). **Сырые `print`/`debugPrint` в `lib/` запрещены** (тесты — исключение). Исключения транспорта/фреймворка (типизированные `DaoException` + `ApiException`-enum с `.map`) **обязаны** маппиться в доменные `RepositoryException` через `BaseRepositoryHelper.execute<T>()`. `RepositoryResult.exception` всегда несёт подтип `BaseRepositoryException`, никогда «сырую» ошибку Dio/фреймворка. `BaseRepositoryHelper.execute<T>()` **всегда** логирует через обязательный `LogRepository`. Намеренно проглоченное исключение обязано иметь inline-комментарий, почему это безопасно. См. [04-data-layer.md](04-data-layer.md).

### Принцип 7 — Cache-first реактивные репозитории (с сетевой карвут-оговоркой)

Для пользовательских наблюдаемых ресурсов репозитории — **cache-first и реактивные**: реактивный Sembast-DAO (`onSnapshots`, транзакции) + env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory) через провайдеры `@LazySingleton(as: AppDatabase, env: [...])`. Репозиторий подписывается на стрим DAO один раз и кормит один `BehaviorSubject<RepositoryResult<...>>`; экспонирует парные `watchXxx()` (Stream) + `fetchXxx()` (Future). Удалённый API гидратирует локальное хранилище; UI смотрит на локальные стримы (local-first).

> **Карвут:** пагинированные серверо-владеемые списки и одноразовые POST-ы — **network-only**: без DAO и без `BehaviorSubject`. Список чатов NOX (общий открытый шаринг-спейс; эндпоинт вида `GET /api/v1/chats/` — *пример, бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт*) — именно такой случай: пагинированный серверный список → сетевой, без кэш-слоя (см. [07-pagination.md](07-pagination.md)).

### Принцип 8 — Только токены дизайна (light + dark), Semantics, единый файл фиче-флагов

В фиче-коде запрещены «сырые» `Color`, `EdgeInsets`, `TextStyle` и системный overlay-стиль. Используются только токены: `AppColorsTokens`, `AppSpacingTokens`, `AppTextStyleTokens`, `AppOverlayStyleTokens`. Spacing/типографика — через `flutter_screenutil` (адаптивные токены). Темизация — **light + dark** через `ThemeExtension<AppColors>` + `AppTheme.light()`/`dark()` + `context.appColors` + `themeMode` из `AppRootBloc`. Новые интерактивные виджеты оборачивают интерактивный элемент в `Semantics(label:, button: true)`. Все статические тоглы — в **одном** `lib/general/feature_flags.dart` как `static const bool` (remote-config-флаги — вне области этого модуля). См. [06-theming.md](06-theming.md).

### Принцип 9 — Compile-time изоляция флейворов

Флейвор резолвится на этапе компиляции: `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг `flavor → env`: `prod → Environment.prod`, `stage → Environment.dev`. Все флейвор-специфичные значения приходят через `--dart-define-from-file`; **никакого runtime-ветвления по флейвору**. Секреты — через SOPS + age + mise + флейворные Android/iOS-сборки. Версионирование — CalVer + сдвинутая эпоха (`YY.M.D+EPOCH`). `main.dart` оборачивает запуск в `runZonedGuarded`, ждёт `configureDependencies(env)`, затем `getIt.allReady()`. Отдельного BLoC-обсервера нет: логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует), а ошибки BLoC-обработчиков оборачиваются `BaseBloc.executeLogic`. См. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md).

---

## 2. Десять золотых правил

Это компактная памятка-чеклист для ревью. Каждое правило проверяется одной строкой и кодируется в `CLAUDE.md` приложения. Правила 1–9 — операционные проекции принципов конституции; правило 10 добавляет стандарт пагинации.

1. **Один пакет, три слоя-папки, односторонние зависимости.** `presentation → domain ← data`; `domain` не импортирует ничего; один `pubspec.yaml`, один `build_runner`, одна `configureDependencies(env)`. (Принцип 1.)
2. **Каждый метод репозитория возвращает `RepositoryResult<T>`** (или `Stream<...>`); `.exception` всегда `BaseRepositoryException`; доступ через `match()`/`hasData`, **никогда `result.data!`**. (Принцип 2.)
3. **Трёхчастный data-model split.** Entity (`@freezed` + json) ↔ Mapper ↔ Model (`@freezed`, без json); логика модели — в `extension`-геттерах. Entity — только базовые типы. (Принцип 3.)
4. **Один конфиг на один вызов** — `@freezed`-класс с маркером `RepositoryConfig`, передаётся как `{required XxxConfig config}`. (Принцип 4.)
5. **BLoC через `@freezed sealed` State/Event + `BaseBloc.executeLogic` + логика-в-расширениях.** Подсостояния `Initializing`/`Initialized`/`Error`. Побочные эффекты — через `PublishSubject`, не через state. BLoC-типы — только `.freezed.dart`. (Принцип 5.)
6. **Единый канал логирования `LogRepository`; маппинг доменных исключений.** Никаких сырых `print`/`debugPrint` в `lib/`; транспортные ошибки → `RepositoryException` через `BaseRepositoryHelper.execute<T>()`. (Принцип 6.)
7. **Cache-first реактивные репозитории** для пользовательских наблюдаемых ресурсов (`BehaviorSubject` + Sembast-DAO); **карвут**: пагинированные серверные списки и одноразовые POST-ы — network-only. (Принцип 7.)
8. **Только токены дизайна; light + dark; Semantics; единый `feature_flags.dart`.** Никаких хардкод-цветов/отступов/стилей/overlay. (Принцип 8.)
9. **Codegen-first, генераты не редактируются руками.** Freezed + json_serializable + injectable; после правки любого аннотированного класса — прогон генератора. `*.g.dart`/`*.freezed.dart`/`*.config.dart`/`lib/design/gen/**` исключены из анализа и форматирования. (Принцип 9.)
10. **Пагинация — стандарт v5.** `infinite_scroll_pagination ^5.1.1`, stateless `PagingState`-в-блоке (никогда `PagingController`), переиспользуемое расширение `PagingStateExt.applyPage`, дефолтный flavor — OFFSET (`PageMetadata{int? nextPage, int total}`), cursor — документированная альтернатива; ошибки прокидываются в `pagingState.error`. (См. [07-pagination.md](07-pagination.md).)

> **Дополнительный нерушимый инвариант:** `AlertDialogHelper` — **единственный** канал пользовательских ошибок (см. §8 ниже и [05-presentation-layer.md](05-presentation-layer.md)). Компиляция-флейвор-изоляция (Принцип 9 конституции) и единый канал ошибок дополняют десятку золотых правил, но проверяются вместе с ними на каждом ревью.

---

## 3. Конвенции нейминга

Эти правила абсолютны: scaffolding-скиллы, анализатор и кодогенерация на них опираются. Нейтральный сквозной пример — **Item**; пустые скелеты используют плейсхолдеры `<Feature>` / `<feature>` / `<Model>`. Первая реальная фича для реализации — **список чатов** (открытый общий шаринг-спейс — серверо-владеемый, network-only пагинированный список), но шаблоны держатся на нейтральном Item.

### 3.1 Регистр идентификаторов

| Сущность | Регистр | Пример |
|---|---|---|
| Имена файлов (включая генераты) | `snake_case.dart` | `item_model.dart`, `item_model.freezed.dart` |
| Классы, интерфейсы, enum, mixin | `PascalCase` | `ItemModel`, `ItemRepository` |
| Переменные, поля, методы, параметры | `camelCase` | `itemRepository`, `fetchItems()` |
| Константы | `static const`-члены класса (предпочтительнее top-level) | `AppSpacingTokens.s16` |
| BLoC-события | повелительное наклонение (imperative) | `LoadItems`, `UpdateSearchQuery` |
| BLoC-состояния | Freezed-варианты | `Initializing`, `Initialized`, `Error` |

### 3.2 Паттерны имён артефактов

| Артефакт | Паттерн | Пример (Item) | Каноническое расположение |
|---|---|---|---|
| Доменная модель | `*Model` | `ItemModel` | `lib/domain/model/<feature>/` |
| Data-entity | `*Entity` | `ItemEntity` | `lib/data/entity/<feature>/` |
| Контракт репозитория | `*Repository` | `ItemRepository` | `lib/domain/repository/<feature>/` |
| Реализация репозитория | `*RepositoryImpl` | `ItemRepositoryImpl` | `lib/data/repository/<feature>/` |
| Конфиг репозитория | `*Config` / `*RepositoryConfigs` | `GetItemsConfig` | `lib/domain/repository/<feature>/` |
| Mapper | `*Mapper` | `ItemMapper` | `lib/data/mapper/<feature>/` |
| DAO | `*Dao` | `ItemDao` | `lib/data/local/` |
| API-клиент | `Get*Api` / `Post*Api` (файл `get_items_api.dart`) | `GetItemsApi` | `lib/data/remote/api/<feature>/` |
| Request builder | `*ApiRequestBuilder` | `GetItemsApiRequestBuilder` | `lib/data/remote/request_builder/<feature>/` |
| Страница | `*Page` | `ItemListPage` | `lib/presentation/pages/<page>_page/` |
| BLoC | `*Bloc` | `ItemListBloc` | `lib/presentation/pages/<page>_page/bloc/` |
| Файлы BLoC | `*_bloc.dart`, `*_event.dart`, `*_state.dart` | `item_list_bloc.dart` | та же папка `bloc/` |
| Общие виджеты | `App*Widget` | `AppProgressWidget`, `AppErrorWidget`, `AppEmptyContentWidget` | `lib/presentation/widgets/` |
| Токены дизайна | `App*Tokens` | `AppSpacingTokens`, `AppImagesTokens` | `lib/design/` |
| ThemeExtension | `App*` | `AppColors` (+ `LightAppColors` / `DarkAppColors`) | `lib/design/theme/` |

Ключевые пары имён, которые легко перепутать:

- **Интерфейс vs реализация:** `item_repository.dart` (контракт в `lib/domain/`) vs `item_repository_impl.dart` (реализация в `lib/data/`).
- **Доменная модель vs data-entity:** `ItemModel` (в `lib/domain/model/`) vs `ItemEntity` (в `lib/data/entity/`).
- **API vs config:** `get_items_api.dart` (REST-клиент) vs `get_items_config.dart` (объект-конфиг вызова).

### 3.3 Семантика имён методов репозитория

Имена методов контракта кодируют, **откуда** данные и их **кардинальность**:

```dart
// One-shot, reads a single record.
Future<RepositoryResult<ItemModel>> fetchItem({required String id});

// One-shot, reads a parametrized list.
Future<RepositoryResult<List<ItemModel>>> getItems({required GetItemsConfig config});

// Reactive stream of updates.
Stream<RepositoryResult<ItemModel>> watchItem({required String id});

// Mutations.
Future<RepositoryResult<ItemModel>> createItem({required ItemModel item});
Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item});
Future<RepositoryResult<void>>      deleteItem({required String id});

// Local-cache lifecycle.
Future<void> clean();
```

| Префикс | Возврат | Семантика |
|---|---|---|
| `fetch*` | `Future<RepositoryResult<T>>` | one-shot чтение одной записи |
| `get*` | `Future<RepositoryResult<T>>` | параметризованное/списочное чтение |
| `watch*` | `Stream<RepositoryResult<T>>` | реактивный стрим, бэкается `BehaviorSubject` |
| `create*` / `update*` | `Future<RepositoryResult<T>>` | мутация, возвращает обновлённую модель |
| `delete*` | `Future<RepositoryResult<void>>` | удаление |
| `clean` | `Future<void>` | очистка локального кэша (при logout / wipe) |

Каждый метод контракта возвращает обёрнутый `RepositoryResult<T>` — **никогда** голый `Future<T>`. Списочные чтения принимают единственный `{required XxxConfig config}`; всегда конструируются явно (`GetItemsConfig.firstPage()` / `GetItemsConfig.nextPage(page: …)`), никогда zero-arg.

---

## 4. Конвенции импортов

### 4.1 Полные `package:`-импорты

Использовать полные `package:nox_app/...`-импорты по всему коду. Избегать относительной `../`-навигации — особенно в доменных моделях, entity и мапперах.

```dart
// CORRECT
import 'package:nox_app/domain/model/items/item_model.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';

// WRONG — fragile relative traversal
import '../../../domain/model/items/item_model.dart';
```

Единственные допустимые относительные импорты — `part`-директивы генератов (`part 'item_model.freezed.dart';`) и sibling-`part of` внутри папки BLoC.

### 4.2 Порядок импортов

Группы, разделённые пустой строкой (`directives_ordering`):

1. Dart SDK — `dart:async`, `dart:convert`
2. Flutter framework — `package:flutter/material.dart`
3. Third-party — `package:freezed_annotation/...`, `package:injectable/...`
4. Локальные импорты — `package:nox_app/...`
5. `part`-директивы

### 4.3 Бочки (barrels)

Внутри одного пакета бочки нужны меньше, чем в трёхпакетной схеме, но папки-фичи могут экспонировать локальную бочку для удобства (`lib/domain/model/models.dart`, re-export по одному `export` на публичную модель). Cross-package-алиасинг (`import '...' as domain;`), нужный в трёхпакетной раскладке, здесь **не требуется** — все типы в одном пакете.

---

## 5. Конвенции коммитов

(Правила формы коммита — независимы от модели ветвления.)

### 5.1 Сабджект

Хорошо оформленный сабджект завершает фразу: *«If applied, this commit will ___»*.

- **Повелительное наклонение**, с заглавной, без точки в конце.
- **≤ 50 символов.**

```text
Add item list pagination          ← correct
Added item list pagination        ← wrong (past tense)
Adds item list pagination.        ← wrong (3rd person + period)
```

### 5.2 Тело

Если тело нужно — отделять от сабджекта пустой строкой и переносить на ~72 символах. Объяснять и проблему, и обоснование решения. Буллеты `-` / `*` + одиночный пробел.

### 5.3 Атомарные коммиты

- Каждый коммит компилируется и проходит тесты независимо.
- Не смешивать форматирование/перемещения кода с логическими изменениями — разделять.
- Одно логическое изменение на коммит; включать сопутствующие правки доков/тестов.

### 5.4 DCO sign-off

Все коммиты несут sign-off (Developer Certificate of Origin):

```bash
git commit -s
```

Без `-s` строка sign-off отсутствует и PR отклоняется.

### 5.5 База PR

Рекомендуемая модель — GitFlow-вариант: фиче-ветки мёрджатся в `develop`, `develop` мёрджится в `master` на релизе. Для скелета приложения выбрать одну модель и задокументировать её в собственном `CONTRIBUTING.md`; правила «imperative-subject + atomic + sign-off» от ветвления не зависят.

> **Согласование с репозиторием NOX:** коммиты и пуши в `develop`/`master` и merge PR **не** выполняются автономно. Изменения стейджатся, показывается дифф, предлагается точная команда коммита — и ожидается явное подтверждение владельца. Это не отменяет правила выше: они описывают форму коммита, а это — кто и когда его выполняет.

---

## 6. Жёсткое правило форматирования (HARD RULE)

После правки форматировать **только изменённые файлы**, с явными путями:

```bash
fvm dart format -l 140 path/to/file_a.dart path/to/file_b.dart
```

- **Никогда** не запускать форматирование всего репозитория (`dart format .` / `make format`) как шаг завершения задачи — это переформатирует всё и создаёт массивные несвязанные диффы, блокирующие коммит. Форматирование всего репо — только CI-gate.
- **Никогда** не вычислять файлы для форматирования через `git diff` — это подтянет ветко-расходящийся шум.
- **Никогда** не форматировать генераты (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`, `*.mocks.dart`).
- **Длина строки — 140 символов** (`formatter: page_width: 140` в `analysis_options.yaml` — источник истины; команды также передают `-l 140` для явности).

Скоуп форматирования — `lib/`, `test/`. Исключения — все генераты выше.

---

## 7. Локализация (стойка)

**Инфраструктуры i18n нет (пока).** Все пользовательские строки захардкожены на английском, централизованы в `lib/general/text_constants.dart` как `static const String`-поля, организованные в `///`-секции, мапящиеся 1:1 на страницы/виджеты. Пакет `intl` используется **только** для форматирования (даты/числа).

> **Запланирована миграция на локализацию (отдельный таск).** После полной реализации проекта и всех экранов планируется перенос пользовательских строк на полноценную систему локализации (ARB + `flutter_localizations` / `gen-l10n`, либо эквивалент — выбор конкретного инструмента откладывается на тот же таск). Это **отдельная задача в конце**, а не часть текущей работы. Поэтому `text_constants.dart` уже сейчас должен быть **теоретически пригоден к переносу**: каждая константа должна 1:1 ложиться в будущий ARB-ключ.

```dart
// lib/general/text_constants.dart
final class TextConstants {
  /// General
  static const appName = 'NOX';

  /// General actions
  static const actionCancel = 'Cancel';
  static const actionTryAgain = 'Try Again';
  static const actionConfirm = 'Confirm';

  /// General errors
  static const errorGeneralTitle = 'Something went wrong';
  static const errorGeneralMessage = "We couldn't complete your request. Please try again later.";
  static const errorConnection = 'No internet connection.';
  static const errorAccess = 'Access error. Please sign in again.';
  static const errorNotFound = 'Not found.';

  /// <FeatureName>  — one section per feature
  // static const itemListTitle = 'Items';
}
```

**Чтобы файл оставался migration-ready** (под будущий перенос на ARB/локализацию):

- Одна `static const String` на каждый пользовательский текст; **никакой конкатенации строк в рантайме**. Параметризованные строки оформляй как методы (`static String greeting(String name) => 'Hello, $name';`), чтобы они отобразились в ARB-плейсхолдеры, а не склеивались вручную.
- Логичная группировка по `///`-секциям (фича/экран) и стабильные говорящие имена ключей (`itemListTitle`, `errorConnection`) — они станут именами ARB-ключей.
- Никакой логики/форматирования внутри строк: форматирование чисел/дат идёт через `intl` во форматтерах (`lib/general/formatters/`, см. [06-theming.md](06-theming.md)), а не в `TextConstants`.
- Множественное число / род / падежи (если появятся) — выноси в методы, а не склеивай руками: ICU-плюрализация будет добавлена на этапе локализации.

---

## 8. Пользовательские ошибки (единый канал)

- `AlertDialogHelper.showErrorSnackBar(context, message)` — **единственный** канал пользовательских error-snackbar'ов; `AlertDialogHelper.showSnackBar` — для не-error info.
- **Никогда** не показывать сырые сообщения исключений. Транслировать `RepositoryException` → человекочитаемые строки в BLoC (см. `_translate(...)` в [05-presentation-layer.md](05-presentation-layer.md)), используя `TextConstants`.

---

## 9. Фиче-флаги

Все статические тоглы — в **одном** модуле как `static const bool`-поля. Ad-hoc флаг-константы где-либо ещё запрещены. Remote-config-флаги — вне области этого модуля (out of scope).

```dart
// lib/general/feature_flags.dart
class FeatureFlags {
  static const bool enabledSomeFeature = true;
  // dev-only flags: document why + that they must be false on merge.
}
```

---

## 10. Тестирование (стойка)

- Тесты зеркалят `lib/` под `test/`.
- Глобальный сетап — `test/flutter_test_config.dart` → `TestsUtils.initializeMock()` → `configureDependencies(Environment.test)`.
- Мокинг — Mockito; bloc-тесты — `bloc_test`; интеграционные — `integration_test`.
- DI-окружение `Environment.test` подключает in-memory `AppDatabaseTest`.

```dart
// test/flutter_test_config.dart
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await TestsUtils.initializeMock(); // → configureDependencies(Environment.test)
  await testMain();
}
```

Базовые шаблоны для копирования первой фичи: тест маппера + тест request-builder + bloc-тест.

---

## 11. Семь несущих подводных камней (gotchas)

Правила, которые легче всего нарушить. Каждое — несущее. Сведены к однопакетной схеме и переопределениям этого блюпринта.

### 11.1 Entity — только базовые типы

Data-entity (`*Entity`) содержат **только** скаляры (`String`, `int`, `double`, `bool`), коллекции скаляров/вложенных entity (`List<T>`, `Map<String, dynamic>`), `DateTime`-как-ISO-8601-`String` и nullable-варианты. Никаких enum, value-типов, конвертеров. Всё обогащение (`String → enum`, `String → DateTime`, числовая точность) — в **маппере**, не в entity.

```dart
// lib/data/entity/item/item_entity.dart
@freezed
abstract class ItemEntity with _$ItemEntity {
  const factory ItemEntity({
    required String id,
    required String name,
    required String status,        // plain String — NOT an enum
    required String createdAt,     // ISO-8601 String — NOT DateTime in JSON-land
    required String? description,
  }) = _ItemEntity;

  factory ItemEntity.fromJson(Map<String, Object?> json) => _$ItemEntityFromJson(json);
}
```

Доменная модель — богатые типы, никакого JSON:

```dart
// lib/domain/model/items/item_model.dart  (rich types, NO json_serializable)
@freezed
abstract class ItemModel with _$ItemModel {
  const factory ItemModel({
    required String id,
    required String name,
    required ItemStatus status,    // enum
    required DateTime createdAt,   // DateTime
    required String? description,
  }) = _ItemModel;
}
```

| Конверсия | Где происходит |
|---|---|
| `String → enum` / `enum → String` | `ItemMapper.toModel()` / `toEntity()` |
| `String → DateTime` / `DateTime → ISO-8601 String` | `ItemMapper.toModel()` / `toEntity()` |
| числовое форматирование/парсинг | `ItemMapper.toModel()` / `toEntity()` (`num`/`double` + `intl`) |

### 11.2 BLoC — это `@freezed sealed`, НЕ рукописный Equatable

В этом блюпринте state/event BLoC — `@freezed sealed`-юнионы с `const factory`-конструкторами `Initializing`/`Initialized`/`Error`, тонким `BaseBloc.executeLogic` и логикой в `extension`-геттерах. Это **правило блюпринта**: BLoC — на Freezed, а **не** рукописные sealed на `Equatable`. BLoC-типы имеют только `.freezed.dart`, никогда `.g.dart`. Полная троица — в [05-presentation-layer.md](05-presentation-layer.md).

Это касается **не только BLoC**: `equatable` **намеренно исключён из зависимостей**. Value-equality (`==` / `hashCode`) везде даёт Freezed — любой value-объект объявляется `@freezed`-классом, а **не** наследует `Equatable`. Подключать `equatable` обратно — только если найдётся кейс, который Freezed реально не закрывает (на сегодня такого нет). См. заметку «Почему нет `equatable`» в [01-stack-and-tooling.md](01-stack-and-tooling.md).

### 11.3 Env-список в DI — несущий

Реализации репозиториев аннотируются `@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])`. **Env-список обязателен**, потому что Sembast-база env-scoped (Dev/Prod = IO, Test = memory) — пропуск списка ломает резолюцию провайдера `AppDatabase`. DAO/мапперы/API-клиенты/request-builder'ы регистрируются плоским `@lazySingleton` (без env-фильтра — во всех окружениях). Env-scoped провайдеры базы (`AppDatabaseDev`/`AppDatabaseProd`/`AppDatabaseTest`) — через `@LazySingleton(as: AppDatabase, env: [...])` по окружению. См. [02-dependency-injection.md](02-dependency-injection.md).

```dart
@LazySingleton(
  as: ItemRepository,
  env: [Environment.dev, Environment.prod, Environment.test],
)
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository { ... }
```

### 11.4 Форматировать только изменённые файлы @140

`fvm dart format -l 140 <явные пути>`. Никакого whole-repo-формата, никакого вычисления через `git diff`, никакого форматирования генератов. См. §6.

### 11.5 Никогда `result.data!` — только `match()`/`hasData`

`RepositoryResult<T>` — `@freezed`-тип с data-XOR-exception. Прямой `result.data!` запрещён; доступ через расширение `match<R>(onData:, onError:)` или геттер `hasData`:

```dart
result.match<void>(
  onData: (items) => emit(ItemListState.initialized(items: items)),
  onError: (exception) => emit(ItemListState.error(exception: exception)),
);
```

### 11.6 Конец задачи — gen → format → analyze

После любого изменения модели/репозитория/страницы запускать **в порядке**: кодогенерация → форматирование изменённых файлов → анализ.

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart format -l 140 <changed files...>
fvm flutter analyze
```

(Или инвокнуть `/check-build` — см. [12-dev-commands.md](12-dev-commands.md).)

### 11.7 Запуск кодогенерации после правки аннотированных классов

После правки любого `@freezed` / `@JsonSerializable` / `injectable`-аннотированного класса — регенерация. В однопакетной схеме порядок прост — один прогон:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

В отличие от трёхпакетной раскладки (где требуется последовательность `data → domain → root`), внутри одного пакета `build_runner` запускается один раз и генерит всё (`*.freezed.dart`, `*.g.dart`, `*.config.dart`).

---

## 12. Скелет `CLAUDE.md` приложения

Заготовка `CLAUDE.md` для `lib/`, переносящая в проектную память существо этого блюпринта. Прозу держать на русском (репо-правило), код/команды/идентификаторы — на английском.

```markdown
# CLAUDE.md — NOX (lib/)

## Обзор проекта
Flutter-приложение (iOS, Android, Windows, Linux, macOS) для NOX. ОДИН Dart-пакет `nox_app`.
Слои — папки в `lib/`: data / domain / presentation + di / general / design / resource.
Flutter 3.44.1 (FVM, `.fvmrc`). Dart sdk >=3.12.0 <4.0.0. Line length 140.
Флейворы: stage, prod. applicationId/bundle: com.cyphernetlabs.noxapp (stage: com.cyphernetlabs.noxapp.stage).
Архитектурный референс: docs/patterns/mobile/ (этот блюпринт — каноничный источник).

## Основные команды
- Codegen:  fvm dart run build_runner build --delete-conflicting-outputs
- Tests:    fvm flutter test
- Analyze:  fvm flutter analyze
- Format (ТОЛЬКО изменённые файлы, @140):  fvm dart format -l 140 <paths>

## Архитектура (золотые правила — несущие инварианты)
1. Один пакет, три слоя-папки; presentation → domain ← data; domain не импортирует ничего.
2. Каждый метод репозитория → RepositoryResult<T>; доступ через match()/hasData, никогда result.data!.
3. Трёхчастный split: Entity(@freezed+json) ↔ Mapper ↔ Model(@freezed, без json); логика в extension-геттерах.
4. Один @freezed-конфиг (RepositoryConfig) на вызов, {required XxxConfig config}.
5. BLoC через @freezed sealed State/Event + BaseBloc.executeLogic + логика-в-расширениях;
   подсостояния Initializing/Initialized/Error; побочные эффекты через PublishSubject.
6. Единый канал LogRepository; маппинг исключений в RepositoryException; никаких сырых print.
7. Cache-first реактивные репозитории (BehaviorSubject + Sembast-DAO);
   карвут: пагинированные серверные списки и одноразовые POST-ы — network-only.
8. Только токены дизайна; light + dark (ThemeExtension<AppColors>); Semantics; единый feature_flags.dart.
9. Codegen-first; генераты (*.g.dart/*.freezed.dart/*.config.dart/lib/design/gen/**) не редактируются руками.
10. Пагинация — infinite_scroll_pagination ^5.1.1, stateless PagingState-в-блоке, PagingStateExt.applyPage,
    дефолт OFFSET; ошибки → pagingState.error.

## Несущие правила
- HARD RULE форматирования: только изменённые файлы, явные пути, @140; никакого whole-repo / git-diff.
- AlertDialogHelper — единственный канал пользовательских ошибок; сырые exception-сообщения не показывать.
- Локализации i18n нет: строки в lib/general/text_constants.dart (static const), intl только для форматирования.
- entity_converter.dart поддерживается вручную: новую entity регистрировать в EntityConverter (fromJson И toJson).
- Compile-time флейворы: AppFlavor.getFlavor() из String.fromEnvironment('app.flavor'); никакого runtime-ветвления.
- Конец задачи: codegen → format (изменённые) → analyze.

## Нейминг
Файлы snake_case; классы/enum PascalCase; члены camelCase; BLoC-события imperative;
состояния — Freezed-варианты Initializing/Initialized/Error; интерфейс item_repository.dart vs
impl item_repository_impl.dart; домен ItemModel vs data ItemEntity; api get_items_api.dart;
config get_items_config.dart.
```

> **Заметка про обслуживание `entity_converter.dart`:** реестр `EntityConverter` поддерживается **вручную**. При добавлении новой entity её нужно зарегистрировать в **обоих** диспатчах (`fromJson` И `toJson`), иначе — runtime `ArgumentError('No converter found for type ...')`. Это единственный hand-maintained реестр в data-слое; см. [04-data-layer.md](04-data-layer.md).

---

## Чеклист

После применения этого документа должно выполняться:

- [ ] Каждый новый файл — `snake_case.dart`; каждый класс/enum — `PascalCase`; члены — `camelCase`.
- [ ] Суффиксы артефактов соответствуют §3.2 (`*Model`, `*Entity`, `*Repository`, `*RepositoryImpl`, `*Config`, `*Mapper`, `*Dao`, `*Page`, `*Bloc`).
- [ ] Методы репозитория названы `fetch*` / `get*` / `watch*` / `create*` / `update*` / `delete*` / `clean` и возвращают `RepositoryResult<T>` (никогда голый `Future<T>`).
- [ ] Импорты — полные `package:nox_app/...`; никакой `../`-навигации, кроме `part`-директив.
- [ ] Файлы организованы по папке-странице (presentation: одна плоская папка `lib/presentation/pages/<page>_page/` на экран) / по сущности (domain/data), не по типу артефакта.
- [ ] Entity — только базовые типы; всё обогащение в мапперах.
- [ ] State/event BLoC — `@freezed sealed`-юнионы с `Initializing`/`Initialized`/`Error`; только `.freezed.dart`, никогда `.g.dart`; побочные эффекты — через `PublishSubject`.
- [ ] Реализации репозиториев — `@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])`; DAO/мапперы/API — `@lazySingleton`.
- [ ] `RepositoryResult` читается через `match()`/`hasData`; нигде нет `result.data!`.
- [ ] Пагинация — `infinite_scroll_pagination ^5.1.1`, `PagingState`-в-блоке, `applyPage`; ошибки в `pagingState.error`.
- [ ] Темизация — light + dark через `ThemeExtension<AppColors>`; в фиче-коде только токены, никаких хардкод-значений.
- [ ] Логирование — только `LogRepository`; никаких `print`/`debugPrint` в `lib/`.
- [ ] Пользовательские ошибки — только через `AlertDialogHelper`; сырые exception-сообщения не показываются.
- [ ] Ни один `*.freezed.dart` / `*.g.dart` / `*.config.dart` не редактировался руками.
- [ ] Конец задачи: codegen → format (только изменённые файлы, `-l 140`) → `fvm flutter analyze` — всё чисто.
- [ ] Коммиты — imperative, ≤50-символьный сабджект с заглавной, атомарные, с `git commit -s` (с учётом репо-правил о подтверждении владельцем).
- [ ] `CLAUDE.md` приложения создан из скелета §12 (золотые правила, нейминг, HARD RULE форматирования, локализация, заметка про `entity_converter.dart`).

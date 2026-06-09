# 00 — Обзор архитектуры

> **Назначение:** дать единую ментальную модель приложения — однопакетная Clean Architecture (presentation → domain ← data) с Freezed-BLoC, реактивными репозиториями и DI на injectable+get_it. Это карта, к которой привязаны все остальные документы блюпринта.
> **Когда читать:** в самом начале, до того как трогать любой файл, пакет или шаблон. Это входная точка набора `docs/patterns/mobile/`.
> **Целевые платформы:** iOS, Android, Windows, Linux, macOS (web — вне scope). Desktop-floor зафиксирован (дефолты Flutter 3.44.1), single-window подтверждён, оболочка адаптивная (`NavigationRail` на десктопе); packaging/signing — FUTURE.
> **Связанные документы:** [01-stack-and-tooling.md](01-stack-and-tooling.md) (SDK, зависимости, FVM), [02-dependency-injection.md](02-dependency-injection.md) (injectable + get_it bootstrap), [03-domain-layer.md](03-domain-layer.md) (модели, `RepositoryResult`, контракты), [04-data-layer.md](04-data-layer.md) (entity, DAO, мапперы, импл, REST), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, страницы, виджеты), [06-theming.md](06-theming.md) (`AppColors`, `AppTheme`, токены), [07-pagination.md](07-pagination.md) (offset/cursor пагинация), [08-conventions-and-constitution.md](08-conventions-and-constitution.md) (полная конституция и правила), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (флейворы, секреты, версии), [10-code-templates.md](10-code-templates.md) (copy-paste шаблоны), [11-scaffolding-plan.md](11-scaffolding-plan.md) (порядок сборки), [12-dev-commands.md](12-dev-commands.md) (dev-команды), [13-deep-links.md](13-deep-links.md) (deep/universal links), [14-networking-and-auth.md](14-networking-and-auth.md) (сеть/auth, connectivity + app-lifecycle), [15-push-notifications.md](15-push-notifications.md) (FCM), [16-file-upload.md](16-file-upload.md) (2-step upload вложения в чат), [17-analytics.md](17-analytics.md) (клиентская аналитика, вендоронезависимо).

Этот документ — каноническая карта. Точные, готовые к копированию шаблоны живут в послойных документах, перечисленных выше; здесь задаются раскладка `lib/`, ответственность каждого слоя, реальное направление зависимостей, сценарии чтения и записи данных и набор принципов, который держит всё это вместе.

---

## 1. Ментальная модель: один пакет, три слоя — папками

Приложение — это **один Dart-пакет** `nox_app` с одним `pubspec.yaml` и одним прогоном `build_runner`. Слои Clean Architecture здесь — это **папки внутри одного `lib/`**, а не отдельные пакеты:

```
┌──────────────────────────────────────────────────────────┐
│  presentation/   страницы, виджеты, BLoC, навигация       │
│        │  зависит ↓ (только от domain)                     │
├────────┼──────────────────────────────────────────────────┤
│  domain/         модели, ИНТЕРФЕЙСЫ репозиториев, ошибки   │
│        ▲  от него зависят оба соседних слоя                │
├────────┼──────────────────────────────────────────────────┤
│  data/           РЕАЛИЗАЦИИ репозиториев, entity, мапперы, │
│                  API, DAO                                  │
│           зависит ↑ (только от domain)                     │
└──────────────────────────────────────────────────────────┘
```

> **Важно — это НЕ три пакета.** Правило этого блюпринта: один пакет, одни импорты `package:nox_app/...`, один генератор, один `configureDependencies(env)`. Трёхпакетный монорепо (`domain/`, `data/` как path-зависимости с двусторонним циклом `domain ⇄ data`) здесь **не используется**. Любой путь вида `domain/lib/src/...` или `data/lib/src/...` приводится к однопакетному `lib/domain/...` / `lib/data/...`. Никакого цикла `domain ⇄ data` нет — `domain` не импортирует ничего.

**Почему один пакет, а не три.** Три path-пакета давали изоляцию на уровне `pubspec`, но платили за это: тройным `pub get` + `build_runner`, трёхуровневой цепочкой DI и реальным циклом зависимостей `domain ⇄ data` (потому что DI-bootstrap домена дёргал data). В одном пакете изоляция слоёв обеспечивается **дисциплиной импортов** (см. §3) и линтером, а не границами пакетов — этого достаточно для кросс-платформенного приложения (iOS, Android, Windows, Linux, macOS), и это убирает всю оркестрационную сложность.

---

## 2. Раскладка `lib/` (ASCII-дерево)

```
nox_app/
├── pubspec.yaml                        ← ОДИН pubspec на весь проект
├── analysis_options.yaml               line length 140, исключения для генерации
├── .fvmrc                              Flutter 3.44.1, закреплён через FVM
├── lib/
│   ├── main.dart                       точка входа: runZonedGuarded → configureDependencies(env)
│   │                                   → getIt.allReady() → runApp(AppRoot)
│   │
│   ├── di/                             ← Dependency Injection (единый ярус)
│   │   ├── configure_dependencies.dart        @InjectableInit(initializerName: r'$initGetIt')
│   │   │                                       Future<void> configureDependencies(String env)
│   │   ├── configure_dependencies.config.dart ГЕНЕРИРУЕТСЯ ($initGetIt)
│   │   └── global_aliases.dart                getIt<T>() удобные геттеры (напр. getItemRepository)
│   │
│   ├── general/                        ← кросс-слойные утилиты (без UI, без бизнес-логики)
│   │   ├── constants.dart                     Constants (regex, размеры, флаги)
│   │   ├── feature_flags.dart                 единый модуль фич-флагов
│   │   ├── text_constants.dart                строковые константы / тексты
│   │   └── utils/                             platform_utils, форматтеры
│   │
│   ├── domain/                         ← ДОМЕН (импортирует НИЧЕГО из data/presentation)
│   │   ├── exception/
│   │   │   ├── base_repository_exception.dart
│   │   │   └── repository_exception.dart       enum RepositoryException
│   │   ├── model/
│   │   │   ├── app_config/
│   │   │   │   ├── app_flavor_type.dart         enum AppFlavorType{prod,stage}
│   │   │   │   ├── app_flavor.dart              AppFlavor.getFlavor() (String.fromEnvironment)
│   │   │   │   └── app_config_model.dart        конфиг флейвора (apiUrl/apiSignatureKey/…)
│   │   │   └── item/
│   │   │       └── item_model.dart             @freezed доменная модель (БЕЗ JSON)
│   │   └── repository/
│   │       ├── base/
│   │       │   ├── repository_result.dart      @freezed RepositoryResult<T> (success XOR error)
│   │       │   ├── repository_result_handling.dart  match<R>(onData, onError)
│   │       │   ├── repository_config.dart       маркер RepositoryConfig
│   │       │   └── page_metadata.dart           PageMetadata{required int total, int? nextPage} (offset; @freezed, без JSON)
│   │       ├── app_config/
│   │       │   └── app_config_repository.dart   контракт конфиг-репозитория (см. 14)
│   │       ├── item/
│   │       │   ├── item_repository.dart        контракт (abstract interface)
│   │       │   └── get_items_config.dart       GetItemsConfig (параметры запроса/пагинации)
│   │       └── log_repository.dart             LogRepository (интерфейс единого канала логов)
│   │
│   ├── data/                           ← ДАННЫЕ (импортирует только domain)
│   │   ├── entity/
│   │   │   ├── base/
│   │   │   │   ├── response_entity.dart         @freezed ResponseEntity<T> ({data,timestamp,trace_id,meta})
│   │   │   │   └── entity_converter.dart        ручной реестр EntityConverter<E>
│   │   │   └── item/
│   │   │       └── item_entity.dart             @freezed entity (только базовые типы) + .g.dart
│   │   ├── exception/
│   │   │   ├── dao_exception.dart               DaoException
│   │   │   ├── api_exception.dart               ApiException enum + .map → RepositoryException
│   │   │   ├── base_repository_helper.dart      mixin execute<T>() (ВСЕГДА логирует через LogRepository)
│   │   │   └── base_domain_exception_helper.dart
│   │   ├── local/
│   │   │   ├── app_database.dart                Sembast, env-scoped (Dev/Prod=IO, Test=memory)
│   │   │   └── item_dao.dart                    @lazySingleton DAO (onSnapshots, transactions)
│   │   ├── mapper/
│   │   │   ├── base_mapper.dart                 BaseMapper<E,M,...> (+ list-варианты)
│   │   │   └── item/item_mapper.dart            ItemMapper (entity ⇄ model)
│   │   ├── remote/
│   │   │   ├── api/
│   │   │   │   ├── base/base_api.dart
│   │   │   │   └── item/get_items_api.dart      GetItemsApi REST-клиент
│   │   │   └── request_builder/
│   │   │       └── item/get_items_api_request_builder.dart
│   │   ├── log/
│   │   │   └── log_repository_impl.dart         @LazySingleton(as: LogRepository) — единый канал логов
│   │   └── repository/
│   │       └── item/item_repository_impl.dart   @LazySingleton(as: ItemRepository)
│   │
│   ├── presentation/                   ← ПРЕЗЕНТАЦИЯ (импортирует только domain)
│   │   ├── app/
│   │   │   ├── app_root.dart                    AppRoot: корневой MaterialApp + навигация
│   │   │   └── bloc/                            app-level BLoC (тема, init)
│   │   │       └── app_root_bloc.dart           AppRootBloc + part event/state (@freezed)
│   │   ├── base/
│   │   │   └── base_bloc.dart                   BaseBloc<E,S> с executeLogic try/catch
│   │   ├── navigation/
│   │   │   └── app_router_helper.dart           PlatformAwarePageRoute
│   │   ├── pages/
│   │   │   ├── base/
│   │   │   │   └── base_state_page.dart         BaseStatePage<T>
│   │   │   └── item_list_page/                  рабочий пример страницы
│   │   │       ├── item_list_page.dart          StatefulWidget: routeName + route() + BlocProvider
│   │   │       ├── bloc/
│   │   │       │   ├── item_list_bloc.dart       part 'item_list_event.dart'; part 'item_list_state.dart';
│   │   │       │   ├── item_list_event.dart      part of bloc; @freezed sealed Event
│   │   │       │   └── item_list_state.dart      part of bloc; @freezed sealed State
│   │   │       └── widgets/                      виджеты, приватные для страницы
│   │   ├── helpers/                             UI-хелперы (AlertDialogHelper)
│   │   ├── widgets/                             кросс-страничные App*Widget (progress/error/empty/refresh)
│   │   └── extension/                           расширения презентации
│   │
│   ├── design/                         ← дизайн-токены + сгенерированные ассеты
│   │   ├── app_spacing_tokens.dart             responsive отступы (flutter_screenutil)
│   │   ├── app_text_style_tokens.dart          типографика
│   │   ├── app_images_tokens.dart
│   │   ├── app_overlay_style_tokens.dart       AppOverlayStyleTokens (system UI overlay)
│   │   └── gen/                                 ГЕНЕРИРУЕТСЯ (assets), не редактируется руками
│   │
│   └── resource/                       ← тема приложения
│       └── app_theme.dart                      AppTheme.light()/dark() + ThemeExtension<AppColors>
```

> Никакого `lib/ui/` нет. Весь UI живёт под `lib/presentation/`. Если где-то встречается старый UI-паттерн `lib/ui/` — игнорируйте его.

---

## 3. Правило зависимостей (одностороннее)

Изоляция слоёв обеспечивается дисциплиной импортов внутри единого пакета:

- **`lib/domain/`** импортирует **ничего** из `data/` или `presentation/`. Это чистый Dart + аннотации Freezed. Домен — это контракт.
- **`lib/data/`** импортирует `domain/` (чтобы реализовывать его интерфейсы и возвращать его модели). **Никогда** не импортирует `presentation/`.
- **`lib/presentation/`** импортирует `domain/` (потребляет интерфейсы и модели через DI). **Никогда** не импортирует `data/`. Презентация знает только абстрактный интерфейс репозитория; конкретный `*Impl` подставляется через DI.

```
   presentation/  ──depends on──▶  domain/  ◀──depends on──  data/
   (UI, BLoC)                      (контракт)                (реализация)
```

Именно это делает архитектуру переносимой: доменный слой — единственный контракт, и оба края подключаются к нему. Поскольку `domain` не импортирует `data`, **никакого цикла нет** — в отличие от трёхпакетного варианта, где `data` и `domain` ссылались бы друг на друга. DI связывает интерфейс с реализацией в рантайме (`@LazySingleton(as: ItemRepository)`), так что `presentation` и `domain` никогда не видят `*Impl` напрямую.

---

## 4. Сквозной поток данных — ЧТЕНИЕ

Рабочий пример: `ItemListPage`, показывающая список элементов. Первая **реальная** фича, которую предстоит собрать, — это **список чатов** (открытые общие пространства) поверх бэкенда NOX (например, через `GET /api/v1/chats/` — *пример, эндпоинт NOX TBD: бэкенд/протокол ещё не выбран, заменить на реальный контракт*); на нём отрабатывается ровно этот же путь чтения.

```
1. Page (ItemListPage)
   initState() → создаёт ItemListBloc ..add(const ItemListEvent.initialize())

2. BLoC (ItemListBloc._onInitialize)
   _itemRepository = getIt<ItemRepository>()
   → вызывает _itemRepository.getItems(config: GetItemsConfig.firstPage())
     (постраничный серверный список; для потока одного элемента — watchItem(id:))

3. Доменный контракт (ItemRepository)
   getItems возвращает Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> (постраничный список)
   watchItem возвращает Stream<RepositoryResult<ItemModel>> (поток одного элемента)

4. Data-импл (ItemRepositoryImpl с BaseRepositoryHelper)
   оборачивает работу в execute<T>(() async { ... })
   → постраничный серверный список network-only: обращается к GetItemsApi
     (для кэшируемых ресурсов был бы local-first путь через ItemDao)
   → execute<T>() ВСЕГДА логирует через LogRepository (единый канал)

5. API-клиент (GetItemsApi)
   HTTP GET → JSON → PaginatedResponse<ItemEntity>{data, pagination} через EntityConverter
   (для кэшируемых ресурсов DAO отдаёт ItemEntity из Sembast store / потока onSnapshots)

6. Mapper (ItemMapper extends BaseMapper<ItemEntity, ItemModel, ...>)
   toModel(entity:) → ItemModel
   (базовые типы → богатые: String→enum через .name, String(ISO-8601)→DateTime)

7. Repository impl
   возвращает RepositoryResult.success(data: (items, meta))
   (для кэшируемого ресурса watchItem отдавал бы через BehaviorSubject<RepositoryResult<ItemModel>>)

8. BLoC
   result.match(
     onData: ((items, meta)) => emit(ItemListState.initialized(items: items)),
     onError: (e)            => emit(ItemListState.error(exception: e)),
   )
   (никогда не разыменовывать data вслепую — только через match/success-ветку)

9. UI (BlocBuilder)
   state.map(
     initializing: (_) => AppProgressWidget(),
     initialized:  (s) => список,
     error:        (s) => AppErrorWidget(s.exception),
   )
```

Пути чтения для **пользовательских ресурсов с локальным кэшем** — local-first: DAO (Sembast) служит источником истины для UI; удалённые данные втекают в локальное хранилище через маппер, а затем реактивно вытекают обратно через `BehaviorSubject`.

> **Важная оговорка — список чатов читается иначе.** Список чатов — это **серверный, постранично-владеемый список**. Для таких списков и для одноразовых POST-ов действует явное исключение из local-first: они **network-only** (нет DAO, нет `BehaviorSubject`). BLoC хранит `PagingState` и подгружает страницы напрямую через репозиторий — см. §7 принципов и [07-pagination.md](07-pagination.md). Local-first путь (с DAO и subject) остаётся для пользовательских ресурсов, которые имеет смысл кэшировать целиком (например, профиль).

---

## 5. Сквозной поток данных — ЗАПИСЬ

Рабочий пример: создание или обновление элемента.

```
1. UI-действие
   onPressed → bloc.add(ItemListEvent.updateItem(item: ItemModel(...)))

2. BLoC (_onUpdateItem)
   emit(state.copyWith(isSaving: true))   // флаг "в процессе" через copyWith
   → _itemRepository.updateItem(item: ...)  (или createItem(item: ...))

3. Доменный контракт (ItemRepository.updateItem)
   возвращает Future<RepositoryResult<ItemModel>>; принимает полную ItemModel

4. Data-импл (ItemRepositoryImpl.updateItem)
   execute<ItemModel>(() async {
     final entity = _itemMapper.toEntity(model: item);
     await _itemDao.put(entity: entity);          // атомарный upsert
     return _itemMapper.toModel(entity: entity);  // round-trip без потерь
   })

5. DAO (ItemDao.put)
   db.transaction((txn) { read → transform → put }) — атомарная запись
   бросает DaoException при сбое; реактивные подписчики переэмитят через onSnapshots

6. (опционально) API-клиент (GetItemsApi)
   POST/PUT entity JSON → ApiException.map → доменный RepositoryException

7. Repository impl
   возвращает RepositoryResult.success(data: model)  (или .error(exception:))

8. BLoC
   result.match(
     onData: (_) => emit(state.copyWith(isSaving: false)),
     onError: (e) => emit(state.copyWith(isSaving: false /* + error */)),
   )
```

Мутации защищены `execute<T>()` (необработанные ошибки становятся `RepositoryException.unknown` и логируются единым каналом) и выполняются внутри DAO-транзакций, так что типизированные доменные исключения чисто доходят обратно до BLoC. Для network-only ресурсов (POST без локального кэша) шаги 5 и реактивные подписчики выпадают — репозиторий просто бьёт в API и возвращает `RepositoryResult`.

---

## 6. Конвенция папки страницы

Привязка идёт к **страницам приложения**, а не к абстрактным «фичам»: один экран = одна самодостаточная папка `<page>_page/` под `lib/presentation/pages/`. BLoC экрана владеет подпапкой `bloc/`; файлы события и состояния — это Dart `part` файла BLoC, поэтому sealed-иерархия остаётся приватной для трио, а сгенерированный `*.freezed.dart` лежит рядом. Приватные для страницы виджеты живут в `widgets/`.

```
lib/presentation/pages/<page>_page/
├── <page>_page.dart          # StatefulWidget: routeName + static Route route() + BlocProvider
├── bloc/
│   ├── <page>_bloc.dart       # part '<page>_event.dart'; part '<page>_state.dart'; part '<page>_bloc.freezed.dart';
│   ├── <page>_event.dart      # part of bloc; @freezed sealed Event-union
│   └── <page>_state.dart      # part of bloc; @freezed sealed State-union
└── widgets/                   # виджеты, приватные для этой страницы
```

Рабочий пример — `item_list_page/` (`item_list_page.dart` + `bloc/{item_list_bloc, item_list_event, item_list_state}.dart` + `widgets/`). Кросс-страничные переиспользуемые виджеты (кнопки, инпуты, progress/error/empty-состояния, refresh-индикатор) живут выше — под `lib/presentation/widgets/`, **а не** внутри `widgets/` конкретной страницы.

> **Для BLoC используется Freezed.** Правило этого блюпринта: события и состояния — это `@freezed sealed` unions (`*.freezed.dart`, **никогда** `*.g.dart` — на BLoC-типах нет `fromJson`), а не рукописные `sealed`-классы на `Equatable` с ручными `when()`/`copyWith()`. Canonical-имена подсостояний (`Initializing` / `Initialized` / `Error`) сохраняются и выражаются `const factory`-конструкторами Freezed. Производная/вычисляемая логика выносится в **extension-геттеры**, а не в тело `@freezed`. Тонкий `BaseBloc<E,S>` (в `lib/presentation/base/`) оборачивает обработчики в `executeLogic` с `try/catch`. Полностью — в [05-presentation-layer.md](05-presentation-layer.md).

---

## 7. Имена с первого взгляда

Нейтральный рабочий пример сквозь весь блюпринт — **Item**. Для пустых скелетов используются плейсхолдеры `<Feature>` / `<feature>` / `<Model>`. Первая реальная фича — **список чатов**.

| Артефакт | Шаблон | Пример |
|---|---|---|
| Доменная модель | `*Model` | `ItemModel` |
| Entity | `*Entity` | `ItemEntity` |
| Контракт репозитория | `*Repository` | `ItemRepository` |
| Реализация репозитория | `*RepositoryImpl` | `ItemRepositoryImpl` |
| Конфиг запроса | `Get*Config` | `GetItemsConfig` |
| Маппер | `*Mapper` | `ItemMapper` |
| DAO | `*Dao` | `ItemDao` |
| API-клиент | `Get*Api` / `*Api` | `GetItemsApi` |
| Страница | `*Page` | `ItemListPage` |
| Трио BLoC | `*_bloc.dart` / `*_event.dart` / `*_state.dart` | `item_list_bloc.dart` |
| BLoC-классы | `*Bloc` / `*Event` / `*State` | `ItemListBloc` / `ItemListEvent` / `ItemListState` |
| Кросс-фичевые виджеты | `App*Widget` | `AppProgressWidget` |
| Дизайн-токены | `App*Tokens` | `AppSpacingTokens` |

Файлы — `snake_case.dart`; классы/enum — `PascalCase`; члены — `camelCase`. Используются полные `package:`-импорты (без относительных `../`), кроме директив `part`. Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и **никогда** не редактируются руками. Полные правила импортов и именования — в [08-conventions-and-constitution.md](08-conventions-and-constitution.md).

---

## 8. Управляющие принципы (кратко)

Полная «конституция» — **9 принципов конституции + 10 золотых правил** (см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md)); каждый PR проверяется против неё. Решения по Freezed-BLoC и пагинации не образуют новых номеров — они свёрнуты внутрь существующих принципов/правил. Ниже — не нумерованная конституция, а краткая выжимка управляющих идей, к которым привязан этот документ:

- **Изоляция слоёв Clean Architecture** — одностороннее правило зависимостей из §3 (`presentation → domain ← data`, `domain` не импортирует ничего).
- **Однопакетная компоновка** — один `pubspec.yaml`, один `build_runner`, один ярус DI (`configureDependencies(env)` + единственный `@InjectableInit` → один сгенерированный `configure_dependencies.config.dart`).
- **Управление состоянием на BLoC = Freezed** — `@freezed sealed` State/Event unions; тонкий `BaseBloc<E,S>` с `executeLogic`; вычисляемая логика в extension-геттерах; `copyWith` для переходов. Никакого `setState`-driven бизнес-кода.
- **Codegen-first модели** — Freezed для всех моделей/entity; ручную сериализацию и `==`/`hashCode` не пишем. JSON (`*.g.dart`) — только на entity-слое; доменные модели и BLoC-типы — без JSON.
- **Композиция в data-пайплайне** — мапперы композируют дочерние мапперы через конструктор; `BaseMapper` даёт list-варианты; entity содержат только базовые типы (enum как `.name` String, DateTime как ISO-8601 String) — вся коэрция в маппере.
- **Дисциплина дизайн-токенов** — только токены (`AppSpacingTokens`, `AppTextStyleTokens`, responsive через `flutter_screenutil`); `Semantics` на интерактивных виджетах; единый `feature_flags.dart`.
- **Наблюдаемость и обработка ошибок** — единый канал `LogRepository` (обязательный, никакого raw `print`); типизированные `DaoException`/`ApiException` мапятся в доменный `RepositoryException`; `BaseRepositoryHelper.execute<T>()` всегда логирует.
- **Реактивные репозитории + carve-out** — для кэшируемых пользовательских ресурсов: `BehaviorSubject` + реактивный Sembast DAO (`onSnapshots`, transactions); env-scoped `AppDatabase` (Dev/Prod=IO, Test=memory) через `@LazySingleton(as: AppDatabase, env: [...])`; репозиторий подписывается на поток DAO один раз. **Carve-out:** постранично-владеемые серверные списки (список чатов) и одноразовые POST — **network-only**, без DAO и subject (см. [07-pagination.md](07-pagination.md)).
- **`RepositoryResult<T>` повсюду** — `@freezed` с данными-XOR-исключением (`.success(data:)` / `.error(exception:)`); поверхностный `match<R>(onData, onError)`. Никогда не разыменовывать `data` вслепую.
- **Тематизация — light + dark** — `ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `context.appColors`; `themeMode` приходит из `AppRootBloc`; конкретная палитра и responsive-токены — из базового варианта (см. [06-theming.md](06-theming.md)).
- **Унифицированный envelope ответа** — паттерн: бэкенд возвращает единый конверт, на data-слое это `ResponseEntity<T>` + рукописный реестр `EntityConverter<E>`. Форма `{data, timestamp, trace_id, meta}` — *пример: бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт*.
- **Компиляционная изоляция флейворов** — `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг `prod → Environment.prod`, `stage → Environment.dev`. Никакого рантайм-ветвления по флейвору. Секреты через SOPS+age+mise; версии — CalVer + сдвинутая эпоха (`YY.M.D+EPOCH`). См. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md).

---

## Чеклист

После прочтения этого документа вы должны уметь подтвердить:

- [ ] Вы понимаете, что это **один пакет** `nox_app` с одним `pubspec.yaml` и одним `build_runner`, а слои (`presentation`, `domain`, `data`) — это **папки** в `lib/`, а не отдельные pub-пакеты.
- [ ] Вы можете сформулировать одностороннее правило зависимостей (`presentation → domain ← data`, `domain` не импортирует ничего) и понимаете, почему **цикла `domain ⇄ data` здесь нет** (в отличие от трёхпакетного варианта).
- [ ] Вы можете провести путь чтения (UI → BLoC → контракт → impl → DAO/API → mapper → `RepositoryResult` → Freezed-состояние) и записи (UI → BLoC → impl `execute<T>` → DAO-транзакция → результат).
- [ ] Вы знаете carve-out: пользовательские кэшируемые ресурсы идут local-first (DAO + `BehaviorSubject`), а **постраничные серверные списки (список чатов) и одноразовые POST — network-only**.
- [ ] Вы знаете ключевые принципы: `RepositoryResult` (success XOR error), entity на базовых типах vs богатые модели, codegen-never-edited, **Freezed-BLoC** (а не рукописный Equatable-sealed).
- [ ] Вы знаете, что нейтральный рабочий пример — **Item**, первая реальная фича — **список чатов**, а следующий документ к прочтению — [01-stack-and-tooling.md](01-stack-and-tooling.md).

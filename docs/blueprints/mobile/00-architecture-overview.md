# 00 — Обзор архитектуры

> **Назначение:** дать единую ментальную модель приложения — однопакетная Clean Architecture (presentation → domain ← data) с Freezed-BLoC, реактивными репозиториями и DI на injectable+get_it. Это карта, к которой привязаны все остальные документы блюпринта.
> **Когда читать:** в самом начале, до того как трогать любой файл, пакет или шаблон. Это входная точка набора `docs/blueprints/mobile/`.
> **Целевые платформы:** iOS, Android, Windows, Linux, macOS (web — вне scope). Desktop-floor зафиксирован (дефолты Flutter 3.44.1), single-window подтверждён, оболочка адаптивная (`NavigationRail` на десктопе); packaging/signing — FUTURE.
> **Связанные документы:** [01-stack-and-tooling.md](01-stack-and-tooling.md) (SDK, зависимости, FVM), [02-dependency-injection.md](02-dependency-injection.md) (injectable + get_it bootstrap), [03-domain-layer.md](03-domain-layer.md) (модели, `RepositoryResult`, контракты), [04-data-layer.md](04-data-layer.md) (entity, DAO, мапперы, импл, REST), [05-presentation-layer.md](05-presentation-layer.md) (Freezed-BLoC, страницы, виджеты), [06-theming.md](06-theming.md) (`AppColors`, `AppTheme`, токены), [07-pagination.md](07-pagination.md) (offset/cursor пагинация), [08-conventions-and-constitution.md](08-conventions-and-constitution.md) (архитектурный свод блюпринта и правила), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (флейворы, секреты, версии), [10-code-templates.md](10-code-templates.md) (copy-paste шаблоны), [11-scaffolding-plan.md](11-scaffolding-plan.md) (порядок сборки), [12-dev-commands.md](12-dev-commands.md) (dev-команды), [13-deep-links.md](13-deep-links.md) (deep/universal links), [14-networking-and-auth.md](14-networking-and-auth.md) (сеть/auth, connectivity + app-lifecycle), [15-push-notifications.md](15-push-notifications.md) (FCM), [16-file-upload.md](16-file-upload.md) (2-step upload вложения в чат), [17-analytics.md](17-analytics.md) (клиентская аналитика, вендоронезависимо).

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

> **Важно — это НЕ три пакета.** Ранние варианты этого блюпринта описывали монорепо из трёх pub-пакетов (`domain/`, `data/` как path-зависимости с двусторонним циклом `domain ⇄ data`). Тот подход здесь **отменён намеренно**. У нас один пакет, одни импорты `package:nox_app/...`, один генератор, один `configureDependencies(env)`. Любой путь вида `domain/lib/src/...` или `data/lib/src/...` из исходников переписывается в однопакетный `lib/domain/...` / `lib/data/...`. Никакого цикла `domain ⇄ data` нет — `domain` не импортирует ничего.

**Почему один пакет, а не три.** Три path-пакета давали изоляцию на уровне `pubspec`, но платили за это: тройным `pub get` + `build_runner`, трёхуровневой цепочкой DI и реальным циклом зависимостей `domain ⇄ data` (потому что DI-bootstrap домена дёргал data). В одном пакете изоляция слоёв обеспечивается **дисциплиной импортов** (см. §3) и линтером, а не границами пакетов — этого достаточно для кросс-платформенного приложения (iOS, Android, Windows, Linux, macOS), и это убирает всю оркестрационную сложность.

---

## 2. Раскладка `lib/` (ASCII-дерево)

```
nox_app/
├── pubspec.yaml                        ← ОДИН pubspec на весь проект
├── analysis_options.yaml               line length 140, исключения для генерации
├── .fvmrc                              Flutter 3.44.1, закреплён через FVM
├── lib/
│   ├── main.dart                       точка входа: runZonedGuarded → Future.wait([configureDependencies(env),
│   │                                   setPreferredOrientations(portraitUp)]) → getIt.allReady()
│   │                                   → getIt<AppConfigRepository>().initialize(flavorType:) → runApp(AppRoot)
│   │
│   ├── di/                             ← Dependency Injection (единый ярус)
│   │   ├── configure_dependencies.dart        @InjectableInit(initializerName: r'$initGetIt')
│   │   │                                       Future<void> configureDependencies(String env)
│   │   ├── configure_dependencies.config.dart ГЕНЕРИРУЕТСЯ ($initGetIt)
│   │   └── global_aliases.dart                getIt<T>() удобные геттеры (logRepository, itemRepository)
│   │
│   ├── general/                        ← кросс-слойные утилиты (без UI, без бизнес-логики)
│   │   ├── constants.dart                     Constants (regex, размеры, railBreakpoint=840dp)
│   │   ├── feature_flags.dart                 единый модуль фич-флагов
│   │   ├── text_constants.dart                строковые константы / тексты
│   │   ├── platform_utils.dart                PlatformUtils (геттеры iOS/Android/Windows/macOS/Linux)
│   │   └── formatters/                        ValueFormatter, DateFormatter
│   │
│   ├── domain/                         ← ДОМЕН (импортирует НИЧЕГО из data/presentation)
│   │   ├── exception/
│   │   │   ├── base_repository_exception.dart  abstract marker BaseRepositoryException
│   │   │   └── repository_exception.dart       enum RepositoryException implements BaseRepositoryException
│   │   ├── model/
│   │   │   ├── app_config/
│   │   │   │   ├── app_flavor_type.dart         enum AppFlavorType{prod,stage}
│   │   │   │   ├── app_flavor.dart              AppFlavor.getFlavor() (String.fromEnvironment('app.flavor'))
│   │   │   │   └── app_config.dart              AppConfig({required AppFlavorType flavor}) (plain class)
│   │   │   └── item/
│   │   │       ├── item_model.dart              @freezed доменная модель (БЕЗ JSON)
│   │   │       └── item_status.dart             enum ItemStatus
│   │   └── repository/
│   │       ├── base/
│   │       │   ├── base.dart                    barrel-экспорт base/*
│   │       │   ├── repository_result.dart       @freezed RepositoryResult<T> (success XOR error)
│   │       │   ├── repository_result_handling.dart  match<R>(onData, onError)
│   │       │   ├── repository_config.dart       маркер RepositoryConfig
│   │       │   └── page_metadata.dart           PageMetadata{required int total, int? nextPage} (1-based; @freezed, без JSON)
│   │       ├── app_config/
│   │       │   └── app_config_repository.dart   контракт конфиг-репозитория (см. 14)
│   │       ├── item/
│   │       │   ├── item_repository.dart         контракт (abstract interface)
│   │       │   └── get_items_config.dart        GetItemsConfig (параметры запроса/пагинации; defaultPage=1)
│   │       └── log_repository.dart              LogRepository (интерфейс единого канала логов)
│   │
│   ├── data/                           ← ДАННЫЕ (импортирует только domain)
│   │   ├── entity/
│   │   │   ├── base/
│   │   │   │   ├── response_entity.dart         @freezed ResponseEntity<T> ({data,timestamp,trace_id,meta} — пример/TBD)
│   │   │   │   └── entity_converter.dart        ручной реестр EntityConverter<E>
│   │   │   └── item/
│   │   │       ├── item_entity.dart             @freezed entity (только базовые типы) + .g.dart
│   │   │       └── items_entity.dart            @freezed ItemsEntity{items,page,page_size,total} + .g.dart
│   │   ├── exception/
│   │   │   └── base_repository_helper.dart      mixin execute<T>() (DioException→internal, прочее→unknown; ВСЕГДА логирует через LogRepository)
│   │   ├── local/
│   │   │   ├── app_database.dart                Sembast, env-scoped (Dev/Prod=IO, Test=memory)
│   │   │   └── item/item_dao.dart               @lazySingleton DAO (per-ID store, onSnapshots, transactions)
│   │   ├── mapper/
│   │   │   ├── base_mapper.dart                 BaseMapper<E,M,...> (+ list-варианты)
│   │   │   └── item/item_mapper.dart            ItemMapper (entity ⇄ model)
│   │   ├── remote/
│   │   │   ├── api_client.dart                  тонкая обёртка над Dio (base URL/auth/HMAC/security-headers/token source — пример/TBD: бэкенд не выбран)
│   │   │   └── api/
│   │   │       └── item/get_items_api.dart      GetItemsApi REST-клиент
│   │   └── repository/
│   │       ├── log_repository_impl.dart                 @LazySingleton(as: LogRepository) — единый канал логов
│   │       ├── app_config/app_config_repository_impl.dart @LazySingleton(as: AppConfigRepository)
│   │       └── item/item_repository_impl.dart           @LazySingleton(as: ItemRepository) — network-only (mapper + api)
│   │
│   ├── presentation/                   ← ПРЕЗЕНТАЦИЯ (импортирует только domain)
│   │   ├── app/
│   │   │   ├── app_root.dart                    AppRoot: корневой MaterialApp + навигация (роутинг пока inline)
│   │   │   ├── bloc/                            app-level BLoC (тема, init)
│   │   │   │   └── app_root_bloc.dart           AppRootBloc + part event/state (@freezed)
│   │   │   └── widgets/
│   │   │       └── app_shell.dart               адаптивная оболочка: width-driven NavigationBar↔NavigationRail
│   │   │                                        (Constants.railBreakpoint=840dp), center-docked + FAB,
│   │   │                                        IndexedStack-body, 2 destination (Chats/Settings), single-window, без профиля
│   │   ├── base/
│   │   │   └── base_bloc.dart                   BaseBloc<E,S> с executeLogic try/catch
│   │   ├── pages/
│   │   │   ├── base/
│   │   │   │   └── base_state_page.dart         BaseStatePage<T>
│   │   │   ├── placeholder/
│   │   │   │   ├── chats_placeholder_page.dart     заглушка вкладки Chats (пока без BLoC)
│   │   │   │   └── settings_placeholder_page.dart  заглушка вкладки Settings (пока без BLoC)
│   │   │   └── item_list_page/                  рабочий пример страницы
│   │   │       ├── item_list_page.dart          StatefulWidget: routeName + route() + BlocProvider
│   │   │       ├── bloc/
│   │   │       │   ├── item_list_bloc.dart       part 'item_list_event.dart'; part 'item_list_state.dart';
│   │   │       │   ├── item_list_event.dart      part of bloc; @freezed sealed Event
│   │   │       │   └── item_list_state.dart      part of bloc; @freezed sealed State
│   │   │       └── widgets/                      виджеты, приватные для страницы
│   │   ├── pagination/
│   │   │   └── paging_state_ext.dart            PagingStateExt.applyPage (infinite_scroll_pagination v5)
│   │   ├── helpers/                             UI-хелперы (AlertDialogHelper)
│   │   ├── widgets/                             кросс-страничные App*Widget (progress/error/empty/refresh)
│   │   └── extension/                           расширения презентации
│   │
│   ├── design/                         ← дизайн-токены + тема + сгенерированные ассеты
│   │   ├── app_spacing_tokens.dart             responsive отступы (flutter_screenutil)
│   │   ├── app_text_style_tokens.dart          типографика
│   │   ├── app_images_tokens.dart              AppImagesTokens (_base='assets/png') — рукописный канал
│   │   ├── app_overlay_style_tokens.dart       AppOverlayStyleTokens (system UI overlay)
│   │   ├── gen/assets.gen.dart                 flutter_gen → пути ассетов (генерится, gitignored)
│   │   └── theme/
│   │       ├── app_theme.dart                  AppTheme.light()/dark() — сборка ThemeData + регистрация расширения AppColors
│   │       ├── app_colors.dart                 ThemeExtension<AppColors> + Light/DarkAppColors (приватная палитра)
│   │       ├── nox_color_scheme.dart           ГЕНЕРИРУЕТСЯ из nox-handoff: const noxLightScheme/noxDarkScheme
│   │       ├── nox_text_theme.dart             ГЕНЕРИРУЕТСЯ из nox-handoff: noxTextTheme
│   │       ├── nox_tokens.dart                 ГЕНЕРИРУЕТСЯ из nox-handoff: числовые токены
│   │       └── nox_brand.dart                  ГЕНЕРИРУЕТСЯ из nox-handoff: бренд-константы
│   │
│   └── resource/                       ← зарезервированный слой (пока только .gitkeep)
```

> Никакого `lib/ui/` нет. Весь UI живёт под `lib/presentation/`. Если где-то в исходниках встречается старый UI-паттерн `lib/ui/` — игнорируйте его.
>
> **Маршрутизация.** Отдельной папки `lib/presentation/navigation/` в скелете пока нет — роутинг живёт inline в `app_root.dart` (`_navigatorKey`, `AppShell` как `home`). Конвенция `app_router_helper.dart` (`PlatformAwarePageRoute`) — целевой шаблон, который вводится с появлением первой навигируемой фичи (см. [05-presentation-layer.md](05-presentation-layer.md), [13-deep-links.md](13-deep-links.md)).
>
> **Слой `resource/`** объявлен (NOX-инвариант), но сейчас это **пустой зарезервированный плейсхолдер** (`.gitkeep`). Тема приложения живёт **не** здесь, а в `lib/design/theme/` (`app_theme.dart`); `resource/` ждёт первого реального потребителя.

---

## 3. Правило зависимостей (одностороннее)

Изоляция слоёв обеспечивается дисциплиной импортов внутри единого пакета:

- **`lib/domain/`** импортирует **ничего** из `data/` или `presentation/`. Это чистый Dart + аннотации Freezed. Домен — это контракт. Доменному слою **разрешено** импортировать `lib/general/` (платформо-нейтральные утилиты и константы — без UI и без бизнес-логики), но `data/` и `presentation/` — **никогда**.
- **`lib/data/`** импортирует `domain/` (чтобы реализовывать его интерфейсы и возвращать его модели). **Никогда** не импортирует `presentation/`.
- **`lib/presentation/`** импортирует `domain/` (потребляет интерфейсы и модели через DI). **Никогда** не импортирует `data/`. Презентация знает только абстрактный интерфейс репозитория; конкретный `*Impl` подставляется через DI.

```
   presentation/  ──depends on──▶  domain/  ◀──depends on──  data/
   (UI, BLoC)                      (контракт)                (реализация)
```

Именно это делает архитектуру переносимой: доменный слой — единственный контракт, и оба края подключаются к нему. Поскольку `domain` не импортирует `data`, **никакого цикла нет** — в отличие от трёхпакетного варианта из исходников, где `data` и `domain` ссылались друг на друга. DI связывает интерфейс с реализацией в рантайме (`@LazySingleton(as: ItemRepository)`), так что `presentation` и `domain` никогда не видят `*Impl` напрямую.

---

## 4. Сквозной поток данных — ЧТЕНИЕ

Рабочий пример: `ItemListPage`, показывающая список элементов. Первая **реальная** фича, которую предстоит собрать, — это **список чатов** (открытый общий список чатов: server-owned, network-only paginated) поверх бэкенда NOX (например, через `GET /api/v1/chats/` — *пример, эндпоинт NOX TBD: бэкенд/протокол ещё не выбран, заменить на реальный контракт*); на нём отрабатывается ровно этот же путь чтения.

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
   HTTP GET → JSON → ResponseEntity<ItemsEntity>{items, page, page_size, total} через EntityConverter
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
   при сбое бросает ошибку — `execute<T>()` маппит в `RepositoryException.unknown`; реактивные подписчики переэмитят через onSnapshots

6. (опционально) API-клиент (GetItemsApi)
   POST/PUT entity JSON → `DioException` → `RepositoryException.internal` (маппинг внутри `execute<T>()`)

7. Repository impl
   возвращает RepositoryResult.success(data: model)  (или .error(exception:))

8. BLoC
   result.match(
     onData: (_) => emit(state.copyWith(isSaving: false)),
     onError: (e) => emit(state.copyWith(isSaving: false /* + error */)),
   )
```

Мутации защищены `execute<T>()` (необработанные ошибки становятся `RepositoryException.unknown` и логируются единым каналом) и выполняются внутри DAO-транзакций, так что типизированные доменные исключения чисто доходят обратно до BLoC. Для network-only ресурсов (POST без локального кэша) шаги 5 и реактивные подписчики выпадают — репозиторий просто бьёт в API и возвращает `RepositoryResult`.

> **Важная оговорка — это целевой шаблон, а не текущий скелет.** Полный путь записи выше (`ItemListEvent.updateItem`, `ItemRepository.updateItem`/`createItem`, `ItemDao.upsert`/`saveData` в транзакции) — это **аспирационный** canonical-шаблон CRUD, который приезжает с первой кэшируемой фичей. В скелете Feature-001 его **нет**: `ItemRepository` экспонирует только `getItems(config:)` + `clean()` (network-only carve-out, без DAO и записи), `ItemListEvent` ограничен `{ initialize, loadItems }`, а методы записи DAO называются `upsert` / `saveData` (не `put`). Читайте §5 как ориентир будущего write-пути, а не как уже отгруженный API.

---

## 6. Конвенция папки страницы

Привязка идёт к **страницам приложения**, а не к абстрактным «фичам»: один экран = одна самодостаточная папка `<page>_page/` под `lib/presentation/pages/`. BLoC экрана владеет подпапкой `bloc/`; файлы события и состояния — это Dart `part` файла BLoC, поэтому sealed-иерархия остаётся приватной для трио, а сгенерированный `*.freezed.dart` лежит рядом. Приватные для страницы виджеты живут в `widgets/`.

Каждая навигируемая страница (`*Page` с `routeName`/`route()`) **обязательно** владеет собственным BLoC под `bloc/` — **даже если страница logic-less** (тогда минимальный BLoC: trio `Initializing`/`Initialized`/`Error` или value-BLoC а-ля `AppRootBloc`; см. [05-presentation-layer.md](05-presentation-layer.md) §3.4/§6.1 и [08-conventions-and-constitution.md](08-conventions-and-constitution.md) Принцип 5.1). Переиспользуемые виджеты (`widgets/`) BLoC **не требуют**.

> **Расхождение со скелетом (терпимо до первой реальной фичи).** В текущем скелете `AppShell` своего BLoC не имеет, а заглушки `chats_placeholder_page.dart` / `settings_placeholder_page.dart` — это stateless-страницы без `bloc/`. Это сознательные упрощения скелета: Принцип 5.1 в полную силу включается, когда заглушки заменяются реальными навигируемыми фичами (список чатов, настройки).

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

> **Использование Freezed для BLoC — намеренное переопределение.** В ранних вариантах блюпринта события и состояния были рукописными `sealed`-классами на `Equatable` с ручными `when()`/`copyWith()`. Здесь это **отменено намеренно**: события и состояния — это `@freezed sealed` unions (`*.freezed.dart`, **никогда** `*.g.dart` — на BLoC-типах нет `fromJson`). Canonical-имена подсостояний — **bare**: `Initializing` / `Initialized` / `Error` (так в коде: `const factory ItemListState.error({BaseRepositoryException? exception}) = Error;`, ветвление как `Initializing()` / `Initialized()` / `Error()`). Префиксные имена (`<Feature>Initializing`…) допустимы как вариант для избегания коллизий, но канон — bare. Производная/вычисляемая логика выносится в **extension-геттеры**, а не в тело `@freezed`. Тонкий `BaseBloc<E,S>` (в `lib/presentation/base/`) оборачивает обработчики в `executeLogic` с `try/catch`. Каждая навигируемая страница владеет собственным BLoC, даже logic-less (Принцип 5.1). Полностью — в [05-presentation-layer.md](05-presentation-layer.md).

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

Полный **архитектурный свод блюпринта** — **9 принципов + 10 золотых правил + Принцип 5.1** (см. [08-conventions-and-constitution.md](08-conventions-and-constitution.md)); каждый PR проверяется против него. Это внутренний свод набора `docs/blueprints/mobile/` — он не подменяет реальную конституцию проекта (`.specify/memory/constitution.md`, v1.1.0), а конкретизирует её архитектурный принцип. Решения по Freezed-BLoC и пагинации не образуют новых номеров — они свёрнуты внутрь существующих принципов/правил. Ниже — не нумерованный свод, а краткая выжимка управляющих идей, к которым привязан этот документ:

- **Изоляция слоёв Clean Architecture** — одностороннее правило зависимостей из §3 (`presentation → domain ← data`, `domain` не импортирует ничего).
- **Однопакетная компоновка** — один `pubspec.yaml`, один `build_runner`, один ярус DI (`configureDependencies(env)` + единственный `@InjectableInit` → один сгенерированный `configure_dependencies.config.dart`).
- **Управление состоянием на BLoC = Freezed** — `@freezed sealed` State/Event unions с **bare**-именами подсостояний (`Initializing`/`Initialized`/`Error`); тонкий `BaseBloc<E,S>` с `executeLogic`; вычисляемая логика в extension-геттерах; `copyWith` для переходов. Никакого `setState`-driven бизнес-кода. **Каждая навигируемая страница имеет свой BLoC (logic-less — минимальный trio или value-BLoC); переиспользуемые виджеты — без BLoC (Принцип 5.1).**
- **Codegen-first модели** — Freezed для всех моделей/entity; ручную сериализацию и `==`/`hashCode` не пишем. JSON (`*.g.dart`) — только на entity-слое; доменные модели и BLoC-типы — без JSON.
- **Композиция в data-пайплайне** — мапперы композируют дочерние мапперы через конструктор; `BaseMapper` даёт list-варианты; entity содержат только базовые типы (enum как `.name` String, DateTime как ISO-8601 String) — вся коэрция в маппере.
- **Дисциплина дизайн-токенов** — только токены (`AppSpacingTokens`, `AppTextStyleTokens`, responsive через `flutter_screenutil`); `Semantics` на интерактивных виджетах; единый `feature_flags.dart`.
- **Наблюдаемость и обработка ошибок** — единый канал `LogRepository` (обязательный, никакого raw `print`); типизированной иерархии исключений нет — необработанные ошибки мапятся в `RepositoryException` (`DioException → internal`, прочее → `unknown`) внутри `BaseRepositoryHelper.execute<T>()`, который всегда логирует.
- **Реактивные репозитории + carve-out** — для кэшируемых пользовательских ресурсов: `BehaviorSubject` + реактивный Sembast DAO (`onSnapshots`, transactions); env-scoped `AppDatabase` (Dev/Prod=IO, Test=memory) через `@LazySingleton(as: AppDatabase, env: [...])`; репозиторий подписывается на поток DAO один раз. **Carve-out:** постранично-владеемые серверные списки (список чатов) и одноразовые POST — **network-only**, без DAO и subject (см. [07-pagination.md](07-pagination.md)).
- **`RepositoryResult<T>` повсюду** — `@freezed` с данными-XOR-исключением (`.success(data:)` / `.error(exception:)`); поверхностный `match<R>(onData, onError)`. Никогда не разыменовывать `data` вслепую.
- **Тематизация — light + dark** — `ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `context.appColors`; `themeMode` приходит из `AppRootBloc`; `ColorScheme`/`TextTheme` берутся из сгенерированного хендоффа (`nox_color_scheme.dart`/`nox_text_theme.dart`, регенерируются из `docs/design/system/nox-handoff/`), а **не** через `ColorScheme.fromSeed` (см. [06-theming.md](06-theming.md)).
- **Кросс-платформенность и адаптивная оболочка** — пять целевых платформ (iOS, Android, Windows, Linux, macOS; web вне scope); single-window. `AppShell` — width-driven `NavigationBar`↔`NavigationRail` на `Constants.railBreakpoint=840dp`, center-docked `+` FAB, `IndexedStack`-body, 2 destination (Chats/Settings), без отдельного экрана профиля. Платформенные ветки — через `PlatformUtils` (`isIOS`/`isAndroid`/`isWindows`/`isMacOS`/`isLinux`); десктоп-специфика (push/deep-links/secure-storage) вводится no-op/disabled-заглушкой с первым десктоп-потребителем подсистемы, не раньше.
- **Унифицированный envelope ответа** — паттерн: бэкенд возвращает единый конверт, на data-слое это `ResponseEntity<T>` + рукописный реестр `EntityConverter<E>`. Форма `{data, timestamp, trace_id, meta}` — *пример: бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт*.
- **Компиляционная изоляция флейворов** — `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг `prod → Environment.prod`, `stage → Environment.dev`. Никакого рантайм-ветвления по флейвору. Секреты через SOPS+age+mise; версии — CalVer + сдвинутая эпоха (`YY.M.D+EPOCH`). См. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md).

---

## Чеклист

После прочтения этого документа вы должны уметь подтвердить:

- [ ] Вы понимаете, что это **один пакет** `nox_app` с одним `pubspec.yaml` и одним `build_runner`, а слои (`presentation`, `domain`, `data`, `di`, `general`, `design`, `resource`) — это **папки** в `lib/`, а не отдельные pub-пакеты.
- [ ] Вы можете сформулировать одностороннее правило зависимостей (`presentation → domain ← data`, `domain` не импортирует ничего, кроме `general/`) и понимаете, почему **цикла `domain ⇄ data` здесь нет** (в отличие от трёхпакетного варианта из исходников).
- [ ] Вы можете провести путь чтения (UI → BLoC → контракт → impl → DAO/API → mapper → `RepositoryResult` → Freezed-состояние) и записи (UI → BLoC → impl `execute<T>` → DAO-транзакция → результат), и знаете, что необработанные ошибки мапятся в `RepositoryException` (`DioException → internal`, прочее → `unknown`) — **типизированной иерархии исключений нет**.
- [ ] Вы знаете carve-out: пользовательские кэшируемые ресурсы идут local-first (DAO + `BehaviorSubject`), а **постраничные серверные списки (список чатов) и одноразовые POST — network-only**.
- [ ] Вы знаете ключевые принципы: `RepositoryResult` (success XOR error), entity на базовых типах vs богатые модели, codegen-never-edited, **Freezed-BLoC** с bare-именами подсостояний (а не рукописный Equatable-sealed), пять целевых платформ с адаптивной оболочкой (`NavigationBar`↔`NavigationRail` на 840dp).
- [ ] Вы знаете, что нейтральный рабочий пример — **Item**, первая реальная фича — **список чатов**, а следующий документ к прочтению — [01-stack-and-tooling.md](01-stack-and-tooling.md).

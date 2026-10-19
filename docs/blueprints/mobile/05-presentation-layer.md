# 05 — Слой представления (BLoC)

> **Назначение:** задать канонический скелет слоя представления (`lib/presentation/`) для приложения `nox_app`: Freezed-BLoC (sealed State/Event unions), тонкий `BaseBloc<E,S>`, `BaseStatePage<T>`, паттерн страницы, app-shell (`AppRoot` + `AppRootBloc` + адаптивный `AppShell`), каналы side-эффектов, дисциплину конкурентности и потребление `RepositoryResult<T>`.
> **Когда читать:** когда вы создаёте любой экран, BLoC или app-shell-виджет, либо проводите связку «page → BLoC → repository». Первая реальная фича — список чатов (личное пространство одного человека, ревизия 2026-09-10) — строится ровно по этому паттерну: пагинированный список поверх **cache-first** репозитория (`ChatRepositoryImpl` + `ChatDao` над Sembast, реактивный `watchChats()`), а не network-only carve-out — network-only остался только у верификационного `Item`-харнесса.
> **Связанные документы:** `00-architecture-overview.md` (карта слоёв), `02-dependency-injection.md` (`getIt`, `configureDependencies`), `03-domain-layer.md` (`RepositoryResult<T>`, контракты репозиториев), `04-data-layer.md` (откуда приходят данные), `06-theming.md` (`ThemeExtension<AppColors>`, `context.appColors`, токены spacing/typography), `07-pagination.md` (полный контракт `PagingState`-in-bloc, `PagingStateExt.applyPage`), `08-conventions-and-constitution.md` (нейминг, формат, конституция), `10-code-templates.md` (готовые шаблоны), `11-scaffolding-plan.md` (порядок создания файлов).

---

## 0. Что этот слой переопределяет (важно прочитать первым)

**Этот слой использует Freezed для State и Event BLoC.** Это сознательно **переопределяет** старое правило «no Freezed for state», которое фигурировало в ранних вариантах блюпринта (ручные `sealed ... extends Equatable` + рукописный `when()` в той же ручной иерархии). Здесь:

- State и Event — это `@freezed sealed class` unions с генерируемыми `when()` / `map()` / `maybeWhen()` / `maybeMap()`.
- Равенство — это **глубокое value-equality от Freezed** (не `Equatable` с ручным `props`).
- Переходы — через сгенерированный `copyWith`.
- Производная/вычисляемая логика живёт в **extension-геттерах на состоянии**, а не в теле `@freezed`.
- На типах BLoC **нет `fromJson`** — это чисто in-memory типы, никогда не сериализуются. Поэтому генерируется только `*.freezed.dart`, **никогда** `*.g.dart`.

Что сохранено из исходного подхода без изменений:

- **Канонические имена подсостояний** `Initializing` / `Initialized` / `Error` — теперь как Freezed `const factory`-конструкторы (`.initializing()` / `.initialized()` / `.error()`; классы-варианты по умолчанию короткие — `= Initializing` / `= Initialized` / `= Error`, см. §3.1).
- Ветвление тела страницы по подсостояниям `initializing` / `initialized` / `error` — в коде это Dart 3 `switch (state)`; Freezed-`when()` генерируется, но в `lib/` не вызывается (§5.3).
- `BaseStatePage<T>` (scaffoldKey, реактивный `useDrawer`/`closeDrawer` с отложенным `setState`, платформозависимый `buildAppBar()`).
- Паттерн страницы: `StatefulWidget` + `static Route<T> route()` (`MaterialPageRoute` + `RouteSettings(name: '/…')` — имя маршрута пишется прямо здесь, отдельной константы нет), BLoC в `initState` и `close()` в `dispose`, побочные эффекты — `BlocListener` по статусу в состоянии.
- App-shell: `AppRoot` (хостит `MaterialApp` + `GlobalKey<NavigatorState>`, тема из `AppRootBloc`) + `AppRootBloc` (одно конкретное состояние с `copyWith`, **не** trio).
- `RepositoryResult<T>` потребляется через `match()` / `hasData` — **никогда** `result.data!`.

Добавлено в этом подходе: `@freezed sealed` State/Event, тонкий `BaseBloc<E,S>` с `executeLogic`, логика в extension-геттерах, продвинутый toolkit конкурентности (epoch-guard + `debounce`/`debounceIf`).

Конвенция нейминга для unions: **`sealed`** для multi-variant unions (State, Event), **`abstract`** для single-variant value-объектов — например, `AppRootState` объявляется как `@freezed abstract class` с одним конструктором (одно состояние, не trio; `copyWith` генерируется Freezed), см. §6.1.

---

## 1. Раскладка и конвенции слоя

Слой представления живёт в `lib/presentation/`. Это единственный слой, импортирующий Flutter-виджеты для экранов, держащий BLoC'и и зависящий от `lib/domain/` — никогда напрямую от `lib/data/`. Репозитории и службы блок берёт через доменные интерфейсы: `getIt<ChatRepository>()`, `getIt<OutboxService>()`, `getIt<AttachmentPrefetchService>()` (интерфейсы — `lib/domain/service/`, реализации в `lib/data/` подставляет DI, см. `00-architecture-overview.md` §3). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив внутри trio).

Ниже — **целевая** раскладка слоя. Часть директорий пока отсутствует в скелете и заводится вместе с первым потребителем (помечено `# FUTURE` — тот же принцип «no-op/disabled stub вводится с первым потребителем подсистемы», что и для push / deep-links / secure-storage); фактический состав скелета — в сноске под деревом.

```
lib/
├── di/
│   └── configure_dependencies.dart          # getIt entry point (см. 02-dependency-injection.md)
├── design/                                   # ThemeExtension<AppColors> + токены (см. 06-theming.md)
│   ├── app_spacing_tokens.dart              # AppSpacingTokens.sN (spacing/typography scale)
│   └── theme/
│       └── app_colors.dart                  # context.appColors (ThemeExtension<AppColors>)
├── general/
│   ├── constants.dart                        # Constants.designSize, Constants.railBreakpoint=840
│   ├── l10n_extension.dart                   # context.l10n; строки — в lib/l10n/app_{en,uk}.arb
│   └── bloc_concurrency/                     # FUTURE: продвинутые transformer'ы (§5.8)
│       ├── debounce.dart                      #   debounce transformer (advanced)
│       └── debounce_if.dart                   #   debounceIf transformer (advanced)
└── presentation/
    ├── app/
    │   ├── app_root.dart                     # корневой MaterialApp + смена корневого маршрута по app-state
    │   ├── bloc/
    │   │   ├── app_root_bloc.dart
    │   │   ├── app_root_event.dart
    │   │   └── app_root_state.dart
    │   └── widgets/
    │       └── app_shell.dart                # скелетная оболочка Feature-001, не смонтирована (§6.5)
    ├── base/
    │   ├── base_bloc.dart                     # BaseBloc<E,S> с executeLogic
    │   └── bloc_transformers.dart             # debounceRestartable (поиск, проверки имени)
    ├── helpers/                              # app_feedback_helper.dart (showAppSnackBar/showAppBanner, §8),
    │                                         # adaptive_lightbox.dart, connection_problem_text.dart
    ├── extension/                            # FUTURE: расширения презентации
    ├── pagination/
    │   └── paging_state_ext.dart            # PagingStateExt.applyPage (§5.5, 07-pagination.md)
    ├── pages/
    │   ├── base/
    │   │   └── base_state_page.dart          # абстрактный State<T> base
    │   ├── placeholder/                      # route_placeholder_page.dart, settings_placeholder_page.dart
    │   ├── <page>_page/                      # продуктовые страницы (chats_list, chat_thread, connect, …)
    │   └── item_list_page/                   # Item-харнесс верификации (mock-данные, FR-013)
    │       ├── item_list_page.dart
    │       └── bloc/
    │           ├── item_list_bloc.dart        # @freezed part-host, handlers, transformers
    │           ├── item_list_event.dart       # @freezed sealed Event union (part of)
    │           └── item_list_state.dart       # @freezed sealed State union + extensions (part of)
    └── widgets/                              # UI kit: App*Widget по группам — state/ primitives/ chat/ media/
                                              # onboarding/ settings/ connection/ qr/ shell/
```

> **Что есть в коде.** В `lib/presentation/` нет только `extension/`, а в `lib/general/` — `bloc_concurrency/`: это целевые места, заводимые с первым потребителем; единственный собственный transformer проекта — `debounceRestartable` в `base/bloc_transformers.dart`. Живая оболочка — `TabBarShell` (`widgets/shell/tab_bar_shell_widget.dart`), скелетный `AppShell` не смонтирован. Токены spacing живут в `lib/design/app_spacing_tokens.dart`, `app_colors.dart` — в `lib/design/theme/` (см. `06-theming.md`).

Нейминг (полная таблица — в `08-conventions-and-constitution.md`):

| Артефакт              | Паттерн                                                          | Пример                                    |
|-----------------------|-----------------------------------------------------------------|-------------------------------------------|
| Папка страницы        | `lib/presentation/pages/<page>_page/`                           | `lib/presentation/pages/item_list_page/`  |
| Виджет страницы       | `<Page>Page`                                                    | `ItemListPage`                            |
| State страницы        | `_<Page>PageState extends BaseStatePage<T>`                     | `_ItemListPageState`                      |
| Папка BLoC            | `lib/presentation/pages/<page>_page/bloc/`                      | `lib/presentation/pages/item_list_page/bloc/` |
| BLoC                  | `<Page>Bloc extends BaseBloc<Event, State>`                     | `ItemListBloc`                            |
| State union           | `<Page>State` (`@freezed sealed`)                               | `ItemListState`                           |
| Event union           | `<Page>Event` (`@freezed sealed`)                               | `ItemListEvent`                           |
| Файлы BLoC trio       | `<page>_bloc.dart`, `<page>_event.dart`, `<page>_state.dart`    | `item_list_bloc.dart`                     |
| Общие виджеты         | `App*Widget`                                                    | `AppProgressWidget`                       |

**Ключевые правила слоя**

- Event и State — `@freezed sealed class` unions, **никогда** `Equatable`, **никогда** `fromJson`.
- State реализует подсостояния `Initializing` / `Initialized` / `Error` как `const factory`-конструкторы; вычисляемые значения — в `extension`-геттерах.
- BLoC получают репозитории и службы через `getIt<XxxRepository>()` / `getIt<XxxService>()` (доменные интерфейсы); `StreamSubscription` хранятся в полях и отменяются в `close()`.
- Побочный эффект (навигация, снэкбар, диалог) — статус в состоянии блока, страница ловит его `BlocListener` (`BlocConsumer`) с `listenWhen` (§5.6); поиск и проверка имени — трансформер `debounceRestartable()` (§5.8).
- Все строки для пользователя — из локализации; ни одной голой строки в виджетах. Канон — ARB-локализация (`lib/l10n/app_en.arb` + `app_uk.arb`, EN+UK, одинаковые наборы ключей, доступ через `context.l10n`). В снипетах ниже `TextConstants.<key>` — плейсхолдер блюпринта для ключа ARB: файла `text_constants.dart` в коде нет, в виджете это `context.l10n.<key>`, а BLoC отдаёт наружу исключение или enum, и в строку их переводит виджет.
- Цвета/отступы/типографика — только через токены (см. `06-theming.md`): цвет — из `Theme.of(context).colorScheme`, `NoxBrand`, `NoxScrims`, `NoxOpacity`; `context.appColors` фичи не вызывают. Ни одного голого `Color` / `EdgeInsets` / `TextStyle` в коде фич.

> Десктопная multi-window-маршрутизация (`desktop_multi_window`, `WindowsConfig`, `MultiWindowHelper`) намеренно опущена — приложение использует только single-window `Navigator`. Это подтверждено и для десктопных таргетов (Windows, Linux, macOS): single-window `Navigator` — единый канон на всех пяти платформах, `desktop_multi_window` не используется. `window_manager` (минимальный размер окна, кастомный title bar) — опциональный FUTURE, **не** входит в скелет. Сама оболочка size-driven (`AppShell`, §6.5), поэтому корректна при любом размере окна — отдельной десктопной маршрутизации не требуется.

---

## 2. `BaseBloc<E, S>` — тонкая основа

Все BLoC фич расширяют тонкую базу с единственным `executeLogic` try/catch-обёртчиком (путь импорта адаптирован под single-package):

**Файл:** `lib/presentation/base/base_bloc.dart`

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

Два момента, которые нужно усвоить:

- Первый аргумент `onError` — это **предформатированная строка** `'$e, $s'` (исключение **плюс** стек-трейс, склеенные). Сырое исключение и стек-трейс также передаются отдельно.
- `onError` опционален. Если его не передать — брошенное исключение будет **поймано и тихо проглочено** (никакого изменения состояния, никакого rethrow). Это сознательная асимметрия: для большинства handler'ов мы передаём `onError` и явно эмитим `ItemListState.error(...)` или показываем snackbar; для редких «фоновых» загрузок (где падение одной страницы не должно сносить весь экран) — `onError` опускаем. Решайте осознанно.

> Замечание для нашего проекта: даже когда `onError` опущен, **финальное логирование уже произошло** на уровне репозитория — `BaseRepositoryHelper.execute<T>()` всегда пишет через обязательный `LogRepository` (см. `04-data-layer.md`). BLoC-слой не использует сырой `print`. Ошибки самих BLoC-handler'ов оборачиваются `BaseBloc.executeLogic` — отдельного BLoC-observer'а в проекте **нет**.

---

## 3. BLoC-trio на Freezed — `Item` как worked example

Каждая страница имеет ровно три файла под `bloc/`:

- `item_list_bloc.dart` — `BaseBloc`, с `part`-директивами на два других файла.
- `item_list_event.dart` — `@freezed sealed` Event union (`part of` bloc).
- `item_list_state.dart` — `@freezed sealed` State union + extension-геттеры (`part of` bloc).

> **Канонические имена вариантов — короткие** (`Initializing` / `Initialized` / `Error`), как в шипнутом коде (`= Initializing` / `= Initialized` / `= Error`, extension `ItemListStateExt`). `part of` / `part` изолируют короткие имена внутри библиотеки bloc, поэтому они безопасно переиспользуются между страницами без коллизий; тесты ассертят варианты через `switch`/`isA<Initialized>()` в той же библиотеке либо через фабрики (`ItemListState.initialized(...)`). Имена вариантов **Event** (`Initialize`, `LoadItems`) — тоже короткие.
>
> **Допустимый вариант (избежание коллизий):** если вариант State нужен **за пределами** библиотеки bloc (cross-library `isA<...>()` в тестах) или мешает совпадение голого `Error` с `dart:core.Error`, redirect-имена можно префиксовать именем страницы (`= ItemListInitializing` / `= ItemListInitialized` / `= ItemListError`, extension `ItemListInitializedExt`). Это эквивалентная по семантике альтернатива; примеры ниже даны на коротких именах в соответствии с кодом скелета. Выбирайте один стиль на проект и держитесь его.

### 3.1 Event — `@freezed sealed` union

**Файл:** `lib/presentation/pages/item_list_page/bloc/item_list_event.dart`

```dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListEvent with _$ItemListEvent {
  /// Один раз из initState через `..add(const ItemListEvent.initialize())`.
  const factory ItemListEvent.initialize() = Initialize;

  /// Загрузить страницу: reset=true — первая страница / сброс (поиск и
  /// pull-to-refresh), false — load-more.
  const factory ItemListEvent.loadItems({@Default(false) bool reset}) = LoadItems;

  /// Изменилась строка поиска (трансформер `debounceRestartable()` на регистрации handler'а).
  const factory ItemListEvent.searchChanged(String query) = SearchChanged;

  /// Страница показала снэкбар о сбое догрузки — статус-эффект гасится.
  const factory ItemListEvent.loadErrorShown() = LoadErrorShown;
}
```

> На Event union **нет** `fromJson`; `@Default` у полей события допустим (`reset` по умолчанию — догрузка). Тап по элементу событием блока не становится: переход, которому блоку нечего решать, страница делает сама (§5.1).

### 3.2 State — `@freezed sealed` union + extension-геттеры

Подсостояния — это `const factory`-конструкторы `Initializing` / `Initialized` / `Error`. Вся производная логика (`isEmpty`, `isSearching` и т.п.) — в `extension`-геттере на конкретном варианте, **не** в теле `@freezed`.

**Файл:** `lib/presentation/pages/item_list_page/bloc/item_list_state.dart`

```dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListState with _$ItemListState {
  /// Загрузка / экран ещё не готов к показу.
  const factory ItemListState.initializing() = Initializing;

  /// Данные загружены и готовы к взаимодействию.
  const factory ItemListState.initialized({
    @Default(<ItemModel>[]) List<ItemModel> items,
    required PagingState<String, ItemModel> pagingState,
    @Default(GetItemsConfig.defaultPage) int nextPage,
    @Default(false) bool isLastPage,
    @Default(false) bool loadingInProgress,
    @Default('') String query,

    /// Статус-эффект: догрузка упала, пока элементы на экране. Страница
    /// показывает снэкбар из BlocListener и отвечает `loadErrorShown()`.
    BaseRepositoryException? loadError,
  }) = Initialized;

  /// Что-то упало при init или операции.
  const factory ItemListState.error({
    BaseRepositoryException? exception,
  }) = Error;
}

/// Производные значения — в extension, не в теле @freezed.
extension InitializedExt on Initialized {
  bool get isEmpty => items.isEmpty && !loadingInProgress;

  bool get isSearching => query.trim().isNotEmpty;
}
```

> Это **полный (aspirational) worked-example** State реальной фичи (с `query`/`loadError`); шипнутый Item-харнесс — лёгкое подмножество с extension `ItemListStateExt` (геттеры `pagedItems`/`hasMore`) и без поиска и статуса-эффекта. Сверка скелет ↔ полный паттерн — в §3.5.
>
> **Поля «тотал» в стейте нет** — и не должно появляться: `PageMetadata` (`lib/domain/repository/base/page_metadata.dart`) — это ровно `{required bool hasMore, int? nextPage}`, ответы контракта v0 несут `has_more` и никогда не несут total (см. §5.5).

Ключевые отличия от исходного подхода, которые нужно держать в голове:

- **`copyWith` сгенерирован Freezed** — рукописный `copyWith()` на каждом варианте больше не нужен.
- **`when()` сгенерирован Freezed** — прежний рукописный exhaustive-matcher удалён.
- **Равенство — глубокое value-equality от Freezed** — `props`-список из `Equatable` больше не пишется. Именно это глубокое равенство разблокирует гранулярные ребилды (§5.4).
- **`PagingState<String, ItemModel>`** — ключ `K` у нас `String` = id элемента (one-item-per-page: ключи — это id элементов; координату следующей порции держит state, а не `K`: страничный путь — `PageMetadata.nextPage` (`int`), seq-курсорный путь треда — `oldestLoadedSeq` (`int?`)). См. §5.5 и `07-pagination.md`.

> **Очистка nullable-поля через Freezed `copyWith`.** Сгенерированный `copyWith({Type? field})` не различает «не передано» и «передано `null`». Для полей, которые надо явно сбрасывать в `null`, в Freezed используйте `copyWith(field: null)` напрямую при опущенном объекте — Freezed-`copyWith` корректно ставит `null`, потому что генерирует sentinel-логику. Если поле обязательно nullable и должно очищаться вместе с другими, эмитьте новый вариант через фабрику `ItemListState.initialized(...)`. (Прежний хак `clearXxx`-флага на Freezed не нужен.)

### 3.3 BLoC — handlers, статус-эффект, stale-guard

BLoC:

- Вызывает `super(const ItemListState.initializing())` и регистрирует один `on<Event>(_handler)` на событие в конструкторе.
- Резолвит репозитории и службы через `getIt<XxxRepository>()` / `getIt<XxxService>()`.
- Поиск — `on<SearchChanged>(…, transformer: debounceRestartable())` из `lib/presentation/base/bloc_transformers.dart`: 300 мс тишины, затем последнее событие, а обработчик предыдущего отменяется (§5.8).
- После каждого `await` **перечитывает `this.state`** и выходит, если запрос устарел (stale-guard).
- Побочный эффект — статус в состоянии (`loadError`): страница ловит его `BlocListener` и гасит событием `loadErrorShown()` (см. §5.6). Стримов-эффектов у блока нет.
- Строк не производит: отдаёт исключение, в слова его переводит страница (`context.l10n`).
- Потребляет `RepositoryResult<T>` через `match()` / `hasData` — **никогда** `result.data!`.

**Файл:** `lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart`

```dart
import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

part 'item_list_event.dart';
part 'item_list_state.dart';
part 'item_list_bloc.freezed.dart';

class ItemListBloc extends BaseBloc<ItemListEvent, ItemListState> {
  ItemListBloc() : super(const ItemListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadItems>(_onLoadItems, transformer: sequential());
    on<SearchChanged>(_onSearchChanged, transformer: debounceRestartable());
    on<LoadErrorShown>(_onLoadErrorShown);
  }

  final _itemRepository = getIt<ItemRepository>();

  FutureOr<void> _onInitialize(Initialize event, Emitter<ItemListState> emit) async {
    emit(ItemListState.initialized(pagingState: PagingState<String, ItemModel>()));
    add(const ItemListEvent.loadItems(reset: true));
  }

  FutureOr<void> _onLoadItems(LoadItems event, Emitter<ItemListState> emit) async {
    final state = this.state;
    if (state is! Initialized || state.loadingInProgress) return;

    emit(state.copyWith(loadingInProgress: true));

    final query = state.query;
    final isFirstPage = event.reset;
    final config = isFirstPage
        ? GetItemsConfig.firstPage(search: query.isEmpty ? null : query)
        : GetItemsConfig.nextPage(page: state.nextPage, search: query.isEmpty ? null : query);

    final result = await _itemRepository.getItems(config: config);

    // stale-guard: state мог измениться за время await.
    final updated = this.state;
    if (updated is! Initialized || updated.query != query) return;

    if (result.hasData) {
      final (incoming, meta) = result.data!;
      final existingList = isFirstPage ? <ItemModel>[] : updated.items;
      final r = updated.pagingState.applyPage(
        existingList: existingList,
        response: (incoming, meta),
        keyExtractor: (e) => e.id,
      );
      emit(updated.copyWith(
        items: r.updatedList,
        pagingState: r.pagingState,
        nextPage: r.nextPage ?? updated.nextPage,
        isLastPage: !meta.hasMore,
        loadingInProgress: false,
      ));
    } else if (isFirstPage && updated.items.isEmpty) {
      emit(ItemListState.error(exception: result.exception));
    } else {
      // Не первая страница: показанное остаётся, а статус-эффект просит страницу
      // сказать об ошибке снэкбаром.
      emit(updated.copyWith(
        pagingState: updated.pagingState.copyWith(error: result.exception),
        loadingInProgress: false,
        loadError: result.exception,
      ));
    }
  }

  FutureOr<void> _onSearchChanged(SearchChanged event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is! Initialized) return;
    final query = event.query.trim();
    if (state.query == query) return; // (поиск — пример полной фичи, см. §3.5)
    // Загрузка прежнего запроса, если она идёт, кончится на stale-guard'е.
    emit(state.copyWith(
      items: const [],
      pagingState: PagingState<String, ItemModel>(),
      loadingInProgress: false,
      query: query,
    ));
    add(const ItemListEvent.loadItems(reset: true));
  }

  void _onLoadErrorShown(LoadErrorShown event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is Initialized) emit(state.copyWith(loadError: null));
  }
}
```

Заметки по реализации:

- `result.data!` здесь допустим **только** под защитой `if (result.hasData)` — это не нарушение правила «никогда `result.data!`», а распаковка record-кортежа `(List<ItemModel>, PageMetadata)` после явной проверки. Альтернативный, более чистый способ — `result.match(...)` (см. §5.7).
- `PagingStateExt.applyPage` — переиспользуемое расширение из `07-pagination.md`; не реализуйте склейку страниц вручную в каждом BLoC.
- **Pull-to-refresh — тот же `loadItems(reset: true)`.** Отдельного события и `Completer` в нём нет: страница ждёт ответа блока на своём стриме — первого состояния `Error` или `Initialized` с `loadingInProgress == false` (§5.1, `07-pagination.md`).
- Блок строк не производит (у него нет `BuildContext`, а значит и `context.l10n`): в `loadError` он кладёт исключение, а в слова его переводит слушатель на странице (`_describe`, §5.1) — сырой текст исключения не показывается никогда (правило канала snackbar'ов, §8). `RepositoryException` — enum из 12 значений (к базовым добавлены wire-коды контракта v0 §2.1: `invalidRequest`, `nameTaken`, `payloadTooLarge`, `attachmentGone`, `rateLimited`, `unsupportedSchema`; маппинг кода — `RepositoryException.fromWireCode`), поэтому `switch` перевода обязан оставаться исчерпывающим, иначе он не скомпилируется.

### 3.4 Пустой скелет (`<Page>`)

Шаблон без worked-example-полей — для копипасты при заведении новой страницы:

```dart
part of '<page>_bloc.dart';

@freezed
sealed class <Page>State with _$<Page>State {
  const factory <Page>State.initializing() = <Page>Initializing;
  const factory <Page>State.initialized() = <Page>Initialized;
  const factory <Page>State.error({BaseRepositoryException? exception}) = <Page>Error;
}
```

```dart
part of '<page>_bloc.dart';

@freezed
sealed class <Page>Event with _$<Page>Event {
  const factory <Page>Event.initialize() = Initialize;
}
```

```dart
class <Page>Bloc extends BaseBloc<<Page>Event, <Page>State> {
  <Page>Bloc() : super(const <Page>State.initializing()) {
    on<Initialize>(_onInitialize);
  }

  FutureOr<void> _onInitialize(Initialize event, Emitter<<Page>State> emit) async {
    // загрузка + emit(<Page>Initialized(...)) | emit(<Page>Error(...))
  }
}
```

> **Этот пустой trio — ОБЯЗАТЕЛЬНЫЙ минимум для logic-less навигируемой страницы, а не опция** (Принцип 5.1, [08](08-conventions-and-constitution.md)). Страница без бизнес-логики берёт именно его (или одновариантный value-BLoC §6.1), но **не остаётся вовсе без BLoC**. Переиспользуемые виджеты (ненавигируемые компоненты) BLoC не требуют. (Узкий фазовый carve-out для чисто презентационных UI-first экранов на заглушках, до подключения репозитория — см. исключение в §5.)

### 3.5 Что реализовано в скелете vs полный паттерн

Worked-example выше (§3.1–§3.3) — это **полный (aspirational) канон**: он учит поиску, pull-to-refresh, статусу-эффекту и конкурентности, которые понадобятся реальным фичам (так устроен список чатов). Шипнутый в Feature-001 `Item`-харнесс — сознательно **лёгкое подмножество** (verification-only, FR-013; см. [11-scaffolding-plan.md](11-scaffolding-plan.md)). Отличия скелета от полного паттерна:

- **Event** (`item_list_event.dart`) — только `initialize()` + `loadItems({@Default(false) bool reset})`. Нет `searchChanged` / `loadErrorShown`.
- **State** (`item_list_state.dart`) — поля `pagingState` (`required`, первым), `items`, `nextPage` (`@Default(GetItemsConfig.defaultPage)`, **1-based**), `isLastPage`, `loadingInProgress`. Нет `query` / `loadError`, нет и «тотала». Extension — `ItemListStateExt on ItemListState` с геттерами `pagedItems` / `hasMore` (а не `InitializedExt.isEmpty`/`isSearching` из полного примера).
- **BLoC** (`item_list_bloc.dart`) — `on<LoadItems>(_onLoadItems, transformer: sequential())`; тело завёрнуто в `executeLogic(onError:)`, ветвление через `result.match<void>(onData:, onError:)`. Нет поиска (`debounceRestartable()`) и статуса-эффекта.
- **`ItemModel`** (`domain/model/item/item_model.dart`) — поля `id`, `name`, `required String? description`, `required ItemStatus status`, `required DateTime createdAt`; extension-геттеры `isArchived` + `displayName` (см. `03-domain-layer.md`).
- **Страница-харнесс как tab-body.** Шипнутый `ItemListPage` рендерится телом вкладки внутри `AppShell` (без собственного `Scaffold`), поэтому `_ItemListPageState extends State<ItemListPage>`, а **не** `BaseStatePage<ItemListPage>`. `BaseStatePage<T>` (§4) обязателен для **навигируемых** страниц, владеющих собственным `Scaffold` (со `static route()`) — именно такую каноническую форму показывает worked-example §5. Placeholder-страница (`SettingsPlaceholderPage`) — `StatelessWidget` по той же причине (тело вкладки без Scaffold).

Полный паттерн не «понижается» под харнесс — он остаётся целевым стандартом блюпринта; харнесс лишь доказывает, что вертикаль `page → BLoC → repository` компилируется end-to-end на mock-данных.

---

## 4. `BaseStatePage<T>` — базовый `State` страницы

Абстрактный `State` для каждой страницы. Даёт `scaffoldKey`, реактивное drawer-состояние и платформозависимую фабрику AppBar (путь импорта токенов адаптирован под `06-theming.md`).

**Файл:** `lib/presentation/pages/base/base_state_page.dart`

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

abstract class BaseStatePage<T extends StatefulWidget> extends State<T> {
  /// Глобальный ключ для доступа к Scaffold (drawers, snackbars, dialogs).
  final scaffoldKey = GlobalKey<ScaffoldState>();

  bool _useDrawerValue = false;

  bool get useDrawer => _useDrawerValue;

  /// Реактивный тоггл drawer'а. Откладывает setState в post-frame callback,
  /// поэтому безопасно вызывать во время build.
  set useDrawer(bool value) {
    if (value != _useDrawerValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _useDrawerValue = value;
        });
      });
    }
  }

  /// Программно закрыть drawer (no-op, если drawer не используется).
  void closeDrawer() {
    if (useDrawer) {
      scaffoldKey.currentState?.closeDrawer();
    }
  }

  /// Платформозависимая фабрика AppBar. Переопределяйте на странице;
  /// верните null, если AppBar не нужен.
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

Что это даёт каждой странице:

- `scaffoldKey` — передавайте в `Scaffold(key: scaffoldKey, ...)`.
- `useDrawer` / `closeDrawer()` — реактивное управление drawer'ом с безопасным отложенным `setState`.
- `buildAppBar()` — платформозависимый AppBar; переопределяйте под кастомные title-bar'ы или возвращайте `null`.

---

## 5. Паттерн страницы — `ItemListPage`

Каждая страница — `StatefulWidget` с:

- `static Route<T> route(...)` — фабрика, возвращающая `MaterialPageRoute<T>` с `RouteSettings(name: '/…')`: имя маршрута пишется прямо здесь, константы `routeName` и реестра маршрутов нет. Вызывающий пушит тир-офф: `Navigator.of(context).push(ItemDetailsPage.route(itemId: id))`.
- `State`, расширяющий `BaseStatePage<T>` и владеющий `late final` BLoC.
- BLoC создаётся в `initState()` с `..add(const ItemListEvent.initialize())`, закрывается в `dispose()`.
- Побочные эффекты — `BlocListener` / `BlocConsumer` с `listenWhen` по статусу в состоянии (§5.6); подписок на стримы блока у страницы нет.
- `build()` оборачивает `BlocProvider` + `BlocConsumer` (или `BlocBuilder`) и рендерит через `state.when(...)`.

> **Это не опционально (Принцип 5.1, [08](08-conventions-and-constitution.md)).** ЛЮБАЯ навигируемая страница (есть `route()`) **обязана** владеть собственным BLoC. Если бизнес-логики нет — страница всё равно получает минимальный BLoC: трио `Initializing`/`Initialized`/`Error` из §3.4 либо одновариантный value-BLoC как `AppRootBloc` (§6.1). Непавигируемые переиспользуемые **виджеты** (`lib/presentation/widgets/`, page-private `widgets/`) BLoC **не требуют** — их состоянием управляет страница-владелец.
>
> **Исключение — UI-first фаза (до бэкенда), санкционировано владельцем 2026-06-20.** Пока у навигируемого экрана НЕТ ни репозитория, ни реальной асинхронной логики, ни нетривиального изменяемого доменного состояния, такой **чисто презентационный** экран допускается как `StatelessWidget`/локальный `StatefulWidget` **без** BLoC. Под это подпадают dev-поверхности (`HomePage`, `UiKitPage`, `ScreensGalleryPage`, `RoutePlaceholderPage`; строки dev-меню в настройках закомментированы, и в продукт они не ведут), экраны UI-этапа M1 (`docs/archive/roadmap-phase1.md` / `specs/004-splash-simple-screens/`): splash, универсальный экран ошибки, About, Terms, Appearance, Language, Notifications, — просмотрщик картинок `ImageViewerPage` и живая оболочка `TabBarShell`. **Как только к экрану подключается реальный репозиторий/async, он получает свой Freezed-BLoC** по правилу выше (так `FileViewPage` получил `FileViewBloc`). Условие «без репозитория и async» растягивают два экрана: `TabBarShell` (живая подписка `sessionRepository.watchLabel()` + `setState`) — его состояние вкладок переезжает в value-BLoC (форма §6.1; в коде это маркер `// TODO(blueprint-shell-bloc)`), — и `NotificationsBody` (чтение и запись настройки + сервис системного разрешения; исключение записано в докстринге класса), который тоже переезжает на BLoC. Это узкий, фазово-ограниченный carve-out (резолюция дрейфа по Принципу III — правится блюпринт, а не код), а НЕ отмена 5.1 для экранов с реальным состоянием.

### 5.1 Worked example

**Файл:** `lib/presentation/pages/item_list_page/item_list_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/general/feature_flags.dart';
// TextConstants below is the blueprint's placeholder for ARB keys (§1); there is no such file.
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/item_details_page/item_details_page.dart';
import 'package:nox_app/presentation/pages/item_list_page/bloc/item_list_bloc.dart';
import 'package:nox_app/presentation/pages/item_list_page/widgets/item_tile_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

class ItemListPage extends StatefulWidget {
  const ItemListPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const ItemListPage(),
    settings: const RouteSettings(name: '/items'),
  );

  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends BaseStatePage<ItemListPage> {
  late final ItemListBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = ItemListBloc()..add(const ItemListEvent.initialize());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ItemListBloc>.value(
      value: _bloc,
      child: BlocConsumer<ItemListBloc, ItemListState>(
        // Status effect: a later page failed while items are on screen.
        listenWhen: (previous, current) =>
            current is Initialized &&
            current.loadError != null &&
            (previous is! Initialized || previous.loadError != current.loadError),
        listener: (context, state) {
          showAppSnackBar(context, text: _describe((state as Initialized).loadError), error: true);
          _bloc.add(const ItemListEvent.loadErrorShown());
        },
        builder: (context, state) {
          return Scaffold(
            key: scaffoldKey,
            appBar: AppBar(title: const Text(TextConstants.itemListTitle)),
            body: state.when(
              initializing: () => const AppProgressWidget(),
              initialized: (initialized) => _buildList(context, initialized),
              error: (_) => AppErrorWidget(
                onTryAgain: () => _bloc.add(const ItemListEvent.initialize()),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => AppEmptyContentWidget(glyph: NoxIcons.forum, title: TextConstants.itemsEmptyTitle, message: TextConstants.itemsEmptyMessage);

  Widget _buildList(BuildContext context, Initialized state) {
    if (state.isEmpty) return _empty();

    final list = PagedListView<String, ItemModel>.separated(
      state: state.pagingState,
      fetchNextPage: () => _bloc.add(const ItemListEvent.loadItems()),
      builderDelegate: PagedChildBuilderDelegate<ItemModel>(
        itemBuilder: (_, item, __) => ItemTileWidget(
          key: ValueKey(item.id),
          item: item,
          // Nothing for the bloc to decide: the page navigates itself.
          onTap: () => Navigator.of(context).push(ItemDetailsPage.route(itemId: item.id)),
        ),
        firstPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
        newPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
        noItemsFoundIndicatorBuilder: (_) => _empty(),
        firstPageErrorIndicatorBuilder: (_) => AppErrorWidget(
          onTryAgain: () => _bloc.add(const ItemListEvent.loadItems(reset: true)),
        ),
      ),
      separatorBuilder: (_, __) => SizedBox(height: AppSpacingTokens.s8),
    );
    if (!FeatureFlags.enablePullToRefresh) return list;
    return RefreshIndicator(onRefresh: _refresh, child: list);
  }

  /// Keeps the RefreshIndicator spinner up until the reset load actually
  /// finishes: the bloc emits loadingInProgress true, then false (or Error).
  Future<void> _refresh() async {
    final done = _bloc.stream.firstWhere((s) => s is Error || (s is Initialized && !s.loadingInProgress));
    _bloc.add(const ItemListEvent.loadItems(reset: true));
    await done.timeout(const Duration(seconds: 5), onTimeout: () => _bloc.state);
  }

  /// The exception in the person's words. The bloc has no BuildContext, so it
  /// hands out the exception and the page reads the copy.
  String _describe(BaseRepositoryException? exception) {
    if (exception is RepositoryException) {
      switch (exception) {
        case RepositoryException.connection:
          return TextConstants.errorConnection;
        case RepositoryException.unauthenticated:
        case RepositoryException.authentication:
          return TextConstants.errorAccess;
        case RepositoryException.notFound:
        case RepositoryException.attachmentGone:
          return TextConstants.errorNotFound;
        case RepositoryException.unknown:
        case RepositoryException.internal:
        case RepositoryException.invalidRequest:
        case RepositoryException.nameTaken:
        case RepositoryException.payloadTooLarge:
        case RepositoryException.rateLimited:
        case RepositoryException.unsupportedSchema:
          return TextConstants.errorGeneralMessage;
      }
    }
    return TextConstants.errorGeneralMessage;
  }
}
```

> **Pull-to-refresh — как у списка чатов 5.1.** Стоковый `RefreshIndicator` оборачивает сам `PagedListView` (не `Scaffold`), включается флагом `FeatureFlags.enablePullToRefresh`. `onRefresh` шлёт обычный `loadItems(reset: true)` и ждёт ответа блока на его стриме: первого `Error` или `Initialized` с `loadingInProgress == false`, но не дольше 5 с. Собственного виджета-индикатора и `Completer` в событии нет (`lib/presentation/pages/chats_list_page/chats_list_page.dart`, `_refresh`).

> **Навигация по тапу.** Переход, которому блоку нечего решать, страница делает сама — так 5.1 открывает тред на узкой ширине. Навигационный статус в состоянии (`LoginStatus.navConnect`, `navResume`) нужен, когда переход — исход работы блока (§5.6).

### 5.2 Страница с параметрами

Если странице нужны конструкторные параметры — добавляйте их и в конструктор, и в `route()`:

```dart
class ItemDetailsPage extends StatefulWidget {
  const ItemDetailsPage({super.key, required this.itemId});

  final String itemId;

  static Route<void> route({required String itemId}) => MaterialPageRoute<void>(
    builder: (_) => ItemDetailsPage(itemId: itemId),
    settings: const RouteSettings(name: '/item-details'),
  );

  @override
  State<ItemDetailsPage> createState() => _ItemDetailsPageState();
}
```

> Конвенция: detail-страницы — это отдельные плоские папки `lib/presentation/pages/<page>_details_page/` рядом с родительской страницей, каждая со своим BLoC-trio.

### 5.3 Рендер тела через `when()` / `map()` и Dart 3 `switch`

Базовый способ — сгенерированный Freezed-`when()` (как в `build()` выше): тело страницы — это `state.when(initializing:, initialized:, error:)`. Так исходная конструкция `body: state.when(...)` переносится без изменений (но теперь `when` сгенерирован, а не рукописный).

> **Сверка с кодом.** Под `freezed ^3.2.5` `when()`/`whenOrNull()` по-прежнему генерируются, но callback подсостояния принимает его поля **позиционно** (`initialized: (pagingState, items, nextPage, isLastPage, loadingInProgress) => …`), а не сам объект `Initialized`. В шипнутом `lib/` вызовов `.when(` **нет ни одного**: все страницы рендерятся через Dart 3 `switch (state)` (`app_root.dart`, `qr_scan_page.dart`, `item_list_page.dart`). Поэтому `switch` — рабочий канон, а `state.when(...)` в сниппетах этого документа читается как «ветвление по подсостояниям».

Для чистых **виджетов-проекций** (которые только проецируют состояние и не владеют BLoC) предпочтителен Dart 3 exhaustive `switch` с деструктуризацией — он короче и компилятор гарантирует полноту:

```dart
Widget _body(ItemListState state) {
  return switch (state) {
    Initializing() => const AppProgressWidget(),
    Initialized(:final items) when items.isEmpty => _empty(),
    Initialized() => _buildList(context, state as Initialized),
    Error(:final exception) => AppErrorWidget(
        message: _describe(exception),
        onTryAgain: () => _bloc.add(const ItemListEvent.initialize()),
      ),
  };
}
```

`Error(:final exception)` достаёт `exception` прямо из варианта. Поскольку `ItemListState` — `sealed`, компилятор требует исчерпать все варианты — пропущенный вариант не скомпилируется.

### 5.4 Гранулярные ребилды — `buildWhen` на value-equality Freezed

Когда один монолитный `Initialized` стоит за всей фичей, гранулярные ребилды достигаются **per-slice `BlocBuilder` с `buildWhen`**, сравнивающим только нужный срез. Это разблокировано именно **глубоким value-equality от Freezed**: если срез не изменился по `==`, `buildWhen` возвращает `false` и поддерево пропускается.

```dart
// Перерисовываем только индикатор «загрузка в процессе», а не весь список.
BlocBuilder<ItemListBloc, ItemListState>(
  buildWhen: (prev, curr) {
    if (prev is! Initialized || curr is! Initialized) return prev.runtimeType != curr.runtimeType;
    return prev.loadingInProgress != curr.loadingInProgress;
  },
  builder: (context, state) {
    final inProgress = state is Initialized && state.loadingInProgress;
    return inProgress ? const LinearProgressIndicator() : const SizedBox.shrink();
  },
);
```

> Это работает **только** благодаря неизменяемой копировальной дисциплине (всегда `copyWith` / новая фабрика, никогда не мутировать коллекцию состояния на месте) — иначе identity меняется непредсказуемо и `buildWhen` ломается. Подробный разбор гранулярных ребилдов для дерева (per-node `BlocBuilder`, keyed by `getNodeState(parentApiName:)`) — см. §6 case study territories tree.

### 5.5 Пагинация — `PagingState`-in-bloc (v5)

Проект на **v5 `PagingState` API** пакета `infinite_scroll_pagination ^5.1.1`: BLoC строит неизменяемый `PagingState<PageKey, Item>` внутри `Initialized`. **Нет** widget-owned `PagingController`, нет `addPageRequestListener`. Учёт порций живёт в состоянии BLoC. Общий доменный тип метаданных — `PageMetadata{required bool hasMore, int? nextPage}` (тотала на проводе нет). В контракте v0 **два реальных пути** (фаза 025), и оба собирают `PagingState` одним и тем же `PagingStateExt.applyPage` — признак конца списка в нём один: `!meta.hasMore`.

- **Страничный (paged) — список чатов.** Запрос `page` + `page_size`, страницы **1-based** (`GetChatsConfig.defaultPage = 1`); ответ `{chats, has_more}`, `nextPage = hasMore ? page + 1 : null` вычисляется **на клиенте**. UI — `PagedListView(state:, fetchNextPage:)`, координата следующей порции — `nextPage` в стейте.
- **Seq-курсорный — история сообщений.** Запрос `before_seq` + `limit` (`GetMessagesConfig.tail()` / `.olderThan()`), ответ `{messages, has_more}`, батч идёт по возрастанию `seq`, сервер молча зажимает `limit` до 100. Стейт треда держит `oldestLoadedSeq` (`int?`), а не номер страницы, и **не** использует `PagedListView`: это `reverse: true` `ListView.builder` с догрузкой старой истории из слушателя `ScrollController`.

`CursorPaginationMetadata{String? nextCursor}` остаётся задокументированной опцией — только на случай эндпоинта со **строковым** непрозрачным курсором; в проекте такого нет. Полный контракт — `PagingStateExt.applyPage`, error-builder'ы v5, курсорный вариант helper'а — в `07-pagination.md`. Здесь — только связка: BLoC кладёт `PagingState` в `Initialized`, страница рендерит список, `result.exception` прокидывается в `pagingState.error` для v5-error-builder'ов.

### 5.6 Побочные эффекты — статус в состоянии + `BlocListener`

Транзиентный эффект (навигация, снэкбар, диалог) — **статус в состоянии блока**. Страница ловит его `BlocListener` (или `BlocConsumer`, когда она же строит тело) с `listenWhen`, сравнивающим прошлое и новое значение статуса, — переход состояния, а не каждое построение. Эффект, который не должен сработать повторно, страница, отработав, гасит событием, и статус возвращается в покой. Стримов-эффектов у блока нет, подписок на них у страницы — тоже.

| Форма статуса | Когда | Пример в коде |
|---|---|---|
| **enum-статус** + событие «отработано» | переход или ответ, который — исход работы блока | `LoginStatus.navConnect` / `navResume` → `Navigator.push(ConnectPage.route(...))` + `LoginEvent.navigationHandled()`; `ConnectStatus.cancelled` → экран закрывается в post-frame |
| **поле-эффект** `T?`, гасится событием | разовый снэкбар с данными | `Initialized.loadError` → `showAppSnackBar` + `ItemListEvent.loadErrorShown()` (§3.3, §5.1) |
| **счётчик-тик** `int` | один и тот же эффект может повториться подряд | `AppRootState.settingsSaveErrorTick` → снэкбар ошибки сохранения настроек |

Пример — экран входа (`lib/presentation/pages/login_page/login_page.dart`):

```dart
BlocConsumer<LoginBloc, LoginState>(
  listenWhen: (previous, current) => previous.status != current.status,
  listener: (context, state) {
    switch (state.status) {
      case LoginStatus.navConnect:
        // A readable link goes on to the connection screen.
        Navigator.of(context).push(ConnectPage.route(link: state.id.trim()));
        _bloc.add(const LoginEvent.navigationHandled()); // status back to idle
      // ... navResume and the other nav* statuses the same way
      default:
        break;
    }
  },
  builder: (context, state) => /* ... */,
);
```

> Ошибка, которая принадлежит экрану (строка под полем ввода), — обычное состояние, без «отработано»: виджет рисует её из статуса при каждом построении (`LoginStatus.errorFormat` → `context.l10n.loginInvalidId`). В слова статус и исключение переводит страница (`context.l10n`): у блока нет `BuildContext`.
>
> **Поиск и проверка имени чата** — не эффект, а трансформер: `on<SearchChanged>(…, transformer: debounceRestartable())` у `ChatsListBloc`, `on<ChatAvailabilityRequested>` / `on<RenameAvailabilityRequested>` у `CreateChatBloc` / `RenameChatBloc` (`lib/presentation/base/bloc_transformers.dart`: 300 мс тишины, затем последнее событие, обработчик предыдущего отменяется; §5.8).

### 5.7 Потребление `RepositoryResult<T>` — `match()` / `hasData`, никогда `data!`

`RepositoryResult<T>` (см. `03-domain-layer.md`) — это `@freezed` с data-XOR-exception. Потребляйте через `match<R>(onData:, onError:)` или guard `result.hasData`; **никогда** не пишите `result.data!` без предшествующего `hasData`-guard'а:

```dart
final result = await _itemRepository.getItems(config: config);
result.match<void>(
  onData: (page) {
    final (items, meta) = page;
    final current = this.state;
    if (current is Initialized) emit(current.copyWith(items: items, isLastPage: !meta.hasMore));
  },
  onError: (exception) => emit(ItemListState.error(exception: exception)),
);
```

### 5.8 Конкурентность — дефолт и продвинутый toolkit

**ДЕФОЛТ (плоские списки, поиск).** Два инструмента:

1. **stale-guard** — после каждого `await` перечитать `this.state` и выйти, если контекст (например, `query`) изменился. Уже показано в `_onLoadItems` (§3.3).
2. **`debounceRestartable()`** — проектный трансформер для поиска и проверки имени (`lib/presentation/base/bloc_transformers.dart`, `debounceRestartable<E>([Duration duration = const Duration(milliseconds: 300)])` = `events.debounceTime(duration).switchMap(mapper)`): ждёт 300 мс тишины ввода, берёт последнее событие и **отменяет** предыдущий in-flight handler. Регистрируется как `on<SearchChanged>(_handler, transformer: debounceRestartable())`. Голый `restartable()` из `bloc_concurrency` для ввода не берётся: без паузы он отправлял бы запрос на каждую букву. Загрузки страниц идут через `sequential()`.

**ПРОДВИНУТЫЙ toolkit (representation/tree BLoC, загружающие много узлов конкурентно):**

- **epoch-guard** — поле `int _epoch = 0`; на `reset`-событии `++_epoch` и захват нового значения, на не-reset-загрузке — захват текущего без инкремента. Захваченный `myEpoch` перепроверяется на входе, после reset-emit и (критично) после единственного network-`await` через `_isStaleRequest(myEpoch) => epoch != _epoch`. Каждый reset разом инвалидирует все прежние in-flight загрузки.
- **`debounce` / `debounceIf` transformers** (300 мс, на rxdart) — `debounce` через `switchMap` (новый event отменяет предыдущий handler), `debounceIf((e) => e.reset, 300ms)` разбивает поток по предикату: `reset == true` дебаунсятся, `reset == false` проходят мгновенно (через `asyncExpand`, без отмены).
- **`BaseBloc.executeLogic`** — оборачивает тело async-handler'а; `onError` эмитит терминальный `Error` (или опускается для фоновых загрузок, см. §2).

> **Case study (territories tree).** Дерево хранится в state плоским нормализованным `Map<String?, NodeState>` (ключ — id родителя, `null` = корень); UI — чистая проекция этого map. Каждый узел несёт свой `LoadingState` + `cursor`, поэтому два узла на разной глубине грузятся одновременно без коллизий. `reset`-событие на смене модели/поиска делает `++_epoch` и стирает дерево; epoch-guard после `await` отбрасывает устаревшие ответы (старая in-flight-загрузка не дописывает элементы прежней модели в текущее дерево). `debounceIf((e) => e.reset)` дебаунсит ресеты, но пропускает «load more» мгновенно. Гранулярные ребилды — per-node `BlocBuilder` с `buildWhen`, сравнивающим `getNodeState(parentApiName: widget.item.apiName)` по value-equality Freezed: загрузка одного узла перерисовывает **только** его тайл. Все хирургические мутации (insert/remove/update/move) патчат map на месте через `copyWith` + клонирование коллекций — `State`-объект, достижимый до `emit`, никогда не мутируется. Этот паттерн — для деревьев и сложных представлений; для плоского списка чатов достаточно дефолтного toolkit'а (stale-guard + `debounceRestartable()`).

---

## 6. App-shell — `AppRoot` + `AppRootBloc`

App-shell хостит `MaterialApp`, подаёт тему из `AppRootBloc` и ставит `home: const SplashPage()`; дальше корневой маршрут меняется по app-state через `GlobalKey<NavigatorState>` (`unauthorized` → `LoginPage`, `registrationPending` → `SetUsernamePage`, `authorized` → `TabBarShell`; §6.1). Таблицы маршрутов и router-пакета нет. Навигация внутри фичи — обычный `Navigator.of(context).push(<Page>.route(...))`.

> **Навигационная модель NOX — 3-элементный нижний бар (mobile) / рельса (desktop).** Продуктовая оболочка NOX — `Chats`-вкладка, центральный docked `+` FAB (создание чата, виден на обеих вкладках узкой ширины) и `Settings`-вкладка; отдельного profile-экрана нет (profile-подобные пункты живут в Settings). Живая оболочка — `TabBarShell` (§6.5), **size-driven** и единая для всех пяти таргетов; на широкой ширине `+` — кнопка в заголовке панели чатов, а не FAB на рельсе. Скелетный `AppShell` Feature-001 (харнесс `Item` и заглушка настроек в `body`, `+` — no-op) не смонтирован.

> **Принцип 5.1 для оболочки.** Навигируемая страница **с реальным состоянием/async** обязана владеть собственным BLoC (минимальный trio §3.4 или одновариантный value-BLoC §6.1; переиспользуемые виджеты — нет). Чисто презентационные UI-first экраны на заглушках (лаунчер/галерея/статичные экраны M1) подпадают под фазовый carve-out §5 и BLoC не требуют до подключения реального репозитория. **Оболочка:** состояние вкладок `TabBarShell` (выбранная вкладка и подписка на имя аккаунта) переезжает в value-BLoC — одно состояние с `copyWith`, форма §6.1; в коде это маркер `// TODO(blueprint-shell-bloc)`. Скелетный `AppShell` и `SettingsPlaceholderPage` не смонтированы и живут без BLoC.

> **Обработка входящих ссылок.** Deep links не реализованы: `app_links` объявлен в `pubspec.yaml`, но в `lib/` не импортируется, `DeepLinkRepository` в коде нет. Целевое место — `AppRoot`: там подписываются на `DeepLinkRepository.watchDeepLink()`, и оттуда `AppRootBloc` маршрутизирует deep / universal links (`GlobalKey<NavigatorState>` для навигации без `BuildContext`). Полный механизм (пайплайн `app_links` → парсинг → типизированная модель → dispatch-table, нативная интеграция, `ValidateDeepLinkPage`) — в [13-deep-links.md](13-deep-links.md). Здесь shell остаётся минимальным; deep-link-обвязка добавляется поверх по мере необходимости.

### 6.1 `AppRootBloc` — одно конкретное состояние, не trio

App-level state — это **одно конкретное состояние** `AppRootState` с `copyWith` (а **не** trio `Initializing`/`Initialized`/`Error`), потому что оно всегда «живое»: несёт `themeMode` с момента старта и лишь мутирует это поле. Темы — статические `AppTheme.light()` / `AppTheme.dark()` через `ThemeExtension<AppColors>` (см. `06-theming.md`), их строит `MaterialApp`, а не state.

**Файл:** `lib/presentation/app/bloc/app_root_event.dart`

```dart
part of 'app_root_bloc.dart';

@freezed
sealed class AppRootEvent with _$AppRootEvent {
  const factory AppRootEvent.initialize() = Initialize;
  const factory AppRootEvent.setTheme({required ThemeMode themeMode}) = SetTheme;
}
```

**Файл:** `lib/presentation/app/bloc/app_root_state.dart`

```dart
part of 'app_root_bloc.dart';

@freezed
abstract class AppRootState with _$AppRootState {
  const factory AppRootState({
    required ThemeMode themeMode,
  }) = _AppRootState;
}
```

> `AppRootState` объявлен `@freezed abstract` (single-variant value-объект) — у него один вариант, поэтому `abstract`, а не `sealed`. `copyWith` сгенерирован Freezed. Снипет выше — минимальная форма с одним `themeMode`; реальный `AppRootState` несёт ещё `lastAppState` / `appliedAppState` / `isReady` (двухфазное применение app-state), `settingsSaveErrorTick` (снэкбар ошибки сохранения настроек) и `pairRequest` / `pairAnswering` / `pairAnswerFailed` (вопрос о новом устройстве), начальное значение — `AppRootState.initial()`; события — ещё `updateAppState`, `applyAppState`, `pairRequestsChanged`, `pairRequestAnswered` (ниже). `ThemeData` (`AppTheme.light()` / `AppTheme.dark()`) в state не живут: их строит `MaterialApp` (см. §6.2), а `BlocBuilder` вокруг него перестраивается только при смене `themeMode`.

**Файл:** `lib/presentation/app/bloc/app_root_bloc.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'app_root_event.dart';
part 'app_root_state.dart';
part 'app_root_bloc.freezed.dart';

class AppRootBloc extends BaseBloc<AppRootEvent, AppRootState> {
  AppRootBloc() : super(const AppRootState(themeMode: ThemeMode.system)) {
    on<Initialize>(_onInitialize);
    on<SetTheme>(_onSetTheme);
  }

  FutureOr<void> _onInitialize(Initialize event, Emitter<AppRootState> emit) async {
    // Хук для глобального startup-кода (например, загрузить сохранённый themeMode).
  }

  FutureOr<void> _onSetTheme(SetTheme event, Emitter<AppRootState> emit) async {
    emit(state.copyWith(themeMode: event.themeMode));
  }
}
```

> **Auth/splash-флоу — реализован в Feature-009 (`specs/009-app-state-flow/`).** `AppRoot` оборачивает `MaterialApp` в `MultiBlocListener`, swap'ающий корневой маршрут через `_navigatorKey.currentState!.pushReplacement(...)` (первый переход со splash) либо `pushAndRemoveUntil(..., (_) => false)` (последующие — обнуляют стек через авторизационную границу) при смене **применённой** фазы app-state. Несущие части: `AppStateRepository` (in-memory `BehaviorSubject`-**проекция** сигналов сессии, **без DAO**) → расширенный `AppRootState` с **двухфазным применением** (`lastAppState`/`appliedAppState`/`isReady`: первый переход удержан за splash-анимацией, последующие применяются немедленно) + события `UpdateAppState`/`ApplyAppState`, питаемые подпиской `_onInitialize` на `watchAppState()`. Состояния NOX: `init` / `unauthorized` / `registrationPending` (first-login `Set username`) / `authorized`. Сигналы сессии — `SessionModel { identifier, label?, authorId?, onboardingComplete }` (`identifier` → `flutter_secure_storage`, флаги → `shared_preferences`); мутации оркеструет `AuthRepository` по контракту «мутируй → `fetchAppState()`». One-shot `sessionExpired`-snackbar — через `showAppSnackBar(..., error: true)` (`lib/presentation/helpers/app_feedback_helper.dart`; post-frame, navigator context). Принудительный выход приходит только от сессии: `unauthenticated` в ответ на `session.hello` и событие `device.revoked` ([14-networking-and-auth.md](14-networking-and-auth.md) §6.0). `AuthInterceptor` (feature 019) только ставит заголовок `Authorization` с токеном, у которого писателя нет, и пропускает любую ошибку дальше: `401` от `/files` — неудавшаяся передача, и выхода он **не** вызывает. Команды идут по WebSocket (реальные data-source'ы `RealChatRemoteDataSource`/`RealMessageRemoteDataSource`/`RealFileRemoteDataSource`, `env: [Environment.dev]`), Dio несёт только байты файлов (фаза 028); `ApiClient.initBase(address:)` вызывает `LiveSessionStarter` — при старте со спаренным адресом, затем на каждом приветствии с адресом соединения, через которое оно пришло. Адрес и ключ сервера приходят только ссылкой спаривания и хранятся с сессией; адреса сервера в сборке нет. Вход — спаривание по ссылке (контракт §8A, [14-networking-and-auth.md](14-networking-and-auth.md) §6.4а). Первый переход различается по `previous.appliedAppState == init` (без `NavigatorObserver`). Первое состояние при этом ждёт и старта приложения (фаза 048): `main.dart` передаёт его в `AppStateRepository.holdUntil`, и `watchAppState()` ничего не выводит, пока ключ локальной базы не получен и данные не открыты, — заставка стоит, сколько бы ни молчал сейф ([04-data-layer.md](04-data-layer.md) §6г). Поэтому всё, что делает первый экран, видит уже итог старта: в том числе экран входа, который продолжает ожидание одобрения после перезапуска (фаза 046), — данные, снятые на старте, уносят ожидание с собой. Полная мотивация — `docs/archive/app-state-flow-migration.md`.

> **Вопрос поверх любого экрана — запрос нового устройства (фаза 046).** `AppRoot` хостит единственный глобальный диалог приложения: устройство, выпустившее приглашение, спрашивает, пустить ли новое (`AppPairRequestDialogWidget`, `lib/presentation/widgets/settings/app_pair_request_dialog_widget.dart`; экран 8.2), на обеих ширинах. Состояние — в том же `AppRootState`: `pairRequest` (`PairRequest?` — самый старый ждущий запрос, о котором спрашивают сейчас), `pairAnswering` (`bool?` — ответ в пути: `true` — `Allow`, `false` — `Deny`) и `pairAnswerFailed` (ответ не дошёл; кнопки снова доступны). События — `PairRequestsChanged(List<PairRequest>)` из подписки `_onInitialize` на `PairRequestService.watchRequests()` (только там, где служба зарегистрирована, — `[dev]`) и `PairRequestAnswered({requestId, allow})`; новый вопрос начинается с чистого листа, а ответ, пришедший, когда спрашивают уже о другом, ничего не меняет. Диалог — отдельный `DialogRoute` на корневом навигаторе (`/pair-request`, `barrierDismissible: false`), а не виджет в дереве: так он настоящий диалог — барьер, фокус внутри, диктор читает его как диалог — поверх любого экрана. `_syncPairDialog()` поднимает, снимает или меняет его так, чтобы он спрашивал о запросе, который держит блок, и только на экране вошедшего (`appliedAppState.state == authorized`) после первой смены корневого маршрута: смена заменяет верхний маршрут и заменила бы диалог. После каждой смены корня синхронизация повторяется в post-frame-колбэке; диалог, снятый чем-то другим (сменой корня, `pop` для экрана под ним), поднимается снова, пока вопрос стоит. Диалог строится для ОДНОГО запроса: пока он уходит, блок может уже держать следующий — такой диалог сохраняет свой вопрос и ответов больше не принимает. Сам виджет закрыт `PopScope(canPop: false)`: ни барьер, ни back, ни Escape вопрос не отложат.

### 6.2 `AppRoot` — корневой `MaterialApp`

**Файл:** `lib/presentation/app/app_root.dart`

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/app_overlay_style_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/general/constants.dart';
// TextConstants below is the blueprint's placeholder for ARB keys (§1); there is no such file.
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/app/widgets/app_shell.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final AppRootBloc _bloc;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _bloc = AppRootBloc()..add(const AppRootEvent.initialize());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AppRootBloc>.value(
      value: _bloc,
      child: BlocBuilder<AppRootBloc, AppRootState>(
        builder: (context, state) {
          // 1) Снаружи отключаем системный масштаб шрифта (OS accessibility font size):
          //    размеры задаёт ТОЛЬКО дизайн-скейл ScreenUtil, а не настройка ОС.
          //    См. 06-theming.md §3.2.
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
            // 2) Инициализируем глобальный ScreenUtil от дизайн-канвы 360×779.
            child: ScreenUtilInit(
              designSize: Constants.designSize, // Size(360, 779) — lib/general/constants.dart
              // Clamps `.sp` to 0.90..1.00 so type never grows on a wide window.
              // Mandatory in every ScreenUtilInit (app and test harness alike);
              // `minTextAdapt` is a dead no-op once a resolver is set.
              fontSizeResolver: AppTextStyleTokens.fontSizeResolver,
              builder: (context, child) {
                return MaterialApp(
                  title: TextConstants.appName,
                  navigatorKey: _navigatorKey,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: state.themeMode,
                  scrollBehavior: const MaterialScrollBehavior().copyWith(
                    dragDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  // 3) MaterialApp переустанавливает MediaQuery — повторно пиним textScaler=1.0
                  //    уже ВНУТРИ, чтобы OS-масштаб шрифта не вернулся
                  //    ни на одном экране.
                  // 4) Системный overlay по умолчанию — регион по активной теме (статус-бар
                  //    и навигационная панель); AppBar и splash ставят свой поверх
                  //    (06-theming.md §6.1).
                  builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
                    value: AppOverlayStyleTokens.of(Theme.of(context).colorScheme),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                  // Скелет: home — оболочка AppShell. В lib/ — home: const SplashPage(), а корневой
                  // маршрут свапается через _navigatorKey по app-state (блок «auth/splash-флоу», §6.1).
                  home: const AppShell(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
```

> **Снипет выше — скелетная (Feature-001) форма `_AppRootState`, а не код `lib/`.** Реальный `lib/presentation/app/app_root.dart` — тот же каркас (`AppRootBloc` + `ScreenUtilInit` + двойной `MediaQuery` + `AnnotatedRegion<SystemUiOverlayStyle>` в `MaterialApp.builder`), но с `home: const SplashPage()`, `MultiBlocListener`, свапающим корневой маршрут по app-state-спине и поднимающим диалог 8.2 (§6.1), `LocaleController` (live EN/UK, `MaterialApp.locale`) и `onGenerateTitle` из `context.l10n`. `WidgetsBindingObserver` в нём нет: переход приложения из фона на передний план слушает data-слой (`AppLifecycleService` → выбор пути, [14](14-networking-and-auth.md) §6), а не app-root. Подписки на состояние сети у app-root тоже нет: плашки «нет связи» локальны — BLoC'и 5.1, 5.2, 5.4 слушают `ConnectionStatusService.watchStatus()` (§6.6). Auth-контура из [14](14-networking-and-auth.md) §4 (Bearer, refresh, реакция на `401`) в NOX нет и не будет: аутентифицирует соединение канал нативного модуля (`POST /auth` → `POST /auth2`), токенов контракт не несёт ([14](14-networking-and-auth.md) §6.0); §6.4 ниже — пример устройства слоя, а не план.

> **UI-скейл — «дизайн выглядит ~одинаково на всех устройствах».** Обёртка `ScreenUtilInit(designSize: Constants.designSize=Size(360,779), fontSizeResolver: AppTextStyleTokens.fontSizeResolver)` + двойной `MediaQuery` (внешний `TextScaler.noScaling`, внутренний `TextScaler.linear(1.0)`) — это **ядро** решения по адаптивности: системный масштаб шрифта полностью нейтрализован, а все размеры (`AppSpacingTokens.sN`, `AppTextStyleTokens`) выводятся из дизайн-скейла `ScreenUtil`. Полное описание механизма и токенов — в [06-theming.md](06-theming.md) §3.2.

### 6.3 `main.dart` — точка входа

`main.dart` оборачивает запуск в `runZonedGuarded`, регистрирует лицензии встроенных шрифтов в `LicenseRegistry`, на Windows до любого вопроса о папке переносит папку данных в `%LOCALAPPDATA%`, резолвит флейвор, дожидается `configureDependencies(env)` затем `getIt.allReady()`, поднимает конфиг-репозиторий `AppConfigRepository.initialize(flavorType:)`, убирает устаревшие ключи и вызывает `runApp(AppRoot)`, держа первое состояние приложения до конца старта `_start()` (папка данных вне бэкапов, локальные данные под ключом, живой канал, очередь исходящих). `env` выводится из флейвора (`prod → Environment.prod`, `stage → Environment.dev`, см. `09-build-and-secrets-infra.md`). Полный `main.dart` с `_start()` и разбор каждого шага — в `02-dependency-injection.md` §10; ниже — его функция `main()`.

```dart
void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // The licence texts of the bundled fonts travel with them (LicenseRegistry).
      registerFontLicenses();
      // Before anything asks for a folder: on Windows the data lives in the local application data.
      AppDataRoot.useLocalFolderOnWindows();

      // 1) Резолвим флейвор на этапе компиляции, маппим флейвор -> DI-окружение.
      final flavor = AppFlavor.getFlavor();
      final env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev;

      // 2) Собираем контейнер (+ блокируем ориентацию параллельно),
      //    затем ждём async pre-resolve.
      await Future.wait<dynamic>([
        configureDependencies(env),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
      await getIt.allReady(); // резолвит preResolve: true async-регистрации (SharedPreferences)

      // 3) Поднимаем конфиг-репозиторий под выбранный флейвор и убираем устаревшие ключи.
      await getIt<AppConfigRepository>().initialize(flavorType: flavor);
      await sessionRepository.sweepLegacyKeys();

      // 4) Первый экран ждёт старта: заставка стоит, пока он идёт.
      final started = _start();
      appStateRepository.holdUntil(started);
      runApp(const AppRoot());
      await started;
    },
    (error, stack) {
      // Финальный safety-net: всё, что просочилось мимо BLoC. Логируем через LogRepository,
      // если DI уже поднят. Раннее падение до DI — крайне редкое.
      if (getIt.isRegistered<LogRepository>()) {
        getIt<LogRepository>().error(target: 'main', error: error, stackTrace: stack);
      }
    },
  );
}
```

> `configureDependencies(env)` — единый одноуровневый DI entry-point из `02-dependency-injection.md` (`@InjectableInit(initializerName: r'$initGetIt')`). Никаких `isHost` / `useIpc` — single-process. `AppConfigRepository.initialize(flavorType:)` (контракт — `14-networking-and-auth.md` §2) поднимает флейвор-зависимый конфиг **после** готового контейнера.

### 6.4 App-lifecycle observer (resume → превентивный refresh)

> **Пример, а не форма NOX.** Аутентификацию в NOX даёт канал: проверка `POST /auth` → `POST /auth2` на каждом соединении по ключу устройства и ключу сервера из ссылки спаривания ([14](14-networking-and-auth.md) §6.0); токенов и их обновления нет, а принудительный выход приходит только от сервера — `unauthenticated` на приветствие и событие `device.revoked`. Поэтому весь auth-контур ниже (`AuthBloc`, `AppResumed`, refresh access-токена, реакция на `401`) читается как **пример устройства слоя**; в коде этого слоя нет.

App-root `State` (`_AppRootState`, §6.2) подмешивает `WidgetsBindingObserver` и на `AppLifecycleState.resumed` дёргает `getIt<AuthBloc>().add(const AppResumed())` — превентивный refresh access-токена **до** первого запроса после долгого background (полный контракт + обязательный re-entrancy guard — в [14-networking-and-auth.md](14-networking-and-auth.md) §5.4; `AuthBloc` — часть auth-флоу `14` §4, появляется с auth-контуром). Канон: подписка в `initState`, отписка в `dispose`. Observer ставится **один раз** на app-root, а не на каждой странице, и НЕ реализует refresh сам — лишь триггерит тот же код auth-контура, что отрабатывает реактивно на `401`. Тот же `State` мог бы подписаться на состояние сети (UX-баннер «нет сети») — см. `14` §5; в коде плашки «нет связи» локальны: их BLoC'и 5.1, 5.2, 5.4 слушают `ConnectionStatusService.watchStatus()`, а `ConnectivityService.watchOnline()` presentation не слушает вовсе (§6.2).

```dart
class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  // ... _bloc (AppRootBloc) + _navigatorKey из §6.2 ...

  @override
  void initState() {
    super.initState();
    _bloc = AppRootBloc()..add(const AppRootEvent.initialize());
    WidgetsBinding.instance.addObserver(this);
    // + подписка на ConnectivityService.watchOnline() → AuthBloc (UX-баннер; см. 14 §5.4)
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      getIt<AuthBloc>().add(const AppResumed()); // ← делегат auth-контуру (док 14 §5.4)
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.close();
    super.dispose();
  }
}
```

> Observer интегрировался бы в **существующий** `_AppRootState` (§6.2) — тот уже держит `AppRootBloc` + `ScreenUtilInit`; добавляется `with WidgetsBindingObserver` + подписки. В NOX lifecycle слушает data-слой (`AppLifecycleService`, `[dev, prod]`; в `[test]` — `ForegroundAppLifecycleService`): возврат на передний план будит выбор пути ([14-networking-and-auth.md](14-networking-and-auth.md) §6).

### 6.5 Адаптивная оболочка (mobile нижний бар / desktop рельса)

Ниже сначала — скелетный `AppShell` Feature-001 (форма и правила ширины), затем — живая оболочка `TabBarShell`, которую монтирует приложение.

`AppShell` (`lib/presentation/app/widgets/app_shell.dart`, не смонтирован) — это `LayoutBuilder`-обёртка между `AppRoot` и страницей; переключение между мобильной и десктопной раскладкой **width-driven** — по `constraints.maxWidth >= Constants.railBreakpoint` (840dp, граница M3 medium→expanded), а **не** по `Platform`. Большое окно на десктопе и большой планшет получают одинаковую раскладку; узкое окно на десктопе остаётся на мобильной. Один и тот же размер-зависимый код корректен на всех пяти таргетах (iOS, Android, Windows, Linux, macOS).

Две ветки:

- **Mobile-ветка** (`maxWidth < Constants.railBreakpoint`): `Scaffold` с нижним баром (`Chats` / центральный docked `+` FAB / `Settings`). Нижний бар — кастомный `BottomAppBar` (`CircularNotchedRectangle`) + `FloatingActionButton` в `floatingActionButtonLocation: centerDocked` (стоковый `NavigationBar` не умеет docked-FAB с вырезом); см. locked-спеку `docs/design/spec/screens/tab-bar-shell.md`.
- **Desktop-ветка** (`maxWidth >= Constants.railBreakpoint`): `Row[ NavigationRail(labelType: NavigationRailLabelType.all, leading: FloatingActionButton(child: AppIconWidget(NoxIcons.add))), VerticalDivider(width: hairline), Expanded(body) ]` — `leading`-FAB рейла и есть «доковый» `+`.

Общее для обеих веток:

- Ровно две destination'ы, иконки — SVG через `AppIconWidget`: `Chats` = `NoxIcons.forum` (выбранная — `NoxIcons.forumFill`), `Settings` = `NoxIcons.settings` (выбранная — `NoxIcons.settingsFill`); подписи — `context.l10n.chats` / `context.l10n.settings`.
- Индикатор выбранной destination — стоковый M3 (в десктопном рейле — `secondaryContainer`; в кастомном нижнем баре выбранный элемент подсвечивается через `colorScheme.primary`).
- `body` — `IndexedStack` (сохраняет состояние вкладок при переключении).
- Аватара аккаунта в скелете нет (в живой оболочке он есть — ниже); profile-экрана в NOX нет (см. карту экранов).
- Single-window `Navigator` сохраняется (§1) — оболочка не вводит multi-window.

Скелет Feature-001 (без реальных продуктовых фич):

- `Chats`-вкладка ведёт на страницу-харнесс `Item` (та же, что и в §3–§5; mock-данные, FR-013), `Settings` — на `SettingsPlaceholderPage`.
- `+` — no-op со snackbar'ом: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.comingSoon)))`. Никакого create-flow.
- Скелетный `AppShell` даёт только rail + единый `body` (без list-detail); list-detail — у живой оболочки ниже.
- Нативный OS window chrome — **без** кастомного title bar в скелете (у живой оболочки — `AppWindowTitlebarWidget` внутри окна; нативный chrome окна — FUTURE, см. note про `window_manager`, §1).
- Скелетный `AppShell` — обычный `StatefulWidget` без BLoC, выбранная вкладка `_index` хранится в локальном `setState`.

**Живая оболочка — `TabBarShell`** (`lib/presentation/widgets/shell/tab_bar_shell_widget.dart`, Feature-006), собранная на kit-виджетах (`AppBottomBarWidget` + center-docked `AppCreateFabWidget` на мобайле; `AppWindowTitlebarWidget` над рукописной рельсой `AppNavigationRailWidget` на десктопе), а **не** на стоковых `NavigationBar`/`NavigationRail`. Несущие отличия от скелетного `AppShell`:

- Рельса — рукописная, 80dp: волосяная линия справа, две ячейки `Semantics(button, selected)`, выбранная иконка заливается (без «пилюли» вокруг), внизу — аватар аккаунта (`_NavRailAccountAvatar`). **FAB'а на рельсе нет:** на широкой ширине `+` — кнопка в заголовке панели чатов, поэтому при открытых настройках создать чат с широкой ширины нельзя.
- Состояние вкладок (выбранная вкладка `AppTab`, имя аккаунта для аватаров) переезжает в value-BLoC оболочки (форма §6.1) — в коде это маркер `// TODO(blueprint-shell-bloc)` на локальном `AppTab _active` + `setState`; обе вкладки смонтированы в `Stack` из `IgnorePointer` + `AnimatedOpacity` с кросс-фейдом `NoxDuration.tabFade`, поэтому состояние вкладок переживает переключение. Оболочка держит подписку `sessionRepository.watchLabel()`, которая питает оба аватара аккаунта (рельса и действие в app-bar вкладки Chats на мобайле).
- Вкладки хостят реальные 5.1 `ChatsListPage` + 7.1 `SettingsRootPage` (как вкладка оболочки страница выбирает ветку по `forceWide`, а не по своей ширине: рельса сужает тело); `+` → реальный 6.1 (width-adaptive: push на мобайле / `Dialog` на десктопе); системный back: на не-Chats вкладке — на Chats, на Chats — отдаётся маршруту (`PopScope(canPop: true)`).
- **Desktop list-detail:** 5.1 — рельса + панель списка чатов (360) + панель треда (лента 5.2); 7.1 — рельса + меню настроек (340) + detail-панель (≤680). Выбор строки/пункта — **view-state** (`selectedChatId` в `ChatsListBloc`; локальный раздел в 7.1), меняет панель **без** push через контейнер `AppListDetailWidget`. Источник десктоп-раскладки — авторитетный корпус `nox-desktop-screens/{01-chats,02-settings}.md` + owner-решение (`specs/006-shell-settings-chats` Clarifications).

> Референс десктопной раскладки (rail, ширины, слоты) — `docs/design/system/nox-desktop-screens/`. Брейкпоинт `Constants.railBreakpoint = 840` задан в `lib/general/constants.dart` (см. `06-theming.md`).

### 6.6 Связь: экран подключения, раздел «Связь» и причина на плашке (фаза 045)

Три поверхности, через которые человек видит и правит путь до сервера; сам путь — [14-networking-and-auth.md](14-networking-and-auth.md) §6.

- **Экран подключения** — `ConnectPage` (`lib/presentation/pages/connect_page/`, маршрут `/onboarding/connect`) с `ConnectBloc`: одно Freezed-состояние значения с `copyWith` (форма §6.1, не trio) — поля, их ошибки формата, `useTor`, статус `ConnectStatus {idle, connecting, waiting, linkExpired, linkRejected, declined, failed, cancelled}`, причина `problem` и `cancelling`. Формат проверяет `AddressFormat` (`lib/general/connection/address_format.dart`), и только изменённое: значение, равное значению из ссылки, годно как есть. Экран входа 2.1 (`LoginBloc`) ссылку только читает: отказ разбора (`errorFormat`, `errorNewerVersion`) говорит сам, а читаемую ссылку — вставленную, отсканированную на 2.2 или прочитанную с картинки — отправляет сюда (`navConnect`). `Connect` зовёт `AuthRepository.signIn(identifier:, connection: ConnectionSettings)`, дальше app-state-спина (§6.2) уводит на 2.3 или 4.1. Пока идёт попытка, блок слушает `ConnectionStatusService` и показывает найденную причину сразу, а системный back закрыт `PopScope`. Раскладка — `AppOnboardingScaffoldWidget` с `leading` (стрелка назад на узкой ширине).
- **Ожидание подтверждения (фаза 046).** `ConnectBloc` слушает `AuthRepository.watchAwaitingApproval()` и переходит в `waiting` только из `connecting`: поток отдаёт последнее значение новому слушателю, и устаревшее «ждёт» не должно захватить экран, на котором `Connect` не нажимали. В `waiting` (`isBusy`) поля уступают место заголовку, индикатору и строке `connectWaitingApproval` (живая область), а действие одно — `Cancel` → `CancelRequested` → `AuthRepository.cancelPairing()`; `PopScope` и стрелка назад закрыты. Исходы `signIn` раскладываются в статус: `PairingException.declined` → `declined` (`connectDeclined` под `Connect`), `RepositoryException.notFound` → `linkExpired` (так же звучит и запрос, истёкший без ответа), `PairingException.cancelled` → `cancelled` — слушатель закрывает экран в post-frame (`PopScope` ожидания иначе отверг бы `pop`). Причину, найденную во время ожидания, блок держит, но не показывает: ожидание, кончившееся окончательным отказом канала, говорит её под `Connect`, как любая неудачная попытка. **Возврат к ожиданию после перезапуска:** `LoginBloc` при открытии экрана (`ResumeChecked`) спрашивает `AuthRepository.pendingPairing()` и для живого ожидания уходит в `navResume` с `PendingPairing`; страница входа открывает `ConnectPage.route(link:, resume: true, settings:)`, и блок с `resume` сразу шлёт `ConnectRequested` с полями и `useTor`, как они были.
- **Раздел «Связь»** — `ConnectionPage` (`/settings/connection`, `AppDetailScaffoldWidget`) поверх `ConnectionBody`; на широкой ширине то же тело заполняет detail-панель настроек (`_Section.connection` в `settings_root_page.dart`) — раскол Body/Page, как у остальных листьев настроек. Блок `ConnectionSettingsBloc` принадлежит телу: `Save` и `Use Tor` идут через `sequential()` (обе записи — чтение-изменение-запись одной записи, и обе перезапускают канал), подписки — на `ServerAddressesRepository.watch()` (новые адреса сервера ложатся в поля, которые человек не правит) и на `ConnectionStatusService` (строка над полями, пока связи нет); любое применённое изменение — `SessionPhaseService.reconnect()`. Поля обоих экранов — один виджет `AppConnectionFieldsWidget`.
- **Причина на плашке.** Состояния 5.1, 5.2 и 5.4 несут `problem` рядом с `isOffline` / `isServerMismatch`; `AppNoticeStripWidget` говорит текст причины, когда он известен, иначе `noConnection`, а при `isServerMismatch` — текст `otherServer`. Текст причины берётся только из `ConnectionProblemText.text(l10n)` (`lib/presentation/helpers/connection_problem_text.dart`): одна причина не должна звучать на разных экранах по-разному. Для голденов у каждого из трёх экранов есть отладочный сценарий `turnOnTor`.

---

## 7. Общие виджеты `App*Widget` (stateless)

Три переиспользуемых stateless-виджета рендерят стандартные подсостояния; они живут в `lib/presentation/widgets/state/` рядом с плашками (`AppNoticeStripWidget`, `AppBannerShellWidget`) и индикатором связи. Используются внутри `switch (state)`. Все строки — из `context.l10n`, отступы — из `AppSpacingTokens` / `AppDimensionTokens`, цвета — из `Theme.of(context).colorScheme` (+ `NoxBrand`/`NoxScrims`/`NoxOpacity`); `context.appColors` — двухполевой каркас, в фичах не вызывается (см. `06-theming.md` §2).

### 7.1 `AppProgressWidget`

**Файл:** `lib/presentation/widgets/state/app_progress_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Centered loading state for `state.when(initializing: ...)` and first-page
/// pagination indicators. Wraps [AppSpinnerWidget] (`primary` on `surface`).
class AppProgressWidget extends StatelessWidget {
  const AppProgressWidget({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(child: AppSpinnerWidget(size: size));
  }
}
```

### 7.2 `AppErrorWidget`

**Файл:** `lib/presentation/widgets/state/app_error_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Error state: an error glyph + an optional message + an optional retry CTA.
class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({super.key, this.message, this.onTryAgain});

  final String? message;
  final VoidCallback? onTryAgain;

  static double get _iconSize => AppDimensionTokens.icon.illustration;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconWidget(NoxIcons.error, size: _iconSize, color: colorScheme.onSurfaceVariant),
            SizedBox(height: AppSpacingTokens.s16),
            Text(
              message ?? context.l10n.errorGeneralTitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (onTryAgain != null) ...[
              SizedBox(height: AppSpacingTokens.s16),
              FilledButton(onPressed: onTryAgain, child: Text(context.l10n.actionTryAgain)),
            ],
          ],
        ),
      ),
    );
  }
}
```

### 7.3 `AppEmptyContentWidget`

**Файл:** `lib/presentation/widgets/state/app_empty_content_widget.dart`

Пустое состояние списка по дизайну `EmptyState`: квадрат 132 с обводкой, в нём глиф Material Symbols 56 и две брендовые точки (бирюзовая сверху справа, золотая снизу слева), под ним заголовок и сообщение. Конструктор — `AppEmptyContentWidget({required SvgGenImage glyph, required String title, required String message})`: глиф, заголовок и текст даёт экран (`NoxIcons.*`, `context.l10n.*`). Размеры — `AppDimensionTokens.size.emptyArt`, `AppDimensionTokens.layout.messageMaxW`; цвета точек — `NoxBrand`.

> Конвенция нейминга: префиксуйте каждый переиспользуемый presentation-виджет `App` (`AppProgressWidget`, `AppErrorWidget`, `AppEmptyContentWidget`). Держите их stateless и single-purpose.

---

## 8. Сюрфейсинг ошибок — `showAppSnackBar` / `showAppBanner` (единственный канал)

Единственный канал транзиентных сообщений — две функции верхнего уровня в `lib/presentation/helpers/app_feedback_helper.dart`: `showAppSnackBar` (снэкбар) и `showAppBanner` (постоянный баннер сверху). Никогда не показывайте сырой текст исключения — в `text` идёт уже переведённая строка (`context.l10n`, §3.3). Для in-body error-ветки — `AppErrorWidget` (§7.2), для плашки «нет связи» на экране — `AppNoticeStripWidget` (§6.6).

```dart
// lib/presentation/helpers/app_feedback_helper.dart (signatures)

/// Transient feedback. The neutral palette and floating behaviour come from
/// `snackBarTheme`; only the error variant overrides to `errorContainer`/`onErrorContainer`.
void showAppSnackBar(BuildContext context, {required String text, String? actionLabel, VoidCallback? onAction, bool error = false});

/// Persistent banner: `surfaceContainer`, optional leading glyph, top of screen. The action
/// always dismisses the banner first, then runs [onAction] (default label `actionDismiss`).
void showAppBanner(BuildContext context, {required String text, SvgGenImage? icon, String? actionLabel, VoidCallback? onAction});
```

> Цвета берутся из `Theme.of(context).colorScheme` и `snackBarTheme` (`nox_component_themes.dart`), скругление — `NoxRadius.xs`; `context.appColors` здесь не участвует.

---

## 9. Доступность (Accessibility)

Новые интерактивные виджеты ОБЯЗАНЫ оборачивать свой интерактивный элемент в `Semantics` с осмысленным `label` и `button: true`:

```dart
Semantics(
  label: TextConstants.itemActionOpen,
  button: true,
  child: SomeTappableContainerUsingTokens(...),
)
```

Стоковые кнопки с текстом (`FilledButton` в `AppErrorWidget`, §7.2) несут семантику сами; `Semantics` нужен кастомным тапаемым контейнерам (так сделаны ячейки рельсы, §6.5), а действию из одной иконки — подсказка (`tooltip`) и имя для диктора. Цели касания — не меньше 48×48 при `textScale: 2.0`: это проверяют `test/presentation/widgets/accessibility_test.dart` и `test/presentation/pages/m1_settings_accessibility_test.dart`.

---

## 10. Поток Page ↔ BLoC ↔ Repository (резюме)

```
initState()                 _bloc = ItemListBloc()..add(ItemListEvent.initialize())
  → BaseBloc ctor           super(const ItemListState.initializing()); on<Initialize>(_onInitialize)
  → _onInitialize           emit(Initialized(pagingState: PagingState())); add(LoadItems(reset: true))
  → _onLoadItems            getIt<ItemRepository>().getItems(config:)
  → RepositoryResult<T>     result.hasData / result.match(onData:, onError:)
  → emit                    Initialized(items:, pagingState:, nextPage:, isLastPage:) | Error(exception:)
  → BlocConsumer            builder: state.when(initializing:, initialized:, error:)
  → виджеты                 AppProgressWidget | RefreshIndicator(PagedListView)/AppEmptyContentWidget | AppErrorWidget
  → побочные эффекты        listener (listenWhen по loadError) → showAppSnackBar(error: true) + loadErrorShown()
  → тап по элементу         Navigator.push(ItemDetailsPage.route(itemId:)) — со страницы, без блока
dispose()                   _bloc.close()
```

---

## Чеклист

После применения этого документа в проекте `nox_app` должно быть:

- [ ] `lib/presentation/base/base_bloc.dart` с `BaseBloc<E,S>` и `executeLogic` (понимать `'$e, $s'`-аргумент и тихий swallow при опущенном `onError`).
- [ ] `lib/presentation/pages/base/base_state_page.dart` с `BaseStatePage<T>` (`scaffoldKey`, реактивный `useDrawer`/`closeDrawer`, платформозависимый `buildAppBar()`).
- [ ] BLoC-trio на фичу: `*_bloc.dart` + `part`-связанные `*_event.dart` / `*_state.dart` — оба `@freezed sealed` unions, **без** `Equatable`, **без** `fromJson` (генерируется только `*.freezed.dart`).
- [ ] Подсостояния `Initializing` / `Initialized` / `Error` как `const factory`-конструкторы; производные значения — в `extension`-геттерах, не в теле `@freezed`.
- [ ] Переходы через сгенерированный `copyWith`; рендер тела — Dart 3 `switch (state)` с деструктуризацией (вызовов `.when(` в `lib/` нет; `state.when(...)` в снипетах читается как ветвление по подсостояниям, §5.3).
- [ ] BLoC резолвят репозитории и службы через `getIt<XxxRepository>()` / `getIt<XxxService>()` (доменные интерфейсы; `lib/data/` презентация не импортирует), хранят `StreamSubscription` в полях и отменяют в `close()`.
- [ ] BLoC потребляют `RepositoryResult<T>` через `match()` / `hasData` — никакого `result.data!` без guard'а.
- [ ] Побочные эффекты: статус в состоянии (enum-статус, поле-эффект или счётчик-тик) + `BlocListener` / `BlocConsumer` с `listenWhen` на странице; разовый эффект гасится событием (`navigationHandled()`, `loadErrorShown()`); стримов-эффектов нет (§5.6).
- [ ] Конкурентность: дефолт — stale-guard (перечитать `this.state` после `await`) + `debounceRestartable()` для поиска и проверки имени, `sequential()` для загрузок; продвинутый toolkit (epoch-guard + `debounce`/`debounceIf` + `executeLogic`) — для tree/representation BLoC.
- [ ] Пагинация — `PagingState`-in-bloc (v5); два пути контракта v0 через один `PagingStateExt.applyPage` (конец списка — `!meta.hasMore`, тотала на проводе нет): страничный (`page`/`page_size`, `nextPage` считается клиентски) для списка чатов и seq-курсорный (`before_seq`/`limit`, `oldestLoadedSeq` в стейте, без `PagedListView`) для истории сообщений; детали в `07-pagination.md`.
- [ ] Страница: `static Route<T> route(...)` с именем маршрута прямо в `RouteSettings(name: '/…')` (константы `routeName` нет), `State extends BaseStatePage<T>`, `late final` BLoC в `initState()` и `close()` в `dispose()`, `BlocProvider` + `BlocConsumer` (`listenWhen` для эффектов) + `switch (state)`; pull-to-refresh — стоковый `RefreshIndicator` вокруг `PagedListView`, `onRefresh` ждёт ответа блока на его стриме. **BLoC обязателен для ЛЮБОЙ навигируемой страницы (`route()`) — даже logic-less (минимальный trio или value-BLoC, Принцип 5.1); переиспользуемые виджеты BLoC не требуют.**
- [ ] App-shell: `AppRootBloc` (`@freezed abstract` одно состояние с `themeMode`, app-state-спиной и вопросом о новом устройстве + `copyWith`, **не** trio), `AppRoot` (`GlobalKey<NavigatorState>`, тема из `AppRootBloc`, `home: const SplashPage()` и смена корневого маршрута по app-state).
- [ ] Адаптивная оболочка — width-driven `LayoutBuilder` на `Constants.railBreakpoint = 840` (а **не** `Platform`). Живая — `TabBarShell`: mobile — `AppBottomBarWidget` + centerDocked `AppCreateFabWidget`; desktop — `AppWindowTitlebarWidget` над рукописной `AppNavigationRailWidget` (80dp, аватар аккаунта внизу, без FAB; `+` — в заголовке панели чатов); ровно 2 destination'ы (`Chats`/`Settings`), вкладки живут в `Stack` и переживают переключение, single-window; корректна на всех пяти таргетах (§6.5). Скелетный `AppShell` (`BottomAppBar` / `NavigationRail` с leading `+` FAB, `IndexedStack`) не смонтирован.
- [ ] UI-скейл: `MaterialApp` обёрнут в `ScreenUtilInit(designSize: Constants.designSize` = `Size(360, 779)`, `fontSizeResolver: AppTextStyleTokens.fontSizeResolver)` + двойной `MediaQuery` (`TextScaler.noScaling` снаружи, `TextScaler.linear(1.0)` внутри `builder`) — OS-масштаб шрифта отключён, размеры выводятся из дизайн-скейла (§6.2; механизм — `06-theming.md` §3.2).
- [ ] Системный overlay: `MaterialApp.builder` ставит `AnnotatedRegion<SystemUiOverlayStyle>` с `AppOverlayStyleTokens.of(colorScheme)` активной темы — статус-бар и навигационная панель; `SplashPage` — свой `AppOverlayStyleTokens.splash`; `AppBar` задаёт стиль поверх сам; `SystemChrome.setSystemUIOverlayStyle` и сырого `SystemUiOverlayStyle` в `lib/presentation/` нет (`06-theming.md` §6.1).
- [ ] `main.dart` в `runZonedGuarded`, `configureDependencies(env)` → `getIt.allReady()` → конфиг и уборка ключей → `appStateRepository.holdUntil(_start())` → `runApp(AppRoot)` (полностью — `02-dependency-injection.md` §10).
- [ ] Общие виджеты `AppProgressWidget` / `AppErrorWidget` / `AppEmptyContentWidget` в `lib/presentation/widgets/state/` (stateless, строки из `context.l10n`, spacing из `AppSpacingTokens`/`AppDimensionTokens`).
- [ ] `showAppSnackBar` / `showAppBanner` (`helpers/app_feedback_helper.dart`) — единственный канал транзиентных сообщений (цвета из `colorScheme`/`snackBarTheme`); `AppErrorWidget` — для in-body error-ветки.
- [ ] `Semantics(label:, button: true)` на кастомных тапаемых виджетах; `tooltip` на действиях из одной иконки; цели касания ≥ 48×48.
- [ ] Гранулярные ребилды — per-slice `BlocBuilder` с `buildWhen` на value-equality Freezed; неизменяемая копировальная дисциплина (всегда `copyWith` / новая фабрика).
- [ ] Нет `desktop_multi_window` / `WindowsConfig` / IPC-маршрутизации; нет голых `Color`/`EdgeInsets`/`TextStyle` в коде фич.
- [ ] `fvm flutter analyze` проходит для `lib/`.

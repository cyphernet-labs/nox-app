# 05 — Слой представления (BLoC)

> **Назначение:** задать канонический скелет слоя представления (`lib/presentation/`) для приложения `nox_app`: Freezed-BLoC (sealed State/Event unions), тонкий `BaseBloc<E,S>`, `BaseStatePage<T>`, паттерн страницы, app-shell (`AppRoot` + `AppRootBloc` + адаптивный `AppShell`), каналы side-эффектов, дисциплину конкурентности и потребление `RepositoryResult<T>`.
> **Когда читать:** когда вы создаёте любой экран, BLoC или app-shell-виджет, либо проводите связку «page → BLoC → repository». Первая реальная фича — список чатов (открытые общие пространства) — строится ровно по этому паттерну: это серверный, network-only пагинированный список (carve-out network-only применим к нему напрямую).
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
- Рендер тела страницы через `state.when(initializing:, initialized:, error:)` — теперь это **сгенерированный** Freezed-`when()`, а не рукописный.
- `BaseStatePage<T>` (scaffoldKey, реактивный `useDrawer`/`closeDrawer` с отложенным `setState`, платформозависимый `buildAppBar()`).
- Паттерн страницы: `StatefulWidget` + `static const String routeName` + `static Route route()` (`MaterialPageRoute` + `RouteSettings(name:)`), BLoC в `initState`, side-эффект-подписки в `initState` и отмена в `dispose`.
- App-shell: `AppRoot` (хостит `MaterialApp` + `GlobalKey<NavigatorState>`, тема из `AppRootBloc`) + `AppRootBloc` (одно конкретное состояние с `copyWith`, **не** trio).
- `RepositoryResult<T>` потребляется через `match()` / `hasData` — **никогда** `result.data!`.

Добавлено в этом подходе: `@freezed sealed` State/Event, тонкий `BaseBloc<E,S>` с `executeLogic`, логика в extension-геттерах, продвинутый toolkit конкурентности (epoch-guard + `debounce`/`debounceIf`).

Конвенция нейминга для unions: **`sealed`** для multi-variant unions (State, Event), **`abstract`** для single-variant value-объектов — например, `AppRootState` объявляется как `@freezed abstract class` с одним конструктором (одно состояние, не trio; `copyWith` генерируется Freezed), см. §6.1.

---

## 1. Раскладка и конвенции слоя

Слой представления живёт в `lib/presentation/`. Это единственный слой, импортирующий Flutter-виджеты для экранов, держащий BLoC'и и зависящий от `lib/domain/` (никогда напрямую от `lib/data/`). Импорты — полные `package:nox_app/...`, относительные `../` запрещены (кроме `part`-директив внутри trio).

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
│   ├── text_constants.dart                   # все строки для пользователя
│   └── bloc_concurrency/                     # FUTURE: продвинутые transformer'ы (§5.8)
│       ├── debounce.dart                      #   debounce transformer (advanced)
│       └── debounce_if.dart                   #   debounceIf transformer (advanced)
└── presentation/
    ├── app/
    │   ├── app_root.dart                     # корневой MaterialApp + глобальная навигация
    │   ├── bloc/
    │   │   ├── app_root_bloc.dart
    │   │   ├── app_root_event.dart
    │   │   └── app_root_state.dart
    │   └── widgets/
    │       └── app_shell.dart                # адаптивная оболочка (mobile bar / desktop rail), §6.5
    ├── base/
    │   └── base_bloc.dart                     # BaseBloc<E,S> с executeLogic
    ├── helpers/                              # FUTURE: alert_dialog_helper.dart — канал snackbar'ов (§8)
    ├── extension/                            # FUTURE: расширения презентации
    ├── pagination/
    │   └── paging_state_ext.dart            # PagingStateExt.applyPage (§5.5, 07-pagination.md)
    ├── pages/
    │   ├── base/
    │   │   └── base_state_page.dart          # абстрактный State<T> base
    │   ├── placeholder/                      # скелетные заглушки вкладок
    │   │   ├── chats_placeholder_page.dart
    │   │   └── settings_placeholder_page.dart
    │   └── item_list_page/                   # Item-харнесс верификации (mock-данные, FR-013)
    │       ├── item_list_page.dart
    │       └── bloc/
    │           ├── item_list_bloc.dart        # @freezed part-host, handlers, transformers
    │           ├── item_list_event.dart       # @freezed sealed Event union (part of)
    │           └── item_list_state.dart       # @freezed sealed State union + extensions (part of)
    └── widgets/                              # FUTURE: App*Widget (AppProgressWidget/AppErrorWidget/...)
```

> **Что реально есть в скелете (Feature-001).** Сейчас в `lib/presentation/` присутствуют: `app/app_root.dart`, `app/bloc/` (`AppRootBloc`-trio), `app/widgets/app_shell.dart`, `base/base_bloc.dart`, `pages/base/base_state_page.dart`, `pages/placeholder/` (2 заглушки; `ChatsPlaceholderPage` сейчас не подключён — Chats-вкладка ведёт на `ItemListPage`-харнесс), `pages/item_list_page/` (страница + BLoC-trio), `pagination/paging_state_ext.dart`. Директории `helpers/`, `extension/`, `widgets/` и `general/bloc_concurrency/` пока **отсутствуют** — это канонические целевые места, заводимые с первой реальной фичей (см. сноску о реализованном vs полном паттерне в §3.5). Токены spacing живут в `lib/design/app_spacing_tokens.dart`, `app_colors.dart` — в `lib/design/theme/` (см. `06-theming.md`).

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
- BLoC получают репозитории через `getIt<XxxRepository>()`; `StreamSubscription` хранятся в полях и отменяются в `close()`.
- Все строки для пользователя — из `TextConstants` (в `lib/general/text_constants.dart`); ни одной голой строки в виджетах.
- Цвета/отступы/типографика — только через токены / `context.appColors` (см. `06-theming.md`); ни одного голого `Color` / `EdgeInsets` / `TextStyle` в коде фич.

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

  /// Загрузить страницу: reset=true — первая страница / сброс, false — load-more.
  const factory ItemListEvent.loadItems({
    required bool reset,
    Completer<void>? completer,
  }) = LoadItems;

  /// Pull-to-refresh: несёт Completer, который bloc завершает.
  const factory ItemListEvent.refreshRequested({
    required Completer<void> completer,
  }) = RefreshRequested;

  /// Изменение строки поиска (debounce/restartable на уровне handler'а).
  const factory ItemListEvent.updateSearchQuery({
    required String value,
  }) = UpdateSearchQuery;

  /// Пользователь тапнул элемент — навигация уйдёт через side-effect-стрим.
  const factory ItemListEvent.showItemDetails({
    required String itemId,
  }) = ShowItemDetails;
}
```

> На Event union **нет** `@Default`/`fromJson`. `Completer<void>?` — обычное опциональное поле; значение по умолчанию — `null`.

### 3.2 State — `@freezed sealed` union + extension-геттеры

Подсостояния — это `const factory`-конструкторы `Initializing` / `Initialized` / `Error`. Вся производная логика (`isAnyInProgress` и т.п.) — в `extension`-геттере на конкретном варианте, **не** в теле `@freezed`.

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
    @Default(0) int total,
    @Default(GetItemsConfig.defaultPage) int nextPage,
    @Default(false) bool isLastPage,
    @Default(false) bool loadingInProgress,
    @Default(false) bool refreshInProgress,
    @Default('') String searchQuery,
  }) = Initialized;

  /// Что-то упало при init или операции.
  const factory ItemListState.error({
    BaseRepositoryException? exception,
  }) = Error;
}

/// Производные значения — в extension, не в теле @freezed.
extension InitializedExt on Initialized {
  bool get isAnyInProgress => loadingInProgress || refreshInProgress;

  bool get isEmpty => items.isEmpty && !loadingInProgress;
}
```

> Это **полный (aspirational) worked-example** State реальной фичи (с `searchQuery`/`refreshInProgress`); шипнутый Item-харнесс — лёгкое подмножество с extension `ItemListStateExt` (геттеры `pagedItems`/`hasMore`) и без полей поиска/refresh. Сверка скелет ↔ полный паттерн — в §3.5.

Ключевые отличия от исходного подхода, которые нужно держать в голове:

- **`copyWith` сгенерирован Freezed** — рукописный `copyWith()` на каждом варианте больше не нужен.
- **`when()` сгенерирован Freezed** — прежний рукописный exhaustive-matcher удалён.
- **Равенство — глубокое value-equality от Freezed** — `props`-список из `Equatable` больше не пишется. Именно это глубокое равенство разблокирует гранулярные ребилды (§5.4).
- **`PagingState<String, ItemModel>`** — ключ `K` у нас `String` = id элемента (one-item-per-page: ключи — это id элементов; OFFSET-флейвор отслеживается через `PageMetadata.nextPage` (`int`) в state, а не через `K`). См. §5.5 и `07-pagination.md`.

> **Очистка nullable-поля через Freezed `copyWith`.** Сгенерированный `copyWith({Type? field})` не различает «не передано» и «передано `null`». Для полей, которые надо явно сбрасывать в `null`, в Freezed используйте `copyWith(field: null)` напрямую при опущенном объекте — Freezed-`copyWith` корректно ставит `null`, потому что генерирует sentinel-логику. Если поле обязательно nullable и должно очищаться вместе с другими, эмитьте новый вариант через фабрику `ItemListState.initialized(...)`. (Прежний хак `clearXxx`-флага на Freezed не нужен.)

### 3.3 BLoC — handlers, side-эффект-стримы, stale-guard

BLoC:

- Вызывает `super(const ItemListState.initializing())` и регистрирует один `on<Event>(_handler)` на событие в конструкторе.
- Резолвит репозитории через `getIt<XxxRepository>()`.
- Search использует `transformer: restartable()` из `bloc_concurrency` (дефолт для поиска).
- После каждого `await` **перечитывает `this.state`** и выходит, если запрос устарел (stale-guard).
- Навигация/snackbar'ы уходят через `PublishSubject`-стримы (rxdart), **никогда** через state (см. §5.6).
- Потребляет `RepositoryResult<T>` через `match()` / `hasData` — **никогда** `result.data!`.

**Файл:** `lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart`

```dart
import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

part 'item_list_event.dart';
part 'item_list_state.dart';
part 'item_list_bloc.freezed.dart';

class ItemListBloc extends BaseBloc<ItemListEvent, ItemListState> {
  ItemListBloc() : super(const ItemListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadItems>(_onLoadItems, transformer: sequential());
    on<RefreshRequested>(_onRefreshRequested);
    on<UpdateSearchQuery>(_onUpdateSearchQuery, transformer: restartable());
    on<ShowItemDetails>(_onShowItemDetails);
  }

  final _itemRepository = getIt<ItemRepository>();

  final _errorMessagesController = PublishSubject<String>();
  final _navigateToDetailsController = PublishSubject<ItemModel>();

  Stream<String> get errorMessages => _errorMessagesController.stream;

  Stream<ItemModel> get navigateToDetails => _navigateToDetailsController.stream;

  @override
  Future<void> close() async {
    await _errorMessagesController.close();
    await _navigateToDetailsController.close();
    await super.close();
  }

  FutureOr<void> _onInitialize(Initialize event, Emitter<ItemListState> emit) async {
    emit(ItemListState.initialized(pagingState: PagingState<String, ItemModel>()));
    add(const ItemListEvent.loadItems(reset: true));
  }

  FutureOr<void> _onLoadItems(LoadItems event, Emitter<ItemListState> emit) async {
    final state = this.state;
    if (state is! Initialized || state.loadingInProgress) return;

    emit(state.copyWith(loadingInProgress: true, refreshInProgress: event.reset));

    final query = state.searchQuery;
    final isFirstPage = event.reset;
    final config = isFirstPage
        ? GetItemsConfig.firstPage(search: query.isEmpty ? null : query)
        : GetItemsConfig.nextPage(page: state.nextPage, search: query.isEmpty ? null : query);

    final result = await _itemRepository.getItems(config: config);

    // stale-guard: state мог измениться за время await.
    final updated = this.state;
    if (updated is! Initialized || updated.searchQuery != query) return;

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
        total: meta.total,
        nextPage: r.nextPage ?? updated.nextPage,
        isLastPage: meta.nextPage == null,
        loadingInProgress: false,
        refreshInProgress: false,
      ));
    } else if (isFirstPage && updated.items.isEmpty) {
      emit(ItemListState.error(exception: result.exception));
    } else {
      // Не первая страница: оставляем уже показанные элементы, показываем snackbar.
      emit(updated.copyWith(
        pagingState: updated.pagingState.copyWith(error: result.exception),
        loadingInProgress: false,
        refreshInProgress: false,
      ));
      _errorMessagesController.add(_translate(result.exception));
    }

    event.completer?.complete();
  }

  FutureOr<void> _onRefreshRequested(RefreshRequested event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is Initialized && !state.isAnyInProgress) {
      add(ItemListEvent.loadItems(reset: true, completer: event.completer));
    } else if (!event.completer.isCompleted) {
      event.completer.complete();
    }
  }

  FutureOr<void> _onUpdateSearchQuery(UpdateSearchQuery event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is! Initialized) return;
    final query = event.value.trim();
    if (state.searchQuery == query) return; // (UpdateSearchQuery — пример полной фичи, см. §3.5)
    emit(state.copyWith(
      items: const [],
      pagingState: PagingState<String, ItemModel>(),
      searchQuery: query,
    ));
    add(const ItemListEvent.loadItems(reset: true));
  }

  void _onShowItemDetails(ShowItemDetails event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is! Initialized) return;
    final match = state.items.firstWhereOrNull((e) => e.id == event.itemId);
    if (match != null) _navigateToDetailsController.add(match);
  }

  String _translate(BaseRepositoryException? exception) {
    if (exception is RepositoryException) {
      switch (exception) {
        case RepositoryException.connection:
          return TextConstants.errorConnection;
        case RepositoryException.unauthenticated:
        case RepositoryException.authentication:
          return TextConstants.errorAccess;
        case RepositoryException.notFound:
          return TextConstants.errorNotFound;
        case RepositoryException.unknown:
        case RepositoryException.internal:
          return TextConstants.errorGeneralMessage;
      }
    }
    return TextConstants.errorGeneralMessage;
  }
}
```

Заметки по реализации:

- `result.data!` здесь допустим **только** под защитой `if (result.hasData)` — это не нарушение правила «никогда `result.data!`», а распаковка record-кортежа `(List<ItemModel>, PageMetadata)` после явной проверки. Альтернативный, более чистый способ — `result.match(...)` (см. §5.7).
- `PagingStateExt.applyPage` — переиспользуемое расширение из `07-pagination.md`; не реализуйте склейку страниц вручную в каждом BLoC.
- `_translate` предпереводит исключение в строку **до** показа snackbar'а — никогда не показываем сырой текст исключения (правило AlertDialogHelper, §8).

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

> **Этот пустой trio — ОБЯЗАТЕЛЬНЫЙ минимум для logic-less навигируемой страницы, а не опция** (Принцип 5.1, [08](08-conventions-and-constitution.md)). Страница без бизнес-логики берёт именно его (или одновариантный value-BLoC §6.1), но **не остаётся вовсе без BLoC**. Переиспользуемые виджеты (ненавигируемые компоненты) BLoC не требуют.

### 3.5 Что реализовано в скелете vs полный паттерн

Worked-example выше (§3.1–§3.3) — это **полный (aspirational) канон**: он учит поиску, pull-to-refresh, side-эффект-стримам и конкурентности, которые понадобятся реальным фичам (например, списку чатов). Шипнутый в Feature-001 `Item`-харнесс — сознательно **лёгкое подмножество** (verification-only, FR-013; см. [11-scaffolding-plan.md](11-scaffolding-plan.md)). Отличия скелета от полного паттерна:

- **Event** (`item_list_event.dart`) — только `initialize()` + `loadItems({@Default(false) bool reset})`. Нет `refreshRequested` / `updateSearchQuery` / `showItemDetails`.
- **State** (`item_list_state.dart`) — поля `pagingState` (`required`, первым), `items`, `nextPage` (`@Default(GetItemsConfig.defaultPage)`, **1-based**), `isLastPage`, `total`, `loadingInProgress`. Нет `refreshInProgress` / `searchQuery`. Extension — `ItemListStateExt on ItemListState` с геттерами `pagedItems` / `hasMore` (а не `InitializedExt.isAnyInProgress`/`isEmpty` из полного примера).
- **BLoC** (`item_list_bloc.dart`) — `on<LoadItems>(_onLoadItems, transformer: sequential())`; тело завёрнуто в `executeLogic(onError:)`, ветвление через `result.match<void>(onData:, onError:)`. Нет rxdart `PublishSubject`-стримов, нет `_translate`, нет `restartable()`-поиска.
- **`ItemModel`** (`domain/model/item/item_model.dart`) — поля `id`, `name`, `required String? description`, `required ItemStatus status`, `required DateTime createdAt`; extension-геттеры `isArchived` + `displayName` (см. `03-domain-layer.md`).
- **Страница-харнесс как tab-body.** Шипнутый `ItemListPage` рендерится телом вкладки внутри `AppShell` (без собственного `Scaffold`), поэтому `_ItemListPageState extends State<ItemListPage>`, а **не** `BaseStatePage<ItemListPage>`. `BaseStatePage<T>` (§4) обязателен для **навигируемых** страниц, владеющих собственным `Scaffold` (с `routeName`/`route()`) — именно такую каноническую форму показывает worked-example §5. Placeholder-страницы (`ChatsPlaceholderPage`/`SettingsPlaceholderPage`) — `StatelessWidget` по той же причине (тело вкладки без Scaffold).

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

- `static const String routeName` — строковый id для реестра маршрутов.
- `static Route route(...)` — фабрика, возвращающая `MaterialPageRoute` с `RouteSettings(name: routeName)`.
- `State`, расширяющий `BaseStatePage<T>` и владеющий `late final` BLoC.
- BLoC создаётся в `initState()` с `..add(const ItemListEvent.initialize())`, закрывается в `dispose()`.
- Side-эффект-подписки создаются в `initState()`, отменяются в `dispose()`.
- `build()` оборачивает `BlocProvider` + `BlocBuilder` и рендерит через `state.when(...)`.

> **Это не опционально (Принцип 5.1, [08](08-conventions-and-constitution.md)).** ЛЮБАЯ навигируемая страница (есть `routeName` + `route()`) **обязана** владеть собственным BLoC. Если бизнес-логики нет — страница всё равно получает минимальный BLoC: трио `Initializing`/`Initialized`/`Error` из §3.4 либо одновариантный value-BLoC как `AppRootBloc` (§6.1). Непавигируемые переиспользуемые **виджеты** (`lib/presentation/widgets/`, page-private `widgets/`) BLoC **не требуют** — их состоянием управляет страница-владелец.

### 5.1 Worked example

**Файл:** `lib/presentation/pages/item_list_page/item_list_page.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/design/theme/app_colors.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/helpers/alert_dialog_helper.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/item_details_page/item_details_page.dart';
import 'package:nox_app/presentation/pages/item_list_page/bloc/item_list_bloc.dart';
import 'package:nox_app/presentation/pages/item_list_page/widgets/item_tile_widget.dart';
import 'package:nox_app/presentation/widgets/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/app_progress_widget.dart';

class ItemListPage extends StatefulWidget {
  const ItemListPage({super.key});

  static const String routeName = '/items';

  static Route route() => MaterialPageRoute(
        builder: (_) => const ItemListPage(),
        settings: const RouteSettings(name: routeName),
      );

  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends BaseStatePage<ItemListPage> {
  late final ItemListBloc _bloc;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<ItemModel>? _navSub;

  @override
  void initState() {
    super.initState();
    _bloc = ItemListBloc()..add(const ItemListEvent.initialize());
    _errorSub = _bloc.errorMessages.listen((message) {
      if (mounted) AlertDialogHelper.showErrorSnackBar(context, message);
    });
    _navSub = _bloc.navigateToDetails.listen((item) {
      if (mounted) Navigator.of(context).push(ItemDetailsPage.route(itemId: item.id));
    });
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _errorSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ItemListBloc>.value(
      value: _bloc,
      child: BlocBuilder<ItemListBloc, ItemListState>(
        builder: (context, state) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: Scaffold(
              key: scaffoldKey,
              appBar: AppBar(title: const Text(TextConstants.itemListTitle)),
              body: state.when(
                initializing: () => const AppProgressWidget(),
                initialized: (initialized) => _buildList(context, initialized),
                error: (_) => AppErrorWidget(
                  onTryAgain: () => _bloc.add(const ItemListEvent.initialize()),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, Initialized state) {
    if (state.isEmpty) return const AppEmptyContentWidget();

    return PagedListView<String, ItemModel>.separated(
      state: state.pagingState,
      fetchNextPage: () => _bloc.add(const ItemListEvent.loadItems(reset: false)),
      builderDelegate: PagedChildBuilderDelegate<ItemModel>(
        itemBuilder: (_, item, __) => ItemTileWidget(
          key: ValueKey(item.id),
          item: item,
          onTap: () => _bloc.add(ItemListEvent.showItemDetails(itemId: item.id)),
        ),
        firstPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
        newPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
        noItemsFoundIndicatorBuilder: (_) => const AppEmptyContentWidget(),
        firstPageErrorIndicatorBuilder: (_) => AppErrorWidget(
          onTryAgain: () => _bloc.add(const ItemListEvent.loadItems(reset: true)),
        ),
      ),
      separatorBuilder: (_, __) => SizedBox(height: AppSpacingTokens.s8),
    );
  }

  Future<void> _refresh() {
    final completer = Completer<void>();
    _bloc.add(ItemListEvent.refreshRequested(completer: completer));
    return completer.future;
  }
}
```

### 5.2 Страница с параметрами

Если странице нужны конструкторные параметры — добавляйте их и в конструктор, и в `route()`:

```dart
class ItemDetailsPage extends StatefulWidget {
  const ItemDetailsPage({super.key, required this.itemId});

  final String itemId;

  static const String routeName = '/item-details';

  static Route route({required String itemId}) => MaterialPageRoute(
        builder: (_) => ItemDetailsPage(itemId: itemId),
        settings: const RouteSettings(name: routeName),
      );

  @override
  State<ItemDetailsPage> createState() => _ItemDetailsPageState();
}
```

> Конвенция: detail-страницы — это отдельные плоские папки `lib/presentation/pages/<page>_details_page/` рядом с родительской страницей, каждая со своим BLoC-trio.

### 5.3 Рендер тела через `when()` / `map()` и Dart 3 `switch`

Базовый способ — сгенерированный Freezed-`when()` (как в `build()` выше): тело страницы — это `state.when(initializing:, initialized:, error:)`. Так исходная конструкция `body: state.when(...)` переносится без изменений (но теперь `when` сгенерирован, а не рукописный).

Для чистых **виджетов-проекций** (которые только проецируют состояние и не владеют BLoC) предпочтителен Dart 3 exhaustive `switch` с деструктуризацией — он короче и компилятор гарантирует полноту:

```dart
Widget _body(ItemListState state) {
  return switch (state) {
    Initializing() => const AppProgressWidget(),
    Initialized(:final items) when items.isEmpty => const AppEmptyContentWidget(),
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
// Перерисовываем только индикатор «refresh в процессе», а не весь список.
BlocBuilder<ItemListBloc, ItemListState>(
  buildWhen: (prev, curr) {
    if (prev is! Initialized || curr is! Initialized) return prev.runtimeType != curr.runtimeType;
    return prev.refreshInProgress != curr.refreshInProgress;
  },
  builder: (context, state) {
    final inProgress = state is Initialized && state.refreshInProgress;
    return inProgress ? const LinearProgressIndicator() : const SizedBox.shrink();
  },
);
```

> Это работает **только** благодаря неизменяемой копировальной дисциплине (всегда `copyWith` / новая фабрика, никогда не мутировать коллекцию состояния на месте) — иначе identity меняется непредсказуемо и `buildWhen` ломается. Подробный разбор гранулярных ребилдов для дерева (per-node `BlocBuilder`, keyed by `getNodeState(parentApiName:)`) — см. §6 case study territories tree.

### 5.5 Пагинация — `PagingState`-in-bloc (v5)

Проект на **v5 `PagingState` API** пакета `infinite_scroll_pagination ^5.1.1`: BLoC строит неизменяемый `PagingState<PageKey, Item>` внутри `Initialized`; виджет потребляет его через `PagedListView(state:, fetchNextPage:)`. **Нет** widget-owned `PagingController`, нет `addPageRequestListener`. Учёт страниц живёт в состоянии BLoC. Дефолтный флейвор — **OFFSET** (`PageMetadata{int? nextPage, int total}`), страницы **1-based** (`GetItemsConfig.defaultPage = 1`, `hasMore = (page*pageSize) < total`, `nextPage = hasMore ? page+1 : null`); CURSOR-альтернатива (`CursorPaginationMetadata{String? nextCursor}`) задокументирована как альтернатива. Конкретный контракт пагинации списка чатов фиксируется позже вместе с бэкендом NOX (бэкенд/протокол NOX ещё не выбран). Полный контракт — `PagingStateExt.applyPage`, error-builder'ы v5, CURSOR-альтернатива — в `07-pagination.md`. Здесь — только связка: BLoC кладёт `PagingState` в `Initialized`, страница рендерит `PagedListView`, `result.exception` прокидывается в `pagingState.error` для v5-error-builder'ов.

### 5.6 Side-эффекты — три способа, и когда что

Транзиентные эффекты (навигация, snackbar) **не** живут в состоянии по умолчанию. Три варианта:

| Способ | Когда использовать |
|---|---|
| **rxdart `PublishSubject` стримы** (`errorMessages` / `navigateToDetails`) — **ДЕФОЛТ** | Транзиентная навигация/snackbar, которые не должны переживать ребилд. Самое чистое разделение «эффект ≠ представление». Producer: `_controller.add(...)`; consumer: подписка в `initState`, отмена в `dispose`. |
| **State-carried one-shot флаг** (producer ставит флаг, clear-event потребляет его в post-frame) | Эффект, который **обязан пережить ребилд** или является частью представления (например, `autoExpandNodeApiName` — автораскрытие узла после вставки). Producer: `emit(state.copyWith(flag: ...))`; consumer в build: `if (state.flag == ...) WidgetsBinding.instance.addPostFrameCallback((_) { ...; _bloc.add(const ClearFlagEvent()); });`. **Обязательно очищать** флаг, иначе он повторно срабатывает на каждом ребилде. |
| **`BlocListener` + `listenWhen`** | Когда эффект естественно привязан к переходу конкретного поля состояния и удобно держать его в дереве рядом с виджетом (навигация по изменению `selectedItem`). |

Пример `BlocListener` (третий вариант — навигация как побочный эффект перехода состояния, без `build`):

```dart
BlocListener<ItemListBloc, ItemListState>(
  listenWhen: (prev, curr) =>
      prev is Initialized && curr is Initialized && prev.searchQuery != curr.searchQuery,
  listener: (context, state) {
    // реакция на смену поискового запроса
  },
  child: /* ... */,
);
```

> **Дефолт нашего проекта** — `PublishSubject`-стримы (как в `ItemListBloc` §3.3). State-carried паттерн применяйте только для эффектов, переживающих ребилд; `BlocListener` — когда эффект логически привязан к одному полю и удобнее держать его в дереве.

### 5.7 Потребление `RepositoryResult<T>` — `match()` / `hasData`, никогда `data!`

`RepositoryResult<T>` (см. `03-domain-layer.md`) — это `@freezed` с data-XOR-exception. Потребляйте через `match<R>(onData:, onError:)` или guard `result.hasData`; **никогда** не пишите `result.data!` без предшествующего `hasData`-guard'а:

```dart
final result = await _itemRepository.getItems(config: config);
result.match<void>(
  onData: (page) {
    final (items, meta) = page;
    final current = this.state;
    if (current is Initialized) emit(current.copyWith(items: items, total: meta.total));
  },
  onError: (exception) => emit(ItemListState.error(exception: exception)),
);
```

### 5.8 Конкурентность — дефолт и продвинутый toolkit

**ДЕФОЛТ (плоские списки, поиск).** Два инструмента:

1. **stale-guard** — после каждого `await` перечитать `this.state` и выйти, если контекст (например, `searchQuery`) изменился. Уже показано в `_onLoadItems` (§3.3).
2. **`restartable()`** из `bloc_concurrency` для поиска — новый поисковый event **отменяет** предыдущий in-flight handler. Регистрируется как `on<UpdateSearchQuery>(_handler, transformer: restartable())`.

**ПРОДВИНУТЫЙ toolkit (representation/tree BLoC, загружающие много узлов конкурентно):**

- **epoch-guard** — поле `int _epoch = 0`; на `reset`-событии `++_epoch` и захват нового значения, на не-reset-загрузке — захват текущего без инкремента. Захваченный `myEpoch` перепроверяется на входе, после reset-emit и (критично) после единственного network-`await` через `_isStaleRequest(myEpoch) => epoch != _epoch`. Каждый reset разом инвалидирует все прежние in-flight загрузки.
- **`debounce` / `debounceIf` transformers** (300 мс, на rxdart) — `debounce` через `switchMap` (новый event отменяет предыдущий handler), `debounceIf((e) => e.reset, 300ms)` разбивает поток по предикату: `reset == true` дебаунсятся, `reset == false` проходят мгновенно (через `asyncExpand`, без отмены).
- **`BaseBloc.executeLogic`** — оборачивает тело async-handler'а; `onError` эмитит терминальный `Error` (или опускается для фоновых загрузок, см. §2).

> **Case study (territories tree).** Дерево хранится в state плоским нормализованным `Map<String?, NodeState>` (ключ — id родителя, `null` = корень); UI — чистая проекция этого map. Каждый узел несёт свой `LoadingState` + `cursor`, поэтому два узла на разной глубине грузятся одновременно без коллизий. `reset`-событие на смене модели/поиска делает `++_epoch` и стирает дерево; epoch-guard после `await` отбрасывает устаревшие ответы (старая in-flight-загрузка не дописывает элементы прежней модели в текущее дерево). `debounceIf((e) => e.reset)` дебаунсит ресеты, но пропускает «load more» мгновенно. Гранулярные ребилды — per-node `BlocBuilder` с `buildWhen`, сравнивающим `getNodeState(parentApiName: widget.item.apiName)` по value-equality Freezed: загрузка одного узла перерисовывает **только** его тайл. Все хирургические мутации (insert/remove/update/move) патчат map на месте через `copyWith` + клонирование коллекций — `State`-объект, достижимый до `emit`, никогда не мутируется. Этот паттерн — для деревьев и сложных представлений; для плоского списка чатов достаточно дефолтного toolkit'а (stale-guard + `restartable()`).

---

## 6. App-shell — `AppRoot` + `AppRootBloc`

App-shell хостит `MaterialApp`, подаёт тему из `AppRootBloc` и ставит home — адаптивную оболочку `AppShell` (§6.5; в скелете `home: const AppShell()`). Навигация внутри фичи — обычный `Navigator.of(context).push(<Page>.route(...))`. Shell держит `GlobalKey<NavigatorState>` для возможных глобальных swap'ов маршрута (например, splash → login → home, если позже понадобится auth-флоу).

> **Навигационная модель NOX — 3-элементный нижний бар (mobile) / `NavigationRail` (desktop).** Продуктовая оболочка NOX — `Chats`-вкладка, центральный docked `+` FAB (создание чата, виден на обеих вкладках) и `Settings`-вкладка; отдельного profile-экрана нет (profile-подобные пункты живут в Settings). Это **size-driven** адаптивная оболочка `AppShell`, единая для всех пяти таргетов — полный канон в §6.5. На этапе скелета (Feature-001) обе вкладки и харнесс `Item` (§3–§5) подключаются в `AppShell.body`; `+` — no-op (см. §6.5).

> **Принцип 5.1 для оболочки.** Любая навигируемая страница обязана владеть собственным BLoC (минимальный trio §3.4 или одновариантный value-BLoC §6.1; переиспользуемые виджеты — нет). Это касается и временной/статичной home: даже заглушка получает минимальный BLoC, а не остаётся без него. **Код-расхождение скелета:** текущий `AppShell` — обычный `StatefulWidget` **без** BLoC (выбранная вкладка `_index` хранится в локальном `setState`), а страницы-плейсхолдеры (`ChatsPlaceholderPage` / `SettingsPlaceholderPage`) — `StatelessWidget` без BLoC. Это сознательное упрощение скелета (наряду со «статичной home без BLoC»), которое снимается при появлении реальных фич: состояние выбранной вкладки переезжает в `AppRootBloc` (одно конкретное состояние с `copyWith`, §6.1), а вкладки получают собственные страницы с BLoC.

> **Обработка входящих ссылок.** `AppRoot` — это место, где подписываются на `DeepLinkRepository.watchDeepLink()` и откуда `AppRootBloc` маршрутизирует deep / universal links (`GlobalKey<NavigatorState>` для навигации без `BuildContext`). Полный механизм (пайплайн `app_links` → парсинг → типизированная модель → dispatch-table, нативная интеграция, `ValidateDeepLinkPage`) — в [13-deep-links.md](13-deep-links.md). Здесь shell остаётся минимальным; deep-link-обвязка добавляется поверх по мере необходимости.

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

> `AppRootState` объявлен `@freezed abstract` (single-variant value-объект) — у него один вариант, поэтому `abstract`, а не `sealed`. `copyWith` сгенерирован Freezed. Несёт ровно одно поле — `themeMode`; `ThemeData` (`AppTheme.light()` / `AppTheme.dark()`) — статические темы, их строит сам `MaterialApp` (см. §6.2), а не state, поэтому пересоздание тем на каждый emit исключено.

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

> **Опциональный auth/splash-флоу.** Расширенный вариант оборачивает `MaterialApp` в `BlocListener`, swap'ающий корневой маршрут (splash → login → home) через `_navigatorKey.currentState!.pushAndRemoveUntil(...)` при смене глобальной фазы app-state. Этот флоу (вместе с `SplashPage` / `LoginPage` / global-state-репозиторием) **опущен из обязательного скелета**. Добавляйте только если домену нужна аутентификация, опираясь на nullable app-state-поле в `AppRootState` + событие `UpdateAppState`, питаемое подпиской на репозиторий.

### 6.2 `AppRoot` — корневой `MaterialApp`

**Файл:** `lib/presentation/app/app_root.dart`

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nox_app/design/theme/app_theme.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
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
              // текст адаптируется по меньшему из факторов width/height
              minTextAdapt: true,
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
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                    child: child ?? const SizedBox.shrink(),
                  ),
                  // home — адаптивная оболочка AppShell (§6.5). Для auth-флоу корневой маршрут
                  // свапается через _navigatorKey/onGenerateRoute (см. блок «auth/splash-флоу», §6.1).
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

> **Скелет `_AppRootState` здесь намеренно минимален и совпадает с шипнутым кодом** (`lib/presentation/app/app_root.dart`): `AppRootBloc` + `ScreenUtilInit` + `home: AppShell`. Он опускает `WidgetsBindingObserver` (lifecycle-observer, resume → превентивный refresh) и подписку на `ConnectivityRepository.watchIsOnline()` — обе части app-root, привязанные к auth-контуру и сети. Поскольку бэкенд/протокол NOX ещё не выбран, эти подсистемы (как и весь auth-флоу из [14-networking-and-auth.md](14-networking-and-auth.md)) — **TBD**; их канон — в [§6.4](#64-app-lifecycle-observer-resume--превентивный-refresh), и они подмешиваются в **тот же** `_AppRootState` с появлением первого потребителя (auth/connectivity), а не раньше.

> **UI-скейл — «дизайн выглядит ~одинаково на всех устройствах».** Обёртка `ScreenUtilInit(designSize: Constants.designSize=Size(360,779), minTextAdapt: true)` + двойной `MediaQuery` (внешний `TextScaler.noScaling`, внутренний `TextScaler.linear(1.0)`) — это **ядро** решения по адаптивности: системный масштаб шрифта полностью нейтрализован, а все размеры (`AppSpacingTokens.sN`, `AppTextStyleTokens`) выводятся из дизайн-скейла `ScreenUtil`. Полное описание механизма и токенов — в [06-theming.md](06-theming.md) §3.2.

### 6.3 `main.dart` — точка входа

`main.dart` оборачивает запуск в `runZonedGuarded`, резолвит флейвор, дожидается `configureDependencies(env)` затем `getIt.allReady()`, поднимает конфиг-репозиторий `AppConfigRepository.initialize(flavorType:)` и вызывает `runApp(AppRoot)`. `env` выводится из флейвора (`prod → Environment.prod`, `stage → Environment.dev`, см. `09-build-and-secrets-infra.md`). Полный разбор шагов — в `02-dependency-injection.md` §10 (это тот же канонический `main.dart`).

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

      // 1) Резолвим флейвор на этапе компиляции, маппим флейвор -> DI-окружение.
      final flavor = AppFlavor.getFlavor();
      final env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev;

      // 2) Собираем контейнер (+ блокируем ориентацию параллельно),
      //    затем ждём async pre-resolve.
      await Future.wait<dynamic>([
        configureDependencies(env),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      ]);
      await getIt.allReady(); // резолвит preResolve: true async-регистрации (PackageInfo)

      // 3) Поднимаем конфиг-репозиторий под выбранный флейвор.
      await getIt<AppConfigRepository>().initialize(flavorType: flavor);

      runApp(const AppRoot());
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

> **TBD (бэкенд/протокол NOX ещё не выбран).** Весь auth-контур ниже (`AuthBloc`, `AppResumed`, refresh access-токена, реакция на `401`) — пример целевого устройства; конкретика появляется вместе с выбранным бэкендом NOX. В скелете этого слоя нет.

App-root `State` (`_AppRootState`, §6.2) подмешивает `WidgetsBindingObserver` и на `AppLifecycleState.resumed` дёргает `getIt<AuthBloc>().add(const AppResumed())` — превентивный refresh access-токена **до** первого запроса после долгого background (полный контракт + обязательный re-entrancy guard — в [14-networking-and-auth.md](14-networking-and-auth.md) §5.4; `AuthBloc` — часть auth-флоу `14` §4, появляется с auth-контуром). Канон: подписка в `initState`, отписка в `dispose`. Observer ставится **один раз** на app-root, а не на каждой странице, и НЕ реализует refresh сам — лишь триггерит тот же код auth-контура, что отрабатывает реактивно на `401`. Тот же `State` подписывается на `ConnectivityRepository.watchIsOnline()` (UX-баннер «нет сети») — см. `14` §5.

```dart
class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  // ... _bloc (AppRootBloc) + _navigatorKey из §6.2 ...

  @override
  void initState() {
    super.initState();
    _bloc = AppRootBloc()..add(const AppRootEvent.initialize());
    WidgetsBinding.instance.addObserver(this);
    // + подписка на ConnectivityRepository.watchIsOnline() → AuthBloc (UX-баннер; см. 14 §5.4)
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

> Observer интегрируется в **существующий** `_AppRootState` (§6.2) — тот уже держит `AppRootBloc` + `ScreenUtilInit`; добавляется `with WidgetsBindingObserver` + подписки. Connectivity/lifecycle — best-effort слой поверх auth-контура (TBD); источник истины о доступности API остаётся за `ApiClient` ([14-networking-and-auth.md](14-networking-and-auth.md) §5.5).

### 6.5 Адаптивная оболочка (mobile нижний бар / desktop `NavigationRail`)

`AppShell` (`lib/presentation/app/widgets/app_shell.dart`) — это `LayoutBuilder`-обёртка между `AppRoot` и страницей; переключение между мобильной и десктопной раскладкой **width-driven** — по `constraints.maxWidth >= Constants.railBreakpoint` (840dp, граница M3 medium→expanded), а **не** по `Platform`. Большое окно на десктопе и большой планшет получают одинаковую раскладку; узкое окно на десктопе остаётся на мобильной. Один и тот же размер-зависимый код корректен на всех пяти таргетах (iOS, Android, Windows, Linux, macOS).

Две ветки:

- **Mobile-ветка** (`maxWidth < Constants.railBreakpoint`): `Scaffold` с нижним баром (`Chats` / центральный docked `+` FAB / `Settings`). Нижний бар — кастомный `BottomAppBar` (`CircularNotchedRectangle`) + `FloatingActionButton` в `floatingActionButtonLocation: centerDocked` (стоковый `NavigationBar` не умеет docked-FAB с вырезом); см. locked-спеку `docs/design/spec/screens/tab-bar-shell.md`.
- **Desktop-ветка** (`maxWidth >= Constants.railBreakpoint`): `Row[ NavigationRail(width: 80, extended: false, labelType: NavigationRailLabelType.all, leading: FloatingActionButton(child: Icon(Icons.add))), VerticalDivider(width: 1), Expanded(body) ]` — `leading`-FAB рейла и есть «доковый» `+`.

Общее для обеих веток:

- Ровно две destination'ы: `Chats` = `Icons.forum` (невыбранная — `Icons.forum_outlined`), `Settings` = `Icons.settings` (невыбранная — `Icons.settings_outlined`).
- Индикатор выбранной destination — стоковый M3 (в десктопном рейле — `secondaryContainer`; в кастомном нижнем баре выбранный элемент подсвечивается через `colorScheme.primary`).
- `body` — `IndexedStack` (сохраняет состояние вкладок при переключении).
- **Аватар аккаунта из десктопного корпуса опущен** — в NOX нет profile-экрана (см. карту экранов).
- Single-window `Navigator` сохраняется (§1) — оболочка не вводит multi-window.

Скелет Feature-001 (без реальных продуктовых фич):

- `Chats`-вкладка ведёт на страницу-харнесс `Item` (та же, что и в §3–§5; mock-данные, FR-013), `Settings` — на `SettingsPlaceholderPage`. (Альтернативная заглушка `ChatsPlaceholderPage` присутствует в коде, но **не подключена**, т.к. Chats-вкладка занята харнессом; её можно удалить или подключить, когда харнесс уедет.)
- `+` — no-op со snackbar'ом. В скелете это сырой `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(TextConstants.comingSoon)))`; когда появится `AlertDialogHelper` (§8), no-op переключается на него. Никакого create-flow.
- **Нет** list-detail / двухпанельной раскладки на десктопе — только rail + единый `body`.
- Нативный OS window chrome — **без** кастомного title bar в скелете; кастомный унифицированный title bar — FUTURE (см. note про `window_manager`, §1).
- **Код-расхождение (Принцип 5.1):** `AppShell` — обычный `StatefulWidget` без BLoC, выбранная вкладка `_index` хранится в локальном `setState` (см. §6 intro) — сознательное упрощение скелета; целевое место для состояния вкладки — `AppRootBloc` (§6.1).

> Референс десктопной раскладки (rail, ширины, слоты) — `docs/design/system/nox-desktop-screens/`. Брейкпоинт `Constants.railBreakpoint = 840` задан в `lib/general/constants.dart` (см. `06-theming.md`).

---

## 7. Общие виджеты `App*Widget` (stateless)

Три переиспользуемых stateless-виджета рендерят стандартные подсостояния. Используются внутри `state.when(...)`. Все строки — из `TextConstants`, отступы — из `AppSpacingTokens`, цвета — через `context.appColors` (см. `06-theming.md`).

### 7.1 `AppProgressWidget`

**Файл:** `lib/presentation/widgets/app_progress_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

class AppProgressWidget extends StatelessWidget {
  const AppProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(top: AppSpacingTokens.s24),
        child: const CircularProgressIndicator(),
      ),
    );
  }
}
```

### 7.2 `AppErrorWidget`

**Файл:** `lib/presentation/widgets/app_error_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/text_constants.dart';

class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({super.key, this.message, this.onTryAgain});

  final String? message;
  final GestureTapCallback? onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.all(AppSpacingTokens.s16),
          child: Center(child: Text(message ?? TextConstants.errorGeneralTitle)),
        ),
        if (onTryAgain != null)
          Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s16),
            child: Center(
              child: Semantics(
                label: TextConstants.actionTryAgain,
                button: true,
                child: FilledButton.icon(
                  onPressed: onTryAgain,
                  icon: Icon(Icons.refresh_rounded, size: AppSpacingTokens.s16),
                  label: const Text(TextConstants.actionTryAgain),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

### 7.3 `AppEmptyContentWidget`

**Файл:** `lib/presentation/widgets/app_empty_content_widget.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/text_constants.dart';

class AppEmptyContentWidget extends StatelessWidget {
  const AppEmptyContentWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: const Center(child: Text(TextConstants.noData)),
    );
  }
}
```

> Конвенция нейминга: префиксуйте каждый переиспользуемый presentation-виджет `App` (`AppProgressWidget`, `AppErrorWidget`, `AppEmptyContentWidget`). Держите их stateless и single-purpose.

---

## 8. Сюрфейсинг ошибок — `AlertDialogHelper` (единственный канал)

`AlertDialogHelper` — **единственный** канал пользовательских snackbar'ов. Никогда не показывайте сырой текст исключения — BLoC сначала предпереводит исключение в строку (геттер `_translate`, §3.3). Для in-body error-ветки — `AppErrorWidget` (§7.2). Цвета берутся через токены / `context.appColors`.

**Файл:** `lib/presentation/helpers/alert_dialog_helper.dart`

```dart
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/app_colors.dart';

class AlertDialogHelper {
  static void showSnackBar(BuildContext context, String message) {
    final colors = context.appColors;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      width: MediaQuery.of(context).size.width * 0.9,
      padding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      backgroundColor: colors.surfaceMuted,
      content: Center(
        child: Text(message, style: TextStyle(color: colors.onSurface), textAlign: TextAlign.center),
      ),
    ));
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    final colors = context.appColors;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      width: MediaQuery.of(context).size.width * 0.9,
      padding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      backgroundColor: colors.error,
      content: Center(
        child: Text(message, style: TextStyle(color: colors.onError), textAlign: TextAlign.center),
      ),
    ));
  }
}
```

> `context.appColors` — extension-аксессор `ThemeExtension<AppColors>` из `06-theming.md`. Имена цветовых ролей (`surfaceMuted`, `onSurface`, `error`, `onError`) — иллюстративны; финальная палитра и точные имена ролей — в `06-theming.md`.

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

(Пример уже применён к кнопке «Try again» в `AppErrorWidget`, §7.2.)

---

## 10. Поток Page ↔ BLoC ↔ Repository (резюме)

```
initState()                 _bloc = ItemListBloc()..add(ItemListEvent.initialize())
  → BaseBloc ctor           super(const ItemListState.initializing()); on<Initialize>(_onInitialize)
  → _onInitialize           emit(Initialized(pagingState: PagingState())); add(LoadItems(reset: true))
  → _onLoadItems            getIt<ItemRepository>().getItems(config:)
  → RepositoryResult<T>     result.hasData / result.match(onData:, onError:)
  → emit                    Initialized(items:, pagingState:, total:) | Error(exception:)
  → BlocBuilder             state.when(initializing:, initialized:, error:)
  → виджеты                 AppProgressWidget | PagedListView/AppEmptyContentWidget | AppErrorWidget
  → side-эффекты            errorMessages → AlertDialogHelper; navigateToDetails → Navigator.push
dispose()                   _navSub.cancel(); _errorSub.cancel(); _bloc.close()
```

---

## Чеклист

После применения этого документа в проекте `nox_app` должно быть:

- [ ] `lib/presentation/base/base_bloc.dart` с `BaseBloc<E,S>` и `executeLogic` (понимать `'$e, $s'`-аргумент и тихий swallow при опущенном `onError`).
- [ ] `lib/presentation/pages/base/base_state_page.dart` с `BaseStatePage<T>` (`scaffoldKey`, реактивный `useDrawer`/`closeDrawer`, платформозависимый `buildAppBar()`).
- [ ] BLoC-trio на фичу: `*_bloc.dart` + `part`-связанные `*_event.dart` / `*_state.dart` — оба `@freezed sealed` unions, **без** `Equatable`, **без** `fromJson` (генерируется только `*.freezed.dart`).
- [ ] Подсостояния `Initializing` / `Initialized` / `Error` как `const factory`-конструкторы; производные значения — в `extension`-геттерах, не в теле `@freezed`.
- [ ] Переходы через сгенерированный `copyWith`; рендер тела через `state.when(...)`; чистые виджеты-проекции — через Dart 3 `switch` с деструктуризацией.
- [ ] BLoC резолвят репозитории через `getIt<XxxRepository>()`, хранят `StreamSubscription` в полях и отменяют в `close()`.
- [ ] BLoC потребляют `RepositoryResult<T>` через `match()` / `hasData` — никакого `result.data!` без guard'а.
- [ ] Side-эффекты: дефолт — `PublishSubject`-стримы (`errorMessages` / `navigateToDetails`); state-carried one-shot и `BlocListener` — по таблице §5.6.
- [ ] Конкурентность: дефолт — stale-guard (перечитать `this.state` после `await`) + `restartable()` для поиска; продвинутый toolkit (epoch-guard + `debounce`/`debounceIf` + `executeLogic`) — для tree/representation BLoC.
- [ ] Пагинация — `PagingState`-in-bloc (v5), OFFSET-флейвор по умолчанию; детали в `07-pagination.md`.
- [ ] Страница: `static const String routeName`, `static Route route(...)`, `State extends BaseStatePage<T>`, `late final` BLoC в `initState()` и `close()` в `dispose()`, side-эффект-подписки в `initState`/`dispose`, `BlocProvider` + `BlocBuilder` + `state.when(...)`. **BLoC обязателен для ЛЮБОЙ навигируемой страницы (`routeName`/`route()`) — даже logic-less (минимальный trio или value-BLoC, Принцип 5.1); переиспользуемые виджеты BLoC не требуют.**
- [ ] App-shell: `AppRootBloc` (`@freezed abstract` одно состояние с `themeMode` + `copyWith`, **не** trio), `AppRoot` (`GlobalKey<NavigatorState>`, тема из `AppRootBloc`, `home: const AppShell()`).
- [ ] Адаптивная оболочка `AppShell` (`lib/presentation/app/widgets/app_shell.dart`): width-driven `LayoutBuilder` на `Constants.railBreakpoint = 840` (а **не** `Platform`); mobile — `BottomAppBar` (`CircularNotchedRectangle`) + centerDocked `+` FAB; desktop — `NavigationRail` (leading `+` FAB) + `VerticalDivider` + `Expanded(body)`; ровно 2 destination'ы (`Chats`/`Settings`), `body` = `IndexedStack`, без profile-аватара, single-window; корректна на всех пяти таргетах (§6.5).
- [ ] UI-скейл: `MaterialApp` обёрнут в `ScreenUtilInit(designSize: Constants.designSize` = `Size(360, 779)`, `minTextAdapt: true)` + двойной `MediaQuery` (`TextScaler.noScaling` снаружи, `TextScaler.linear(1.0)` внутри `builder`) — OS-масштаб шрифта отключён, размеры выводятся из дизайн-скейла (§6.2; механизм — `06-theming.md` §3.2).
- [ ] `main.dart` в `runZonedGuarded`, `configureDependencies(env)` → `getIt.allReady()` → `runApp(AppRoot)`.
- [ ] Общие виджеты `AppProgressWidget` / `AppErrorWidget` / `AppEmptyContentWidget` (stateless, copy из `TextConstants`, spacing из `AppSpacingTokens`).
- [ ] `AlertDialogHelper` — единственный канал snackbar'ов (цвета через `context.appColors`); `AppErrorWidget` — для in-body error-ветки.
- [ ] `Semantics(label:, button: true)` на интерактивных виджетах.
- [ ] Гранулярные ребилды — per-slice `BlocBuilder` с `buildWhen` на value-equality Freezed; неизменяемая копировальная дисциплина (всегда `copyWith` / новая фабрика).
- [ ] Нет `desktop_multi_window` / `WindowsConfig` / IPC-маршрутизации; нет голых `Color`/`EdgeInsets`/`TextStyle` в коде фич.
- [ ] `fvm flutter analyze` проходит для `lib/`.

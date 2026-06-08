# 07 — Пагинация

> **Назначение:** зафиксировать единственный канонический стандарт постраничной подгрузки списков в приложении Speech AI Mobile — библиотека `infinite_scroll_pagination` ^5.1.1 (v5, stateless), `PagingState<K,T>` внутри Freezed-стейта BLoC, переиспользуемый extension `PagingStateExt.applyPage`, OFFSET-модель по умолчанию (под records-list `client_backend`) и CURSOR как альтернатива. **Когда читать:** перед реализацией любого экрана со списком, который сервер отдаёт постранично (первый реальный кейс — список записей `records`), а также при ревью BLoC, отдающего `PagingState`. **Связанные документы:** `05-presentation-layer.md` (BLoC = Freezed, `BaseBloc`, страницы, `state.when`), `04-data-layer.md` (`RepositoryResult`, `ResponseEntity`, mapper, network-only списки), `03-domain-layer.md` (доменные модели `@freezed`, `RepositoryException`), `06-theming.md` (токены для индикаторов/разделителей), `10-code-templates.md` (полные шаблоны), `08-conventions-and-constitution.md` (правила слоёв).

---

## 1. Что это и почему именно так

Постраничная подгрузка — частая операция в Speech AI Mobile: список записей (`records`), список треков внутри записи, любой каталог. Стандарт здесь **один на всё приложение** и не допускает разнобоя.

Ключевые решения (заблокированы для всего блюпринта):

1. **Библиотека — `infinite_scroll_pagination` ^5.1.1 (v5).** В 5-й мажорной версии она stateless: `PagingState<K,T>` — это обычное иммутабельное значение, которое лежит внутри стейта BLoC и напрямую передаётся в `PagedListView(state:, fetchNextPage:)`. **Никаких `PagingController`** (это паттерн v4, он держит собственный стейт вне BLoC и ломает single source of truth) и никаких `addPageRequestListener`.
2. **`PagingState<K,T>` — часть Freezed-стейта BLoC.** Лежит в варианте-наследнике `Initialized` (см. `05-presentation-layer.md` про Freezed-юнионы и канонические подсостояния `Initializing` / `Initialized` / `Error`). Пагинация прививается одинаково независимо от того, Freezed стейт или нет, — три поля (`pagingState`, плоский `items`, `nextPage`/`nextCursor`) просто живут в loaded-кейсе.
3. **Плоский `List<T>` + производные `pages`.** В стейте храним **плоский** `List<T> items` для бизнес-логики (выбор, удаление, поиск), а `pages: List<List<T>>`, которого требует `PagedListView`, **пересчитываем** в helper'е. Хранить `pages: List<List<T>>` напрямую — антипаттерн.
4. **OFFSET-модель по умолчанию.** `client_backend` records-list — offset-based (`page` + `page_size` + `count`), поэтому метаданные по умолчанию — `PageMetadata{int? nextPage, int total}`, `nextPage == null` ⇒ страниц больше нет. CURSOR-модель (`CursorPaginationMetadata{String? nextCursor}`) описана как альтернатива для курсорных эндпоинтов.
5. **`RepositoryResult` остаётся.** Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>` (envelope из `04-data-layer.md`), а не «голый» `Future` + `try/catch`. BLoC вызывает `result.match` / `result.hasData`, применяет helper, и пробрасывает `result.exception` в `pagingState.error` — для v5-билдеров ошибок. **Это ключевой графт:** мы НЕ копируем «сырой» `Future + try/catch` из cursor-гайда, а оборачиваем его в наш envelope.
6. **Один helper `PagingStateExt.applyPage` на весь проект.** Инкапсулирует пересчёт `pages`/`keys`/`hasNextPage`, ветку «пустой результат», всё через `copyWith`. Юнит-тестируется отдельно.
7. **Debounce обязателен** на событии загрузки — `PagedListView` дёргает `fetchNextPage` агрессивно.

---

## 2. Зависимости (`pubspec.yaml`)

```yaml
dependencies:
  flutter_bloc: ^9.0.0                # BLoC
  infinite_scroll_pagination: ^5.1.1  # PagingState + PagedListView (v5, stateless)
  bloc_concurrency: ^0.3.0            # event transformers (sequential / restartable) — основной вариант
  rxdart: ^0.28.0                     # debounceTime для кастомного transformer — альтернатива
```

Документация библиотеки: <https://pub.dev/documentation/infinite_scroll_pagination/latest/>.

---

## 3. Архитектурные принципы (сводка)

1. `PagingState<K,T>` — это часть Freezed-стейта BLoC, а не `PagingController`.
2. Стейт (вариант `Initialized`) хранит три параллельные сущности:
   - `PagingState<String, ItemModel>` — для рендера в `PagedListView` (внутри уже есть `pages`, `keys`, `hasNextPage`, `isLoading`, `error`);
   - `List<ItemModel> items` — плоский список для бизнес-логики;
   - `int nextPage` (OFFSET) **или** `String? nextCursor` (CURSOR) — координата следующей страницы.
3. Сервер возвращает метаданные пагинации; `nextPage == null` / `nextCursor == null` означает «страниц больше нет».
4. **Один** универсальный `LoadItems({required bool reset})` — делает и первую загрузку, и догрузку, и сброс после смены фильтра.
5. Параметры запроса (search / sort / filter) читаем **из стейта, а не из event** — UI вызывает просто `add(LoadItems(reset: false))` без аргументов.
6. Любое изменение фильтра/поиска/сортировки ⇒ `pagingState.reset()` (метод пакета) + очистка `items` + обнуление `nextPage` + `add(LoadItems(reset: true))`.
7. Debounce обязателен на `LoadItems`.
8. Никакой ручной работы с `pages` и `keys` — всё в `PagingStateExt.applyPage`.

---

## 4. Data-слой: метаданные и обёртка ответа

### 4.1 Метаданные пагинации — OFFSET (по умолчанию)

`PageMetadata` — это **доменный** `@freezed`-тип (только `*.freezed.dart`, **без** JSON), который живёт в `lib/domain/repository/base/`. Парсинг сырого envelope в `(List<Entity>, PageMetadata)` — задача **data**-слоя (`PaginatedResponse<T>`, см. §4.3). `nextPage == null` ⇒ это была последняя страница.

```dart
// lib/domain/repository/base/page_metadata.dart
@freezed
abstract class PageMetadata with _$PageMetadata {
  const factory PageMetadata({required int total, int? nextPage}) = _PageMetadata;
}
```

> **Замечание по контракту.** Точные имена полей контракта records-list (`page` / `page_size` / `count`) и 1-based нумерацию сверяйте с `docs/spec/backend_mobile_client_0.2.md` и `postman/SpeechAI_Client_API.postman_collection.json`. Маппинг сырого envelope → `PageMetadata` (вычисление `nextPage` из `page`/`page_size`/`count`) выполняет data-слой в `PaginatedResponse.fromJson`, а не доменная модель.

### 4.2 Метаданные пагинации — CURSOR (альтернатива)

Для курсорных эндпоинтов класс метаданных меняется на `CursorPaginationMetadata` — тоже `@freezed`, **без** JSON, в той же папке `lib/domain/repository/base/`. Всё остальное (BLoC, UI, helper) — идентично.

```dart
// lib/domain/repository/base/cursor_pagination_metadata.dart
@freezed
abstract class CursorPaginationMetadata with _$CursorPaginationMetadata {
  const factory CursorPaginationMetadata({String? nextCursor}) = _CursorPaginationMetadata;
}
```

### 4.3 Обёртка ответа `PaginatedResponse<T>`

Универсальная обёртка на **data**-слое: именно она владеет JSON-разбором. `fromJson` принимает `fromJsonT` для разбора каждого элемента (entity-слой) и мапит сырой envelope в `(List<Entity>, PageMetadata)`. По умолчанию — OFFSET (`PageMetadata`); для cursor подменяется тип `pagination`.

```dart
// lib/data/model/pagination/paginated_response.dart
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';

class PaginatedResponse<T> {
  const PaginatedResponse({required this.data, required this.pagination});

  final List<T> data;
  final PageMetadata pagination;

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final dataJson = json['data'] as List<dynamic>? ?? const [];

    // Сырые поля offset-контракта records-list: page / page_size / count.
    final page = (json['page'] as num?)?.toInt();
    final pageSize = (json['page_size'] as num?)?.toInt();
    final total = (json['count'] as num?)?.toInt() ?? 0;

    // nextPage = текущая + 1, пока не выбрали все элементы; иначе null.
    final loadedSoFar = (page != null && pageSize != null) ? page * pageSize : null;
    final hasMore = (page != null && loadedSoFar != null) ? loadedSoFar < total : false;

    return PaginatedResponse<T>(
      data: dataJson.cast<Map<String, dynamic>>().map(fromJsonT).toList(),
      // Метаданные приходят рядом с данными в едином envelope {data, count, page, page_size, ...}.
      pagination: PageMetadata(total: total, nextPage: hasMore ? page! + 1 : null),
    );
  }
}
```

> Реальный бэкенд оборачивает ответ в `{data, timestamp, trace_id, meta}` (см. `04-data-layer.md`, `ResponseEntity<T>`). Распаковку envelope выполняет API-слой/`EntityConverter`; `PaginatedResponse.fromJson` работает уже с распакованным телом, где рядом с `data` лежат поля пагинации (`count`/`page`/`page_size`).

### 4.4 Конфиг запроса — `GetItemsConfig`

Параметры списка собираются в иммутабельный `@freezed`-конфиг, реализующий `RepositoryConfig` (живёт в `lib/domain/...`, см. `03-domain-layer.md`). Никаких «магических чисел» в BLoC. `defaultPage = 1` (1-based, как в `client_backend`); `pageSize = 20`.

```dart
// lib/domain/repository/item/get_items_config.dart
@freezed
abstract class GetItemsConfig with _$GetItemsConfig implements RepositoryConfig {
  const GetItemsConfig._();

  const factory GetItemsConfig({required int page, String? search}) = _GetItemsConfig;

  factory GetItemsConfig.firstPage({String? search}) => GetItemsConfig(page: defaultPage, search: search);

  factory GetItemsConfig.nextPage({required int page, String? search}) => GetItemsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1; // 1-based, как в client_backend
}
```

### 4.5 Репозиторий: контракт и реализация

Пагинированный server-owned список отдаёт канонический метод `getItems` (префикс `get*` = параметризованный/списочный запрос; `fetch*` зарезервирован под одиночный one-shot `fetchItem`). Метод возвращает `RepositoryResult<(List<ItemModel>, PageMetadata)>` — Dart-record в payload, обёрнутый в наш envelope (именованные варианты `RepositoryResult.success(data:)` / `RepositoryResult.error(exception:)`). Перевод типизированных исключений (`ApiException` / `DaoException` → `BaseRepositoryException`) и обязательное логирование через `LogRepository` делает `BaseRepositoryHelper.execute<TD>()` (см. `04-data-layer.md`). Пагинированные server-owned списки — **network-only** (без DAO/subject), это явный carve-out base.

Полный контракт `ItemRepository` — канонический (см. `04-data-layer.md`); ниже показан целиком, списочный метод — `getItems`:

```dart
// lib/domain/repository/item/item_repository.dart
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';
import 'package:speech_ai_mobile/domain/model/item/item_model.dart';
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';
import 'package:speech_ai_mobile/domain/repository/item/get_item_config.dart';
import 'package:speech_ai_mobile/domain/repository/item/get_items_config.dart';

abstract class ItemRepository {
  Stream<RepositoryResult<ItemModel>> watchItem({required String id});
  Future<RepositoryResult<ItemModel>> fetchItem({required GetItemConfig config});
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config});
  Future<RepositoryResult<ItemModel>> createItem({required ItemModel item});
  Future<RepositoryResult<ItemModel>> updateItem({required ItemModel item});
  Future<RepositoryResult<void>> deleteItem({required String id});
  Future<void> clean();
}
```

```dart
// lib/data/repository/item/item_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:speech_ai_mobile/data/api/item/item_api.dart';
import 'package:speech_ai_mobile/data/exception/base_repository_helper.dart';
import 'package:speech_ai_mobile/data/mapper/item/item_mapper.dart';
import 'package:speech_ai_mobile/domain/repository/base/repository_result.dart';
import 'package:speech_ai_mobile/domain/model/item/item_model.dart';
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';
import 'package:speech_ai_mobile/domain/repository/item/get_items_config.dart';
import 'package:speech_ai_mobile/domain/repository/item/item_repository.dart';

@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])
class ItemRepositoryImpl with BaseRepositoryHelper implements ItemRepository {
  ItemRepositoryImpl(this._api, this._mapper, this._log);

  final ItemApi _api;
  final ItemMapper _mapper;
  @override
  final LogRepository _log;

  @override
  Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config}) {
    // execute ВСЕГДА логирует через LogRepository; callback возвращает уже-обёрнутый RepositoryResult
    // (DioException → internal, прочее → unknown ловит сам execute). См. 04-data-layer.md §5.
    return execute<(List<ItemModel>, PageMetadata)>(() async {
      final response = await _api.getItems(config: config); // PaginatedResponse<ItemEntity>
      final items = response.data.map(_mapper.toModel).toList();
      return RepositoryResult.success(data: (items, response.pagination));
    });
  }

  // Остальные методы контракта (watchItem / fetchItem / createItem / updateItem / deleteItem / clean)
  // — см. 04-data-layer.md; здесь показан только списочный getItems.
}
```

---

## 5. Подпись-фигура: `PagingStateExt.applyPage`

**Это сердце всего подхода** — расширение над `PagingState<K,T>`, скрывающее пересчёт `pages`/`keys`/`hasNextPage` и ветку «пустой результат». Один на проект, юнит-тестируется отдельно.

Ниже — OFFSET-вариант (по умолчанию). Запись `response` распаковывается через `final (incoming, meta) = response;`, где `meta` — `PageMetadata`; признак «последняя страница» — `meta.nextPage == null`, в record возвращается `int? nextPage`. CURSOR-вариант (§5.1) — тот же helper, но `meta` — `CursorPaginationMetadata` и возвращается `String? nextCursor`.

```dart
// lib/presentation/pagination/paging_state_ext.dart
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';

extension PagingStateExt<K, T> on PagingState<K, T> {
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

**Почему это лучше, чем работать с `PagingState` напрямую:**
- инкапсулирует пять полей и одну ветку для «пустого результата»;
- возвращает сразу всё необходимое для обновления стейта (Dart-record);
- легко покрывается юнит-тестом;
- одинаков для всех экранов проекта.

### 5.1 CURSOR-вариант helper'а (альтернатива)

Если эндпоинт курсорный — единственное отличие: тип метаданных `CursorPaginationMetadata`, признак конца — `nextCursor == null`, в record возвращается `String? nextCursor`. Всё остальное идентично.

```dart
// lib/presentation/pagination/paging_state_ext_cursor.dart  (используется ВМЕСТО offset-варианта на курсорных экранах)
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:speech_ai_mobile/domain/repository/base/cursor_pagination_metadata.dart';

extension PagingStateCursorExt<K, T> on PagingState<K, T> {
  ({List<T> updatedList, PagingState<K, T> pagingState, String? nextCursor}) applyPageCursor({
    required List<T> existingList,
    required (List<T>, CursorPaginationMetadata) response,
    required K Function(T) keyExtractor,
  }) {
    final (incoming, meta) = response;
    final updatedList = [...existingList, ...incoming];
    final isLastPage = meta.nextCursor == null;
    final pages = updatedList.map((e) => [e]).toList();
    final keys = updatedList.map(keyExtractor).toList();
    final isNoItems = updatedList.isEmpty && isLastPage;
    final newPagingState = isNoItems
        ? copyWith(pages: <List<T>>[], keys: <K>[], hasNextPage: false, isLoading: false)
        : copyWith(pages: pages, keys: keys, hasNextPage: !isLastPage, isLoading: false);
    return (updatedList: updatedList, pagingState: newPagingState, nextCursor: meta.nextCursor);
  }
}
```

> В проекте по умолчанию подключаем **только** OFFSET-вариант. CURSOR-extension добавляется, лишь когда появляется реальный курсорный эндпоинт.

---

## 6. BLoC-слой (Freezed)

BLoC построен по правилам `05-presentation-layer.md`: `@freezed sealed State` с подсостояниями `Initializing` / `Initialized` / `Error` (как `const factory`), `@freezed sealed Event`, производная логика — в extension-геттерах, переходы — через `copyWith`. На BLoC-типах **нет** `fromJson` (только `*.freezed.dart`).

### 6.1 State (Freezed-юнион)

Поля пагинации (`pagingState`, `items`, `nextPage`) живут в варианте `Initialized` плюс «v1-экстры» (`loadingInProgress`, `refreshInProgress`, `searchQuery`, `total`). Производный геттер `isAnyInProgress` — в extension, не в `@freezed`-теле.

```dart
// lib/presentation/pages/item_list_page/bloc/item_list_state.dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListState with _$ItemListState {
  const factory ItemListState.initializing() = Initializing;

  const factory ItemListState.initialized({
    required PagingState<String, ItemModel> pagingState,
    @Default(<ItemModel>[]) List<ItemModel> items,
    @Default(0) int total,
    @Default(GetItemsConfig.defaultPage) int nextPage,
    @Default(false) bool isLastPage,
    @Default(false) bool loadingInProgress,
    @Default(false) bool refreshInProgress,
    @Default('') String searchQuery,
  }) = Initialized;

  const factory ItemListState.error({BaseRepositoryException? exception}) = Error;
}

/// Производная (computed) логика — в extension-геттерах, НЕ в @freezed-теле.
extension InitializedX on Initialized {
  bool get isAnyInProgress => loadingInProgress || refreshInProgress;
}
```

> CURSOR-вариант стейта отличается одним полем: вместо `int nextPage` хранится `String? nextCursor` (и `defaultPage` уже не нужен). Тип ключа `K` в `PagingState<K, ItemModel>` для CURSOR обычно тоже `String` (id элемента) — он не зависит от способа пагинации.

### 6.2 Event (Freezed-юнион)

Единый `LoadItems({required bool reset})` для первой загрузки, догрузки и reset. Pull-to-refresh несёт `Completer<void>`. Параметры запроса в events **не** передаются — читаются из стейта.

```dart
// lib/presentation/pages/item_list_page/bloc/item_list_event.dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListEvent with _$ItemListEvent {
  /// Однократно из initState: ..add(const ItemListEvent.initialize()).
  const factory ItemListEvent.initialize() = Initialize;

  /// reset == true — первая страница / после смены фильтра; false — догрузка.
  const factory ItemListEvent.loadItems({required bool reset, Completer<void>? completer}) = LoadItems;

  /// Pull-to-refresh: завершаем completer по окончании загрузки.
  const factory ItemListEvent.refreshRequested({required Completer<void> completer}) = RefreshRequested;

  /// Изменение строки поиска (debounce + reset).
  const factory ItemListEvent.updateSearchQuery({required String value}) = UpdateSearchQuery;
}
```

### 6.3 Debounce-трансформеры

Debounce **обязателен** на `LoadItems` — `PagedListView` вызывает `fetchNextPage` агрессивно во время скролла.

**Основной вариант — `bloc_concurrency`:**

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

on<LoadItems>(_onLoadItems, transformer: sequential());        // строго по очереди, без гонок страниц
on<UpdateSearchQuery>(_onUpdateSearchQuery, transformer: restartable()); // новый ввод отменяет старый
```

**Альтернатива — кастомный `rxdart` debounce:**

```dart
import 'package:rxdart/rxdart.dart';

EventTransformer<E> debounce<E>(Duration d) =>
    (events, mapper) => events.debounceTime(d).switchMap(mapper);

on<LoadItems>(_onLoadItems, transformer: debounce(const Duration(milliseconds: 300)));
on<UpdateSearchQuery>(_onUpdateSearchQuery, transformer: debounce(const Duration(milliseconds: 300)));
```

> Рекомендация: `sequential()` для загрузки страниц (исключает гонку при быстрой подгрузке) + `restartable()` для поиска (новый запрос отменяет «протухший») — как основной путь; `rxdart`-debounce — когда нужен явный временной интервал.

### 6.4 BLoC

Ключевые правила (наследуются из `05-presentation-layer.md`):
- `ItemListBloc extends BaseBloc<ItemListEvent, ItemListState>` (НЕ `extends Bloc<...>` напрямую);
- репозиторий резолвится через `getIt<ItemRepository>()`;
- тело load-хендлера обёрнуто в `executeLogic(..., onError: ...)` базового блока;
- координата и параметры берутся **из текущего `state`**, не из event;
- после `await` — повторно читаем `this.state` и выходим, если строка поиска изменилась (stale-guard);
- результат потребляется через `result.hasData` / `result.match`, `result.exception` пробрасывается в `pagingState.error`;
- навигация/снэкбары уходят через `PublishSubject`-стримы, не через стейт (см. `05-presentation-layer.md`).

```dart
// lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart
import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:speech_ai_mobile/di/configure_dependencies.dart';
import 'package:speech_ai_mobile/domain/exception/base_repository_exception.dart';
import 'package:speech_ai_mobile/domain/model/item/item_model.dart';
import 'package:speech_ai_mobile/domain/repository/base/page_metadata.dart';
import 'package:speech_ai_mobile/domain/repository/item/get_items_config.dart';
import 'package:speech_ai_mobile/domain/repository/item/item_repository.dart';
import 'package:speech_ai_mobile/presentation/base/base_bloc.dart';
import 'package:speech_ai_mobile/presentation/pagination/paging_state_ext.dart';

part 'item_list_event.dart';
part 'item_list_state.dart';
part 'item_list_bloc.freezed.dart';

class ItemListBloc extends BaseBloc<ItemListEvent, ItemListState> {
  ItemListBloc() : super(const ItemListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadItems>(_onLoadItems, transformer: sequential());
    on<RefreshRequested>(_onRefreshRequested);
    on<UpdateSearchQuery>(_onUpdateSearchQuery, transformer: restartable());
  }

  final _itemRepository = getIt<ItemRepository>();

  FutureOr<void> _onInitialize(Initialize event, Emitter<ItemListState> emit) async {
    emit(ItemListState.initialized(pagingState: PagingState<String, ItemModel>()));
    add(const LoadItems(reset: true));
  }

  FutureOr<void> _onLoadItems(LoadItems event, Emitter<ItemListState> emit) async {
    final state = this.state;
    if (state is! Initialized || state.loadingInProgress) {
      event.completer?.complete();
      return;
    }

    // Параметры — из стейта, не из event.
    final query = state.searchQuery;
    final isFirstPage = event.reset;
    final existingList = isFirstPage ? const <ItemModel>[] : state.items;
    final config = isFirstPage
        ? GetItemsConfig.firstPage(search: query.isEmpty ? null : query)
        : GetItemsConfig.nextPage(page: state.nextPage, search: query.isEmpty ? null : query);

    // Помечаем загрузку (нижний спиннер PagedListView покажет сам).
    emit(state.copyWith(
      loadingInProgress: true,
      refreshInProgress: isFirstPage,
      pagingState: state.pagingState.copyWith(isLoading: true, error: null),
    ));

    // Тело load-хендлера обёрнуто в executeLogic базового блока (BaseBloc).
    await executeLogic(
      () async {
        final result = await _itemRepository.getItems(config: config);

        // Stale-guard: за время await пользователь мог изменить поиск.
        final updated = this.state;
        if (updated is! Initialized || updated.searchQuery != query) return;

        result.match(
          onData: (data) {
            final (items, meta) = data; // (List<ItemModel>, PageMetadata)
            final applied = updated.pagingState.applyPage(
              existingList: existingList,
              response: (items, meta),
              keyExtractor: (item) => item.id,
            );
            emit(updated.copyWith(
              items: applied.updatedList,
              pagingState: applied.pagingState,
              nextPage: applied.nextPage ?? updated.nextPage, // null ⇒ страниц больше нет, координату не двигаем
              isLastPage: applied.nextPage == null,
              total: meta.total,
              loadingInProgress: false,
              refreshInProgress: false,
            ));
          },
          onError: (exception) {
            if (isFirstPage && updated.items.isEmpty) {
              // Ошибка на первой странице при пустом списке — экран целиком в Error.
              emit(ItemListState.error(exception: exception));
            } else {
              // Ошибка догрузки — surface в pagingState.error для newPageErrorIndicator.
              emit(updated.copyWith(
                loadingInProgress: false,
                refreshInProgress: false,
                pagingState: updated.pagingState.copyWith(isLoading: false, error: exception),
              ));
            }
          },
        );
      },
      onError: (error, exception, stackTrace) {
        // Защитная ветка BaseBloc на случай непредвиденного throw мимо RepositoryResult.
        final updated = this.state;
        if (updated is Initialized) {
          emit(updated.copyWith(
            loadingInProgress: false,
            refreshInProgress: false,
            pagingState: updated.pagingState.copyWith(isLoading: false, error: exception),
          ));
        }
      },
    );

    event.completer?.complete();
  }

  FutureOr<void> _onRefreshRequested(RefreshRequested event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is Initialized && !state.isAnyInProgress) {
      add(LoadItems(reset: true, completer: event.completer));
    } else if (!event.completer.isCompleted) {
      event.completer.complete();
    }
  }

  FutureOr<void> _onUpdateSearchQuery(UpdateSearchQuery event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is! Initialized) return;
    final query = event.value.trim();
    if (state.searchQuery == query) return;

    // Reset-on-filter: reset() пакета + очистка items + обнуление nextPage + перезапуск.
    emit(state.copyWith(
      items: const [],
      pagingState: state.pagingState.reset(),
      nextPage: GetItemsConfig.defaultPage,
      isLastPage: false,
      searchQuery: query,
    ));
    add(const LoadItems(reset: true));
  }
}
```

**Критически важные моменты:**

- `PagingState.reset()` — метод пакета, возвращает чистый `PagingState`. Использовать **всегда** при смене фильтра/поиска/сортировки.
- `event.reset` различает первую загрузку (или после смены фильтра) и догрузку. При `reset: true` координату НЕ читаем — стартуем с `defaultPage`.
- Параметры запроса (search/sort/filter) читаем из `state`, а не передаём в `LoadItems`. UI вызывает просто `add(const LoadItems(reset: false))`.
- Stale-guard после `await`: повторно читаем `this.state` и сверяем `searchQuery` — чтобы не записать «протухший» ответ. `restartable()` на поиске даёт ту же защиту со стороны трансформера.
- Тело хендлера обёрнуто в `executeLogic(() async {…}, onError: (error, exception, stackTrace) {…})` базового блока (`BaseBloc`) — позиционный первый аргумент-логика + 3-аргументный `onError` (см. `05-presentation-layer.md` §2); это и есть точка единого логирования/обработки сбоев.
- `result.match(onData:, onError:)` — потребление `RepositoryResult` (именованные `success(data:)` / `error(exception:)`). `exception` уходит в `pagingState.error` (догрузка) или в `ItemListState.error` (первая страница при пустом списке) — это **ключевой графт**: мы не используем «сырой» `try/catch`, а потребляем `RepositoryResult`.

---

## 7. UI-слой

`PagedListView` — обычный список, который читает `PagingState` и зовёт `fetchNextPage` при приближении к концу. Оборачиваем в `BlocSelector` по `pagingState`, чтобы не ребилдить список при изменении других полей (search text, total и т.д.). Pull-to-refresh — `AppRefreshIndicatorWidget` **над** `Scaffold`.

```dart
// lib/presentation/pages/item_list_page/item_list_page.dart (фрагмент _buildList)
Widget _buildList(Initialized state) {
  return BlocSelector<ItemListBloc, ItemListState, PagingState<String, ItemModel>>(
    // Селектор по pagingState — иначе список перестраивается при любом изменении стейта.
    selector: (s) => s is Initialized ? s.pagingState : PagingState<String, ItemModel>(),
    builder: (context, pagingState) {
      return PagedListView<String, ItemModel>.separated(
        state: pagingState,
        fetchNextPage: () => context.read<ItemListBloc>().add(const LoadItems(reset: false)),
        builderDelegate: PagedChildBuilderDelegate<ItemModel>(
          itemBuilder: (context, item, index) => ItemTileWidget(
            key: ValueKey(item.id), // помогает Flutter переиспользовать виджеты при reset
            item: item,
            onTap: () => context.read<ItemListBloc>().add(ShowItemDetails(itemId: item.id)),
          ),
          firstPageProgressIndicatorBuilder: (_) =>
              Center(child: GeneralProgressWidget(size: AppSpacingTokens.s16)),
          newPageProgressIndicatorBuilder: (_) => Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s16),
            child: Center(child: GeneralProgressWidget(size: AppSpacingTokens.s16)),
          ),
          noItemsFoundIndicatorBuilder: (_) =>
              Center(child: Text(TextConstants.noData, style: AppTextStyleTokens.body(color: context.appColors.onSurface))),
          noMoreItemsIndicatorBuilder: (_) => const SizedBox.shrink(),
          firstPageErrorIndicatorBuilder: (_) => Center(
            child: GeneralErrorWidget(onTryAgain: () => context.read<ItemListBloc>().add(const LoadItems(reset: true))),
          ),
          newPageErrorIndicatorBuilder: (_) => Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s16),
            child: Center(
              child: Text(TextConstants.errorLoadMore, style: AppTextStyleTokens.body2(color: context.appColors.error)),
            ),
          ),
        ),
        separatorBuilder: (_, __) => SizedBox(height: AppSpacingTokens.s6),
      );
    },
  );
}
```

Pull-to-refresh — обёртка **над** `Scaffold` на самом верхнем уровне `build()`:

```dart
@override
Widget build(BuildContext context) {
  return BlocProvider.value(
    value: _bloc,
    child: BlocBuilder<ItemListBloc, ItemListState>(
      builder: (context, state) {
        return AppRefreshIndicatorWidget(
          onRefresh: _refresh,
          child: Scaffold(
            appBar: AppBar(title: Text(TextConstants.itemListTitle)),
            body: state.when(
              initializing: () => Center(child: GeneralProgressWidget(size: AppSpacingTokens.s16)),
              initialized: _buildList,
              error: (_) => Center(child: GeneralErrorWidget(onTryAgain: () => _bloc.add(const Initialize()))),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _refresh() async {
  final completer = Completer<void>();
  _bloc.add(RefreshRequested(completer: completer));
  return completer.future;
}
```

Заметки по UI:

- `BlocSelector` по `pagingState` обязателен — иначе список ребилдится при любом изменении стейта.
- `key: ValueKey(item.id)` помогает Flutter правильно переиспользовать виджеты при reset.
- Поле поиска вызывает `add(UpdateSearchQuery(value: text))` — debounce в BLoC сам сгладит ввод.
- Цвета/отступы/типографика — только через токены (`context.appColors`, `AppSpacingTokens`, `AppTextStyleTokens`), см. `06-theming.md`. Никакого сырого `Color`/`EdgeInsets`/`TextStyle` в коде экрана.
- `PagedGridView`, `PagedSliverList`, `PagedSliverGrid` — те же правила, меняется только виджет.

---

## 8. Тестирование BLoC (`blocTest`)

Обязательно дождаться debounce (`wait:`). При `sequential()` явный `wait` не требуется, но при `rxdart`-debounce — нужен.

```dart
blocTest<ItemListBloc, ItemListState>(
  'loads first page on init',
  build: () {
    when(() => repository.getItems(config: any(named: 'config'))).thenAnswer(
      (_) async => RepositoryResult.success(
        data: (
          [const ItemModel(id: '1', name: 'A')],
          const PageMetadata(nextPage: 2, total: 40),
        ),
      ),
    );
    return ItemListBloc();
  },
  act: (bloc) => bloc.add(const Initialize()),
  wait: const Duration(milliseconds: 350), // ждём debounce, если используется rxdart-вариант
  expect: () => [
    isA<Initialized>().having((s) => s.loadingInProgress, 'loadingInProgress', true),
    isA<Initialized>()
        .having((s) => s.items.length, 'items.length', 1)
        .having((s) => s.nextPage, 'nextPage', 2)
        .having((s) => s.total, 'total', 40)
        .having((s) => s.pagingState.hasNextPage, 'hasNextPage', true),
  ],
);
```

Что обязательно покрыть тестами:
- первая загрузка успешна;
- догрузка добавляет в **конец** `items`, не затирает существующие;
- смена `searchQuery` ⇒ `items` очищается, `nextPage` сбрасывается на `defaultPage`, `pagingState.reset()` применён;
- ответ с `nextPage == null` (или `nextCursor == null`) ⇒ `hasNextPage: false`, `isLastPage: true`;
- ошибка догрузки ⇒ `pagingState.error` заполнен, `loadingInProgress: false`, экран НЕ уходит целиком в `Error`;
- ошибка первой страницы при пустом списке ⇒ эмит `ItemListState.error`;
- пустой первый ответ при пустом списке ⇒ `isNoItems`-ветка helper'а (пустой `pages`, `hasNextPage: false`).

`PagingStateExt.applyPage` тестируется **отдельным** unit-тестом (без BLoC): склейка списка, пересчёт `pages`/`keys`, ветка `isNoItems`, перенос `nextPage`.

---

## 9. Чеклист интеграции в новый экран

1. Подключить `infinite_scroll_pagination: ^5.1.1` + `bloc_concurrency` (+ опционально `rxdart`) в `pubspec.yaml`.
2. Использовать общий доменный `PageMetadata` (`lib/domain/repository/base/`) + data-слойную обёртку `PaginatedResponse<T>` (`lib/data/model/pagination/`) (CURSOR-вариант — только если эндпоинт курсорный).
3. Привести списочный метод репозитория к канонической сигнатуре `Future<RepositoryResult<(List<T>, PageMetadata)>> getItems({required GetItemsConfig config})` через `BaseRepositoryHelper.execute`.
4. Подключить общий extension `PagingStateExt.applyPage` (один на проект; OFFSET по умолчанию).
5. В Freezed-стейте `Initialized` хранить тройку: `PagingState<String, T>`, `List<T> items`, `int nextPage` (+ `total`, `loadingInProgress`, `refreshInProgress`, `searchQuery`). Производное — в extension-геттере (`isAnyInProgress`).
6. Сделать единый `LoadItems({required bool reset})`; debounce обязателен (`sequential()` для load + `restartable()` для поиска).
7. Параметры запроса (search/sort/filter) — из `state`, не из event.
8. Любое изменение фильтра/поиска/сортировки ⇒ `pagingState.reset()` + очистка `items` + обнуление `nextPage` + `add(LoadItems(reset: true))`.
9. Pull-to-refresh: `RefreshRequested(Completer<void>)` + `AppRefreshIndicatorWidget` над `Scaffold`.
10. В UI — `PagedListView<String, T>.separated` внутри `BlocSelector` по `pagingState`; заполнить все слоты `PagedChildBuilderDelegate`; `key: ValueKey(item.id)`.
11. Покрыть BLoC тестами по чеклисту из §8 + отдельный unit-тест на `applyPage`.

---

## 10. Антипаттерны (чего избегать)

- **Не использовать `PagingController`** из v4 — он держит свой стейт вне BLoC и ломает single source of truth.
- **Не плодить** отдельные `LoadFirstPageEvent` / `LoadNextPageEvent` — один `LoadItems({reset})` дешевле в поддержке.
- **Не вызывать `fetchNextPage` без debounce** — `PagedListView` дёргает его агрессивно при скролле.
- **Не хранить `pages: List<List<T>>` напрямую** в стейте — там должна быть плоская `List<T>`; преобразование в `pages` делает helper.
- **Не передавать** поисковую строку/сортировку через `LoadItems` — читать из `state`, иначе UI и BLoC разойдутся.
- **Не использовать «сырой» `Future + try/catch`** в репозитории — только `RepositoryResult` + `BaseRepositoryHelper.execute` (envelope + обязательное логирование + перевод исключений).
- **Не класть `fromJson`** на BLoC-типы (`*.g.dart` для стейта/event запрещён) — у Freezed-юнионов BLoC только `*.freezed.dart`.
- **Не двигать `nextPage`** при `applied.nextPage == null` — это сигнал «страниц больше нет».
- **Не забыть `BlocSelector`** по `pagingState` в UI — без него список ребилдится на каждое изменение стейта.
- **Не кэшировать** пагинированные server-owned списки в DAO/`BehaviorSubject` — по carve-out из `04-data-layer.md` они network-only.

---

## Чеклист

- [ ] Подключены `infinite_scroll_pagination ^5.1.1` (v5) + `bloc_concurrency` (+ опц. `rxdart`).
- [ ] Созданы `PageMetadata` (OFFSET, по умолчанию) и `PaginatedResponse<T>`; `CursorPaginationMetadata` — только под курсорные эндпоинты.
- [ ] Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>` через `BaseRepositoryHelper.execute` (никакого «сырого» `try/catch`).
- [ ] Один общий `PagingStateExt.applyPage` (OFFSET) на проект; CURSOR-вариант — по необходимости.
- [ ] Freezed-стейт `Initialized` хранит `PagingState` + плоский `items` + `nextPage` (+ `total`/`loadingInProgress`/`refreshInProgress`/`searchQuery`); производное — в extension-геттере.
- [ ] Единый `LoadItems({required bool reset})`; debounce обязателен (`sequential()` + `restartable()` основной путь).
- [ ] Параметры запроса читаются из `state`; reset-on-filter через `pagingState.reset()` + очистка + перезапуск.
- [ ] `result.exception` пробрасывается в `pagingState.error` (догрузка) / `ItemListState.error` (первая страница при пустом списке).
- [ ] UI: `PagedListView` в `BlocSelector` по `pagingState`; все слоты делегата заполнены; `ValueKey(item.id)`.
- [ ] Pull-to-refresh: `RefreshRequested(Completer<void>)` + `AppRefreshIndicatorWidget` над `Scaffold`.
- [ ] BLoC покрыт тестами (§8) + отдельный unit-тест на `applyPage`.
- [ ] `fvm flutter analyze` проходит для затронутых файлов.

# 07 — Пагинация

> **Назначение:** зафиксировать единственный канонический стандарт постраничной подгрузки списков в приложении NOX — библиотека `infinite_scroll_pagination` ^5.1.1 (v5, stateless), `PagingState<K,T>` внутри Freezed-стейта BLoC, переиспользуемый extension `PagingStateExt.applyPage` и две модели пагинации контракта v0 — страничная (список чатов) и seq-курсорная (история сообщений). **Когда читать:** перед реализацией любого экрана со списком, который сервер отдаёт постранично (первый реальный кейс — список чатов: общий открытый server-owned список, который с фазы 026 читается **read-through**: страница берётся с сервера и оседает в `ChatDao` поверх Sembast, а кэш отдаёт срез сам только на реактивном тике и при мёртвом канале), а также при ревью BLoC, отдающего `PagingState`. **Связанные документы:** `05-presentation-layer.md` (BLoC = Freezed, `BaseBloc`, страницы, `state.when`), `04-data-layer.md` (`RepositoryResult`, `ResponseEntity`, mapper, кэш-first vs network-only), `03-domain-layer.md` (доменные модели `@freezed`, `RepositoryException`), `06-theming.md` (токены для индикаторов/разделителей), `10-code-templates.md` (полные шаблоны), `08-conventions-and-constitution.md` (правила слоёв).

> **Реактивный рефреш поверх пагинации (Feature 014).** `PagingState` + `applyPage` + `getX` остаются **единственной проекцией** списка; реактивность добавляется как **change-signal**: подписка на `watchX()` (значение игнорируется) диспатчит `loadX(refresh: true)`, который перечитывает уже загруженное через тот же `getX`/`applyPage` и складывает результат в live-стейт (без спиннера, сохраняя scroll/поиск/desktop-выбор). Форма перечитывания зависит от пути: список чатов заново читает префикс страниц `1..loadedPageCount`; тред с фазы 025 делает ОДИН tail-запрос `limit = items.length + pageSize` (курсорный путь не имеет номеров страниц). С фазы 026 (живой бэкенд в окружении `dev` — это флейвор `stage`, флейвора `dev` в проекте нет) так и вышло — форма не изменилась: `watchX()` — стрим изменений над локально-кэшированным срезом (`ChatDao.watch()` / `MessageDao`), а `getX` идёт в сервер с фолбэком в кэш при мёртвом канале (`on SocketUnavailableException`); сам тик рефреша перечитывает с флагом `cachedOnly: true` и провода не касается. См. `specs/014-reactive-data-refresh/`.

---

## 1. Что это и почему именно так

Постраничная подгрузка — частая операция в NOX: список чатов, любой server-owned постраничный каталог. Стандарт здесь **один на всё приложение** и не допускает разнобоя.

Ключевые решения (заблокированы для всего блюпринта):

1. **Библиотека — `infinite_scroll_pagination` ^5.1.1 (v5).** В 5-й мажорной версии она stateless: `PagingState<K,T>` — это обычное иммутабельное значение, которое лежит внутри стейта BLoC и напрямую передаётся в `PagedListView(state:, fetchNextPage:)`. **Никаких `PagingController`** (это паттерн v4, он держит собственный стейт вне BLoC и ломает single source of truth) и никаких `addPageRequestListener`.
2. **`PagingState<K,T>` — часть Freezed-стейта BLoC.** Лежит в варианте-наследнике `Initialized` (см. `05-presentation-layer.md` про Freezed-юнионы и канонические подсостояния `Initializing` / `Initialized` / `Error`). Пагинация прививается одинаково независимо от того, Freezed стейт или нет, — три поля (`pagingState`, плоский `items`, `nextPage`/`nextCursor`) просто живут в loaded-кейсе.
3. **Плоский `List<T>` + производные `pages`.** В стейте храним **плоский** `List<T> items` для бизнес-логики (выбор, удаление, поиск), а `pages: List<List<T>>`, которого требует `PagedListView`, **пересчитываем** в helper'е. Хранить `pages: List<List<T>>` напрямую — антипаттерн.
4. **Две контрактные модели пагинации (контракт v0, фаза 025).** Метаданные едины — `PageMetadata{required bool hasMore, int? nextPage}` (`hasMore` = wire `has_more`; `total` на проводе не существует). Список чатов — **страничный** путь (`page`/`page_size` в запросе, `nextPage` вычисляется клиентски, `hasMore` с провода); история сообщений — **курсорный** путь (`before_seq` от минимального загруженного `seq`, `limit`, порция по возрастанию `seq`; `nextPage` не используется). Серверный потолок порции — 100 c молчаливым клампингом.
5. **`RepositoryResult` остаётся.** Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>` (envelope из `04-data-layer.md`), а не «голый» `Future` + `try/catch`. BLoC вызывает `result.match` / `result.hasData`, применяет helper, и пробрасывает `result.exception` в `pagingState.error` — для v5-билдеров ошибок. **Это ключевое правило:** мы НЕ используем «сырой» `Future + try/catch`, а всегда оборачиваем загрузку страницы в наш envelope.
6. **Один helper `PagingStateExt.applyPage` на весь проект.** Инкапсулирует пересчёт `pages`/`keys`/`hasNextPage`, ветку «пустой результат», всё через `copyWith`. Юнит-тестируется отдельно.
7. **Debounce обязателен** на событии загрузки — `PagedListView` дёргает `fetchNextPage` агрессивно.

---

## 2. Зависимости (`pubspec.yaml`)

```yaml
dependencies:
  flutter_bloc: ^9.0.0                # BLoC
  infinite_scroll_pagination: ^5.1.1  # PagingState + PagedListView (v5, stateless)
  bloc_concurrency: ^0.3.0            # event transformers (sequential / restartable) — primary option
  rxdart: ^0.28.0                     # debounceTime for a custom transformer — alternative
```

Документация библиотеки: <https://pub.dev/documentation/infinite_scroll_pagination/latest/>.

---

## 3. Архитектурные принципы (сводка)

1. `PagingState<K,T>` — это часть Freezed-стейта BLoC, а не `PagingController`.
2. Стейт (вариант `Initialized`) хранит три параллельные сущности:
   - `PagingState<String, ItemModel>` — для рендера в `PagedListView` (внутри уже есть `pages`, `keys`, `hasNextPage`, `isLoading`, `error`);
   - `List<ItemModel> items` — плоский список для бизнес-логики;
   - `int nextPage` (страничный путь) **или** `int? oldestLoadedSeq` (seq-курсор треда) — координата следующей порции.
3. Сервер возвращает `has_more` вместо `total` (контракт v0); на страничном пути `nextPage = hasMore ? page + 1 : null` (1-based, вычисляется клиентски), на курсорном — следующая порция запрашивается `before_seq = min(seq загруженного)`. `hasMore == false` означает «страниц больше нет».
4. **Один** универсальный `LoadItems({required bool reset})` — делает и первую загрузку, и догрузку, и сброс после смены фильтра.
5. Параметры запроса (search / sort / filter) читаем **из стейта, а не из event** — UI вызывает просто `add(LoadItems(reset: false))` без аргументов.
6. Любое изменение фильтра/поиска/сортировки ⇒ `pagingState.reset()` (метод пакета) + очистка `items` + обнуление `nextPage` + `add(LoadItems(reset: true))`.
7. Debounce обязателен на `LoadItems`.
8. Никакой ручной работы с `pages` и `keys` — всё в `PagingStateExt.applyPage`.

---

## 4. Data-слой: метаданные и обёртка ответа

### 4.1 Метаданные пагинации — общий `PageMetadata`

`PageMetadata` — это **доменный** `@freezed`-тип (только `*.freezed.dart`, **без** JSON), который живёт в `lib/domain/repository/base/`. Маппинг ответа в `(List<ItemModel>, PageMetadata)` — задача **data**-слоя (реализация репозитория, см. §4.3 и §4.5, плюс канон `04-data-layer.md` §8). `hasMore == false` ⇒ это была последняя страница; `nextPage` — **1-based** индекс следующей страницы страничного пути (курсорный путь оставляет его `null`).

```dart
// lib/domain/repository/base/page_metadata.dart
/// Contract-shaped page metadata: the server reports only whether more rows
/// exist beyond this slice (no totals on the wire). nextPage carries the
/// 1-based next page index for the paged chats path; the cursor-paged
/// messages path leaves it null and advances by before_seq instead.
@freezed
abstract class PageMetadata with _$PageMetadata {
  const factory PageMetadata({
    /// Whether rows exist beyond this slice (wire has_more).
    required bool hasMore,

    /// 1-based index of the next page (paged path only), null otherwise.
    int? nextPage,
  }) = _PageMetadata;
}
```

> **Замечание по контракту (актуализировано фазой 025).** Реальные формы зафиксированы контрактом v0: страницы `{chats|messages, has_more}`, история — курсором `before_seq`/`limit` (порция по возрастанию `seq`, потолок 100 c клампингом). Живые кадры сервера закоммичены в `test/fixtures/wire/` и пиннят wire-слой. Мёртвый verification-срез `ItemsEntity{items, page, page_size, total}` сохраняет старую форму намеренно (не продукт).

### 4.2 Метаданные пагинации — CURSOR (альтернатива)

**Реальный курсорный путь проекта — история сообщений (фаза 025) — обходится БЕЗ отдельного класса метаданных.** `GetMessagesConfig` несёт `{chatId, int? beforeSeq, int limit, bool cachedOnly}` (статики `tail(...)` — с фазы 026 принимает `cachedOnly`, тот самый флаг реактивного тика — и `olderThan(...)`); потолок порции серверный, поэтому клампится не в фабриках, а на проводе: `maxLimit = 100` + геттер `wireLimit` (кэш-only чтение вправе просить окно шире — иначе уже сохранённые строки стали бы недостижимы); репозиторий возвращает тот же `PageMetadata{hasMore}`; координату держит блок треда — `oldestLoadedSeq` в стейте, догрузка `olderThan(oldestLoadedSeq)`, оптимистичные отправки сортируются вниз сентинелом `kPendingSeq`. Тред при этом не использует `PagedListView` — `reverse: true` `ListView.builder` + prefetch по `ScrollController`; но `applyPage` он ВЫЗЫВАЕТ для сборки `PagingState` (учёт `hasNextPage`, см. `chat_thread_bloc.dart`).

Класс `CursorPaginationMetadata` ниже остаётся документированной альтернативой для эндпоинтов со **строковым** непрозрачным курсором (в проекте пока не встречаются) — в `lib/` его сегодня **нет**; когда понадобится, он ляжет тоже `@freezed`, **без** JSON, в ту же папку `lib/domain/repository/base/`. Всё остальное (BLoC, UI, helper) — идентично.

```dart
// lib/domain/repository/base/cursor_pagination_metadata.dart
@freezed
abstract class CursorPaginationMetadata with _$CursorPaginationMetadata {
  const factory CursorPaginationMetadata({String? nextCursor}) = _CursorPaginationMetadata;
}
```

### 4.3 Маппинг ответа списка → `(List<ItemModel>, PageMetadata)`

Отдельной generic-обёртки списка на **data**-слое **нет** (лишняя сущность). Репозиторий ходит не в REST-класс напрямую, а в `ItemRemoteDataSource` (seam фичи 016), чья mock-реализация делегирует в `GetItemsApi` (`lib/data/remote/api/item/get_items_api.dart`); обе стороны возвращают `ResponseEntity<ItemsEntity>`, где `ItemsEntity` — JSON-сериализуемая entity (`*.freezed.dart` + `*.g.dart`), которая несёт срез страницы плюс offset-метаданные: `items`, `page`, `page_size`, `total`. Эта форма — **замороженный мёртвый verification-срез**, а не продуктовый контракт: продуктовый страничный путь (`chats.list`, контракт v0 §4) отдаёт `{chats, has_more}` и `total` на проводе не имеет. Маппинг `ItemsEntity{items, page, page_size, total}` → `(List<ItemModel>, PageMetadata)` выполняет реализация репозитория — канон описан в [04-data-layer.md](04-data-layer.md) §8 и ниже в §4.5. `nextPage` — ТОЛЬКО клиентское вычисление; формула координаты (1-based):

```dart
// lib/data/entity/item/items_entity.dart
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

```dart
// Inside ItemRepositoryImpl.getItems (canon — 04-data-layer.md §8, full code — §4.5):
// 1-based offset: there are more pages while fewer than total have been fetched.
final hasMore = (entity.page * entity.pageSize) < entity.total;
final nextPage = hasMore ? entity.page + 1 : null;
```

- Выбрано всё (`page * page_size >= total`) ⇒ `hasMore == false` ⇒ `nextPage = null` — страниц больше нет.
- Пустой `items` на запрошенной странице — штатное завершение списка (`nextPage = null`), не ошибка.
- `total` в `PageMetadata` не попадает — репозиторий сворачивает его в `hasMore` (контрактные обёртки v0 отдают `has_more` готовым, без `total`).

> Envelope реален с фазы 025: `ResponseEntity<T>` несёт `success` + `error{code, message}` + `data` (контракт v0, §2.1), распаковка — `BaseRepositoryHelper.unwrapEnvelope` + `EntityConverter`. Имена ключей и путь запроса `GetItemsApi` (`v1/items`, query `page` / `page_size` / `search`) остаются примером мёртвого verification-среза — как и его собственный комментарий «backend/protocol not chosen», намеренно замороженный вместе со срезом; продуктовые формы — `{chats|messages, has_more}` (см. замечание по контракту в §4.1).

### 4.4 Конфиг запроса — `GetItemsConfig`

Параметры списка собираются в иммутабельный `@freezed`-конфиг, реализующий `RepositoryConfig` (живёт в `lib/domain/...`, см. `03-domain-layer.md`). Никаких магических чисел страницы в BLoC — первая страница выражается только фабрикой `GetItemsConfig.firstPage()`. `defaultPage = 1` (1-based — как в контракте v0 §4: `chats.list{page, page_size, query?}` → `{chats, has_more}`); `pageSize = 20` — клиентский дефолт, отправляется в `page_size` всегда явно (серверный потолок — 100 с молчаливым клампингом). Продуктовый близнец этого конфига — `GetChatsConfig` (`lib/domain/repository/chat/get_chats_config.dart`) с теми же `defaultPage`/`pageSize`; `GetItemsConfig` ниже — замороженный verification-срез.

```dart
// lib/domain/repository/item/get_items_config.dart
@freezed
abstract class GetItemsConfig with _$GetItemsConfig implements RepositoryConfig {
  const GetItemsConfig._();

  const factory GetItemsConfig({required int page, String? search}) = _GetItemsConfig;

  factory GetItemsConfig.firstPage({String? search}) => GetItemsConfig(page: defaultPage, search: search);

  factory GetItemsConfig.nextPage({required int page, String? search}) => GetItemsConfig(page: page, search: search);

  static const int pageSize = 20;
  static const int defaultPage = 1;
}
```

### 4.5 Репозиторий: контракт и реализация

Пагинированный server-owned список отдаёт канонический метод `getItems` (префикс `get*` = параметризованный/списочный запрос; `fetch*` зарезервирован под одиночный one-shot `fetchItem`). Метод возвращает `RepositoryResult<(List<ItemModel>, PageMetadata)>` — Dart-record в payload, обёрнутый в наш envelope (именованные варианты `RepositoryResult.success(data:)` / `RepositoryResult.error(exception:)`). Низкоуровневые исключения data-слоя не образуют отдельной типизированной иерархии: их **маппит в `enum RepositoryException` (маркер `BaseRepositoryException`)** и обязательно логирует через `LogRepository` миксин `BaseRepositoryHelper.execute<TD>()` (см. `04-data-layer.md`). Веток перевода **четыре**: уже доменный `BaseRepositoryException` (например, код ошибки контракта, поднятый `unwrapEnvelope` через `RepositoryException.fromWireCode`) пробрасывается неразбавленным; `SocketUnavailableException` → `connection` (фаза 026 — без неё мёртвый канал попал бы в catch-all как `unknown`, и кэш-фоллбэк ниже стал бы недостижим); `DioException` маппится по типу и статусу (таймауты/`connectionError` → `connection`, 401 → `unauthenticated`, 403 → `authentication`, 404 → `notFound`, остальное → `internal`); catch-all → `unknown`. Форма возврата одинакова независимо от того, откуда репозиторий берёт срез: продуктовые пагинированные списки (чаты, история сообщений) с фазы 026 — **read-through поверх кэша** (`ChatDao` / `MessageDao` поверх Sembast): каждое не-`cachedOnly` чтение идёт в `*RemoteDataSource` ровно за запрошенным окном и оседает в кэше (`_persistWire` / `_fetchWindow`, а не единоразовый seed фичи 013), поиск по чатам намеренно уходит на сервер (локальная фильтрация превратила бы «поиск по общему пространству» в «поиск по загруженному»), `PageMetadata` списка чатов берётся с провода (`hasMore`), а у треда собирается как «источник ИЛИ остаток кэша»; кэш обслуживает срез сам только при `cachedOnly: true` (тик рефреша) и при мёртвом канале (`on SocketUnavailableException`), а действительно **network-only** (без DAO/subject) остался только замороженный verification-срез `Item`: чатовые one-shot команды с фазы 026 тоже пишут в DAO (`createChat` и `updateChatName` кладут серверный ответ через `_chatDao.upsert`, `isChatNameTaken` сперва смотрит в кэш), а отправка сообщения с фазы 027 идёт вообще не одним выстрелом, а через долговечную очередь (`outbox`). Канон обеих веток — `04-data-layer.md` §8.

Полный контракт `ItemRepository` — канонический (см. `04-data-layer.md`); ниже показан целиком как **аспирационный стандарт блюпринта**, списочный метод — `getItems`:

```dart
// lib/domain/repository/item/item_repository.dart
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/item/get_item_config.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';

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
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/data/remote/datasource/item_remote_data_source.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';

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
}
```

> **Канонический шаблон vs текущий harness (FR-013).** В `lib/` реальный `ItemRepository` — намеренно урезанный подмножество показанного контракта: только `getItems(...)` + `clean()` (network-only, без DAO/subject — carve-out, доживший ровно в этом замороженном verification-срезе, а не в продуктовых списках). Полный CRUD + cache-first `watchItem` (с `ItemDao` + `BehaviorSubject`) — это завершённый Item-пример блюпринта, который приходит вместе с фичей, которой нужно кэширование; см. `04-data-layer.md`. Реализация `getItems` выше — байт-в-байт с `lib/data/repository/item/item_repository_impl.dart`: конструктор `(this._itemMapper, this._itemRemote)` с зависимостью на интерфейс `ItemRemoteDataSource` (seam фичи 016, а не на конкретный API-класс; логирование наследуется через mixin `BaseRepositoryHelper`, без инъекции `LogRepository`-поля), null-payload ⇒ `RepositoryResult.error(exception: RepositoryException.unknown)`, маппинг через `_itemMapper.toListModel(entities: entity.items)`. За интерфейсом сегодня стоит `MockItemRemoteDataSource`, делегирующий в MOCK-класс `GetItemsApi` (path `v1/items`, query `page` / `page_size` / `search`) — замороженный пример verification-среза. Продуктовый транспорт — WebSocket-конверт контракта v0 — пришёл **фазой 026**: `NoxSocketClient` (`lib/data/remote/socket/nox_socket_client.dart`) плюс DI-флип mock → real в окружении `dev`, куда ведёт флейвор `stage` (флейворы — только `stage` и `prod`): `RealChatRemoteDataSource` / `RealMessageRemoteDataSource`, `env: [Environment.dev]` (`MockItemRemoteDataSource` флипа не получает и остаётся во всех окружениях — срез мёртвый). REST/Dio остаётся только под upload/download блобов (фаза 028); боевой контур поверх `wss:443` с пиннингом ключа — **целевая форма продакшена, в коде её ещё нет**: `socket_channel_factory.dart` — голый `IOWebSocketChannel.connect(url, pingInterval: 25s)` без `SecurityContext` и проверки отпечатка, а адрес берётся из `AppConfig.apiUrl` (в `config/stage.json` это локальный `http://127.0.0.1:8080`).

---

## 5. Подпись-фигура: `PagingStateExt.applyPage`

**Это сердце всего подхода** — расширение над `PagingState<K,T>`, скрывающее пересчёт `pages`/`keys`/`hasNextPage` и ветку «пустой результат». Один на проект, юнит-тестируется отдельно.

Ниже — вариант для страничного пути. Запись `response` распаковывается через `final (incoming, meta) = response;`, где `meta` — `PageMetadata`; признак «последняя страница» — `!meta.hasMore` (фаза 025), в record возвращается `int? nextPage`. CURSOR-вариант (§5.1) — тот же helper, но `meta` — `CursorPaginationMetadata` и возвращается `String? nextCursor`.

```dart
// lib/presentation/pagination/paging_state_ext.dart
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';

/// Encapsulates v5 PagingState assembly (page-of-pages + keys + hasNextPage).
/// Generic over K (K = item id, one item per page). Used by BOTH contract-v0
/// paths: the paged chats list and the seq-cursor thread — the end of the list
/// is `!meta.hasMore`, while the next coordinate (`nextPage` or `before_seq`)
/// is the caller's business.
extension PagingStateExt<K, T> on PagingState<K, T> {
  ({List<T> updatedList, PagingState<K, T> pagingState, int? nextPage}) applyPage({
    required List<T> existingList,
    required (List<T>, PageMetadata) response,
    required K Function(T) keyExtractor,
  }) {
    final (incoming, meta) = response;
    final updatedList = [...existingList, ...incoming];
    final isLastPage = !meta.hasMore;
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
// lib/presentation/pagination/paging_state_ext_cursor.dart  (NOT in lib/ today: it would replace applyPage only on a
// string-cursor endpoint; the project's real seq-cursor thread uses the paged applyPage — see the note below)
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/domain/repository/base/cursor_pagination_metadata.dart';

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

> В проекте подключён **только** страничный вариант helper'а — им пользуется и реальный курсорный путь (тред, seq-курсор `before_seq`): `applyPage` собирает его `PagingState`, а координату держит `oldestLoadedSeq` в стейте, не `nextPage` (см. §4.2). CURSOR-extension добавляется, лишь когда появится эндпоинт со строковым курсором.

---

## 6. BLoC-слой (Freezed)

BLoC построен по правилам `05-presentation-layer.md`: `@freezed sealed State` с подсостояниями `Initializing` / `Initialized` / `Error` (как `const factory`), `@freezed sealed Event`, производная логика — в extension-геттерах, переходы — через `copyWith`. На BLoC-типах **нет** `fromJson` (только `*.freezed.dart`).

### 6.1 State (Freezed-юнион)

Поля пагинации (`pagingState`, `items`, `nextPage`) живут в варианте `Initialized` плюс вспомогательные поля (`loadingInProgress`, `refreshInProgress`, `searchQuery`; `total` из стейтов удалён фазой 025 — его больше нет и в `PageMetadata`). Производный геттер `isAnyInProgress` — в extension, не в `@freezed`-теле. Имена членов юниона — **bare** (`Initializing` / `Initialized` / `Error`), как в боевом коде; префиксная форма (`ItemList<...>`) — допустимый вариант против коллизий имён, но канон блюпринта здесь — bare.

```dart
// lib/presentation/pages/item_list_page/bloc/item_list_state.dart
part of 'item_list_bloc.dart';

@freezed
sealed class ItemListState with _$ItemListState {
  const factory ItemListState.initializing() = Initializing;

  const factory ItemListState.initialized({
    required PagingState<String, ItemModel> pagingState,
    @Default(<ItemModel>[]) List<ItemModel> items,
    @Default(GetItemsConfig.defaultPage) int nextPage,
    @Default(false) bool isLastPage,
    @Default(false) bool loadingInProgress,
    @Default(false) bool refreshInProgress,
    @Default('') String searchQuery,
  }) = Initialized;

  const factory ItemListState.error({BaseRepositoryException? exception}) = Error;
}

/// Computed (derived) logic lives in extension getters, NOT in the @freezed body.
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
  /// Fired once from initState: ..add(const ItemListEvent.initialize()).
  const factory ItemListEvent.initialize() = Initialize;

  /// reset == true — first page / after a filter change; false — load more.
  const factory ItemListEvent.loadItems({required bool reset, Completer<void>? completer}) = LoadItems;

  /// Pull-to-refresh: complete the completer once loading finishes.
  const factory ItemListEvent.refreshRequested({required Completer<void> completer}) = RefreshRequested;

  /// Search query change (debounce + reset).
  const factory ItemListEvent.updateSearchQuery({required String value}) = UpdateSearchQuery;

  /// Item tapped — navigation flows via a side-effect stream (see 05-presentation-layer.md §3.3).
  const factory ItemListEvent.showItemDetails({required String itemId}) = ShowItemDetails;
}
```

### 6.3 Debounce-трансформеры

Debounce **обязателен** на `LoadItems` — `PagedListView` вызывает `fetchNextPage` агрессивно во время скролла.

**Основной вариант — `bloc_concurrency`:**

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

on<LoadItems>(_onLoadItems, transformer: sequential());        // strictly serial, no page races
on<UpdateSearchQuery>(_onUpdateSearchQuery, transformer: restartable()); // new input cancels the old one
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
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/item/get_items_config.dart';
import 'package:nox_app/domain/repository/item/item_repository.dart';
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

  // Navigation — side-effect stream (canon 05 §3.3), not via state. The page
  // subscribes to navigateToDetails in initState (full page widget — in 05 §3.3).
  final _navigateToDetailsController = PublishSubject<ItemModel>();

  Stream<ItemModel> get navigateToDetails => _navigateToDetailsController.stream;

  @override
  Future<void> close() async {
    await _navigateToDetailsController.close();
    await super.close();
  }

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

    // Params come from state, not from the event.
    final query = state.searchQuery;
    final isFirstPage = event.reset;
    final existingList = isFirstPage ? const <ItemModel>[] : state.items;
    final config = isFirstPage
        ? GetItemsConfig.firstPage(search: query.isEmpty ? null : query)
        : GetItemsConfig.nextPage(page: state.nextPage, search: query.isEmpty ? null : query);

    // Mark loading (PagedListView shows the bottom spinner itself).
    emit(state.copyWith(
      loadingInProgress: true,
      refreshInProgress: isFirstPage,
      pagingState: state.pagingState.copyWith(isLoading: true, error: null),
    ));

    // The load-handler body is wrapped in BaseBloc.executeLogic.
    await executeLogic(
      () async {
        final result = await _itemRepository.getItems(config: config);

        // Stale-guard: the user may have changed the search during the await.
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
              nextPage: applied.nextPage ?? updated.nextPage, // null => no more pages, keep coordinate
              isLastPage: !meta.hasMore,
              loadingInProgress: false,
              refreshInProgress: false,
            ));
          },
          onError: (exception) {
            if (isFirstPage && updated.items.isEmpty) {
              // First-page error with an empty list — the whole screen goes to Error.
              emit(ItemListState.error(exception: exception));
            } else {
              // Load-more error — surface in pagingState.error for newPageErrorIndicator.
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
        // BaseBloc guard branch for an unexpected throw that bypasses RepositoryResult.
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

    // Reset-on-filter: package reset() + clear items + reset nextPage + restart.
    emit(state.copyWith(
      items: const [],
      pagingState: state.pagingState.reset(),
      nextPage: GetItemsConfig.defaultPage,
      isLastPage: false,
      searchQuery: query,
    ));
    add(const LoadItems(reset: true));
  }

  void _onShowItemDetails(ShowItemDetails event, Emitter<ItemListState> emit) {
    final state = this.state;
    if (state is! Initialized) return;
    final match = state.items.firstWhereOrNull((e) => e.id == event.itemId);
    if (match != null) _navigateToDetailsController.add(match);
  }
}
```

**Критически важные моменты:**

- `PagingState.reset()` — метод пакета, возвращает чистый `PagingState`. Использовать **всегда** при смене фильтра/поиска/сортировки.
- `event.reset` различает первую загрузку (или после смены фильтра) и догрузку. При `reset: true` координату НЕ читаем — стартуем с `defaultPage`.
- Параметры запроса (search/sort/filter) читаем из `state`, а не передаём в `LoadItems`. UI вызывает просто `add(const LoadItems(reset: false))`.
- Stale-guard после `await`: повторно читаем `this.state` и сверяем `searchQuery` — чтобы не записать «протухший» ответ. `restartable()` на поиске даёт ту же защиту со стороны трансформера.
- Тело хендлера обёрнуто в `executeLogic(() async {…}, onError: (error, exception, stackTrace) {…})` базового блока (`BaseBloc`) — позиционный первый аргумент-логика + 3-аргументный `onError` (см. `05-presentation-layer.md` §2); это и есть точка единого логирования/обработки сбоев.
- `result.match(onData:, onError:)` — потребление `RepositoryResult` (именованные `success(data:)` / `error(exception:)`). `exception` уходит в `pagingState.error` (догрузка) или в `ItemListState.error` (первая страница при пустом списке) — это **ключевое правило**: мы не используем «сырой» `try/catch`, а потребляем `RepositoryResult`.

> **Канонический шаблон vs текущий verification-harness (FR-013).** Показанный выше BLoC — это **аспирационный канон** блюпринта (поиск с debounce, pull-to-refresh с `Completer`, stale-guard, side-effect-стрим `navigateToDetails`). Реальный `lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart` — намеренно урезанное подмножество:
> - `ItemListEvent` = `{ initialize, loadItems({@Default(false) bool reset}) }` — без `refreshRequested` / `updateSearchQuery` / `showItemDetails` / `Completer`;
> - `Initialized` = `{ pagingState, items, @Default(GetItemsConfig.defaultPage) int nextPage, isLastPage, loadingInProgress }` — без `searchQuery` / `refreshInProgress`; computed-геттеры в коде — `pagedItems` + `hasMore` (не `isAnyInProgress`);
> - только `sequential()` на `LoadItems`, без `restartable()`/поиска и без `PublishSubject`/`close()`;
> - дополнительная ранняя защита `if (!isReset && !current.pagingState.hasNextPage) return;` — пропуск догрузки, когда страниц больше нет (полезный hardening-приём, который стоит перенять и в канон).
>
> Это «verification harness на mock-данных», а не нарушение блюпринта: расширенные ветки (поиск/refresh/навигация) добавляются вместе с первой реальной фичей (список чатов).

---

## 7. UI-слой (`PagedListView` + pull-to-refresh)

> **Соответствие коду (Принцип III).** `lib/general/text_constants.dart` удалён — канон пользовательских строк это ARB-локализация (`lib/l10n/app_en.arb` + `app_uk.arb`, EN+UK, доступ через `context.l10n`). `TextConstants` в сниппетах ниже — историческое имя из скелета Feature-001; читай его как «строка из `context.l10n`». Так же читаются два других исторических имени в них: `AppTextStyleTokens.body(...)` / `.body2(...)` — это `bodyLarge(...)` / `bodyMedium(...)` (реальный набор фабрик — девять M3-ролей + `monoBody`, [06-theming.md](06-theming.md) §5), а `context.appColors.onSurface` / `.error` — это `Theme.of(context).colorScheme.onSurface` / `.error`: у `AppColors` всего два поля (`surfaceMuted`, `dividerSubtle`), и в коде фич расширение не вызывается ([06-theming.md](06-theming.md) §2).

`PagedListView` — обычный список, который читает `PagingState` и зовёт `fetchNextPage` при приближении к концу. Оборачиваем в `BlocSelector` по `pagingState`, чтобы не ребилдить список при изменении других полей (search text и т.д.). Pull-to-refresh — `AppRefreshIndicatorWidget` **над** `Scaffold`.

```dart
// lib/presentation/pages/item_list_page/item_list_page.dart (_buildList fragment)
Widget _buildList(Initialized state) {
  return BlocSelector<ItemListBloc, ItemListState, PagingState<String, ItemModel>>(
    // Select on pagingState — otherwise the list rebuilds on any state change.
    selector: (s) => s is Initialized ? s.pagingState : PagingState<String, ItemModel>(),
    builder: (context, pagingState) {
      return PagedListView<String, ItemModel>.separated(
        state: pagingState,
        fetchNextPage: () => context.read<ItemListBloc>().add(const LoadItems(reset: false)),
        builderDelegate: PagedChildBuilderDelegate<ItemModel>(
          itemBuilder: (context, item, index) => ItemTileWidget(
            key: ValueKey(item.id), // helps Flutter reuse widgets across a reset
            item: item,
            onTap: () => context.read<ItemListBloc>().add(ItemListEvent.showItemDetails(itemId: item.id)),
          ),
          firstPageProgressIndicatorBuilder: (_) =>
              const AppProgressWidget(),
          newPageProgressIndicatorBuilder: (_) => Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s16),
            child: const AppProgressWidget(),
          ),
          noItemsFoundIndicatorBuilder: (_) =>
              Center(child: Text(TextConstants.noData, style: AppTextStyleTokens.body(color: context.appColors.onSurface))),
          noMoreItemsIndicatorBuilder: (_) => const SizedBox.shrink(),
          firstPageErrorIndicatorBuilder: (_) => Center(
            child: AppErrorWidget(onTryAgain: () => context.read<ItemListBloc>().add(const LoadItems(reset: true))),
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
              initializing: () => const AppProgressWidget(),
              initialized: _buildList,
              error: (_) => Center(child: AppErrorWidget(onTryAgain: () => _bloc.add(const Initialize()))),
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

> **Текущий harness vs канон.** Реальный `lib/presentation/pages/item_list_page/item_list_page.dart` — намеренно минимальный: голый `PagedListView` (`CircularProgressIndicator` + `ListTile` + `AppHairlineDividerWidget` в `separatorBuilder`, тексты — через `context.l10n`), отрисованный **внутри body `AppShell`** (без собственного `Scaffold` и без `AppRefreshIndicatorWidget`), ветвление — `switch`-выражением по bare-состояниям. Это Scaffold-DEMO на mock-данных (FR-013), а не продуктовая фича; токен-виджеты и pull-to-refresh из канона выше приходят с реальным экраном.

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
          // Full page (pageSize=20) of a 40-row source => hasMore is true
          // and the client-computed nextPage advances (§4.5).
          List.generate(
            GetItemsConfig.pageSize,
            (i) => ItemModel(
              id: '$i',
              name: 'A$i',
              description: null,
              status: ItemStatus.active,
              createdAt: DateTime(2026),
            ),
          ),
          const PageMetadata(hasMore: true, nextPage: 2), // 1-based: after page 1 the next is 2
        ),
      ),
    );
    return ItemListBloc();
  },
  act: (bloc) => bloc.add(const Initialize()),
  wait: const Duration(milliseconds: 350), // wait for debounce if the rxdart variant is used
  expect: () => [
    // Emit 1 — _onInitialize: initialized(pagingState: PagingState()) BEFORE loading, loadingInProgress=false (default).
    isA<Initialized>().having((s) => s.loadingInProgress, 'loadingInProgress', false),
    // Emit 2 — _onLoadItems marks loading.
    isA<Initialized>().having((s) => s.loadingInProgress, 'loadingInProgress', true),
    // Emit 3 — onData: page loaded.
    isA<Initialized>()
        .having((s) => s.items.length, 'items.length', GetItemsConfig.pageSize)
        .having((s) => s.nextPage, 'nextPage', 2)
        .having((s) => s.pagingState.hasNextPage, 'hasNextPage', true),
  ],
);
```

Что обязательно покрыть тестами:
- первая загрузка успешна;
- догрузка добавляет в **конец** `items`, не затирает существующие;
- смена `searchQuery` ⇒ `items` очищается, `nextPage` сбрасывается на `defaultPage`, `pagingState.reset()` применён;
- ответ с `hasMore == false` (или `nextCursor == null` в cursor-варианте) ⇒ `hasNextPage: false`, `isLastPage: true`;
- ошибка догрузки ⇒ `pagingState.error` заполнен, `loadingInProgress: false`, экран НЕ уходит целиком в `Error`;
- ошибка первой страницы при пустом списке ⇒ эмит `ItemListState.error`;
- пустой первый ответ при пустом списке ⇒ `isNoItems`-ветка helper'а (пустой `pages`, `hasNextPage: false`).

`PagingStateExt.applyPage` тестируется **отдельным** unit-тестом (без BLoC): склейка списка, пересчёт `pages`/`keys`, ветка `isNoItems`, перенос `nextPage`.

---

## 9. Чеклист интеграции в новый экран

1. Подключить `infinite_scroll_pagination: ^5.1.1` + `bloc_concurrency` (+ опционально `rxdart`) в `pubspec.yaml`.
2. Использовать общий доменный `PageMetadata{hasMore, nextPage?}` (`lib/domain/repository/base/`); маппинг ответа в `(List<T>, PageMetadata)` — в реализации репозитория по канону `04-data-layer.md` §8: страничный путь берёт `has_more` с провода и вычисляет `nextPage` клиентски (1-based), seq-курсорный (`before_seq`/`limit`) оставляет `nextPage` пустым. Свёртка `ItemsEntity{…, total}` → `hasMore` — частный случай замороженного verification-среза, а не образец для продуктового эндпоинта.
3. Привести списочный метод репозитория к канонической сигнатуре `Future<RepositoryResult<(List<T>, PageMetadata)>> getItems({required GetItemsConfig config})` через `BaseRepositoryHelper.execute`.
4. Подключить общий extension `PagingStateExt.applyPage` (один на проект; им пользуются оба пути).
5. В Freezed-стейте `Initialized` хранить тройку: `PagingState<String, T>`, `List<T> items`, `int nextPage` (+ `loadingInProgress`, `refreshInProgress`, `searchQuery`). Производное — в extension-геттере (`isAnyInProgress`).
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
- **Не считать пагинированный список автоматически network-only** — продуктовые списки (чаты, история сообщений) с фазы 026 — read-through через DAO (запрос в источник + запись в кэш, кэш как фолбэк); без DAO/subject остался только замороженный `Item`-срез: чатовые one-shot команды пишут в DAO, а отправка сообщения идёт через очередь `outbox` (`04-data-layer.md` §6а, §8). Форма возврата от ветки не зависит: всегда `RepositoryResult<(List<T>, PageMetadata)>`.

---

## Чеклист

- [ ] Подключены `infinite_scroll_pagination ^5.1.1` (v5) + `bloc_concurrency` (+ опц. `rxdart`).
- [ ] Используется общий `PageMetadata{hasMore, nextPage?}`; `nextPage` вычисляется клиентски в репозитории (канон `04-data-layer.md` §8); seq-курсор сообщений идёт через `GetMessagesConfig.tail/olderThan` без отдельного класса метаданных.
- [ ] Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>` через `BaseRepositoryHelper.execute` (никакого «сырого» `try/catch`).
- [ ] Один общий `PagingStateExt.applyPage` на проект; отдельный CURSOR-вариант — только под строковый курсор.
- [ ] Freezed-стейт `Initialized` хранит `PagingState` + плоский `items` + `nextPage` (+ `loadingInProgress`/`refreshInProgress`/`searchQuery`); производное — в extension-геттере.
- [ ] Единый `LoadItems({required bool reset})`; debounce обязателен (`sequential()` + `restartable()` основной путь).
- [ ] Параметры запроса читаются из `state`; reset-on-filter через `pagingState.reset()` + очистка + перезапуск.
- [ ] `result.exception` пробрасывается в `pagingState.error` (догрузка) / `ItemListState.error` (первая страница при пустом списке).
- [ ] UI: `PagedListView` в `BlocSelector` по `pagingState`; все слоты делегата заполнены; `ValueKey(item.id)`.
- [ ] Pull-to-refresh: `RefreshRequested(Completer<void>)` + `AppRefreshIndicatorWidget` над `Scaffold`.
- [ ] BLoC покрыт тестами (§8) + отдельный unit-тест на `applyPage`.
- [ ] `fvm flutter analyze` проходит для затронутых файлов.

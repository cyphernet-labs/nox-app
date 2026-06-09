# Data Model: Инициализация Flutter-проекта NOX (multi-platform skeleton)

**Branch**: `001-flutter-project-init` | **Phase**: 1 (Design) | **Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

> **Назначение.** Зафиксировать «модель» каркаса. У скелета **нет продуктовых данных** (FR-013): нет чатов, сообщений, идентичности, авторизации. Поэтому модель здесь — это, во-первых, **структурные элементы** проекта (Key Entities из spec) с их атрибутами и правилами, а во-вторых, единственная конкретная data-форма каркаса — **`Item`-verification-harness** на mock-данных (scaffold-demo, не продуктовая фича). Третий блок — сквозной контракт результата `RepositoryResult<T>` + иерархия исключений. Продуктовые сущности (`Chat`, `Message`, идентичность/label) — **вне scope**, только названы как FUTURE.
>
> Источник истины «как» — блюпринт `docs/patterns/mobile/` (`00`/`03`/`04`/`05`/`11`). Бэкенд/протокол/криптоядро не выбраны — сетевые/auth/envelope/endpoint контракты помечены **пример/TBD** (ограничение конституции v1.1.0).

---

## 1. Структурные элементы каркаса («модель» скелета)

Это сущности из раздела **Key Entities** спеки. Каждая описана как «что это / ключевые атрибуты / отношения и правила». Это не runtime-объекты данных, а структурный инвариант проекта, который проверяется глазами против блюпринта.

### 1.1 App package (`nox_app`)

- **Что это.** Единственный Dart-пакет — корень всего кода; держит все слои как папки в одном `lib/` (FR-001; блюпринт `00`, несущий инвариант 1).
- **Ключевые атрибуты.**
  - `pubspec.yaml` `name: nox_app`; все импорты — `package:nox_app/...` (без относительных `../`, кроме `part`-директив).
  - `environment.sdk: '>=3.12.0 <4.0.0'`; Flutter `3.44.1` (пин через `.fvmrc`); line length `140`; lint — стоковый `flutter_lints` (FR-008).
  - Один `pubspec.yaml`, один прогон `build_runner`, один `configureDependencies(env)` / `$initGetIt` (FR-006, FR-007).
- **Отношения и правила.** Никаких трёх пакетов, path-зависимостей или мульти-пакетов. Десктоп-таргеты — дополнительные нативные runner'ы того же пакета (генерируются `flutter create`), не отдельные проекты.

### 1.2 Layer module (слой-папка)

- **Что это.** Слой внутри пакета как директория в `lib/`: `data` / `domain` / `presentation` / `di` / `general` / `design` / `resource` (FR-001; блюпринт `00`/`11` шаг 4).
- **Ключевые атрибуты (роль каждого слоя).**

  | Слой | Роль |
  |---|---|
  | `lib/domain` | Бизнес-контракты: Freezed-модели (без JSON), контракты репозиториев, конфиги, `RepositoryResult<T>`, иерархия исключений. Ничего не импортирует. |
  | `lib/data` | Реализация контрактов: entity (basic-types + JSON), мапперы, DAO (Sembast), repo-impl, remote-API (пример/TBD). |
  | `lib/presentation` | Flutter-UI и BLoC: `AppRoot`/`AppRootBloc`, `AppShell`, `BaseBloc`/`BaseStatePage`, страницы. |
  | `lib/di` | Единый DI-bootstrap: `configureDependencies`, `@InjectableInit`, сгенерированный `.config.dart`, `global_aliases`. |
  | `lib/general` | `Constants` (вкл. `railBreakpoint = 840`, `designSize = Size(360, 779)`), `PlatformUtils`, форматтеры, `TextConstants`, `LogRepository`-канал. |
  | `lib/design` | Тема: `AppTheme.light()/dark()`, `ThemeExtension<AppColors>`, классы токенов, `gen/`. |
  | `lib/resource` | Ассеты и строки (`TextConstants`, EN-only). |

- **Отношения и правила (несущий инвариант).** Зависимости строго однонаправленные: `presentation → domain`, `data → domain`; **`domain` не импортирует ничего** из приложения. Цикла `domain ↔ data` нет — DI связывает реализацию с контрактом без обратной зависимости. Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и не правятся руками.

### 1.3 Platform target

- **Что это.** Целевая платформа сборки; нативный runner того же пакета (FR-002, FR-003; блюпринт `11` шаг 2).
- **Ключевые атрибуты.** Ровно пять: `android`, `ios`, `macos`, `windows`, `linux`. **`web` отсутствует** в наборе таргетов (SC-006). Генерируются `flutter create --platforms=android,ios,macos,windows,linux`. Min-OS — дефолты Flutter `3.44.1` (Windows 10 / macOS 10.15 / GTK3); пин конкретики — FUTURE.
- **Отношения и правила.**
  - Compile/build-verify — 5/5; launch-verify этой итерации — macOS + iOS + Android; Windows/Linux launch — tracked follow-up (CI-раннеры).
  - Native-идентичность на десктопе — **prod-only** этой итерации: macOS `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp` + `PRODUCT_NAME = NOX`; Windows `BINARY_NAME = NOX` + фиксированный GUID; Linux `APPLICATION_ID = com.cyphernetlabs.noxapp` / `.desktop` `Name = NOX`. Distinct stage native identity на десктопе — FUTURE.
  - Десктоп-специфичные деградации (push / deep-links / secure-storage / flavor-secrets) задокументированы прозой (FR-012, SC-007) — кода в скелете нет.

### 1.4 Flavor

- **Что это.** Compile-time вариант сборки, задающий идентификаторы и конфигурацию (FR-010; блюпринт `09`/`11`, инвариант 12).
- **Ключевые атрибуты.** Два значения — `stage`, `prod` (`enum AppFlavorType { prod, stage }`). Резолв — `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`. Маппинг flavor → DI-env: `prod → Environment.prod`, `stage → Environment.dev`.
- **Отношения и правила.**
  - Идентификаторы: prod `applicationId`/bundle id `com.cyphernetlabs.noxapp`, stage `com.cyphernetlabs.noxapp.stage`; display name `NOX` (FR-003).
  - **Никакого runtime-ветвления по flavor'у** — только compile-time.
  - Mobile (Android/iOS) — native `--flavor` + `--dart-define-from-file`. Desktop — flavor через `--dart-define-from-file=config/<flavor>.json` (только `app.flavor`, закоммичен, без секретов); secrets-decrypt на desktop в скелете пропускается (без age-ключа).

### 1.5 App shell

- **Что это.** Адаптивный навигационный каркас приложения с плейсхолдерным содержимым вкладок (FR-004; блюпринт `05` §6.5 / `11` шаг 9).
- **Ключевые атрибуты.**
  - Три назначения: `Chats`, создание чата `+`, `Settings`. Отдельного profile-экрана нет; аватар аккаунта из десктопного корпуса опущен.
  - Переключение раскладки — **width-driven** через `LayoutBuilder` по `constraints.maxWidth >= Constants.railBreakpoint` (840dp, граница M3 medium↔expanded), **не** по `Platform`.
  - Mobile-ветка (`< 840dp`): `Scaffold` + кастомный `BottomAppBar` (`CircularNotchedRectangle`) + центральный docked `+` FAB (`floatingActionButtonLocation: centerDocked`).
  - Desktop-ветка (`>= 840dp`): `NavigationRail` (width `80`, `labelType: all`, `+` как `leading` FAB) + `VerticalDivider` + `Expanded(body)`.
  - Destination-иконки: `Chats` = `Icons.forum`, `Settings` = `Icons.settings`; индикатор — стоковый M3 `secondaryContainer`; `body` = `IndexedStack` (сохраняет состояние вкладок).
- **Отношения и правила (скелет).** Обе destination'ы ведут на одну страницу-плейсхолдер `Item` (`Item`-harness, §2). `+` — no-op со snackbar'ом (через `AlertDialogHelper`), без create-flow. **Нет** list-detail / two-pane раскладки (приходит с реальными фичами). Single-window `Navigator` — единый канон на всех пяти таргетах; нативный OS-title-bar, дефолтное окно runner'а (`window_manager` / 1440×900 / min-size / кастомный title bar = FUTURE).

### 1.6 Design theme

- **Что это.** Тема light/dark, собранная только из дизайн-токенов NOX (FR-005; блюпринт `06`).
- **Ключевые атрибуты.** Material Design 3, light + dark, системная по умолчанию, seed = teal (из `docs/design/system/nox-handoff/`). `AppTheme.light()` / `AppTheme.dark()` композируют Material-базу + `extensions: [LightAppColors()/DarkAppColors()]`; доступ — `context.appColors`; `themeMode` поставляет `AppRootBloc`; токены spacing/typography responsive через `flutter_screenutil` (`designSize = Size(360, 779)`).
- **Отношения и правила.** В коде каркаса нет хардкод-`Color`/`EdgeInsets`/`TextStyle`/system-overlay-style (SC-005). Две brand-фиксированные exceptions независимы от темы: splash background всегда тёмный, QR surface всегда светлый (QR — вне скелета). Сгенерированный Dart дропается/регенерируется из токенов, не правится руками.

### 1.7 Verification harness (`Item`-слайс)

- **Что это.** Сквозной scaffold-demo-слайс блюпринта на **mock-данных** (не продуктовая фича, не реальный бэкенд) — доказывает, что полный вертикальный путь компилируется end-to-end, и несёт baseline-тесты (FR-013 исключение; блюпринт `11` шаг 10).
- **Ключевые атрибуты.** Полный вертикальный срез: `ItemModel` (domain) ↔ `ItemMapper` ↔ `ItemEntity` (data) ↔ `ItemDao` (Sembast), `GetItemsConfig`, `ItemRepository`/`ItemRepositoryImpl`, `ItemListBloc`/`ItemListEvent`/`ItemListState` + `ItemListPage`. Подробная форма — §2.
- **Отношения и правила.** Помечен как scaffold-demo на mock-данных. Список `Item` — server-owned **network-only** carve-out (без DAO/subject для пагинированного списка); источник в скелете — mock (реального бэкенда нет, FR-013). Baseline-тесты: `ItemListBloc` smoke (`Initialize → Initialized`) + round-trip `ItemMapper` (`ItemEntity ↔ ItemModel`).

### 1.8 App config (`AppConfig` / `AppConfigRepository`)

- **Что это.** Флейвор-зависимый конфиг-холдер, поднимаемый в bootstrap после готового DI-контейнера (FR-006/FR-010; `contracts/di-bootstrap.md` §3; блюпринт `02` §7 / `14`).
- **Ключевые атрибуты.** `AppFlavor.getFlavor()` + `enum AppFlavorType { prod, stage }` (`lib/domain/model/app_config/`); `AppConfigRepository.initialize(flavorType:)` вызывается в `main.dart` **после** `getIt.allReady()`. В скелете несёт **только флейвор**; источник токена / `apiUrl` / security-заголовки — **пример/TBD** (бэкенд NOX не выбран).
- **Отношения и правила.** Контракт — `lib/domain/repository/app_config/`; impl — `lib/data/repository/app_config/`; модель — `lib/domain/model/app_config/`. Bootstrap-последовательность идентична на всех 5 таргетах (desktop отличается только источником флейвора — см. §1.4).

---

## 2. `Item` verification-harness — data-форма

Единственная конкретная data-форма каркаса. Следует worked-примеру блюпринта (`03` §6 / `04` §1 / `05` §3). Все поля — на уровне, который подразумевает пример `Item` в блюпринте. **Это mock-данные, не продуктовая модель.**

### 2.1 `ItemModel` — доменная модель (Freezed, без JSON)

`lib/domain/models/item/item_model.dart` (блюпринт `03` §6.1, `11` шаг 10a).

| Поле | Тип | Обязательность | Заметка |
|---|---|---|---|
| `id` | `String` | required | Идентификатор; ключ пагинации (`K = String`) и `ValueKey` тайла. |
| `name` | `String` | required | Отображаемое имя (worked-пример; в `11` шаг 10a — `name`). |
| `description` | `String?` | nullable | Пустая строка нормализуется в `null` в маппере. |
| `status` | `ItemStatus` | `@Default(ItemStatus.draft)` | Богатый enum (в entity хранится как `.name`). |
| `createdAt` | `DateTime` | required | Богатый тип `DateTime` (в entity — ISO-8601 String). |

- **Правила.** `@freezed` + `with _$ItemModel` + `const factory`; ровно одна `part '*.freezed.dart'`; **нет** `fromJson`/`.g.dart`. Производная логика (`isPublished`, `displayName`) — во внешнем `extension ItemModelExt`, не в теле `@freezed`.
- **`ItemStatus`** (`lib/domain/models/item/item_status.dart`): `enum ItemStatus { active, archived, draft }` — мелкий enum в отдельном файле рядом с моделью.

> Поля `imageUrl` / `tags` присутствуют в расширенном worked-примере блюпринта (`03` §6.1), но базовый минимум `Item`-harness — `id` / `name` / `description` / `status` / `createdAt` (форма из `11` шаг 10a). Дополнительные поля опциональны для скелета.

### 2.2 `ItemEntity` — DTO (Freezed + json_serializable, basic-types)

`lib/data/entity/item/item_entity.dart` (блюпринт `04` §1, `11` шаг 10b).

| Поле | Тип | Обязательность | Коэрция (в маппере) |
|---|---|---|---|
| `id` | `String` | required | — |
| `name` | `String` | required | — |
| `description` | `String?` | nullable | пустая строка → `null` |
| `status` | `String` | required | enum-`name` ↔ `ItemStatus` через `values.firstWhere(orElse: draft)` |
| `createdAt` | `String` | required | ISO-8601 ↔ `DateTime` через `parse` / `toIso8601String` |

- **Правила.** Обе `part`-директивы (`.freezed.dart` + `.g.dart`) + `fromJson`. **Только базовые типы** (`String`/`int`/`double`/`bool` + их `List`) — никаких enum-как-enum/`DateTime`. Должен быть зарегистрирован в `EntityConverter` в **обеих** цепочках (`fromJson` + `toJson`).
- **`ItemsEntity`** (`items_entity.dart`): обёртка-коллекция `{ @Default([]) List<ItemEntity> items, @Default(0) int count }` + `fromJson` — single-record store для DAO и форма ответа списочного эндпоинта (`count` = серверный `total`).

### 2.3 `ItemMapper` — entity ↔ model

`lib/data/mapper/item/item_mapper.dart` (блюпринт `04` §4, `11` шаг 10b).

- `@lazySingleton class ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic>`.
- Выполняет **лоссless round-trip** `ItemEntity ↔ ItemModel`: `status` через enum-`name`/`firstWhere(orElse: draft)`, `createdAt` через `DateTime.parse`/`toIso8601String`, пустой `description` → `null`. Вся коэрция «примитив ↔ богатый тип» — только здесь.
- Гарантия: `toEntity(model: toModel(entity: e)) == e` (база round-trip-теста, §1.7).

### 2.4 `ItemDao` — локальное хранилище (Sembast)

`lib/data/local/item/item_dao.dart` (блюпринт `04` §6, `11` шаг 10b).

- `@lazySingleton`; `StoreRef<String, Map<String, dynamic>>`; реактивный `watch()` через `onSnapshots()`, one-shot `getData()`, `saveData`/`upsert`/`removeById`/`cleanData` через атомарные `db.transaction()`.
- Битые записи → пустой список/`null` (не убивают поток); сбой хранилища → **сырое исключение** (ловит catch-all `execute()` → `RepositoryException.unknown`). Cache-miss/not-found — забота callback'а репозитория, не DAO.
- **Network-only carve-out:** для пагинированного списка `getItems` DAO **не используется** (нет DAO-записи для серверного пагинированного списка). DAO нужен только кэшируемой одиночной сущности (`watch`-часть); в чистом скелете `Item`-список идёт по network-only ветке. `AppDatabase` env-scoped: Dev/Prod = `databaseFactoryIo`, Test = `databaseFactoryMemory`.

### 2.5 `GetItemsConfig` — конфиг вызова (Freezed, без JSON)

`lib/domain/repository/item/get_items_config.dart` (блюпринт `03` §5.2, `11` шаг 10a).

| Поле | Тип | Заметка |
|---|---|---|
| `page` | `int` | required; 1-based |
| `search` | `String?` | nullable |

- Константы: `static const int pageSize = 20;`, `static const int defaultPage = 1;`.
- Фабрики: `GetItemsConfig.firstPage({String? search})`, `GetItemsConfig.nextPage({required int page, String? search})`.
- **Правила.** `@freezed abstract` + `implements RepositoryConfig`; только `.freezed.dart`, без `.g.dart`. **Без** `cacheOnly` — список network-only (carve-out). Один Freezed-класс на вызов, не sealed-union на фичу.

### 2.6 `ItemListState` / `ItemListEvent` — BLoC-юнионы (Freezed sealed)

`lib/presentation/pages/item_list_page/bloc/` (блюпринт `05` §3, `11` шаг 10c). Только `.freezed.dart`, **никогда** `.g.dart`/`fromJson` (in-memory типы).

**`ItemListState`** — `@freezed sealed`, подсостояния как `const factory`:

| Вариант | Несёт | Смысл |
|---|---|---|
| `Initializing` | — | Загрузка / экран не готов. |
| `Initialized` | `items: List<ItemModel>`, `pagingState: PagingState<String, ItemModel>`, `total: int`, `nextPage: int`, `isLastPage: bool`, `loadingInProgress: bool`, `refreshInProgress: bool`, `searchQuery: String` | Данные готовы. |
| `Error` | `exception: BaseRepositoryException?` | Сбой init/операции. |

- `PagingState<String, ItemModel>` — ключ `K = String` (= `id` элемента, one-item-per-page); offset отслеживается через `PageMetadata.nextPage` (`int`) в state, не через `K`. Производные геттеры (`isAnyInProgress`, `isEmpty`) — в `extension InitializedExt`, не в теле `@freezed`.

**`ItemListEvent`** — `@freezed sealed`: `Initialize` / `LoadItems({reset, completer?})` (или эквивалент `FetchNextPage`) / `RefreshRequested({completer})` / `UpdateSearchQuery({value})` / `ShowItemDetails({itemId})`. Состав событий — по worked-примеру `05` §3.1 (`11` шаг 10c перечисляет `Initialize`/`FetchNextPage`/`RefreshList`/`SelectItem`/`DeleteItem` как эквивалентный набор).

> Дефолтный flavor пагинации — **OFFSET** (`PageMetadata{int? nextPage, int total}` — `page`/`page_size`/`count`); CURSOR — задокументированная альтернатива. Конкретный контракт пагинации (списка чатов) финализируется позже с бэкендом NOX — **пример/TBD**. `result.exception` пробрасывается в `pagingState.error` для v5-error-builder'ов.

### 2.7 Mock-источник (скелет)

Реального бэкенда нет (FR-013). В скелете `Item`-список питается mock-данными: `GetItemsApi` (`lib/data/remote/api/item/get_items_api.dart`) для среза допускает mock-body; контракт REST/envelope/endpoint (`ResponseEntity<T>` `{data, timestamp, trace_id, meta}`, путь `v1/items`, токен-модель, HMAC/security-заголовки) — **пример/TBD**, заменяется реальным контрактом при выборе бэкенда NOX.

### 2.8 Поток harness (end-to-end)

```text
ItemListPage (presentation)
  → ItemListBloc (getIt<ItemRepository>)
    → ItemRepository.getItems(GetItemsConfig)        [domain contract]
      → ItemRepositoryImpl (data, BaseRepositoryHelper.execute + LogRepository)
        → GetItemsApi (mock-body; реальный REST = пример/TBD)   [NETWORK-ONLY, без DAO]
          → ResponseEntity<ItemsEntity> → ItemMapper.toListModel → (List<ItemModel>, PageMetadata)
      ← RepositoryResult<(List<ItemModel>, PageMetadata)>
    ← match(onData / onError) → PagingStateExt.applyPage → emit(Initialized)
```

---

## 3. Cross-cutting контракт результата

Сквозной примитив, доступный в каркасе даже без реальных репозиториев (FR-014; блюпринт `03` §1–§3).

### 3.1 `RepositoryResult<T>` — data XOR exception

`lib/domain/repository/base/repository_result.dart`.

- `@freezed sealed class RepositoryResult<T>` с **взаимоисключающими** публичными вариантами:
  - `RepositoryResultSuccess<T>` — несёт `data: T` (фабрика `RepositoryResult.success({required T data})`).
  - `RepositoryResultError<T>` — несёт `exception: BaseRepositoryException` (фабрика `RepositoryResult.error({required BaseRepositoryException exception})`).
- Геттеры: `hasData` (булева проверка success), `data` (`T?`, `null` на error), `exception` (`BaseRepositoryException?`, `null` на success).
- **Правила.** Только `.freezed.dart` (не сериализуется, нет `.g.dart`/`fromJson`). Заполнить оба поля одновременно невозможно. **Канон потребления — `match()`**; прямой `result.data!` запрещён вне `hasData`-guard'а.
- **`match<R>({onData, onError})`** (`repository_result_handling.dart`) — исчерпывающий `switch` по двум публичным вариантам; без `onPartial`/`onEmpty`.
- Каждый метод репозитория возвращает `Future<RepositoryResult<T>>` или `Stream<RepositoryResult<T>>`, никогда голый `Future<T>`. `.exception` всегда подтип `BaseRepositoryException`.

### 3.2 Иерархия исключений

- **`BaseRepositoryException`** (`lib/domain/exception/base_repository_exception.dart`) — однострочный маркер `abstract class BaseRepositoryException {}`. Без методов, без JSON.
- **`RepositoryException`** (`lib/domain/exception/repository_exception.dart`) — `enum RepositoryException implements BaseRepositoryException` со значениями:

  | Значение | Смысл |
  |---|---|
  | `unknown` | Обобщённая / немаппнутая ошибка (fallback). |
  | `internal` | Невосстановимое внутреннее состояние / серверная ошибка (5xx). |
  | `authentication` | Провал аутентификации (неверные учётные данные). |
  | `connection` | Сетевой/I-O сбой, таймаут, недостижимый сервер. |
  | `unauthenticated` | Не аутентифицирован (401, нужен повторный вход). |
  | `notFound` | Ресурс не существует (404). |

- **Маппинг (data-слой).** Единственный механизм — `BaseRepositoryHelper.execute<T>()`: `on DioException → RepositoryException.internal`, любой другой `catch → RepositoryException.unknown`; **обязательно** логирует через `LogRepository` перед возвратом. Точные доменные коды (например `notFound` при cache-miss) возвращает сам callback явным `RepositoryResult.error(...)`. Типизированных `ApiException`/`DaoException` в проекте нет.
- **`RepositoryConfig`** (`lib/domain/repository/base/repository_config.dart`) — маркер `abstract class RepositoryConfig {}`; каждый per-call конфиг (`GetItemsConfig`) его реализует.

---

## 4. Продуктовые сущности — OUT (FUTURE, не моделируются)

Следующие сущности **намеренно не входят** в скелет (FR-013) и здесь только названы как будущие — без полей, без data-модели. Они принадлежат отдельным spec-циклам:

- **`Chat`** — открытое общее пространство (server-owned, network-only пагинированный список). Первая реальная фича после скелета; ляжет в `Item`-harness один-в-один. Глобально-уникальное имя ≤64, генерируемый аватар (initials + hash-цвет) — детали в продуктовом spec-цикле, не здесь.
- **`Message`** — текст/файл; локальный статус `sent`/`pending`/`error` (без delivered/read). Не моделируется.
- **Идентичность / label (User identity)** — технический анонимный `Your ID` + публичный label; одна идентичность на устройство, full local wipe при logout; опирается на secure storage (Keychain/DPAPI/libsecret — задокументированы прозой, wiring с auth). Не моделируется.

> Любая из этих сущностей вводится только в своём spec-цикле; контракты сети/auth/envelope/crypto для них — **пример/TBD** до выбора бэкенда/протокола NOX.

---

## 5. Сводка соответствия

| Структурный элемент / форма | Источник (spec) | Источник (блюпринт) |
|---|---|---|
| App package `nox_app` | FR-001, Key Entities | `00`, `11` шаг 2 |
| Layer module ×7 + dependency rules | FR-001, US2 | `00`, `11` шаг 4 |
| Platform target ×5 (no web) | FR-002/003, SC-006 | `11` шаг 2 |
| Flavor `stage`/`prod` | FR-010 | `09`, `11`, инвариант 12 |
| App shell (adaptive) | FR-004 | `05` §6.5, `11` шаг 9 |
| Design theme (light/dark) | FR-005, SC-005 | `06`, `11` шаг 8 |
| Verification harness (`Item`) | FR-013 (исключение), SC-004 | `11` шаг 10 |
| `Item` data-форма (model/entity/mapper/dao/config/state/event) | FR-013 | `03` §5–§6, `04` §1/§4/§6, `05` §3 |
| `RepositoryResult<T>` + исключения | FR-014 | `03` §1–§3 |
| App config (`AppConfig`/`AppConfigRepository`/`AppFlavor`) | FR-006, FR-010 | `02` §7, `14`, `contracts/di-bootstrap.md` |
| `Chat`/`Message`/identity — OUT | FR-013, Assumptions | `00` (named, не моделируются) |

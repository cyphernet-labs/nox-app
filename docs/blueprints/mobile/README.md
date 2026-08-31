# NOX — Архитектурный блюпринт

> **Назначение:** канонический референс архитектуры, паттернов и инфраструктуры кросс-платформенного приложения **NOX** (iOS, Android, Windows, Linux, macOS; web — вне scope; Flutter), которое реализуется в `lib/`. Этот набор документов — единственный источник правды для любого разработчика (и для Claude Code) при имплементации **каждой** фичи приложения. **Когда читать:** перед началом работы над приложением целиком, перед любой новой фичей, и как справочник по конкретному слою/паттерну. **Связанные документы:** все 18 спутниковых файлов `00-architecture-overview.md` … `17-analytics.md` (таблица ниже).
>
> **Статус: рабочий блюпринт** — принят как авторитетный референс для `lib/` (2026-06-08). Любая Flutter/клиентская задача проектируется и кодится **по этому набору** (платформы — iOS, Android, Windows, Linux, macOS; web — вне scope); найденные баги/неверные/расходящиеся реализации приводят блюпринт в корректный вид в том же change-set'е. **Desktop проработан для скелета:** desktop-floor зафиксирован (дефолты Flutter `3.44.1`: Windows 10 / macOS 10.15 / GTK3), single-window подтверждён, адаптивная оболочка выставлена (`NavigationRail` на десктопе, width-driven порог `840dp`), desktop-идентичность задана (prod-only), а desktop compile-smoke прогоняется в CI (3 джоба). **Остаётся FUTURE:** packaging/signing, отдельная stage native identity для десктопа, `window_manager`-полировка (`1440×900` / min-size `640×600` / кастомный title bar) и per-подсистема desktop-native wiring (push / deep-links / secure-storage), которое материализуется с первым потребителем. **Правило fallback:** no-op stub вводится с первым desktop-потребителем подсистемы, не раньше. Известные отложенные гэпы (desktop FUTURE — см. выше; фиче-слои MVP — сетевой auth (app-state-spine реализован в Feature-009: `AppStateRepository`/`SessionRepository`/`AuthRepository` + двухфазная `AppRoot`-навигация; ветка `401 → forced logout` проложена в Feature-019 и остаётся инертной: DI-флип на реальные data-source'ы выполнен фазой 026 (`RealChatRemoteDataSource`/`RealMessageRemoteDataSource` в окружении `dev` — флейвор `stage`, `config/stage.json`), но прикладной обмен идёт по WebSocket, а Dio зарезервирован под блобы фазы 028; реальный sign-in — этап 2 контракта, всё ещё открыт), file-download, доменные контракты, client Sentry, native deep-link, локализация) **сейчас не покрываются**; при заходе в клиентскую фичу — пересобрать gap-анализ.

---

## Что это

Это **унифицированный** и самодостаточный блюпринт — единственный авторитетный референс архитектуры приложения. Новый код пишется только по `docs/blueprints/mobile/`.

> **Источник дизайна (актуальный).** Авторитетная UI/UX-спецификация NOX — в [`../../design/spec/`](../../design/spec/) (`overview.md`, `top-level-screens.md`, `screens/*.md`, `design-system.md`). Машинно-читаемый design-system-хендофф (W3C DTCG-токены — источник истины — плюс сгенерированный Flutter Dart) — в [`../../design/system/nox-handoff/`](../../design/system/nox-handoff/). Блюпринт описывает, **как** реализовать дизайн в коде (особенно [`06-theming.md`](06-theming.md) — маппинг сгенерированных `ColorScheme`/`TextTheme`/токенов в Flutter); регенерировать из токенов, а не править Dart руками.

Блюпринт **доменно-нейтрален**: он описывает архитектуру, слои, кодоген, тулинг и инфраструктуру, не привязываясь к конкретной бизнес-логике. Сквозной worked-пример — нейтральная фича `Item`. **Первая реальная фича**, собранная по этому блюпринту, — список чатов (открытый общий список чатов: server-owned на проводе, но на клиенте — cache-first поверх Sembast, страничный путь контракта v0); об этом упоминается там, где это уместно, но шаблоны остаются на нейтральном `Item`.

---

## Несущие инварианты (проекция конституции и золотых правил)

Это несущие инварианты. Всё остальное — стиль. Авторитетный свод — **9 принципов + 10 золотых правил** (см. [`08-conventions-and-constitution.md`](08-conventions-and-constitution.md)); список ниже — их операционная проекция в этом индексе. Два решения блюпринта — **BLoC = Freezed** и **пагинация = `infinite_scroll_pagination` v5** — свёрнуты в существующие принципы/правила (не как новые отдельные пункты).

1. **ОДИН Dart-пакет, слои — это папки.** Никаких трёх пакетов и path-deps. Слои живут как директории внутри одного `lib/`: `lib/data`, `lib/domain`, `lib/presentation`, плюс `lib/di`, `lib/general`, `lib/design`, `lib/resource` (последняя — зарезервированный/пустой плейсхолдер, сейчас только `.gitkeep`). ОДИН `pubspec.yaml`, ОДИН прогон `build_runner`. Однонаправленные зависимости: `presentation → domain`, `data → domain`; **`domain` не импортирует ничего**. Любые трёхпакетные пути (`domain/lib/src/...`, `data/lib/src/...`) переписываются в однопакетные (`lib/domain/...`, `lib/data/...`). См. `00-architecture-overview.md`.

2. **Единый DI:** один `configureDependencies(String env)` + один `@InjectableInit(initializerName: r'$initGetIt')` + один сгенерированный `configure_dependencies.config.dart`. Никакой трёхуровневой цепочки. См. `02-dependency-injection.md`.

3. **BLoC = Freezed.** `@freezed` `sealed`-юнионы для State и Event; тонкий `BaseBloc<E, S>` с `executeLogic` (try/catch). Производная/вычисляемая логика — в **extension-геттерах** (не в теле `@freezed`-класса). `copyWith` для переходов; `sealed` для много-вариантных юнионов, `abstract` для одно-вариантных value-объектов; **никакого `fromJson` на BLoC-типах** (только `*.freezed.dart`, никогда `*.g.dart`). Это правило блюпринта: BLoC-типы строятся на Freezed, а не на рукописном `sealed` + `Equatable`. Канонические имена под-состояний — `Initializing` / `Initialized` / `Error` (bare-имена union-членов, как в коде; при коллизиях допустим префиксный вариант `<Feature>Initializing`…) — выражаются Freezed-`const factory`-конструкторами. См. `05-presentation-layer.md`.

3a. **Навигируемая страница ⇒ собственный BLoC (даже без логики).** Любой `*Page` с `routeName`/`route()`, попадающий в навигацию приложения, **обязан** иметь свой BLoC: logic-less/статичная страница получает минимальный BLoC (трио `Initializing`/`Initialized`/`Error` или одновариантный value-BLoC а-ля `AppRootBloc`). Переиспользуемые **виджеты** (`lib/presentation/widgets/`) BLoC **не требуют**. См. `05-presentation-layer.md` / `08-conventions-and-constitution.md` Принцип 5.1.

4. **Пагинация = `infinite_scroll_pagination` ^5.1.1** (v5, stateless `PagingState`-в-bloc, **никогда** `PagingController`). Переиспользуемое расширение `PagingStateExt.applyPage` — общее для **обоих** путей контракта v0 (признак конца списка везде `!meta.hasMore`). Доменные метаданные — `PageMetadata{required bool hasMore, int? nextPage}`, **без** `total` (сервер тоталов не отдаёт). Два реальных пути: **(а) список чатов — страничный** (запрос `page`/`page_size`, ответ `{chats, has_more}`; `defaultPage = 1`, `nextPage = hasMore ? page + 1 : null` считается клиентски); **(б) история сообщений — seq-курсор** (запрос `before_seq` + `limit`, ответ `{messages, has_more}`, батч по возрастанию `seq`, сервер молча зажимает `limit` до 100) — там `nextPage` всегда `null`, а координату держит `Initialized.oldestLoadedSeq` в `ChatThreadBloc`. `CursorPaginationMetadata{String? nextCursor}` остаётся задокументированной опцией для гипотетического эндпоинта со **строковым** курсором. Verification-срез `Item` заморожен на своей offset-обёртке `ItemsEntity{items, page, page_size, total}` и сворачивает её в тот же `PageMetadata` (`hasMore = (page*pageSize) < total`) — это пример скелета, а не продуктовый канон. Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>`; `result.exception` прокидывается в `pagingState.error` для v5-error-builder'ов. UI-сторона: список чатов рендерит `PagedListView`, тред — `reverse: true` `ListView.builder` с префетчем от `ScrollController`. См. `07-pagination.md`.

5. **`RepositoryResult<T>` — `@freezed` с data-XOR-exception** (фабрики `success` / `error`, а не «оба nullable»). Усечённое расширение `match<R>(onData, onError)`. Каждый метод репозитория возвращает `RepositoryResult<T>` (или `Stream<RepositoryResult<T>>`), и `.exception` всегда — маркер `BaseRepositoryException` (`RepositoryException` — enum-подтип, реализующий маркер; при необходимости — feature-specific enum'ы того же маркера), никогда сырой `Exception` или фреймворковая ошибка. Отдельной типизированной иерархии исключений data-слоя нет — ошибки мапятся в `RepositoryException` внутри `BaseRepositoryHelper.execute`, у которого **три** ветки `catch`: уже смапленный `BaseRepositoryException` пробрасывается без изменений (не деградирует в `unknown`), `DioException` мапится по типу/статусу (таймауты и `connectionError` → `connection`; 401 → `unauthenticated`; 403 → `authentication`; 404 → `notFound`; иначе `internal`), всё остальное → `unknown`. Коды ошибок провода (контракт v0 §2.1: `invalid_request`, `name_taken`, `payload_too_large`, `attachment_gone`, `rate_limited`, `unsupported_schema`, …) переводятся в enum статикой `RepositoryException.fromWireCode(String)` (неизвестный код → `internal` по правилу эволюции), а единая точка распаковки конверта — `BaseRepositoryHelper.unwrapEnvelope<TD>(ResponseEntity<TD> response, String what)`. См. `03-domain-layer.md`.

6. **Трёхчастный data-split.** API JSON ↔ `Entity` (Freezed **+** `json_serializable`, basic-types-only) ↔ `Mapper` ↔ доменная `Model` (**только** Freezed, без JSON). Бизнес-логика — в `extension`'ах на модели, не в теле Freezed-класса. Сохраняется `ResponseEntity<T>` + рукописный реестр `EntityConverter<E>`; реальная форма конверта — `ResponseEntity({@Default(false) bool success, ErrorWireEntity? error, @EntityConverter() T? data})`, где `ErrorWireEntity{code, message}` — объект ошибки контракта v0 §2.1 (`success` зеркалит проводной `ok`). Новая сущность, достижимая через конверт, добавляется в **обе** цепочки `EntityConverter` (`fromJson` и `toJson`), иначе — `ArgumentError` в рантайме. Вся коэрция типов (`enum` как `.name` String, `DateTime` как ISO-8601 String) — в маппере. См. `04-data-layer.md`.

7. **Один конфиг-объект на API-вызов** — Freezed-класс, передаваемый как `{required XxxConfig config}` (например `GetItemsConfig`). См. `03-domain-layer.md` / `04-data-layer.md`.

8. **Только design-токены.** Никаких хардкод-`Color`, `EdgeInsets`, `TextStyle` или system-overlay-style в коде фич. Тема — **light + dark** через `ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `context.appColors` + `themeMode` из `AppRootBloc`, но с конкретной палитрой и `flutter_screenutil`-токенами spacing/typography + `AppOverlayStyleTokens`. Гибрид. См. `06-theming.md`.

9. **Codegen-first.** Freezed + `json_serializable` + `injectable` + `flutter_gen`. Генератор прогоняется после правки любого аннотированного класса. Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и **никогда не правятся руками**.

10. **Единый канал логирования** — **обязательный** `LogRepository`. Сырые `print` / `debugPrint` в `lib/` запрещены. `BaseRepositoryHelper.execute<T>()` ВСЕГДА логирует через `LogRepository`; ошибки уходят в observability-backend. См. `04-data-layer.md`.

11. **Реактивные cache-first репозитории** — умолчание для всех продуктовых ресурсов: Sembast DAO (`onSnapshots`, транзакции) + env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory) через `@LazySingleton(as: AppDatabase, env: [...])`. Реактивный канал репозитория — `async*`-стрим поверх снапшотов DAO (`watchChats()`, `watchMessages(chatId)`); `BehaviorSubject<RepositoryResult<...>>` остаётся формой для репозитория **без** DAO, проецирующего выведенное состояние (`AppStateRepositoryImpl`). Пагинация, поиск и запись считаются по локальному стору, а `*RemoteDataSource` наполняет его (seed-once на пустом сторе). **Прежний network-only carve-out для paginated server-owned списков отменён (Feature-013):** и список чатов, и история сообщений — cache-first с DAO; network-only остаётся только в замороженном verification-срезе `Item`. См. `04-data-layer.md`.

12. **Compile-time изоляция flavor'ов.** `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг flavor → env: `prod → Environment.prod`, `stage → Environment.dev`. Все flavor-специфичные значения приходят через `--dart-define-from-file`; никакого runtime-ветвления по flavor'у. Секреты — SOPS + age + mise + flavored-сборки Android/iOS. Версионирование — CalVer + shifted-epoch (`YY.M.D+EPOCH`). `main.dart` оборачивается в `runZonedGuarded`, ждёт `configureDependencies(env)` затем `getIt.allReady()`, после чего вызывает `runApp(AppRoot)`. См. `09-build-and-secrets-infra.md`.

---

## Соглашения проекта (используются эти точные имена)

| Сущность | Значение | Значение по умолчанию |
|---|---|---|
| Имя Dart-пакета | `pubspec.yaml` `name:`; все импорты `package:nox_app/...` | `nox_app` *(имя пакета можно переименовать — отмечено только здесь, в README)* |
| Отображаемое имя | App display name | `NOX` |
| `applicationId` / iOS bundle (prod) | Android `applicationId`, iOS bundle id | `com.cyphernetlabs.noxapp` |
| `applicationId` / iOS bundle (stage) | то же для stage-flavor | `com.cyphernetlabs.noxapp.stage` |
| Flavors | Две compile-time-сборки | `stage`, `prod` |
| Flutter SDK | Пинится через FVM (`.fvmrc`) | `3.44.1` |
| Dart SDK constraint | `pubspec.yaml` `environment.sdk` | `>=3.12.0 <4.0.0` |
| Line length | `dart format -l` / `analysis_options.yaml` | `140` |

**Нейтральный worked-пример фичи — `Item`:** `ItemModel` / `ItemEntity` / `ItemRepository` / `ItemRepositoryImpl` / `ItemMapper` / `ItemDao` / `ItemListPage` / `ItemListBloc` / `ItemListEvent` / `ItemListState` / `GetItemsConfig`.

**Пустые скелеты** используют плейсхолдеры `<Feature>` / `<feature>` / `<Model>` — заменяйте их консистентно при инстанцировании шаблона.

**Импорты:** полные `package:`-импорты, без относительных `../` (исключение — директивы `part`). Сгенерированные файлы руками не правятся (см. золотое правило 9).

---

## Карта документов (TOC)

Читать по порядку; каждый документ самодостаточен и содержит **дословные** copy-paste-ready шаблоны (адаптируются find-and-replace'ом плейсхолдеров — `Item` → реальная фича, `<Feature>` → имя).

| # | Документ | Однострочное описание |
|---|---|---|
| — | [`README.md`](README.md) | Этот индекс: назначение, золотые правила, таблица соглашений/имён, TOC, порядок чтения, ключевые решения. |
| 00 | [`00-architecture-overview.md`](00-architecture-overview.md) | Ментальная модель: один пакет, слои-папки, граф зависимостей `presentation → domain ← data`, сквозной read/write data-flow. |
| 01 | [`01-stack-and-tooling.md`](01-stack-and-tooling.md) | Версии Flutter/Dart, полный список зависимостей с обоснованием, FVM, кодоген-стек, lint-конфиг. |
| 02 | [`02-dependency-injection.md`](02-dependency-injection.md) | Единый `injectable` + `get_it`: `configureDependencies(env)`, `@InjectableInit`, окружения prod/dev/test, сгенерированный `.config.dart`. |
| 03 | [`03-domain-layer.md`](03-domain-layer.md) | Контракты репозиториев, Freezed-модели (без JSON), config-объекты, иерархия исключений, `RepositoryResult<T>` (data-XOR-exception). |
| 04 | [`04-data-layer.md`](04-data-layer.md) | Entity (basic-types), `ResponseEntity`/`EntityConverter`, мапперы, REST-API + request-builder, Dio-клиент, repo-impl'ы (cache-first), Sembast DAO. |
| 05 | [`05-presentation-layer.md`](05-presentation-layer.md) | Freezed-BLoC (`BaseBloc`, sealed State/Event, extension-геттеры), страницы, навигация, error-surfacing, accessibility. |
| 06 | [`06-theming.md`](06-theming.md) | Light + dark через `ThemeExtension<AppColors>`, `AppTheme.light()/dark()`, `context.appColors`, `themeMode` из `AppRootBloc`, `flutter_screenutil`-токены. |
| 07 | [`07-pagination.md`](07-pagination.md) | Контракт пагинации: `infinite_scroll_pagination` v5, `PagingState`-в-bloc, `PagingStateExt.applyPage`, страничный путь чатов (`page`/`page_size`) и seq-курсорный путь треда (`before_seq`/`limit`). |
| 08 | [`08-conventions-and-constitution.md`](08-conventions-and-constitution.md) | Стиль кода, нейминг, форматирование, импорты, тесты, feature-flags, стенс по локализации, «конституция» проекта. |
| 09 | [`09-build-and-secrets-infra.md`](09-build-and-secrets-infra.md) | Flavor-изоляция, SOPS+age+mise, flavored-сборки Android/iOS, `dart-define-from-file`, версионирование CalVer, `main.dart`-bootstrap. |
| 10 | [`10-code-templates.md`](10-code-templates.md) | Copy-paste blank-скелеты (`<Feature>`/`<Model>`) для каждого артефакта архитектуры. |
| 11 | [`11-scaffolding-plan.md`](11-scaffolding-plan.md) | Упорядоченный end-to-end план поднятия проекта с нуля и проверки каждого этапа. |
| 12 | [`12-dev-commands.md`](12-dev-commands.md) | Повседневные команды (кодоген, format, analyze, test) и `.claude/commands`-хелперы. |
| 13 | [`13-deep-links.md`](13-deep-links.md) | Обработка входящих ссылок (deep / universal links): `app_links`, `DeepLinkRepository` (парсинг URI → типизированная модель), маршрутизация в `AppRoot`, нативная интеграция. |
| 14 | [`14-networking-and-auth.md`](14-networking-and-auth.md) | Сеть и авторизация: `ApiClient` (Dio + auth-interceptor), `AppConfigRepository` (флейвор-конфиг + источник токена), мост к REST-слою; §4 — адаптация под бэкенд NOX (HMAC-подпись + security-заголовки + access/refresh токен-модель — пример из другого проекта: у NOX транспорт — WebSocket-конверт контракта v0 (целевой прод-канал — `wss:443` с key pinning), клиент реализован фазой 026 (`lib/data/remote/socket/nox_socket_client.dart`, `lib/data/sync/live_session_starter.dart`); этап 1 сервера идёт **без** авторизации, модель аутентификации этапа 2 ещё открыта — `docs/client-backend/architecture/authentication.md`); §5 — connectivity + app-lifecycle. |
| 15 | [`15-push-notifications.md`](15-push-notifications.md) | Push-уведомления (FCM): `firebase_messaging` (mobile-only; desktop — disabled no-op по правилу fallback), device-токен и его ротация, регистрация/разрегистрация на бэкенде NOX, foreground/background/terminated, разрешения, навигация по тапу (через 13). |
| 16 | [`16-file-upload.md`](16-file-upload.md) | Загрузка вложения в чат: 2-step (upload → attach to message). Конкретные multipart-эндпоинты внутри документа — пример; реальный конвейер контракта v0 §7 — `file.uploadBegin` → `PUT` по одноразовому 10-минутному токену → `message.send{attachment:{file_id}}` (скачивание — `file.downloadBegin` → `GET` с `Range`); REST остаётся только для блобов, остальное идёт по сокету. File/image picker, размер/MIME-капы, идемпотентность по natural-key `(chat_id, client_message_id)`, BLoC-прогресс. |
| 17 | [`17-analytics.md`](17-analytics.md) | Клиентская аналитика (вендоронезависимо): `AnalyticsRepository` (интерфейс + impl), `@freezed`-таксоном `AnalyticsEvent`, super-properties, приватность (opt-in по умолчанию, без PII), точки трекинга. |

---

## Рекомендуемый порядок чтения

1. `00-architecture-overview.md` — ментальная модель и data-flow.
2. `01-stack-and-tooling.md` — версии, зависимости, FVM, кодоген.
3. `02-dependency-injection.md` — единый DI-bootstrap.
4. `03-domain-layer.md` — контракты, модели, `RepositoryResult`, исключения, конфиги.
5. `04-data-layer.md` — entity, DAO, мапперы, repo-impl'ы, remote-API.
6. `05-presentation-layer.md` — Freezed-BLoC, страницы, базовые классы, навигация.
7. `06-theming.md` — `ThemeExtension`, токены, тема light/dark.
8. `07-pagination.md` — пагинация v5, `applyPage`, страничный путь чатов и seq-курсор треда.
9. `08-conventions-and-constitution.md` — нейминг, импорты, коммиты, инварианты.
10. `09-build-and-secrets-infra.md` — flavor'ы, секреты, сборки, версионирование.
11. `10-code-templates.md` — blank-скелеты под каждый артефакт.
12. `11-scaffolding-plan.md` — пошаговый план сборки проекта.
13. `12-dev-commands.md` — повседневные команды и слэш-хелперы.
14. `13-deep-links.md` — обработка входящих ссылок (`app_links`, `DeepLinkRepository`, роутинг в `AppRoot`).
15. `14-networking-and-auth.md` — сеть и авторизация (`ApiClient`, `AppConfigRepository`, HMAC/токены — пример/TBD), connectivity + app-lifecycle.
16. `15-push-notifications.md` — push-уведомления (FCM).
17. `16-file-upload.md` — загрузка вложения в чат (2-step upload → attach to message).
18. `17-analytics.md` — клиентская аналитика (вендоронезависимо, opt-in/без PII).

**Быстрый путь:** если нужно просто начать — `11-scaffolding-plan.md` для упорядоченных шагов поднятия проекта, возвращаясь к слой-документам (`03`–`07`) и `10-code-templates.md` по мере необходимости.

---

## Ключевые решения

Краткая выжимка зафиксированных архитектурных решений (детали — в спутниковых документах):

- **ОДИН Dart-пакет** `nox_app`; слои — папки внутри `lib/` (включая зарезервированный `lib/resource`); один `pubspec.yaml`; один `build_runner`; один DI-init.
- **BLoC = Freezed:** sealed State/Event-юнионы, тонкий `BaseBloc<E, S>`, производная логика в extension-геттерах, `copyWith` для переходов, без `*.g.dart` на BLoC-типах.
- **Тема light + dark** через `ThemeExtension<AppColors>` (`AppTheme.light()/dark()`, `context.appColors`, `themeMode` из `AppRootBloc`) с палитрой и `flutter_screenutil`-токенами.
- **Пагинация = `infinite_scroll_pagination` v5** + `PagingStateExt.applyPage` (один helper на оба пути), домен — `PageMetadata{hasMore, nextPage?}` **без** `total`. Контракт v0 (фаза 025): чаты — страничный путь (`page`/`page_size` → `{chats, has_more}`, 1-based, `defaultPage = 1`, `nextPage` считается клиентски), сообщения — seq-курсор (`before_seq`/`limit` → `{messages, has_more}`, `limit` молча зажимается сервером до 100). `CursorPaginationMetadata{String? nextCursor}` — задокументированная опция для строкового курсора; `ItemsEntity{items, page, page_size, total}` — замороженная offset-обёртка verification-среза `Item`, а не продуктовый канон.
- **`RepositoryResult<T>`** — Freezed data-XOR-exception; базовый домен-тип ошибок — маркер `BaseRepositoryException` (`RepositoryException` — enum-подтип, реализующий маркер); ошибки мапятся в `RepositoryException` внутри `BaseRepositoryHelper.execute` в четыре ветки `catch` (`BaseRepositoryException` — насквозь без изменений; `SocketUnavailableException` → `connection`; `DioException` — по типу/статусу; остальное → `unknown`), а коды провода контракта v0 §2.1 — через `RepositoryException.fromWireCode` (неизвестный код → `internal`).
- **Обязательный `LogRepository`** — единый канал логирования, никаких сырых `print`.
- **RU-проза / EN-код:** вся проза и заголовки секций — на русском; код, идентификаторы, пути, имена пакетов, shell-команды, ключи YAML/JSON/TOML, значения enum, имена env-переменных — на английском (inline).

---

## Чеклист

После прочтения этого индекса вы должны мочь подтвердить:

- [ ] Понимаете назначение: канонический блюпринт архитектуры кросс-платформенного Flutter-приложения (iOS/Android/Windows/Linux/macOS) для `lib/`.
- [ ] Знаете авторитетный свод — **9 принципов + 10 золотых правил** (см. [`08-conventions-and-constitution.md`](08-conventions-and-constitution.md)) — и что **BLoC = Freezed** и **пагинация = `infinite_scroll_pagination` v5** — решения блюпринта (свёрнуты в существующие правила).
- [ ] Усвоили соглашения имён: пакет `nox_app` (заменяем), worked-пример `Item`, пустые скелеты `<Feature>`/`<Model>`, `com.cyphernetlabs.noxapp` (+`.stage`), flavor'ы `stage`/`prod`.
- [ ] Знаете один-пакетную модель слоёв (`lib/data`, `lib/domain`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`) и однонаправленность зависимостей.
- [ ] Нашли карту 18 документов (00–17), рекомендуемый порядок чтения и быстрый путь (`11-scaffolding-plan.md`).
- [ ] Поняли ключевые решения и правило **RU-проза / EN-код**.

---

## Маршрутизатор: код-задача → документ

Этот раздел отвечает на вопрос «**я кодю X — какие документы открыть и в каком порядке?**». TOC выше упорядочен по структуре блюпринта (для чтения подряд); этот маршрутизатор упорядочен по **типу задачи** (для точечного захода). Открывайте только релевантные документы; первый в списке — основной (контракт/паттерн), последующие — обязательный контекст.

### По слою/артефакту → документы

Берите эту таблицу, когда задача формулируется в терминах **артефакта** (репозиторий, экран, маппер, секрет). Колонка «Документы» перечислена в порядке открытия.

| Кодю… | Документы (в порядке открытия) | Зачем именно эти |
|---|---|---|
| Новый репозиторий (`XxxRepository` + `XxxRepositoryImpl`) | [03](03-domain-layer.md) → [04](04-data-layer.md) → [02](02-dependency-injection.md) | Контракт + `RepositoryResult` (03), impl/маппер/DAO/remote-API (04), регистрация в DI (02). |
| Экран / BLoC (`XxxPage` + `XxxBloc` + State/Event) | [05](05-presentation-layer.md) → [07](07-pagination.md) → [06](06-theming.md) | Freezed-BLoC и страница (05), пагинация списка если есть (07), design-токены вместо хардкода (06). |
| Сетевой вызов (новый endpoint, request-builder, interceptor) | [14](14-networking-and-auth.md) → [04](04-data-layer.md) | `ApiClient`/auth-interceptor (14); HMAC + security-заголовки там — пример из другого проекта: у NOX прикладной обмен идёт WebSocket-конвертом контракта v0 (транспорт реализован фазой 026), REST остаётся только под блобы (фаза 028), этап 1 — без авторизации; entity/маппер/REST-метод в data-слое (04). |
| Секрет или сборка (flavor, `dart-define`, env-значение, версия) | [09](09-build-and-secrets-infra.md) → [12](12-dev-commands.md) | Flavor-изоляция, SOPS+age+mise, версионирование (09), команды сборки/прогона (12). |
| Deep / universal link (входящая ссылка) | [13](13-deep-links.md) | `app_links`, `DeepLinkRepository`, парсинг URI → модель, роутинг в `AppRoot`, нативная интеграция. |
| Событие аналитики (трекинг, super-property) | [17](17-analytics.md) | `AnalyticsRepository`, `@freezed`-таксономия `AnalyticsEvent`, приватность (вендоронезависимо, opt-in по умолчанию, без PII). |
| Загрузка вложения в чат (upload, picker, размер/MIME-кап) | [16](16-file-upload.md) | 2-step (upload → attach to message); реальный путь контракта v0 §7 — `file.uploadBegin` → `PUT` → `message.send{attachment:{file_id}}`, multipart-эндпоинты документа — пример. File/image picker, размер/MIME-капы, идемпотентность по natural-key `(chat_id, client_message_id)`. |
| Push-уведомление (FCM, device-токен, тап) | [15](15-push-notifications.md) | `firebase_messaging` (mobile-only; desktop — disabled no-op), ротация токена, регистрация на бэкенде NOX, foreground/background/terminated, навигация по тапу (через 13). |

### По фиче → стек документов (порядок)

Берите эту таблицу, когда задача формулируется в терминах **фичи** целиком (а не отдельного артефакта). Стек перечислен в порядке прохождения — от входной точки до presentation.

| Фича | Стек документов (порядок) | Комментарий |
|---|---|---|
| `chats`-list (первая реальная фича) | [11](11-scaffolding-plan.md) → [03](03-domain-layer.md) → [04](04-data-layer.md) → [07](07-pagination.md) → [02](02-dependency-injection.md) → [05](05-presentation-layer.md) | План поднятия (11) → контракт+модель (03) → cache-first `ChatRepositoryImpl` + `ChatDao` поверх Sembast, `ChatRemoteDataSource` только наполняет стор (04) → пагинация (07; контракт списка чатов зафиксирован контрактом v0: страничный запрос `page`/`page_size`, ответ `{chats, has_more}`) → DI (02) → экран+BLoC (05). |
| Auth-флоу (login / refresh / токены) | [14](14-networking-and-auth.md) §3–4 | §3 — мост к REST-слою (`RequestBuilder` + конверт), §4 — адаптация под бэкенд NOX (HMAC + security-заголовки + access/refresh токен-модель — пример: этап 1 сервера идёт без авторизации, модель аутентификации этапа 2 ещё открыта — `docs/client-backend/architecture/authentication.md`). |

### Машинно-читаемая таблица (для ссылки из CLAUDE.md)

Компактная `task-keyword → docs` карта; пригодна для встраивания/ссылки из `CLAUDE.md` или автоматического роутинга агента. Номера — это файлы `NN-*.md` в этом каталоге.

| task-keyword | docs |
|---|---|
| `repository` | `03 04 02` |
| `screen` / `bloc` | `05 07 06` |
| `network-call` | `14 04` |
| `secret` / `build` | `09 12` |
| `deep-link` | `13` |
| `analytics-event` | `17` |
| `file-upload` | `16` |
| `push` | `15` |
| `chats-list` | `11 03 04 07 02 05` |
| `auth-flow` | `14 (§3-4)` |

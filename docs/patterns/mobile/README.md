# NOX — Архитектурный блюпринт

> **Назначение:** канонический референс архитектуры, паттернов и инфраструктуры мобильного приложения **NOX** (iOS + Android, Flutter), которое предстоит реализовать в `lib/` (сейчас — пустой плейсхолдер). Этот набор документов — единственный источник правды для любого разработчика при имплементации **каждой** фичи приложения. **Когда читать:** перед началом работы над приложением целиком, перед любой новой фичей, и как справочник по конкретному слою/паттерну. **Связанные документы:** все 18 спутниковых файлов `00-architecture-overview.md` … `17-analytics.md` (таблица ниже).
>
> **Статус: рабочий блюпринт** — принят как авторитетный референс для `lib/` (2026-06-08). Любая mobile-задача проектируется и кодится **по этому набору**; найденные расхождения чинятся в том же change-set'е. Известные отложенные гэпы (фиче-слои MVP — auth/app-state-spine, file-download, доменные контракты, client Sentry, native deep-link, локализация) **сейчас не покрываются**; при заходе в mobile-фичу — пересобрать gap-анализ.

---

## Что это

Блюпринт **доменно-нейтрален**: он описывает архитектуру, слои, кодоген, тулинг и инфраструктуру, не привязываясь к конкретной бизнес-логике. Сквозной worked-пример — нейтральная фича `Item`. **Первая реальная фича**, которую предстоит собрать по этому блюпринту, — список чатов (открытый общий список чатов: server-owned, network-only paginated-список); об этом упоминается там, где это уместно, но шаблоны остаются на нейтральном `Item`.

---

## Несущие инварианты (проекция конституции и золотых правил)

Это несущие инварианты. Всё остальное — стиль. Авторитетный свод — **9 принципов + 10 золотых правил** (см. [`08-conventions-and-constitution.md`](08-conventions-and-constitution.md)); список ниже — их операционная проекция в этом индексе. Два решения блюпринта — **BLoC = Freezed** и **пагинация = `infinite_scroll_pagination` v5** — свёрнуты в существующие принципы/правила (не как новые отдельные пункты).

1. **ОДИН Dart-пакет, слои — это папки.** Никаких трёх пакетов и path-deps. Слои живут как директории внутри одного `lib/`: `lib/data`, `lib/domain`, `lib/presentation`, плюс `lib/di`, `lib/general`, `lib/design`, `lib/resource`. ОДИН `pubspec.yaml`, ОДИН прогон `build_runner`. Однонаправленные зависимости: `presentation → domain`, `data → domain`; **`domain` не импортирует ничего**. Любые трёхпакетные пути (`domain/lib/src/...`, `data/lib/src/...`) переписываются в однопакетные (`lib/domain/...`, `lib/data/...`). См. `00-architecture-overview.md`.

2. **Единый DI:** один `configureDependencies(String env)` + один `@InjectableInit(initializerName: r'$initGetIt')` + один сгенерированный `configure_dependencies.config.dart`. Никакой трёхуровневой цепочки. См. `02-dependency-injection.md`.

3. **BLoC = Freezed.** `@freezed` `sealed`-юнионы для State и Event; тонкий `BaseBloc<E, S>` с `executeLogic` (try/catch). Производная/вычисляемая логика — в **extension-геттерах** (не в теле `@freezed`-класса). `copyWith` для переходов; `sealed` для много-вариантных юнионов, `abstract` для одно-вариантных value-объектов; **никакого `fromJson` на BLoC-типах** (только `*.freezed.dart`, никогда `*.g.dart`). Это правило блюпринта: BLoC-типы строятся на Freezed, а не на рукописном `sealed` + `Equatable`. Канонические имена под-состояний — `Initializing` / `Initialized` / `Error` — сохраняются и выражаются Freezed-`const factory`-конструкторами. См. `05-presentation-layer.md`.

4. **Пагинация = `infinite_scroll_pagination` ^5.1.1** (v5, stateless `PagingState`-в-bloc, **никогда** `PagingController`). Переиспользуемое расширение `PagingStateExt.applyPage`. **Дефолтный flavor — OFFSET** (`PageMetadata{int? nextPage, int total}`, например `page` + `page_size` + `count`); CURSOR (`CursorPaginationMetadata{String? nextCursor}`) документируется как альтернатива. Конкретный контракт пагинации списка чатов фиксируется позже вместе с бэкендом NOX. Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>`; `result.exception` прокидывается в `pagingState.error` для v5-error-builder'ов. См. `07-pagination.md`.

5. **`RepositoryResult<T>` — `@freezed` с data-XOR-exception** (фабрики `success` / `error`, а не «оба nullable»). Усечённое расширение `match<R>(onData, onError)`. Каждый метод репозитория возвращает `RepositoryResult<T>` (или `Stream<RepositoryResult<T>>`), и `.exception` всегда — подтип `RepositoryException`, никогда сырой `Exception` или фреймворковая ошибка. См. `03-domain-layer.md`.

6. **Трёхчастный data-split.** API JSON ↔ `Entity` (Freezed **+** `json_serializable`, basic-types-only) ↔ `Mapper` ↔ доменная `Model` (**только** Freezed, без JSON). Бизнес-логика — в `extension`'ах на модели, не в теле Freezed-класса. Сохраняется `ResponseEntity<T>` + рукописный реестр `EntityConverter<E>` (унифицированный конверт `{data, timestamp, trace_id, meta}` — пример; бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт). Вся коэрция типов (`enum` как `.name` String, `DateTime` как ISO-8601 String) — в маппере. См. `04-data-layer.md`.

7. **Один конфиг-объект на API-вызов** — Freezed-класс, передаваемый как `{required XxxConfig config}` (например `GetItemsConfig`). См. `03-domain-layer.md` / `04-data-layer.md`.

8. **Только design-токены.** Никаких хардкод-`Color`, `EdgeInsets`, `TextStyle` или system-overlay-style в коде фич. Тема — **light + dark** через `ThemeExtension<AppColors>` + `AppTheme.light()/dark()` + `context.appColors` + `themeMode` из `AppRootBloc`, с конкретной палитрой и `flutter_screenutil`-токенами spacing/typography + `AppOverlayStyleTokens`. См. `06-theming.md`.

9. **Codegen-first.** Freezed + `json_serializable` + `injectable` + `flutter_gen`. Генератор прогоняется после правки любого аннотированного класса. Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`) исключены из анализа и **никогда не правятся руками**.

10. **Единый канал логирования** — **обязательный** `LogRepository`. Сырые `print` / `debugPrint` в `lib/` запрещены. `BaseRepositoryHelper.execute<T>()` ВСЕГДА логирует через `LogRepository`; ошибки уходят в observability-backend. См. `04-data-layer.md`.

11. **Реактивные cache-first репозитории** для user-scoped watchable-ресурсов: `BehaviorSubject` + Sembast DAO (`onSnapshots`, транзакции), env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory) через `@LazySingleton(as: AppDatabase, env: [...])`. Репозиторий подписывается на стрим DAO один раз и кормит один `BehaviorSubject<RepositoryResult<...>>`. **Carve-out:** paginated server-owned списки (включая список чатов) и one-shot POST'ы — **network-only** (без DAO/subject). См. `04-data-layer.md`.

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
| 07 | [`07-pagination.md`](07-pagination.md) | Контракт пагинации: `infinite_scroll_pagination` v5, `PagingState`-в-bloc, `PagingStateExt.applyPage`, OFFSET (дефолт) vs CURSOR. |
| 08 | [`08-conventions-and-constitution.md`](08-conventions-and-constitution.md) | Стиль кода, нейминг, форматирование, импорты, тесты, feature-flags, стенс по локализации, «конституция» проекта. |
| 09 | [`09-build-and-secrets-infra.md`](09-build-and-secrets-infra.md) | Flavor-изоляция, SOPS+age+mise, flavored-сборки Android/iOS, `dart-define-from-file`, версионирование CalVer, `main.dart`-bootstrap. |
| 10 | [`10-code-templates.md`](10-code-templates.md) | Copy-paste blank-скелеты (`<Feature>`/`<Model>`) для каждого артефакта архитектуры. |
| 11 | [`11-scaffolding-plan.md`](11-scaffolding-plan.md) | Упорядоченный end-to-end план поднятия проекта с нуля и проверки каждого этапа. |
| 12 | [`12-dev-commands.md`](12-dev-commands.md) | Повседневные команды (кодоген, format, analyze, test) и `.claude/commands`-хелперы. |
| 13 | [`13-deep-links.md`](13-deep-links.md) | Обработка входящих ссылок (deep / universal links): `app_links`, `DeepLinkRepository` (парсинг URI → типизированная модель), маршрутизация в `AppRoot`, нативная интеграция. |
| 14 | [`14-networking-and-auth.md`](14-networking-and-auth.md) | Сеть и авторизация: `ApiClient` (Dio + auth-interceptor), `AppConfigRepository` (флейвор-конфиг + источник токена), мост к REST-слою; §4 — адаптация под бэкенд NOX (HMAC-подпись + security-заголовки + access/refresh токен-модель — пример; бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт); §6 — connectivity + app-lifecycle. |
| 15 | [`15-push-notifications.md`](15-push-notifications.md) | Push-уведомления (FCM): `firebase_messaging`, device-токен и его ротация, регистрация/разрегистрация на бэкенде NOX, foreground/background/terminated, разрешения, навигация по тапу (через 13). |
| 16 | [`16-file-upload.md`](16-file-upload.md) | Загрузка вложения в чат: 2-step (upload → attach to message) — пример конвейера; бэкенд/протокол NOX ещё не выбран, заменить на реальный контракт. File/image picker, размер/MIME-капы, идемпотентность по natural-key `(chat_id, client_message_id)`, BLoC-прогресс. |
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
8. `07-pagination.md` — пагинация v5, `applyPage`, offset/cursor.
9. `08-conventions-and-constitution.md` — нейминг, импорты, коммиты, инварианты.
10. `09-build-and-secrets-infra.md` — flavor'ы, секреты, сборки, версионирование.
11. `10-code-templates.md` — blank-скелеты под каждый артефакт.
12. `11-scaffolding-plan.md` — пошаговый план сборки проекта.
13. `12-dev-commands.md` — повседневные команды и слэш-хелперы.
14. `13-deep-links.md` — обработка входящих ссылок (`app_links`, `DeepLinkRepository`, роутинг в `AppRoot`).
15. `14-networking-and-auth.md` — сеть и авторизация (`ApiClient`, `AppConfigRepository`, HMAC/токены), connectivity + app-lifecycle.
16. `15-push-notifications.md` — push-уведомления (FCM).
17. `16-file-upload.md` — загрузка вложения в чат (2-step upload → attach to message).
18. `17-analytics.md` — клиентская аналитика (вендоронезависимо, opt-in/без PII).

**Быстрый путь:** если нужно просто начать — `11-scaffolding-plan.md` для упорядоченных шагов поднятия проекта, возвращаясь к слой-документам (`03`–`07`) и `10-code-templates.md` по мере необходимости.

---

## Ключевые решения

Краткая выжимка зафиксированных архитектурных решений (детали — в спутниковых документах):

- **ОДИН Dart-пакет** `nox_app`; слои — папки внутри `lib/`; один `pubspec.yaml`; один `build_runner`; один DI-init.
- **BLoC = Freezed:** sealed State/Event-юнионы, тонкий `BaseBloc<E, S>`, производная логика в extension-геттерах, `copyWith` для переходов, без `*.g.dart` на BLoC-типах.
- **Тема light + dark** через `ThemeExtension<AppColors>` (`AppTheme.light()/dark()`, `context.appColors`, `themeMode` из `AppRootBloc`) с палитрой и `flutter_screenutil`-токенами.
- **Пагинация = `infinite_scroll_pagination` v5** + `PagingStateExt.applyPage`, дефолтный flavor — **OFFSET** (`page`/`page_size`/`count`), CURSOR — альтернатива; конкретный контракт списка чатов фиксируется позже с бэкендом NOX.
- **`RepositoryResult<T>`** — Freezed data-XOR-exception; `RepositoryException` как единый домен-тип ошибок; типизированные `DaoException` / `ApiException` мапятся в него.
- **Обязательный `LogRepository`** — единый канал логирования, никаких сырых `print`.
- **RU-проза / EN-код:** вся проза и заголовки секций — на русском; код, идентификаторы, пути, имена пакетов, shell-команды, ключи YAML/JSON/TOML, значения enum, имена env-переменных — на английском (inline).

---

## Чеклист

После прочтения этого индекса вы должны мочь подтвердить:

- [ ] Понимаете назначение: канонический блюпринт архитектуры iOS+Android Flutter-приложения для `lib/`.
- [ ] Знаете авторитетный свод — **9 принципов + 10 золотых правил** (см. [`08-conventions-and-constitution.md`](08-conventions-and-constitution.md)) — и что **BLoC = Freezed** и **пагинация = `infinite_scroll_pagination` v5** — решения блюпринта (свёрнуты в существующие правила).
- [ ] Усвоили соглашения имён: пакет `nox_app` (заменяем), worked-пример `Item`, пустые скелеты `<Feature>`/`<Model>`, `com.cyphernetlabs.noxapp` (+`.stage`), flavor'ы `stage`/`prod`.
- [ ] Знаете один-пакетную модель слоёв (`lib/data`, `lib/domain`, `lib/presentation`, `lib/di`, `lib/general`, `lib/design`, `lib/resource`) и однонаправленность зависимостей.
- [ ] Нашли карту 18 документов (00–17), рекомендуемый порядок чтения и быстрый путь (`11-scaffolding-plan.md`).
- [ ] Поняли ключевые решения и правило **RU-проза / EN-код**.

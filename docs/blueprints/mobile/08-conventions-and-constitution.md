# 08 — Конвенции и архитектурный свод блюпринта

> **Назначение:** свести воедино архитектурный свод блюпринта (девять управляющих принципов) и операционные конвенции (нейминг, импорты, коммиты, форматирование, локализация, фиче-флаги, тестирование, золотые правила и «несущие» подводные камни), на которые опираются все остальные документы блюпринта. Это раздел, который кодируется в `CLAUDE.md` приложения и проверяется на каждом изменении.
> **Когда читать:** перед тем как создать или переместить любой файл, назвать любой класс, написать любой коммит; перед запуском форматтера; когда нужен авторитетный свод правил, на которые ссылаются шаблоны из остальных документов. Это финальный «контракт качества» блюпринта.
> **Связанные документы:** [00-architecture-overview.md](00-architecture-overview.md) (карта слоёв и принципы), [03-domain-layer.md](03-domain-layer.md) (`RepositoryResult`, доменные модели, конфиги), [04-data-layer.md](04-data-layer.md) (`Entity`/`Mapper`, `BaseRepositoryHelper`, DAO), [05-presentation-layer.md](05-presentation-layer.md) (BLoC-троица на Freezed, `AlertDialogHelper`), [06-theming.md](06-theming.md) (токены дизайна), [07-pagination.md](07-pagination.md) (пагинация v5), [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md) (флейворы, секреты), [10-code-templates.md](10-code-templates.md) (готовые шаблоны), [11-scaffolding-plan.md](11-scaffolding-plan.md) (порядок сборки), [12-dev-commands.md](12-dev-commands.md) (команды разработки).

---

Этот документ — финальный свод. Конкретные copy-paste-ready шаблоны живут в по-слойных документах; здесь фиксируются **инварианты** (архитектурный свод блюпринта) и **операционные правила** (конвенции). Свод объявляет, что нерушимо; конвенции описывают, как именно это соблюдать в повседневной работе. Любое расхождение между шаблоном и этим документом трактуется в пользу этого документа, кроме случаев, где документ явно делегирует деталь по-слойному файлу.

---

## 1. Архитектурный свод блюпринта — девять управляющих принципов

Это несущие инварианты архитектуры клиентского приложения NOX. Всё остальное — стиль. Каждый принцип формулируется так, чтобы его можно было проверить ревью одной строкой. Принципы пронумерованы **арабскими** цифрами (1–9) и неизменны по нумерации (на них ссылаются по номеру из остальных документов блюпринта).

> **Не путать с конституцией Spec Kit.** Этот свод (девять архитектурных принципов блюпринта, арабские 1–9) — **не** конституция проекта NOX. Реальная конституция живёт в `.specify/memory/constitution.md` (версия **v1.3.0**, **семь** принципов с **римской** нумерацией: I — приватность и E2EE; II — спецификации/дизайн-корпус как источник истины; III — архитектурный блюпринт обязателен; IV — верность дизайн-системе; V — языковая дисциплина; VI — паритет платформ mobile ↔ desktop; VII — контракт провода как закон (клиент ↔ сервер)) и управляет всем репозиторием через Constitution Check на этапе `plan`. Слово «конституция» в этом документе ранее означало именно локальный свод блюпринта; во избежание путаницы здесь он называется **«архитектурный свод блюпринта»**, а «конституция» (римские I–VII) — всегда документ Spec Kit.

> **Мост к конституции NOX (Принцип III).** Конституция NOX (Принцип III — «архитектурный блюпринт обязателен») делает этот блюпринт **обязательным** для любого клиентского/Flutter-кода на всех пяти целевых платформах (iOS, Android, Windows, Linux, macOS). Девять архитектурных принципов ниже — операционная развёртка этого мандата; в свою очередь Принцип I конституции (приватность/E2EE: аналитика строго opt-in, без PII/содержимого/идентификаторов, Logout стирает локальные данные) и Принцип IV (верность дизайн-системе) проецируются на Принципы 6/7/8 этого свода. Расхождение кода с блюпринтом устраняется в том же change-set (Принцип II конституции — спека/блюпринт как источник истины).

### Принцип 1 — Один пакет, три слоя-папки, односторонние зависимости

Приложение — **один Dart-пакет** `nox_app` с одним `pubspec.yaml` и одним прогоном `build_runner`. Слои — это **папки** внутри `lib/`, а не отдельные пакеты:

```
lib/
├── data/          → реализации (entity, mapper, dao, api, repository impl)
├── domain/        → контракты и чистые модели (repository, model, exception, RepositoryResult)
├── presentation/  → UI, BLoC (base/base_bloc.dart), страницы, виджеты, навигация, helpers, extension
├── di/            → configure_dependencies.dart (+ .config.dart), global_aliases.dart
├── design/        → токены (App*Tokens) + theme/ (app_theme.dart + AppColors ThemeExtension)
├── general/       → constants, feature_flags, platform_utils, formatters, l10n_extension (context.l10n)
├── l10n/          → ARB-источники (app_en.arb + app_uk.arb) + сгенерированный AppLocalizations
└── resource/      → ресурсы уровня приложения (зарезервированная папка-слой; сейчас только .gitkeep)
```

Направление зависимостей **строго одностороннее**:

```
presentation ──▶ domain ◀── data
```

`presentation` никогда не импортирует `data`; `data` никогда не импортирует `presentation`; **`domain` не импортирует ничего** (ни Flutter, ни персистентность, ни HTTP). Однопакетная схема устраняет цикл `domain ⇄ data`, возможный при трёхпакетной раскладке: внутри одного пакета нет path-зависимостей и нет встречной ссылки `data → domain` ради DI-бутстрапа. DI — **одноуровневый**: единственная `configureDependencies(String env)`, единственная аннотация `@InjectableInit(initializerName: r'$initGetIt')` и единственный сгенерированный `configure_dependencies.config.dart` (см. [02-dependency-injection.md](02-dependency-injection.md)).

> **`resource/` — зарезервированный слой.** Папка `lib/resource/` существует в коде как объявленный слой, но **сейчас пуста** (содержит только `.gitkeep`) — это будущий дом для ресурсов уровня приложения (например, бандленных не-Dart-файлов / будущих resource-файлов). **`app_theme.dart` живёт НЕ здесь, а в `lib/design/theme/app_theme.dart`** (рядом с `app_colors.dart` и сгенерированным дизайн-хэндофом `nox_brand.dart` / `nox_color_scheme.dart` / `nox_text_theme.dart` / `nox_tokens.dart`).

> **Однопакетные пути — правило блюпринта.** Все слой-пути однопакетные: `lib/domain/model/item/item_model.dart`, `lib/data/repository/item/item_repository_impl.dart`. Импорты — всегда `package:nox_app/...`. Описывать «три пакета», path-зависимости или цикл `domain ⇄ data` — нарушение.

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

Сверх трёхчастного split этот блюпринт сохраняет паттерн унифицированного контракта сетевого ответа. Конверт больше не гипотетический: контракт v0 (`docs/client-backend/protocol/contract-draft.md` §2) отвечает `{"id": N, "ok": true, "data": {...}}` либо `{"id": N, "ok": false, "error": {"code", "message"}}`, а в data-слое ему соответствует `ResponseEntity<T>` + вручную поддерживаемый реестр `EntityConverter<E>`:

```dart
// lib/data/entity/base/response_entity.dart
const factory ResponseEntity({@Default(false) bool success, ErrorWireEntity? error, @EntityConverter() T? data}) = _ResponseEntity<T>;
```

`success` зеркалит проводной `ok`, `error` — объект `ErrorWireEntity{code, message}` (§2.1), `data` разрешается реестром `EntityConverter`. Разворачивает конверт `BaseRepositoryHelper.unwrapEnvelope<TD>(response, what)`: есть `data` — вернуть, есть `error` — бросить `RepositoryException.fromWireCode(code)`, иначе `StateError` (битый конверт). См. [04-data-layer.md](04-data-layer.md).

### Принцип 4 — Один объект-конфиг на один вызов API

Каждый параметризованный вызов получает ровно один объект-конфиг — `@freezed`-класс, реализующий маркер `RepositoryConfig`, и передаётся как `{required XxxConfig config}`. Никаких многоаргументных сигнатур и никаких zero-arg list-чтений. Канонический пример: `GetItemsConfig.firstPage()` / `GetItemsConfig.nextPage(page: …)`. Конфиг несёт `page` (+ опциональный `search`); `pageSize` (20) и `defaultPage` (`1`, 1-based — `static const int defaultPage = 1` в коде) — статические константы конфига, а не поля (см. [07-pagination.md](07-pagination.md)). Шаблон одного `@freezed`-конфига на вызов (фабрики `firstPage`/`nextPage`, **без** sealed-union на фичу) — в [03-domain-layer.md](03-domain-layer.md).

### Принцип 5 — BLoC через Freezed-юнионы + `BaseBloc.executeLogic` + логика-в-расширениях

Управление состоянием — **BLoC на Freezed**. State и Event — `@freezed sealed`-юнионы (`sealed` для многовариантных юнионов, `abstract` для одновариантных value-объектов). Канонические подсостояния — `Initializing` / `Initialized` / `Error`, объявленные как `const factory`-конструкторы. Тонкий `BaseBloc<E, S>` оборачивает обработчики в `executeLogic` с единым `try/catch`. Вычисляемая/производная логика живёт в **`extension`-геттерах** над состоянием (не в теле `@freezed`). Переходы — через `copyWith`. BLoC-типы имеют **только `.freezed.dart`, никогда `.g.dart`** (никакого `fromJson` на типах BLoC). Побочные эффекты (навигация, snackbar) уходят через `PublishSubject`-стримы, а не через state.

> **Это сознательно переопределяет старое правило.** Ранний вариант блюпринта описывал BLoC через **рукописные** `sealed`-иерархии на `Equatable` с ручными `when()`/`copyWith()` и правилом «никакого Freezed для state». Этот блюпринт меняет решение: state/event — `@freezed`-юнионы. Имена подсостояний (`Initializing`/`Initialized`/`Error`) сохранены. Полная BLoC-троица — в [05-presentation-layer.md](05-presentation-layer.md).

### Принцип 5.1 — Каждая навигируемая страница имеет собственный BLoC (даже без логики)

Любой `*Page`, участвующий в навигации (имеет `static routeName` + `static Route route()` и попадает в `Navigator` / `onGenerateRoute`), **ОБЯЗАН** владеть собственным BLoC — **даже если у страницы нет бизнес-логики**. Logic-less / статичная страница всё равно получает минимальный BLoC: либо канонический trio `Initializing` / `Initialized` / `Error` (см. [05-presentation-layer.md](05-presentation-layer.md) §3.4), либо одновариантный value-BLoC в стиле `AppRootBloc` ([05](05-presentation-layer.md) §6.1). Переиспользуемые **виджеты** — ненавигируемые UI-компоненты в `lib/presentation/widgets/` или page-private `widgets/` — BLoC **НЕ требуют**: состояние им подаёт страница-владелец. Проверка одной строкой: **есть `routeName`/`route()` ⇒ обязан быть `bloc/`**.

### Принцип 6 — Единый канал логирования + маппинг доменных исключений

Логирование — единственным каналом `LogRepository` (`debug`/`error`). **Сырые `print`/`debugPrint` в `lib/` запрещены** (тесты — исключение). **Типизированной иерархии исключений нет:** есть маркер `abstract class BaseRepositoryException {}` + общий enum `RepositoryException implements BaseRepositoryException { unknown, internal, authentication, connection, unauthenticated, notFound, invalidRequest, nameTaken, payloadTooLarge, attachmentGone, rateLimited, unsupportedSchema }` — шесть последних значений зеркалят коды ошибок контракта v0 §2.1, и `static RepositoryException.fromWireCode(String)` переводит проводной код в enum (неизвестный клиенту код → `internal`, никогда не падение). Фиче-специфичные исключения, если появятся, реализуют тот же маркер отдельными enum. Необработанные ошибки транспорта/фреймворка **обязаны** маппиться в доменный `RepositoryException` через `BaseRepositoryHelper.execute<T>()` — у него **три** ветки catch: `on BaseRepositoryException` (уже доменная ошибка, например из `unwrapEnvelope`, проходит насквозь и не деградирует до `unknown`), `on DioException` (таймауты/`connectionError` → `connection`; 401 → `unauthenticated`; 403 → `authentication`; 404 → `notFound`; иначе `internal`), затем catch-all → `unknown`. Транспорт выбран: WebSocket-конверт для команд и событий. Отгружено фазой 026 — сам клиент конверта (`NoxSocketClient`, `lib/data/remote/socket/nox_socket_client.dart`); **целевая, ещё не построенная** продовая форма канала — `wss:443` с пиннингом ключа (сегодня `SocketChannelFactory` открывает голый `IOWebSocketChannel.connect(url, pingInterval: 25s)` без `SecurityContext` и проверки отпечатка, а `config/stage.json` смотрит на `http://127.0.0.1:8080`, то есть `ws`). REST остаётся только для blob-upload/download (фаза 028, ещё не начата) — Dio будет обслуживать именно этот REST-путь, это не «размеченный пример». `RepositoryResult.exception` всегда несёт подтип `BaseRepositoryException`, никогда «сырую» ошибку транспорта/фреймворка. `BaseRepositoryHelper.execute<T>()` **всегда** логирует через обязательный `LogRepository`. Намеренно проглоченное исключение обязано иметь inline-комментарий, почему это безопасно. См. [04-data-layer.md](04-data-layer.md).

### Принцип 7 — Cache-first реактивные репозитории (с сетевой карвут-оговоркой)

Для пользовательских наблюдаемых ресурсов репозитории — **cache-first и реактивные**: реактивный Sembast-DAO (`onSnapshots`, транзакции) + env-scoped `AppDatabase` (Dev/Prod = IO, Test = memory) через провайдеры `@LazySingleton(as: AppDatabase, env: [...])`. Репозиторий подписывается на стрим DAO один раз и кормит один `BehaviorSubject<RepositoryResult<...>>`; экспонирует парные `watchXxx()` (Stream) + `fetchXxx()` (Future). Удалённый API гидратирует локальное хранилище; UI смотрит на локальные стримы (local-first).

> **Карвут:** одноразовые команды (файловая цепочка §7) и **замороженный** verification-срез `Item` — **network-only**: без DAO и без `BehaviorSubject`. Пагинированность сама по себе под карвут **не** заводит: сегодня он живёт только в `ItemRepositoryImpl` (ни DAO, ни субъекта). Список чатов NOX под него **не** попадает: `ChatRepositoryImpl` — cache-first над Sembast, где `ChatRemoteDataSource` (команда `chats.list` контракта v0 §4: `{page, page_size, query?}` → `{chats, has_more}`) **однократно** засевает пустое хранилище, а дальше список, поиск и пагинация обслуживаются локально (см. [07-pagination.md](07-pagination.md)).

#### 7.1. Инициализация `AppDatabase` и потокобезопасность первого `watch`

`AppDatabase` инициализируется **жадно при старте** — в `AppRootBloc` (на этапе бутстрапа приложения), а **не** лениво в конструкторе репозитория. Это GetIt-синглтон (`@LazySingleton(as: AppDatabase, env: [...])`, env-scoped: Dev/Prod = IO, Test = memory — см. [02-dependency-injection.md](02-dependency-injection.md) §«AppDatabase»), и `AppRootBloc` **дожидается** завершения его инициализации до того, как любой реактивный репозиторий откроет свой стрим. Это защищает от гонки на **первом** вызове `watchXxx()`: к моменту, когда репозиторий подписывается на DAO-стрим (`onSnapshots`) и кормит свой `BehaviorSubject<RepositoryResult<...>>`, нижележащая `Database` уже открыта, и первый снапшот не упирается в ещё не готовое хранилище. Без жадного открытия первый `watchXxx()` мог бы наткнуться на параллельно открывающуюся базу. Это уточнение полностью совместимо с cache-first-инвариантом выше (репозиторий по-прежнему подписывается на DAO-стрим один раз и экспонирует `watchXxx()`/`fetchXxx()`); меняется лишь то, **когда** база гарантированно открыта — на старте, а не по требованию.

### Принцип 8 — Только токены дизайна (light + dark), Semantics, единый файл фиче-флагов

В фиче-коде запрещены «сырые» `Color`, `EdgeInsets`, `TextStyle` и системный overlay-стиль. Используются только токены-классы (4 в коде): `AppSpacingTokens`, `AppDimensionTokens`, `AppTextStyleTokens`, `AppOverlayStyleTokens` (все в `lib/design/`). **Цвет — НЕ токен-класс:** он приходит из `Theme.of(context).colorScheme` (основной канал) плюс `NoxBrand` (бренд-фикс), `NoxScrims` (скримы над QR-камерой) и `NoxOpacity` (альфы поверх ролей); публичного класса-палитры цветов (`AppColorsTokens`) **нет**. `context.appColors` (`ThemeExtension<AppColors>`) на практике — **двухполевой skeleton** (`surfaceMuted`, `dividerSubtle`), не вызываемый нигде в коде фич (см. [06-theming.md](06-theming.md) §2). Ассеты идут **только** через `flutter_gen` (`lib/design/gen/assets.gen.dart` — `Assets.png/.svg`) и реестр иконок `lib/design/nox_icons.dart`; **класса `AppImagesTokens` не существует** — рукописного реестра путей нет, а сырые строковые пути `'assets/…'` вне `lib/design/gen/` запрещены (это стережёт тест `test/design/single_channel_guard_test.dart`). Spacing/типографика — через `flutter_screenutil` (адаптивные токены). Темизация — **light + dark** через `ThemeExtension<AppColors>` + `AppTheme.light()`/`dark()` + `context.appColors` + `themeMode` из `AppRootBloc`. Новые интерактивные виджеты оборачивают интерактивный элемент в `Semantics(label:, button: true)`. Все статические тоглы — в **одном** `lib/general/feature_flags.dart` как `static const bool` (remote-config-флаги — вне области этого модуля). См. [06-theming.md](06-theming.md).

### Принцип 9 — Compile-time изоляция флейворов

Флейвор резолвится на этапе компиляции: `AppFlavorType{prod, stage}` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг `flavor → env`: `prod → Environment.prod`, `stage → Environment.dev`. Все флейвор-специфичные значения приходят через `--dart-define-from-file`; **никакого runtime-ветвления по флейвору**. Секреты — через SOPS + age + mise + флейворные Android/iOS-сборки. Версионирование — CalVer + сдвинутая эпоха (`YY.M.D+EPOCH`). `main.dart` оборачивает запуск в `runZonedGuarded`, ждёт `configureDependencies(env)`, затем `getIt.allReady()`. Отдельного BLoC-обсервера нет: логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует), а ошибки BLoC-обработчиков оборачиваются `BaseBloc.executeLogic`. См. [09-build-and-secrets-infra.md](09-build-and-secrets-infra.md).

---

## 2. Десять золотых правил

Это компактная памятка-чеклист для ревью (надмножество правил из ранних вариантов блюпринта). Каждое правило проверяется одной строкой и кодируется в секции `CLAUDE.md` приложения. Правила 1–8 — операционные проекции Принципов 1–8 архитектурного свода блюпринта; **правило 9 (codegen-first) — самостоятельное операционное правило** (codegen не является отдельным принципом свода; Принцип 9 свода — это компиляция-флейвор-изоляция, отражён отдельным инвариантом ниже); правило 10 добавляет стандарт пагинации.

1. **Один пакет, три слоя-папки, односторонние зависимости.** `presentation → domain ← data`; `domain` не импортирует ничего; один `pubspec.yaml`, один `build_runner`, одна `configureDependencies(env)`. (Принцип 1.)
2. **Каждый метод репозитория возвращает `RepositoryResult<T>`** (или `Stream<...>`); `.exception` всегда `BaseRepositoryException`; доступ через `match()`/`hasData`, **никогда `result.data!`**. (Принцип 2.)
3. **Трёхчастный data-model split.** Entity (`@freezed` + json) ↔ Mapper ↔ Model (`@freezed`, без json); логика модели — в `extension`-геттерах. Entity — только базовые типы. (Принцип 3.)
4. **Один конфиг на один вызов** — `@freezed`-класс с маркером `RepositoryConfig`, передаётся как `{required XxxConfig config}`. (Принцип 4.)
5. **BLoC через `@freezed sealed` State/Event + `BaseBloc.executeLogic` + логика-в-расширениях.** Подсостояния `Initializing`/`Initialized`/`Error`. Побочные эффекты — через `PublishSubject`, не через state. BLoC-типы — только `.freezed.dart`. (Принцип 5.) **Каждая навигируемая страница (`routeName`/`route()`) имеет собственный BLoC — даже logic-less (минимальный trio или value-BLoC а-ля `AppRootBloc`); переиспользуемые виджеты BLoC не требуют. (Принцип 5.1.)**
6. **Единый канал логирования `LogRepository`; маппинг доменных исключений.** Никаких сырых `print`/`debugPrint` в `lib/`; транспортные ошибки → `RepositoryException` через `BaseRepositoryHelper.execute<T>()`. (Принцип 6.)
7. **Cache-first реактивные репозитории** для пользовательских наблюдаемых ресурсов (`BehaviorSubject` + Sembast-DAO) — включая пагинированные серверные списки: и список чатов, и история сообщений идут через DAO (фича 013). **Карвут network-only** сузился до одноразовых команд (файловая цепочка) и замороженного verification-среза `Item`. (Принцип 7.)
8. **Только токены дизайна; light + dark; Semantics; единый `feature_flags.dart`.** Никаких хардкод-цветов/отступов/стилей/overlay. (Принцип 8.)
9. **Codegen-first, генераты не редактируются руками.** Freezed + json_serializable + injectable; после правки любого аннотированного класса — прогон генератора. `*.g.dart`/`*.freezed.dart`/`*.config.dart`/`lib/design/gen/**` исключены из анализа и форматирования. (Операционное правило; Принцип 9 свода — компиляция-флейвор-изоляция — отражён отдельным инвариантом ниже.)
10. **Пагинация — стандарт v5, две реальные дорожки контракта v0.** `infinite_scroll_pagination ^5.1.1`, stateless `PagingState`-в-блоке (никогда `PagingController`), переиспользуемое расширение `PagingStateExt.applyPage` — общее для обеих дорожек (конец списка = `!meta.hasMore`). Метаданные страницы — `PageMetadata({required bool hasMore, int? nextPage})`; **поля `total` не существует** (провод его не отдаёт). Дорожка **paged** (список чатов, §4): запрос `{page, page_size}`, ответ `{chats, has_more}`, `nextPage = hasMore ? page + 1 : null` считается на клиенте, рендер — `PagedListView`, индекс 1-based. Дорожка **seq-курсор** (история сообщений, §5): запрос `{before_seq?, limit}`, ответ `{messages, has_more}`, порция по возрастанию `seq`, сервер **молча** обрезает `limit` потолком 100; блок треда держит `oldestLoadedSeq` (не номера страниц), `nextPage` остаётся `null`, а рендер — `reverse: true` `ListView.builder` с префетчем от `ScrollController`, **без** `PagedListView`. Ошибки в обеих дорожках прокидываются в `pagingState.error`. (См. [07-pagination.md](07-pagination.md).)

> **Дополнительный нерушимый инвариант:** `AlertDialogHelper` — **единственный** канал пользовательских ошибок (см. §8 ниже и [05-presentation-layer.md](05-presentation-layer.md)). Компиляция-флейвор-изоляция (Принцип 9 архитектурного свода блюпринта) и единый канал ошибок дополняют десятку золотых правил, но проверяются вместе с ними на каждом ревью.

---

## 3. Конвенции нейминга

Эти правила абсолютны: scaffolding-скиллы, анализатор и кодогенерация на них опираются. Нейтральный сквозной пример — **Item** (Feature-001, verification-only network-only слайс); пустые скелеты используют плейсхолдеры `<Feature>` / `<feature>` / `<Model>`. Слайс **намеренно заморожен**: его offset-обёртка `ItemsEntity{items, page, page_size, total}` и путь `v1/items` остаются как есть и **каноном продукта не являются** — из `total` он не течёт наружу, потому что `ItemRepositoryImpl` сворачивает страницу в контрактную форму `PageMetadata(hasMore: hasMore, nextPage: hasMore ? entity.page + 1 : null)`. Реальные продуктовые фичи (список чатов, тред) уже реализованы поверх cache-first Sembast, а их проводные формы выровнены по контракту v0 (фаза 025; живой транспорт и флип DI на реальные data source — фаза 026, уже сделаны в окружении `dev`, куда ведёт флейвор `stage`), но шаблоны нейминга держатся на нейтральном Item.

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
| DAO | `*Dao` | `ItemDao` | `lib/data/local/<feature>/` |
| API-клиент | `Get*Api` / `Post*Api` (файл `get_items_api.dart`) | `GetItemsApi` | `lib/data/remote/api/<feature>/` |
| Request builder | `*ApiRequestBuilder` | `GetItemsApiRequestBuilder` | `lib/data/remote/request_builder/<feature>/` |
| Страница | `*Page` | `ItemListPage` | `lib/presentation/pages/<page>_page/` |
| BLoC | `*Bloc` | `ItemListBloc` | `lib/presentation/pages/<page>_page/bloc/` |
| Файлы BLoC | `*_bloc.dart`, `*_event.dart`, `*_state.dart` | `item_list_bloc.dart` | та же папка `bloc/` |
| Общие виджеты | `App*Widget` | `AppProgressWidget`, `AppErrorWidget`, `AppEmptyContentWidget` | `lib/presentation/widgets/` |
| Токены дизайна | `App*Tokens` | `AppSpacingTokens`, `AppDimensionTokens`, `AppTextStyleTokens`, `AppOverlayStyleTokens` | `lib/design/` |
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
import 'package:nox_app/domain/model/item/item_model.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';

// WRONG — fragile relative traversal
import '../../../domain/model/item/item_model.dart';
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

Внутри одного пакета бочки нужны меньше, чем в трёхпакетной схеме, но папки-фичи могут экспонировать локальную бочку для удобства (`lib/domain/model/models.dart`, re-export по одному `export` на публичную модель). Cross-package-алиасинг (`import '...' as domain;`) из трёхпакетных источников **не нужен** — все типы в одном пакете.

---

## 5. Конвенции коммитов

(Свод правил независим от ветвления.)

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

Рекомендуемая модель — GitFlow-вариант: фиче-ветки мёрджатся в `develop`, `develop` мёрджится в `master` на релизе (`master` держит только релизные коммиты). Для скелета приложения выбрать одну модель и задокументировать её в собственном `CONTRIBUTING.md`; правила «imperative-subject + atomic + sign-off» от ветвления не зависят.

> **Согласование с репозиторием NOX:** коммиты и пуши в `develop`/`master` и merge PR **не** выполняются автономно. Изменения стейджатся, показывается дифф, предлагается точная команда коммита — и ожидается явное подтверждение владельца. Это не отменяет правила выше: они описывают форму коммита, а это — кто и когда его выполняет.

---

## 6. Жёсткое правило форматирования (HARD RULE)

После правки форматировать **только изменённые файлы**, с явными путями:

```bash
fvm dart format -l 140 path/to/file_a.dart path/to/file_b.dart
```

- **Никогда** не запускать форматирование всего репозитория (`dart format .` / `make format`) как шаг завершения задачи — это переформатирует всё и создаёт массивные несвязанные диффы, блокирующие коммит. В реальном `Makefile` сейчас есть единственная **мутирующая** цель `format` (`fvm dart format -l 140 lib test`) — она для разового ручного приведения дерева, не как шаг завершения задачи. Рекомендуемая конвенция — добавить **non-mutating** `format-check` (`--output=none --set-exit-if-changed`, ничего не пишет) как CI-гейт форматирования всего репо.
- **Никогда** не вычислять файлы для форматирования через `git diff` — это подтянет ветко-расходящийся шум.
- **Никогда** не форматировать генераты (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`, `*.mocks.dart`).
- **Длина строки — 140 символов** (`formatter: page_width: 140` в `analysis_options.yaml` — источник истины; команды также передают `-l 140` для явности).

Скоуп форматирования — `lib/`, `test/`. Исключения — все генераты выше.

---

## 7. Локализация (стойка)

**Локализация внедрена: ARB + `gen-l10n`, языки UI — английский и украинский.** Централизованного `lib/general/text_constants.dart` **больше нет** (файл удалён, ссылок на `TextConstants` в `lib/` ноль). Единственный источник пользовательских строк — ARB-файлы `lib/l10n/app_en.arb` (шаблон) и `lib/l10n/app_uk.arb`; сегодня в каждом **140 ключей с идентичными наборами** — новая строка обязана лечь в **оба** файла (шаблон `app_en.arb` задаёт API `AppLocalizations`, пропуск в `app_uk.arb` молча оставит украинский на английском фолбэке). Пакет `intl` остаётся **только** для форматирования (даты/числа) в `lib/general/formatters/`.

Проводка (реальный код):

- `pubspec.yaml` → `flutter: generate: true`; конфиг — `l10n.yaml` (`arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-class: AppLocalizations`, `nullable-getter: false`).
- Сгенерированный `lib/l10n/app_localizations*.dart` **гитигнорится** — после любой правки ARB и на свежем клоне нужен `make generate` (он делает `build_runner build` **и** `fvm flutter gen-l10n`), иначе `analyze`/`test` падают на неразрешённом `AppLocalizations`.
- Доступ из UI — расширение `context.l10n` (`lib/general/l10n_extension.dart`), а не `AppLocalizations.of(context)` в каждом виджете.
- Корневой `MaterialApp` (`lib/presentation/app/app_root.dart`) получает `localizationsDelegates` / `supportedLocales` от `AppLocalizations`, а `locale` — от `LocaleController.instance` (выбор языка персистится в `SharedPreferences` под ключом `ui_language`; `AppLanguage.system` → `locale: null`, то есть системный язык с фолбэком на английский). Смена языка перерисовывает приложение **живьём** через `ValueNotifier`.
- Поддерживаемые локали — ровно `en` и `uk`. **Русский языком UI не является никогда** (это язык внутренних доков и спек, см. языковую дисциплину — Принцип V конституции).

Шаблон `lib/l10n/app_en.arb` (каждый ключ обязан существовать и в `app_uk.arb`):

```json
{
  "@@locale": "en",
  "appName": "NOX",
  "chats": "Chats",
  "settings": "Settings",
  "actionCancel": "Cancel",
  "errorGeneralTitle": "Something went wrong",
  "systemChatCreated": "Chat created by {username}",
  "@systemChatCreated": {
    "description": "System line at the top of a chat thread",
    "placeholders": { "username": { "type": "String" } }
  }
}
```

```dart
// Reading localized copy in a widget.
Text(context.l10n.chats);
Text(context.l10n.systemChatCreated(username));
```

**Правила работы с ARB:**

- Один ключ на каждый пользовательский текст; **никакой конкатенации строк в рантайме**. Параметризованный текст — ICU-плейсхолдер (`{username}`) с блоком `@ключ.placeholders`, а не склейка через интерполяцию на стороне виджета.
- Стабильные говорящие имена ключей в `lowerCamelCase`, сгруппированные по фиче/экрану (`chatsLoadError`, `settingsSaveError`, `createChatNetworkError`); ключ не переименовывают ради косметики — он и есть API строки.
- Никакой логики/форматирования внутри строк: числа/даты/размеры файлов форматируются через `intl` в `lib/general/formatters/` (см. [06-theming.md](06-theming.md)), а в ARB попадает уже готовый плейсхолдер.
- Множественное число / род / падежи — через ICU (`plural`/`select`) в самом ARB, а не ручной склейкой в Dart.
- В тестах копия проверяется через файловый `final l10nEn = AppLocalizationsEn();` (`package:nox_app/l10n/app_localizations_en.dart`), **никогда** сырым литералом; `pumpApp` пиннит `locale: Locale('en')` с делегатами `AppLocalizations`, чтобы копия рендерилась детерминированно.

---

## 8. Пользовательские ошибки (единый канал)

- `AlertDialogHelper.showErrorSnackBar(context, message)` — **единственный** канал пользовательских error-snackbar'ов; `AlertDialogHelper.showSnackBar` — для не-error info.
- **Никогда** не показывать сырые сообщения исключений. Транслировать `RepositoryException` → человекочитаемые строки в BLoC (см. `_translate(...)` в [05-presentation-layer.md](05-presentation-layer.md)), а саму копию брать из локализации (`context.l10n`, ключи `lib/l10n/app_en.arb` + `app_uk.arb`) — никаких строковых литералов в презентации.

---

## 9. Фиче-флаги

Все статические тоглы — в **одном** модуле как `static const bool`-поля. Ad-hoc флаг-константы где-либо ещё запрещены. Remote-config-флаги — вне области этого модуля (out of scope).

```dart
// lib/general/feature_flags.dart
abstract final class FeatureFlags {
  const FeatureFlags._();

  static const bool enableSearch = true;
  static const bool enablePullToRefresh = true;
  // dev-only flags: document why + that they must be false on merge.
}
```

---

## 10. Тестирование (стойка)

- Тесты живут под `test/` и **глубоко зеркалят `lib/`** (фиче-папка к фиче-папке), а не плоско под слоем-папкой. Реальный test-tree скелета:
  - `test/data/mapper/item/item_mapper_test.dart`
  - `test/data/local/item/item_dao_test.dart`
  - `test/presentation/pages/item_list_page/item_list_bloc_test.dart`
- Бутстрап DI — **инлайн в каждом тест-файле**: `await configureDependencies(Environment.test)` в `setUp`/`setUpAll` + `await getIt.reset()` в `tearDown` (так устроены шипнутые тесты скелета). Сверх этого построен глобальный авто-хук `test/flutter_test_config.dart` (`flutter test` подхватывает его для всего сьюта): он ставит in-memory моки `SharedPreferences` и `FlutterSecureStorage`, чтобы сборка DI-графа не упиралась в платформенный канал, но сам DI-контейнер **не** строит — это по-прежнему делает каждый тест.
- Мокинг — Mockito; bloc-тесты — `bloc_test`. Интеграционный слой на `integration_test` — **план, а не текущее состояние**: dev-зависимость объявлена в `pubspec.yaml`, каталога `integration_test/` в репозитории нет.
- DI-окружение `Environment.test` подключает in-memory `AppDatabaseTest`.

```dart
// per-test DI bootstrap (как в шипнутых тестах скелета)
setUp(() async {
  await configureDependencies(Environment.test); // Environment.test → in-memory AppDatabaseTest
});
tearDown(() async {
  await getIt.reset();
});
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
// lib/domain/model/item/item_model.dart  (rich types, NO json_serializable)
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

В этом блюпринте state/event BLoC — `@freezed sealed`-юнионы с `const factory`-конструкторами `Initializing`/`Initialized`/`Error`, тонким `BaseBloc.executeLogic` и логикой в `extension`-геттерах. **Это сознательно переопределяет** прежнее правило «BLoC — рукописные sealed на Equatable, без Freezed». BLoC-типы имеют только `.freezed.dart`, никогда `.g.dart`. Полная троица — в [05-presentation-layer.md](05-presentation-layer.md).

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

Это переопределяет трёхпакетную последовательность `data → domain → root` из источников: внутри одного пакета `build_runner` запускается один раз и генерит всё (`*.freezed.dart`, `*.g.dart`, `*.config.dart`).

---

## 12. Скелет `CLAUDE.md` приложения

Заготовка `CLAUDE.md` для `lib/`, переносящая в проектную память существо этого блюпринта. NOX — standalone-репозиторий (один пакет `nox_app`), не монорепо: это отдельный `CLAUDE.md` приложения, а не секция корневого монорепо-файла. Прозу держать на русском (репо-правило), код/команды/идентификаторы — на английском.

```markdown
# CLAUDE.md — NOX (lib/)

## Обзор проекта
Flutter-приложение (iOS, Android, Windows, Linux, macOS; web вне scope) для NOX. ОДИН Dart-пакет `nox_app`.
Слои — папки в `lib/`: data / domain / presentation + di / general / design / l10n / resource.
Flutter 3.44.1 (FVM, `.fvmrc`). Dart sdk >=3.12.0 <4.0.0. Line length 140.
Флейворы: stage, prod. applicationId/bundle: com.cyphernetlabs.noxapp (stage: com.cyphernetlabs.noxapp.stage).
Архитектурный референс: docs/blueprints/mobile/ (этот блюпринт — каноничный источник).

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
   подсостояния Initializing/Initialized/Error; побочные эффекты через PublishSubject;
   навигируемая страница (routeName+route()) ⇒ собственный BLoC даже logic-less (минимальный trio/value-BLoC),
   виджеты — без BLoC (Принцип 5.1).
6. Единый канал LogRepository; маппинг исключений в RepositoryException; никаких сырых print.
7. Cache-first реактивные репозитории (BehaviorSubject + Sembast-DAO), включая пагинированные списки;
   карвут network-only: одноразовые команды и замороженный срез Item.
8. Только токены дизайна; light + dark (ThemeExtension<AppColors>); Semantics; единый feature_flags.dart.
9. Codegen-first; генераты (*.g.dart/*.freezed.dart/*.config.dart/lib/design/gen/**) не редактируются руками.
10. Пагинация — infinite_scroll_pagination ^5.1.1, stateless PagingState-в-блоке, PagingStateExt.applyPage;
    PageMetadata{required bool hasMore, int? nextPage} — поля total нет. Две дорожки контракта v0:
    paged (чаты: page/page_size → {chats, has_more}, 1-based, defaultPage=1, nextPage считает клиент) и
    seq-курсор (сообщения: before_seq/limit → {messages, has_more}); ошибки → pagingState.error.

## Несущие правила
- HARD RULE форматирования: только изменённые файлы, явные пути, @140; никакого whole-repo / git-diff.
- AlertDialogHelper — единственный канал пользовательских ошибок; сырые exception-сообщения не показывать.
- Локализация: EN + UK через ARB (lib/l10n/app_en.arb + app_uk.arb, идентичные наборы ключей) + gen-l10n;
  доступ через context.l10n; text_constants.dart не существует; intl — только форматирование дат/чисел.
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
- [ ] Каждая навигируемая `*Page` (`routeName`/`route()`) имеет собственный BLoC — даже logic-less (минимальный trio `Initializing`/`Initialized`/`Error` или value-BLoC а-ля `AppRootBloc`, Принцип 5.1); переиспользуемые виджеты BLoC не имеют.
- [ ] Ни один `*.freezed.dart` / `*.g.dart` / `*.config.dart` не редактировался руками.
- [ ] Конец задачи: codegen → format (только изменённые файлы, `-l 140`) → `fvm flutter analyze` — всё чисто.
- [ ] Коммиты — imperative, ≤50-символьный сабджект с заглавной, атомарные, с `git commit -s` (с учётом репо-правил о подтверждении владельцем).
- [ ] `CLAUDE.md` приложения создан из скелета §12 (обзор/команды, золотые правила, нейминг, HARD RULE форматирования, локализация, заметка про `entity_converter.dart`).

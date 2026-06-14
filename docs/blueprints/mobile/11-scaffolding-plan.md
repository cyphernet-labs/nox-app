# 11 — План скаффолдинга

> **Назначение:** Главный пошаговый плейбук, по которому собирается приложение NOX с нуля — от пустого `lib/` до компилируемого скелета плюс один рабочий вертикальный срез (фича `Item`, end-to-end, с пагинацией). Каждый шаг закрыт контрольной точкой (VERIFICATION CHECKPOINT) и ссылается на конкретный шаблон в `10-code-templates.md`. **Когда читать:** Когда вы готовы скаффолдить проект и нужна точная упорядоченная последовательность действий, файлов и команд с проверкой после каждого крупного этапа. **Связанные документы:** `10-code-templates.md` (точные байты каждого файла), `00-architecture-overview.md` (общая картина и граф зависимостей), `01-stack-and-tooling.md` (стек/инструменты), `02-dependency-injection.md` (DI), `03-domain-layer.md`, `04-data-layer.md`, `05-presentation-layer.md`, `06-theming.md`, `07-pagination.md`, `08-conventions-and-constitution.md`, `09-build-and-secrets-infra.md`, `12-dev-commands.md`.

---

## Как пользоваться этим плейбуком

- Шаги **строго упорядочены**. Не забегайте вперёд — каждый шаг опирается на артефакты предыдущего. Сломанный фундамент множит ошибки.
- Большинство файлов/конфигов кода, которые вы создаёте, определены дословно в **`10-code-templates.md`** (слойные Dart-шаблоны). **Инфраструктурные файлы** (CI-workflow, `mise.toml`/секреты, Gradle/iOS-сборка, `.gitignore`) определены в **`09-build-and-secrets-infra.md`**, а не в 10. Этот плейбук говорит, *какой* шаблон применить, *куда* и *когда*; точные байты — в файле-источнике (10 для кода, 09 для инфры). **Никогда не выдумывайте и не перефразируйте шаблоны** — берите их verbatim, адаптируя только имена/пути.
- После каждого крупного шага идёт **КОНТРОЛЬНАЯ ТОЧКА**. Не переходите дальше, пока она не пройдена. Если не проходит — чините до перехода.
- Сквозной рабочий пример — фича **`Item`** (`ItemModel` / `ItemEntity` / `ItemRepository` / `ItemRepositoryImpl` / `ItemMapper` / `ItemDao` / `ItemListPage` / `ItemListBloc` / `ItemListEvent` / `ItemListState` / `GetItemsConfig`). Для пустых заготовок используйте плейсхолдеры `<Feature>` / `<feature>` / `<Model>`.
- **Первая РЕАЛЬНАЯ фича**, которую будете строить после скелета, — **список чатов** (открытые общие пространства): это server-owned, network-only пагинируемый список, поэтому carve-out «пагинируемые server-owned списки — NETWORK-ONLY» применяется к нему напрямую. По умолчанию используем offset-флейвор пагинации (`page` + `page_size` + `total`); cursor — задокументированная альтернатива (см. `07-pagination.md`). Конкретный контракт пагинации списка чатов финализируется позже с бэкендом NOX (бэкенд/протокол ещё не выбран). Скелет на `Item` спроектирован так, чтобы список чатов лёг в него один-в-один (см. §10 и `07-pagination.md`).

### Соглашения по именам (зафиксированы для всего блюпринта)

| Сущность | Значение |
|---|---|
| Имя Dart-пакета | `nox_app` (все импорты — `package:nox_app/...`) |
| Отображаемое имя | NOX |
| Android `applicationId` / iOS bundle | `com.cyphernetlabs.noxapp` (stage: `com.cyphernetlabs.noxapp.stage`) |
| macOS bundle id | `com.cyphernetlabs.noxapp` (только `prod`; десктоп-флейворы native-уровнем не разводятся) |
| Windows identity | `NOX` (отображаемое имя) + закоммиченный GUID приложения |
| Linux identity | application-id `com.cyphernetlabs.noxapp`, отображаемое имя `NOX` |
| Флейворы | `stage`, `prod` |
| Выбор флейвора на десктопе | `--dart-define-from-file=config/<flavor>.json` (нативного `--flavor` нет) |
| Flutter / Dart | Flutter 3.44.1 через FVM; Dart sdk `>=3.12.0 <4.0.0` |
| Длина строки форматтера | 140 |

### Ключевое архитектурное правило (single-package)

Этот скелет — **ОДИН Dart-пакет** (`nox_app`). Слои — это **папки** в одном `lib/`: `lib/data`, `lib/domain`, `lib/presentation`, плюс `lib/di`, `lib/general`, `lib/design`, `lib/resource`. **ОДИН** `pubspec.yaml`, **ОДИН** прогон `build_runner`, **ОДИН** `configureDependencies(String env)` с одним `@InjectableInit(initializerName: r'$initGetIt')` и одним сгенерированным `configure_dependencies.config.dart`. Никаких трёх пакетов, path-зависимостей, цикла `domain↔data`. Каноническая форма путей всегда `lib/domain/...` / `lib/data/...` (никаких `domain/lib/src/...`). Слой `lib/resource` зарезервирован и в скелете пуст (`.gitkeep`) — это **не** место для темы (тема живёт в `lib/design/theme/`, см. Шаг 8); сюда лягут shared-ресурсы первой реальной фичи.

### Одноразовое требование: инструменты на PATH

```bash
# FVM нужен каждому скрипту скелета.
brew install fvm   # macOS; для других платформ см. https://fvm.app
# (Опционально, для прод-инфры секретов и флейворных сборок) mise, sops, age.
```

---

## Шаг 1 — Закрепить Flutter SDK через FVM

**Действие.** Создать корень проекта (репозиторий `nox_app`, дерево `lib/`), закрепить точную версию SDK, чтобы каждый разработчик и CI-раннер использовали один Flutter. Все скрипты скелета вызывают `fvm flutter` / `fvm dart` — никогда захардкоженный путь к SDK.

**Файлы** (см. `10-code-templates.md` → «FVM»):
- `.fvmrc` — пинит `{"flutter": "3.44.1"}` (коммитится).

**Команды.**

```bash
# Из корня репозитория:
fvm install            # читает .fvmrc, ставит Flutter 3.44.1 в .fvm-кэш
fvm flutter --version  # подтвердить активную 3.44.1
```

Добавьте `.fvm/` в `.gitignore` (кэш не коммитится); `.fvmrc` **коммитится**.

**КОНТРОЛЬНАЯ ТОЧКА 1**
- [ ] `fvm flutter --version` печатает `Flutter 3.44.1` и `Dart 3.x` (≥ 3.12.0).
- [ ] `.fvmrc` существует и содержит `{"flutter": "3.44.1"}`.
- [ ] `.fvm/` перечислен в `.gitignore`.

---

## Шаг 2 — Один `pubspec.yaml` и объединённые зависимости

**Действие.** Создать ОДИН Flutter-проект (presentation-слой и есть корень) и заменить сгенерированный `pubspec.yaml` единым манифестом из шаблонов. Никаких path-зависимостей `domain`/`data` — это один пакет.

**Файлы** (см. `10-code-templates.md` → «pubspec.yaml»):
- `pubspec.yaml` (единственный) — `name: nox_app`, `environment: sdk: '>=3.12.0 <4.0.0'`, объединённые зависимости всех трёх слоёв.

**Команды.**

```bash
# Создаём РЕАЛЬНЫЙ Flutter-проект (нужны платформенные runner'ы для flutter build/test).
# Целевые платформы: iOS, Android + три десктопа (macOS, Windows, Linux); web вне области.
fvm flutter create --org com.cyphernetlabs --project-name nox_app --platforms=android,ios,macos,windows,linux .

# Заменяем сгенерированный pubspec.yaml единым манифестом из шаблонов, затем:
fvm flutter pub get
```

**Ключевые зависимости (объединённый набор одного пакета).** Архитектурное ядро: `injectable`, `get_it`, `flutter_bloc`, `bloc_test`, `freezed_annotation` + `freezed`, `json_annotation` + `json_serializable`, `rxdart`, `dio`, `infinite_scroll_pagination: ^5.1.1`, `flutter_screenutil`, `intl`, `collection`, `uuid`. Persistence/инфра: `sembast`, `path_provider`, `shared_preferences`, `flutter_secure_storage`, `package_info_plus`, `logger`. Dev: `build_runner`, `injectable_generator`, `freezed`, `json_serializable`, `flutter_lints`, `mockito`.

**Не тянем (вне области этого блюпринта):** `ffi`, `flutter_rust_bridge`, `desktop_multi_window`, `yaru`, `flex_color_picker`, `decimal`, `custom_adaptive_scaffold`, любые crypto/wallet/RGB/FFI/multi-window зависимости.

> **Важно — что именно исключено (а что НЕТ).** Десктоп-таргеты (macOS/Windows/Linux) **включены** (см. Шаг 2); исключаются конкретные desktop-пакеты, а не сама десктоп-поддержка. Конкретно: `desktop_multi_window` исключён = **«no multi-window»** (одно окно на приложение); `custom_adaptive_scaffold` исключён = **«no adaptive-scaffold dep»** (адаптив строим сами на `AppShell`, см. Шаг 9, без сторонней зависимости); `yaru` исключён = **«unified Material 3 (no yaru)»** (единая тема Material 3 на всех таргетах, без Linux-специфичного yaru). Управление нативным окном (`window_manager` / `bitsdojo_window`) в скелет **не входит** — дефолтное системное окно; пересмотр — когда появится конкретное требование к окну.

**КОНТРОЛЬНАЯ ТОЧКА 2 — pub get clean**
- [ ] `fvm flutter pub get` проходит без конфликтов версий.
- [ ] `pubspec.lock` создан в корне.
- [ ] runner'ы для всех 5 таргетов сгенерированы (`android/`, `ios/`, `macos/`, `windows/`, `linux/`), `web/` нет.
- [ ] В `pubspec.yaml` нет path-зависимостей `domain`/`data` (это один пакет).
- [ ] Нет crypto/FFI/multi-window зависимостей.

---

## Шаг 3 — `build.yaml` и `analysis_options.yaml`

**Действие.** Настроить кодогенерацию и статический анализ для единого пакета.

**Файлы** (полные шаблоны — в `01-stack-and-tooling.md` → «build.yaml» / «analysis_options.yaml»):
- `build.yaml` (один) — опции `json_serializable` для всего пакета: `explicit_to_json: true`, `include_if_null: true`, `field_rename: none`, `create_factory: true`, `create_to_json: true`.
- `analysis_options.yaml` (один) — `include: package:flutter_lints/flutter.yaml` (**стандартный** набор, без кастомных правил и без `errors`-карты); `formatter: page_width: 140`; исключения: `**/*.g.dart`, `**/*.freezed.dart`, `**/*.config.dart`, `lib/design/gen/**`, `build/**`.

**Команды.**

```bash
# Эти файлы потребляются build_runner (Шаг 4+) и analyze (Шаг 16).
# Проверка, что YAML парсится:
fvm dart pub get
```

**КОНТРОЛЬНАЯ ТОЧКА 3**
- [ ] `build.yaml` присутствует в корне.
- [ ] `analysis_options.yaml` включает `package:flutter_lints/flutter.yaml`, длину строки 140 и исключает все генерируемые файлы (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, `lib/design/gen/**`).
- [ ] `fvm dart pub get` всё ещё проходит (битый YAML упал бы здесь).

---

## Шаг 4 — Скелет директорий (один `lib/`)

**Действие.** Создать пустое дерево директорий для всех слоёв в одном `lib/`, чтобы последующие шаги клали файлы в канонические места. Кода ещё нет — только папки (`.gitkeep` там, где папка должна коммититься пустой).

**Целевое дерево** (см. `00-architecture-overview.md` за обоснованием):

```
lib/
├── data/
│   ├── di/
│   ├── entity/
│   ├── exception/
│   ├── local/
│   ├── mapper/
│   ├── remote/
│   │   ├── api/
│   │   └── request_builder/base/
│   └── repository/
├── domain/
│   ├── exception/
│   ├── model/
│   └── repository/base/
├── presentation/
│   ├── app/bloc/
│   ├── app/widgets/
│   ├── base/
│   ├── pages/base/
│   ├── widgets/
│   ├── helpers/
│   └── extension/
├── di/
├── general/formatters/
├── design/theme/
├── resource/
└── main.dart
test/utils/
.github/workflows/
```

**Команды.**

```bash
mkdir -p \
  lib/data/di lib/data/entity lib/data/exception lib/data/local lib/data/mapper \
  lib/data/remote/api lib/data/remote/request_builder/base lib/data/repository \
  lib/domain/exception lib/domain/model lib/domain/repository/base \
  lib/presentation/app/bloc lib/presentation/app/widgets lib/presentation/base lib/presentation/pages/base \
  lib/presentation/widgets lib/presentation/helpers lib/presentation/extension \
  lib/di lib/general/formatters lib/design/theme lib/resource \
  test/utils .github/workflows
```

**Однонаправленные зависимости (правило импортов, проверяемое глазами на всех последующих шагах):** `presentation → domain`, `data → domain`; `domain` не импортирует ничего из `data`/`presentation`. Никакого цикла `domain↔data` — DI связывает реализацию с контрактом без обратной зависимости пакета.

**КОНТРОЛЬНАЯ ТОЧКА 4**
- [ ] Дерево выше существует.
- [ ] Лишних файлов нет (только папки).

---

## Шаг 5 — База доменного слоя

**Действие.** Собрать переиспользуемый фундамент `lib/domain/`: обёртка результата, иерархия исключений, маркер конфига. Всё остальное в домене зависит от этого. **Доменные модели — `@freezed` БЕЗ JSON** (только `.freezed.dart`, никогда `.g.dart`); JSON живёт в entity-слое.

**Файлы** (см. `10-code-templates.md` → «Domain base»):
- `lib/domain/exception/base_repository_exception.dart` — абстрактный `BaseRepositoryException`.
- `lib/domain/exception/repository_exception.dart` — `enum RepositoryException implements BaseRepositoryException { unknown, internal, authentication, connection, unauthenticated, notFound }`.
- `lib/domain/repository/base/repository_result.dart` — `@freezed RepositoryResult<T>` с фабриками `success`/`error` (data-XOR-exception, **не** «оба nullable»).
- `lib/domain/repository/base/repository_result_handling.dart` — урезанный `match<R>(onData, onError)` extension (используется вместо `result.data!`).
- `lib/domain/repository/base/repository_config.dart` — `abstract class RepositoryConfig {}`.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

**КОНТРОЛЬНАЯ ТОЧКА 5 — build_runner OK (domain base)**
- [ ] `lib/domain/repository/base/repository_result.freezed.dart` сгенерирован (и **никакого** `repository_result.g.dart` — доменные типы без JSON).
- [ ] build_runner завершился кодом 0.
- [ ] `fvm flutter analyze lib/domain` без ошибок.

---

## Шаг 6 — База data-слоя

**Действие.** Собрать переиспользуемый фундамент `lib/data/`: унифицированный конверт ответа бэкенда, реестр конвертеров entity, базовый маппер, реактивный Sembast DAO + env-scoped `AppDatabase`, Dio-клиент, `BaseRepositoryHelper` с **обязательным** `LogRepository` (типизированной иерархии исключений нет — `DioException → RepositoryException.internal`, прочее → `unknown` внутри `execute<T>()`).

**Файлы** (см. `10-code-templates.md` → «Data base»; авторитетные шаблоны самого data-слоя — в `04-data-layer.md`):
- `lib/data/entity/base/response_entity.dart` — `ResponseEntity<T>` с полями `{success, error, data}` (`@EntityConverter() T? data`) *(форма конверта — **пример**: бэкенд/протокол NOX ещё не выбран; заменить на реальный контракт)*.
- `lib/data/entity/base/entity_converter.dart` — ручной реестр `EntityConverter<E>` (начинайте с пустого диспетчера, добавляйте entity по мере создания). Entity — **только базовые типы**: enum как `.name` String, DateTime как ISO-8601 String, вся коэрция в маппере.
- `lib/data/mapper/base_mapper.dart` — `abstract class BaseMapper<E, M, AdResult, AdParam>` (4 type-параметра; `toModel` / `toEntity` + list-хелперы `toListModel`/`toListEntity`).
- `lib/data/exception/base_repository_helper.dart` — `mixin BaseRepositoryHelper` с защищённым `execute<TD>()`, который **всегда** логирует через `LogRepository` (единый канал, никаких сырых `print`). Типизированной иерархии исключений нет: внутри `execute<TD>()` ровно две catch-ветки — `DioException` маппится в `RepositoryException.internal`, любое прочее необработанное — в `RepositoryException.unknown` (см. `04-data-layer.md` §5). Отдельных `DaoException`/`ApiException`/`BaseDomainExceptionHelper`-файлов **не создавать** (их в коде нет). Dio/транспортные специфики — **пример/TBD** (транспорт NOX не выбран).
- `lib/domain/repository/log_repository.dart` (интерфейс) + `lib/data/repository/log_repository_impl.dart` (impl, `LoggerLogRepository implements LogRepository`) — **обязательный** единый канал логирования (методы ровно `debug({Object? target, required String message})` / `error({Object? target, required Object error, StackTrace? stackTrace})`).
- `lib/data/local/app_database.dart` — `abstract class AppDatabase` (интерфейс ровно `Future<Database> get db;` + `Future<void> clearEntireDatabase();`) + env-scoped провайдеры через `@LazySingleton(as: AppDatabase, env: [...])`: `AppDatabaseDev` / `AppDatabaseProd` (Sembast IO через `databaseFactoryIo`/`path_provider` — mobile/desktop) и `AppDatabaseTest` (Sembast `databaseFactoryMemory`).
- `lib/data/remote/api_client.dart` — тонкая Dio-обёртка `ApiClient` (base URL / auth / HMAC — **пример/TBD**, бэкенд NOX не выбран).
- `lib/data/remote/request_builder/base/request_builder.dart` + `request_builder_helper.dart` — базовый builder запросов.

> *Реактивный DAO: репозиторий подписывается на поток DAO **один раз** (`onSnapshots`, `transactions`) и питает один `BehaviorSubject<RepositoryResult<...>>`. **Carve-out (важно):** пагинируемые server-owned списки и one-shot POST'ы — **NETWORK-ONLY** (без DAO/subject), см. `07-pagination.md` и `04-data-layer.md`.*

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze lib/data
```

**КОНТРОЛЬНАЯ ТОЧКА 6 — build_runner OK (data base)**
- [ ] build_runner завершился кодом 0.
- [ ] `AppDatabaseDev` / `AppDatabaseProd` / `AppDatabaseTest` компилируются (импорты Sembast / `path_provider` на месте).
- [ ] `ResponseEntity`, `EntityConverter`, `BaseMapper`, `ApiClient`, `BaseRepositoryHelper`, `LogRepository` компилируются.
- [ ] `fvm flutter analyze lib/data` без ошибок.

---

## Шаг 7 — Single-tier DI + bootstrap

**Действие.** Свести единый DI-бутстрап. ОДИН `configureDependencies(String env)` с ОДНИМ `@InjectableInit(initializerName: r'$initGetIt')` и ОДНИМ сгенерированным `configure_dependencies.config.dart`. Плюс компиляционная изоляция флейворов, `AppConfig` + `AppConfigRepository`, `global_aliases` и `main.dart`.

**Файлы** (см. `10-code-templates.md` → «DI» и «main.dart»):
- `lib/di/configure_dependencies.dart` — `@InjectableInit(initializerName: r'$initGetIt')`, единственная точка входа DI. В скелете тело **минимальное**: `getIt.$initGetIt(environment: env)` (без явной регистрации `PackageInfo` и без if/else — env-scoping делает сам injectable через `env:[...]` на провайдерах). Регистрация `PackageInfo` — future-задел, проводится с первым потребителем.
- `lib/di/global_aliases.dart` — удобные геттеры над DI-контейнером; в скелете ровно два: `logRepository` (`getIt<LogRepository>()`) и `itemRepository` (`getIt<ItemRepository>()`). Feature-геттеры добавляются по мере фич.
- `lib/domain/model/app_config/app_flavor_type.dart` + `lib/domain/model/app_config/app_flavor.dart` — `enum AppFlavorType { prod, stage }` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')` (дефолт — `prod`); маппинг флейвор→env: `prod → Environment.prod`, `stage → Environment.dev`. `app_flavor.dart` читает **только** `app.flavor`.
- `lib/domain/model/app_config/app_config.dart` — `AppConfig({required AppFlavorType flavor})` (плоский класс; несёт **только** `flavor`; источник токена/`apiUrl`/security-заголовки — *примерные поля; бэкенд/протокол NOX ещё не выбран, набор конфига заменить на реальный контракт*). Контракт — `lib/domain/repository/app_config/app_config_repository.dart` (интерфейс), реализация — `lib/data/repository/app_config/app_config_repository_impl.dart` (`@LazySingleton(as: AppConfigRepository, env:[dev,prod,test])`, без ctor-инъекций, метод `initialize(...)`). (`AppConfigModel` как тип **не существует** — это TBD-цель.)
- `lib/main.dart` — оборачивает в `runZonedGuarded` → `WidgetsFlutterBinding.ensureInitialized()` → определить flavor+env из `AppFlavor.getFlavor()` → `await Future.wait([configureDependencies(env), setPreferredOrientations(portraitUp)])` → `await getIt.allReady()` → `await getIt<AppConfigRepository>().initialize(flavorType: flavor)` → `runApp(const AppRoot())`. Ошибки логируются в `catch` через `LogRepository` под `isRegistered`-guard — отдельного BLoC-обсервера нет. Канонический `main.dart` — `02-dependency-injection.md` §10.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

**КОНТРОЛЬНАЯ ТОЧКА 7 — build_runner OK (DI)**
- [ ] `lib/di/configure_dependencies.config.dart` сгенерирован.
- [ ] Сгенерированный файл объявляет ровно одно расширение `$initGetIt` (никаких `$initDomainGetIt` / `$initDataGetIt` — это один пакет).
- [ ] build_runner завершился кодом 0.
- [ ] `AppFlavor.getFlavor()` читает `String.fromEnvironment('app.flavor')` и маппит `prod→Environment.prod`, `stage→Environment.dev`.

---

## Шаг 8 — Дизайн-система и тема (light + dark)

**Действие.** Добавить фундамент темы: `ThemeExtension<AppColors>`, `AppTheme.light()`/`.dark()` поверх **сгенерированного из токенов** дизайн-хендоффа, четыре класса токенов, `flutter_screenutil` (дизайн-размер 360×779), константы, утилиты платформы, форматтеры, общие виджеты и `AlertDialogHelper`.

**Файлы** (см. `10-code-templates.md` → «Theming» и `06-theming.md`):
- `lib/design/theme/app_colors.dart` — `AppColors extends ThemeExtension<AppColors>` с `LightAppColors` / `DarkAppColors` + extension `context.appColors`. Семантические, mode-зависимые цвета поверх M3 `ColorScheme`; полная token-driven палитра — из `docs/design/system/nox-handoff/`.
- `lib/design/app_spacing_tokens.dart`, `lib/design/app_text_style_tokens.dart`, `lib/design/app_overlay_style_tokens.dart`, `lib/design/app_images_tokens.dart` — **четыре** класса токенов (`AppSpacingTokens` / `AppTextStyleTokens` / `AppOverlayStyleTokens` / `AppImagesTokens`; первые три responsive через `flutter_screenutil`). Каналов ассетов два: каноничен **flutter_gen** (`lib/design/gen/assets.gen.dart` — `Assets.png/.svg`, gitignored, прописан в pubspec + CI), `AppImagesTokens` (`_base = 'assets/png'`) — удобный handwritten-канал. **`AppColorsTokens` НЕ существует**: цвет — только `context.appColors` (публичного класса-палитры нет).
- `lib/design/theme/app_theme.dart` — `AppTheme.light()` / `AppTheme.dark()`. `AppTheme._build(scheme, appColors)` потребляет `const ColorScheme noxLightScheme/noxDarkScheme` (`lib/design/theme/nox_color_scheme.dart`) + `noxTextTheme` (`lib/design/theme/nox_text_theme.dart`) — **НЕ** `ColorScheme.fromSeed` (роли тщательно подобраны), плюс `extensions: [LightAppColors()/DarkAppColors()]`. `themeMode` поставляется `AppRootBloc`. Файлы хендоффа `lib/design/theme/nox_{brand,color_scheme,text_theme,tokens}.dart` **регенерируются** из `docs/design/system/nox-handoff/tokens` (через `docs/design/system/nox-handoff/flutter/`) — не правятся руками. Бренд-фиксированные исключения вне темы: splash всегда тёмный, QR-поверхность всегда светлая.
- `lib/general/constants.dart` — `final class Constants` (приватный ctor, константы, regex'ы, `defaultLocale`, `designSize` = `Size(360, 779)`, `railBreakpoint` = `840`, `defaultNavTransitionTimeMilliseconds`).
- `lib/general/platform_utils.dart` — `PlatformUtils` (desktop/mobile; геттеры по `Platform.isWindows/isMacOS/isLinux` для per-OS нужд).
- `lib/general/text_constants.dart` — `TextConstants` (имя приложения «NOX» + общие строки UI).
- `lib/general/feature_flags.dart` — `FeatureFlags` (compile-time переключатели).
- `lib/general/formatters/date_formatter.dart` — статическая утилита на `intl`; `lib/general/formatters/value_formatter.dart` — `@lazySingleton` (резолвится через `getIt`), в скелете — фиксированный `Constants.defaultLocale`; settings-связанный вариант (locale из `SettingsRepository`) — задокументированная future-цель (см. 06 §8.3).
- *(Канон, aspirational — в скелете ещё нет)* `lib/presentation/helpers/alert_dialog_helper.dart` — `AlertDialogHelper`; и `lib/presentation/widgets/app_progress_widget.dart` / `app_error_widget.dart` / `app_empty_content_widget.dart` — три общих state-виджета. Это целевая форма для реальных фич; **shipped-харнес** их не содержит (каталогов `lib/presentation/widgets/` и `lib/presentation/helpers/` в скелете нет), а `ItemListPage` рендерит состояния inline (`CircularProgressIndicator`/`Center`, см. Шаг 10d). Заводятся с первым реальным потребителем.

**Команды.**

```bash
# В скелете каталога lib/presentation/widgets/ ещё нет; добавьте его в analyze,
# когда заведёте общие state-виджеты (см. выше — aspirational).
fvm flutter analyze lib/design lib/general
```

**КОНТРОЛЬНАЯ ТОЧКА 8 — analyze clean (theming)**
- [ ] `fvm flutter analyze lib/design lib/general` без ошибок.
- [ ] `AppTheme.light()` / `AppTheme.dark()` компилируются, читают `noxLightScheme`/`noxDarkScheme` + `noxTextTheme` (не `fromSeed`) и регистрируют `AppColors` в `extensions`.
- [ ] Четыре класса токенов (`AppSpacingTokens`, `AppTextStyleTokens`, `AppOverlayStyleTokens`, `AppImagesTokens`) экспонируют свои шкалы; картинки — через flutter_gen (`lib/design/gen/assets.gen.dart`) и/или `AppImagesTokens`; цвет — только через `context.appColors`, публичного класса-палитры НЕТ (`AppColorsTokens` не существует).
- [ ] `context.appColors` резолвится из обеих тем (light/dark).

---

## Шаг 9 — База presentation (оболочка + AppRootBloc + Freezed-BLoC-конвенции)

**Действие.** Собрать фундамент presentation: `BaseBloc<E,S>`, `BaseStatePage<T>`, оболочка приложения `AppRoot` с `AppRootBloc` (тема + глобальное состояние, `themeMode`). Здесь же фиксируется **Freezed-BLoC-конвенция** для всех будущих BLoC. Отдельного BLoC-обсервера нет: логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует), а ошибки BLoC-обработчиков оборачиваются `BaseBloc.executeLogic`.

**Файлы** (см. `10-code-templates.md` → «Presentation base» и `05-presentation-layer.md`):
- `lib/presentation/base/base_bloc.dart` — тонкий `BaseBloc<E,S>` с `executeLogic(..., onError: ...)` (try/catch-обёртка); все page-BLoC наследуют его (`extends BaseBloc<…>`), а не `Bloc<…>` напрямую.
- `lib/presentation/pages/base/base_state_page.dart` — `abstract class BaseStatePage<T extends StatefulWidget> extends State<T>` (scaffoldKey, drawer-хелперы, `buildAppBar()`).
- `lib/presentation/app/bloc/app_root_bloc.dart` + `app_root_state.dart` + `app_root_event.dart` — `AppRootBloc` на тонком `BaseBloc<E,S>`; `@freezed` Event sealed union; `AppRootState` — single-variant `@freezed abstract class` с полем `themeMode` (`const factory AppRootState({required ThemeMode themeMode}) = _AppRootState;`), без подсостояний `Initializing` / `Initialized` / `Error`. `MaterialApp` читает `state.themeMode`.
- `lib/presentation/app/app_root.dart` — корневой `MaterialApp` (`theme`/`darkTheme` из `AppTheme`, `themeMode` из `AppRootBloc`, `navigatorKey`, `onGenerateRoute`); обёрнут в `ScreenUtilInit(designSize: Constants.designSize` = `Size(360, 779)`, `minTextAdapt: true)` + двойной `MediaQuery` (`TextScaler.noScaling` / `TextScaler.linear(1.0)`) — нейтрализация OS-масштаба шрифта (UI-скейл, см. `06-theming.md` §3.2); `home` → `AppShell` (адаптивная оболочка скелета).
- `lib/presentation/app/widgets/app_shell.dart` — адаптивная оболочка (`LayoutBuilder`-обёртка): ветвление **width-driven** по `constraints.maxWidth >= Constants.railBreakpoint` (840dp, граница M3 medium→expanded), **не** по `Platform` — узкое окно на десктопе остаётся на мобильной раскладке (см. `05-presentation-layer.md` §6.5). Mobile-ветка — `Scaffold` + нижний бар (`BottomAppBar` с notch) и центральный docked `+` FAB; desktop-ветка — `NavigationRail` с `+` как `leading` FAB. Две destination'ы переключаются через `IndexedStack` (`AppShell._pages`): `Chats` — тело **напрямую** `ItemListPage()` (в скелете это и есть `Item`-верификационный харнес); `Settings` — `lib/presentation/pages/placeholder/settings_placeholder_page.dart`. (`chats_placeholder_page.dart` в скелете присутствует, но в `IndexedStack` не используется — тело `Chats` идёт прямо на `ItemListPage`.) Это единственный адаптивный шов скелета; сторонний `custom_adaptive_scaffold` не используется (`PlatformUtils` остаётся для иных per-OS нужд, но раскладку оболочки НЕ выбирает).

> **Freezed-BLoC-конвенция (фиксируется здесь, применяется ко всем BLoC).** `@freezed` sealed union для State и Event; тонкий `BaseBloc<E,S>` с `executeLogic` (try/catch); производная/вычисляемая логика — в **extension-геттерах** (не в `@freezed`-теле); переходы через `copyWith`; `sealed` для multi-variant union'ов, `abstract` для single-variant value-объектов; **никакого `fromJson` на BLoC-типах** (только `*.freezed.dart`, никогда `*.g.dart`). Это **намеренно перекрывает** ранний подход с руками-написанными sealed+Equatable BLoC и старое правило «no Freezed for state» — см. `05-presentation-layer.md` и `08-conventions-and-constitution.md`. Имена union-членов подсостояний для **multi-variant** стейтов страниц (например `ItemListState`) — **bare** `Initializing` / `Initialized` / `Error`, как `const factory` (`const factory ItemListState.error({BaseRepositoryException? exception}) = Error;`), и переключаются как `Initializing()`/`Initialized()`/`Error()`. Префиксные имена (`<Feature>Initializing`…) — допустимый вариант на случай коллизий, но канон скелета — bare. **Single-variant** value-объекты (например `AppRootState` с `themeMode`) — `@freezed abstract class` с одним конструктором, без трио.

> **Инвариант 3a (навигируемая страница ⇒ свой BLoC).** Любая навигируемая `*Page` с `routeName`/`route()` обязана иметь собственный BLoC (logic-less страницы — минимальный BLoC); переиспользуемые `widgets/` BLoC не требуют. **Code-divergence (скелет):** `AppShell` собственного BLoC не имеет; в `IndexedStack` оболочки лежат `ItemListPage()` (тело `Chats`) и `settings_placeholder_page.dart` (тело `Settings`) — обе достижимы только через `IndexedStack` (не `routeName`-навигируемы), у них нет `routeName`/`route()`, поэтому правило к ним применяется чисто. `chats_placeholder_page.dart` присутствует, но в `IndexedStack` не используется (тело `Chats` идёт прямо на `ItemListPage`). Это допустимые упрощения скелета до прихода реальных фич.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze lib/presentation lib/main.dart
```

**КОНТРОЛЬНАЯ ТОЧКА 9 — analyze clean (presentation base)**
- [ ] `app_root_bloc.freezed.dart` сгенерирован (и **нет** `.g.dart` для BLoC-типов).
- [ ] `fvm flutter analyze lib/presentation lib/main.dart` без ошибок (ссылка на `ItemListPage`-плейсхолдер из `AppShell` резолвится после Шага 10 — временно роутите на заглушку, если строите presentation-базу первой).
- [ ] `BaseBloc`, `BaseStatePage`, `AppRootBloc`, `AppRoot`, `AppShell`, `main.dart` компилируются.
- [ ] `AppShell` (`LayoutBuilder`) ветвится width-driven по `constraints.maxWidth >= Constants.railBreakpoint` (840dp), **не** по `Platform`: нижний бар при `< 840dp`, `NavigationRail` при `>= 840dp`; `AppRoot` `home` → `AppShell`; `IndexedStack` несёт `[ItemListPage(), SettingsPlaceholderPage()]` — `Chats` → `Item`-харнес напрямую, `Settings` → плейсхолдер.

---

## Шаг 10 — Первый вертикальный срез `Item` (с пагинацией, end-to-end)

**Действие.** Реализовать одну фичу сверху-вниз, чтобы доказать совместную работу всех слоёв, DI и пагинации. Это критерий приёмки «скелет работает». Срез включает **offset-пагинацию** (дефолтный флейвор: `PageMetadata{required int total, int? nextPage}`) через `infinite_scroll_pagination ^5.1.1` (v5 stateless `PagingState`-in-bloc), pull-to-refresh. Порядок сборки: домен → данные → DI → presentation.

> Полный контракт пагинации — в `07-pagination.md`. Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>` (конверт `RepositoryResult` **сохраняем**, не используем сырой `Future`+try/catch); `result.exception` пробрасывается в `pagingState.error` для error-builder'ов v5. Конкретный контракт пагинации списка чатов NOX — TBD с бэкендом; `Item` — нейтральный шаблон-болванка.

> **Lean-harness vs aspiration.** Полный канонический `Item`-пример (CRUD + cache-first watch, `GetItemConfig`, search/refresh/concurrency BLoC) — **aspirational**-стандарт блюпринта. Реальный shipped-харнес Feature-001 — намеренно **урезанный** подмножество: `ItemRepository` экспонирует только `getItems(...)` + `clean()` (network-only, без DAO/subject); `ItemListEvent` = `{ Initialize, LoadItems({@Default(false) bool reset}) }`; `ItemListState` — bare-имена с `@Default(GetItemsConfig.defaultPage) int nextPage` (non-nullable). Реальные поля `ItemModel`: `required String id`, `required String name`, `required String? description`, `required ItemStatus status` (без `@Default`), `required DateTime createdAt`; extension-геттеры — `isArchived` (не `isPublished`) + `displayName`.

### 10a — Домен: модель, конфиг, контракт

**Файлы** (см. `10-code-templates.md` → «Item slice: domain»):
- `lib/domain/model/item/item_model.dart` — `@freezed ItemModel` (поля `required String id`, `required String name`, `required String? description`, `required ItemStatus status`, `required DateTime createdAt`). **Без `fromJson`** (доменная модель — только `.freezed.dart`). Производная логика — extension-геттеры `isArchived` + `displayName`.
- `lib/domain/model/item/item_status.dart` — `enum ItemStatus { active, archived, draft }`.
- `lib/domain/repository/item/item_repository.dart` — `abstract class ItemRepository`; методы возвращают `RepositoryResult<...>`; в скелете ровно два: страничный `Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config})` + `Future<void> clean()`.
- `lib/domain/repository/item/get_items_config.dart` — `@freezed abstract class GetItemsConfig implements RepositoryConfig` (`const factory GetItemsConfig({required int page, String? search})`) с фабриками `firstPage({String? search})` / `nextPage({required int page, String? search})` и константами `static const int pageSize = 20;` / `static const int defaultPage = 1;` (**1-based**). Никакого sealed-union `ItemRepositoryConfigs.list`-редиректа; конструировать как `GetItemsConfig.firstPage()` / `GetItemsConfig.nextPage(page: …)`.
- `lib/domain/repository/base/page_metadata.dart` — `@freezed PageMetadata({ required int total, int? nextPage })` (`nextPage` — 1-based индекс следующей страницы; `null` на последней).

### 10b — Данные: entity, api, dao, mapper, impl

**Файлы** (см. `10-code-templates.md` → «Item slice: data»; remote/REST — `04-data-layer.md`):
- `lib/data/entity/item/item_entity.dart` — `@freezed ItemEntity`, **только базовые типы**: `id:String`, `name:String`, `description:String?`, `status:String` (имя enum), `createdAt:String` (ISO-8601) + `fromJson`. Зарегистрировать в `EntityConverter` (и в `fromJson`, и в `toJson`).
- `lib/data/entity/item/items_entity.dart` — `@freezed ItemsEntity` (page-обёртка): `@Default(<ItemEntity>[]) List<ItemEntity> items`, `@JsonKey(name: 'page') required int page`, `@JsonKey(name: 'page_size') required int pageSize`, `@JsonKey(name: 'total') required int total` + `fromJson`. Имена JSON-ключей — **пример** (бэкенд NOX не выбран). Зарегистрировать в `EntityConverter` рядом с `ItemEntity`.
- `lib/data/mapper/item/item_mapper.dart` — `@lazySingleton ItemMapper extends BaseMapper<ItemEntity, ItemModel, dynamic, dynamic>` (без ctor-зависимостей; `status` коэрсится inline через `ItemStatus.values.firstWhere`; ISO-string↔DateTime; раунд-трип `ItemModel` без потерь).
- `lib/data/remote/request_builder/item/get_items_api_request_builder.dart` — `@lazySingleton GetItemsApiRequestBuilder` (offset-параметры `page`/`page_size`; форма запроса — пример/TBD).
- `lib/data/remote/api/item/get_items_api.dart` — `@lazySingleton GetItemsApi`: `execute({required GetItemsConfig config})` возвращает `ResponseEntity<ItemsEntity>` (`ItemsEntity{items, page, pageSize, total}`); `PageMetadata` собирает репозиторий клиентски — канон `04-data-layer.md` §8; в скелете — mock-body (FR-013), реальный путь `v1/items` + `page`/`page_size`/`search` — пример/TBD.
- `lib/data/repository/item/item_repository_impl.dart` — `@LazySingleton(as: ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])`, `ItemRepositoryImpl(this._itemMapper, this._getItemsApi)` (инъекции — mapper + api, **не** DAO; логирование — через миксин `BaseRepositoryHelper`, не отдельным полем), оборачивает каждый метод в `execute<TD>()`. **Страничный список — NETWORK-ONLY** (без DAO/subject — server-owned пагинация). Repo-математика: `hasMore = (page * pageSize) < total; nextPage = hasMore ? page + 1 : null`. Если у фичи есть и кэшируемая часть (watch одной сущности) — она бэкается `BehaviorSubject` и DAO; для `getItems` — нет.
- `lib/data/local/item/item_dao.dart` — `@lazySingleton ItemDao` (per-ID records-store: `stringMapStoreFactory.store('items')`, ключ — `item.id`, с `getById`; `watch()` через `onSnapshots`, CRUD, `db.transaction()`, `cleanData()`) — только если фиче нужен кэш отдельной сущности; для чистого страничного списка DAO не требуется. (Single-record collection-store — помеченная альтернатива.)

### 10c — Freezed-BLoC (с PagingState)

**Файлы** (см. `10-code-templates.md` → «Item slice: presentation» и `07-pagination.md`):
- `lib/presentation/pages/item_list_page/bloc/item_list_state.dart` — `@freezed sealed class ItemListState`; держит `PagingState<String, ItemModel>` (ключ `K` — `String` id элемента, через `keyExtractor: (e) => e.id`) + `@Default(GetItemsConfig.defaultPage) int nextPage` (non-nullable, 1-based) — offset отслеживается полем `nextPage`, ключ остаётся `String`-id (служебный, для дедупа v5); подсостояния — **bare** `Initializing` / `Initialized` / `Error` как `const factory` (`const factory ItemListState.error({BaseRepositoryException? exception}) = Error;`). Производные геттеры — в extension.
- `lib/presentation/pages/item_list_page/bloc/item_list_event.dart` — `@freezed sealed class ItemListEvent` ровно с двумя членами: `const factory ItemListEvent.initialize() = Initialize;` и `const factory ItemListEvent.loadItems({@Default(false) bool reset}) = LoadItems;` — **один** универсальный `LoadItems` для первой загрузки/догрузки/сброса (канон `07-pagination.md` §3 правила 4–5; отдельных `FetchNextPage`/`LoadNextPage`/`RefreshRequested`/`SelectItem`/`DeleteItem` не плодить — в скелете их нет; mutation/selection-события — иллюстративный future).
- `lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart` — `ItemListBloc extends BaseBloc<ItemListEvent, ItemListState>`; `getIt<ItemRepository>()` (через алиас `itemRepository`); применяет страницу через переиспользуемый extension `PagingStateExt.applyPage` (`lib/presentation/pagination/paging_state_ext.dart`); `result.exception → pagingState.error`.

### 10d — Страница

**Файлы** (см. `10-code-templates.md` → «Item slice: presentation»):
- `lib/presentation/pages/item_list_page/item_list_page.dart` — `ItemListPage extends StatefulWidget`; создаёт `ItemListBloc()..add(const ItemListEvent.initialize())` в `initState`, закрывает в `dispose`; `BlocProvider` + `BlocBuilder`; `PagedListView` (v5); рендерит `state` через `switch`. **Канон (aspirational):** навигируемая `*Page` несёт статические `routeName` + `route()`, её state наследует `BaseStatePage<ItemListPage>`, а состояния рендерятся общими виджетами `AppProgressWidget`/`AppErrorWidget`/`AppEmptyContentWidget` (`lib/presentation/widgets/`) — это целевая форма для **реальных** навигируемых фич.
- **Code-divergence (скелет).** Shipped-харнес — урезанная page-форма: `_ItemListPageState extends State<ItemListPage>` (не `BaseStatePage`); `routeName`/`route()` **нет** (слайс не навигируемый — открывается как тело `Chats`-вкладки через `IndexedStack`, см. ниже); состояния рендерятся **inline** (`CircularProgressIndicator`/`Center`/`PagedListView`), а не через `AppProgressWidget`/`AppErrorWidget`/`AppEmptyContentWidget` — этих общих виджетов (и каталога `lib/presentation/widgets/`) в скелете ещё нет. `routeName`/`route()` + `BaseStatePage` + общие state-виджеты добавляются, когда срез станет реальной навигируемой страницей (инвариант 3a).
- В скелете `Item`-слайс достижим как тело `Chats`-вкладки `AppShell` (`IndexedStack`), а `home` `AppRoot` — это `AppShell`. Тело `Chats`-вкладки подключено **напрямую** к `ItemListPage()` (`AppShell._pages = [ItemListPage(), SettingsPlaceholderPage()]`); `chats_placeholder_page.dart` в скелете присутствует, но в `IndexedStack` не используется.

### 10e — DI-регистрация + алиасы

- Добавить `itemRepository`-геттер в `lib/di/global_aliases.dart` (`getIt<ItemRepository>()`). В скелете алиасов ровно два: `logRepository` + `itemRepository` (mapper/api резолвятся напрямую через DI, отдельных алиасов не заводим).
- Убедиться, что `ItemRepositoryImpl` зарегистрирован `as: ItemRepository` для `[dev, prod, test]`.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

**КОНТРОЛЬНАЯ ТОЧКА 10 — полный срез компилируется + analyze clean**
- [ ] build_runner завершился кодом 0 (`item_model.freezed.dart`, `item_entity.{freezed,g}.dart`, `items_entity.{freezed,g}.dart`, `get_items_config.freezed.dart`, `item_list_bloc.freezed.dart`, обновлён `configure_dependencies.config.dart`).
- [ ] `item_model.freezed.dart` есть, `item_model.g.dart` **нет** (доменная модель без JSON); `item_entity.g.dart` / `items_entity.g.dart` есть (entity — с JSON).
- [ ] `fvm flutter analyze` без ошибок.
- [ ] `ItemListPage` рендерит три состояния; `ItemListBloc` резолвит `getIt<ItemRepository>()`, mapper/api резолвятся через DI.
- [ ] Пагинация работает: первая страница грузится, скролл подтягивает следующую через `LoadItems(reset: false)`, ошибка пробрасывается в error-builder, pull-to-refresh сбрасывает `PagingState` через `LoadItems(reset: true)`.
- [ ] Приложение собирается: `fvm flutter run --dart-define-from-file=config/stage.json` показывает список `Item`. Флейвор-файлы `config/stage.json` / `config/prod.json` коммитятся; реальные секреты (если потребуются) подключаются позже, на Шаге 14 (SOPS+age+mise).

---

## Шаг 11 — Tooling (Makefile + mise-задачи)

**Действие.** Добавить оркестрацию кодогена, тестов, форматирования, анализа и флейворных сборок. Всё вызывает `fvm flutter` / `fvm dart` (или Flutter через FVM-симлинк). **Скриптов `script_*.sh` в репозитории нет** — оркестрация это `Makefile` + `.mise.toml` (так в коде).

**Файлы** (см. `10-code-templates.md` → «Makefile» / «mise» и `12-dev-commands.md` / `09-build-and-secrets-infra.md`):
- `Makefile` — dev-таргеты: `deps` (`fvm flutter pub get`), `generate` (`fvm dart run build_runner build --delete-conflicting-outputs`), `format` (`fvm dart format -l 140 lib test`), `analyze` (`fvm flutter analyze`), `test` (`fvm flutter test`), агрегат `gate` (`generate format analyze test`), плюс билд-обёртки `build-macos-stage`/`build-macos-prod`/`build-windows-stage`/`build-linux-stage` (вызывают `mise run build:<platform>:<flavor>`).
- `.mise.toml` — `[tools]` (`sops`, `age`), `[env]` (`SOPS_AGE_KEY_FILE`, `FLUTTER` = `{{ config_root }}/.fvm/flutter_sdk/bin/flutter`) и таски `[tasks."build:<platform>:<flavor>"]` для всех 5 платформ × 2 флейворов (`$FLUTTER build <platform> --debug [--no-codesign|--dart-define-from-file=config/<flavor>.json]`). В скелете все сборки `--debug`, secrets-decrypt-таски нет (release/упаковка = FUTURE, §11a).

> **Конвенция format-split (рекомендация).** Удобно держать мутирующий `format` и неразрушающий `format-check` (для CI) раздельно; текущий `Makefile` имеет один мутирующий `format`, CI делает свой `dart format -l 140 --set-exit-if-changed` (см. Шаг 13).

**Команды.**

```bash
make deps
make generate
make gate
```

**КОНТРОЛЬНАЯ ТОЧКА 11 — оркестрация запускается**
- [ ] `make generate` завершается: pub get + build_runner (один прогон), код 0.
- [ ] `make format` форматирует `lib test` на 140 колонок, не трогая генерируемые (исключены через `analysis_options.yaml`).
- [ ] `make gate` (`generate format analyze test`) проходит end-to-end.
- [ ] `mise run build:android:stage` запускается (debug-сборка через `--dart-define-from-file=config/stage.json`).

---

## Шаг 12 — Test bootstrap + smoke-тест

**Действие.** Добавить глобальный test-bootstrap (мокнутый GetIt + `Environment.test`) и хотя бы один тест, чтобы CI было что гонять.

**Файлы** (см. `10-code-templates.md` → «Test bootstrap»; раскладка `test/` — **глубокое зеркало** `lib/`):
- *(Канон, aspirational — в скелете ещё нет)* `test/flutter_test_config.dart` — `testExecutable`, вызывающий `TestsUtils.initializeMock()` в `setUpAll`; `test/utils/tests_utils.dart` — сбрасывает GetIt, регистрирует mock `PackageInfo`, вызывает `configureDependencies(Environment.test)`, `allowReassignment = true`, `allReady()`, регистрирует core-mock репозитория (`@GenerateMocks([ItemRepository])`). Это целевой общий test-bootstrap (та же форма в `02` §10 и `08` §10).
- `test/presentation/pages/item_list_page/item_list_bloc_test.dart` — `bloc_test` smoke (`Initialize → Initialized`).
- `test/data/mapper/item/item_mapper_test.dart` — раунд-трип маппера `ItemEntity ↔ ItemModel`.
- `test/data/local/item/item_dao_test.dart` — тест per-ID DAO (Sembast memory).

> **Code-divergence (скелет).** Общего test-bootstrap (`flutter_test_config.dart` / `test/utils/`) в репозитории ещё **нет** — три реальных теста бутстрапятся **inline**: `setUpAll(() async => configureDependencies(Environment.test))` + `tearDownAll(() async => getIt.reset())`, без `TestsUtils`/`@GenerateMocks`/mock `PackageInfo`. Общий `TestsUtils` заводится с первым тестом, которому нужны моки.

**Команды.**

```bash
make generate   # (когда заведён общий TestsUtils с @GenerateMocks) сгенерировать моки
make test
```

**КОНТРОЛЬНАЯ ТОЧКА 12 — тесты проходят**
- [ ] `make test` зелёный (в скелете три теста бутстрапятся inline через `configureDependencies(Environment.test)` + `getIt.reset()`; общий `TestsUtils`/моки — aspirational, см. выше).
- [ ] Smoke-тест `ItemListBloc` утверждает переход `Initialize → Initialized` (bare-имена).
- [ ] Раунд-трип маппера `ItemEntity ↔ ItemModel` без потерь.

---

## Шаг 13 — CI-воркфлоу

**Действие.** Добавить GitHub Actions, зеркалящие локальный пайплайн. Никаких Rust/FFI-шагов. NOX — **standalone**-репозиторий, поэтому два собственных workflow (без монорепо-detection/reusable-workflow).

**Файлы** (см. `10-code-templates.md` → «CI» и `09-build-and-secrets-infra.md` §8):
- `.github/workflows/ci.yml` — на push/PR в `develop`/`master` (path-фильтр `lib/**`, `test/**`, `pubspec.*`, `analysis_options.yaml`, `build.yaml`): установка Flutter 3.44.1 (кэш pub-cache); `flutter pub get`; один прогон `build_runner build --delete-conflicting-outputs`; format-check на 140 (`dart format -l 140 --set-exit-if-changed` по `git ls-files lib test`, генерируемые/`docs/` исключены); `flutter analyze`; `flutter test`.
- `.github/workflows/compile-check.yml` — **5 per-platform** debug smoke-джобов (`compile-android`, `compile-ios`, `compile-macos`, `compile-windows`, `compile-linux`; Linux ставит `ninja-build libgtk-3-dev`) для **обоих флейворов** (`stage`/`prod`); Win/Linux — compile-only (launch — отслеживаемый follow-up). Никаких Rust toolchain / cargo / `frb_*` шагов.

**Команды.**

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
fvm flutter test
```

**КОНТРОЛЬНАЯ ТОЧКА 13 — локальное зеркало CI зелёное**
- [ ] `ci.yml` ссылается на Flutter 3.44.1: один прогон build_runner, format-check@140, analyze, test.
- [ ] `compile-check.yml` — 5 per-platform джобов (android/ios/macos/windows/linux) для обоих флейворов; Win/Linux compile-only.
- [ ] Никаких Rust/FFI/`frb_*` шагов.
- [ ] Полная локальная CI-последовательность (`make gate`) зелёная.

---

## Шаг 14 — Секреты + флейворные сборки (5 платформ)

**Действие.** Подключить SOPS+age+mise для секретов и флейворные сборки (Android/iOS + три десктопа) с `--dart-define-from-file`. Флейворы изолированы на компиляции (`AppFlavorType{prod,stage}`); рантайм-ветвления по флейвору нет.

> **Состояние секретов.** `.sops.yaml` + `.mise.toml` существуют; на сегодня **secrets-тасков ноль** (age-ключа в `.mise.toml` нет, `secrets:decrypt` отсутствует). Ниже — конвенция целиком (SOPS+age+mise), но в скелете ещё ничего не подключено. Флейвор инжектится единообразно из закоммиченного `config/<flavor>.json` (`config/stage.json` / `config/prod.json`) на всех пяти платформах.

**Файлы** (см. `09-build-and-secrets-infra.md` и `10-code-templates.md` → «Secrets / Flavors»):
- `.mise.toml`, `.sops.yaml`, `secrets/{stage,prod}.enc.yaml` — per-project шифрованные секреты по флейворам (age-пара проекта, локальный SOPS-конфиг).
- `config/stage.json`, `config/prod.json` — закоммиченные `--dart-define-from-file` JSON'ы на флейвор (несут `app.flavor` → `String.fromEnvironment`). Нативный `--flavor` не используется — единообразный `--dart-define` на всех платформах.
- `android/app/build.gradle.kts` — `applicationId` `com.cyphernetlabs.noxapp` (suffix `.stage`). **Native-уровневое разведение флейворов (отдельный stage applicationId/подпись) отложено** до реальной per-flavor native-нужды (skeleton carve-out, §6/§7).
- iOS — bundle id `com.cyphernetlabs.noxapp[.stage]` (native-флейворы отложены аналогично).
- `.gitignore` исключает расшифрованные артефакты (нативные конфиги, keystores).
- Версионирование — CalVer + shifted-epoch (`YY.M.D+EPOCH`, без ведущих нулей), см. `09-build-and-secrets-infra.md`.

> **Десктоп (macOS/Windows/Linux): выбор флейвора и упаковка.** На десктопе нативного механизма `--flavor` нет — флейвор выбирается **только** через `--dart-define-from-file=config/<flavor>.json` (тот же `app.flavor` → `String.fromEnvironment`, что и на мобайле). macOS bundle id остаётся `com.cyphernetlabs.noxapp` (только `prod`, без `.stage`-суффикса на native-уровне); Windows — отображаемое имя `NOX` + закоммиченный GUID; Linux — application-id `com.cyphernetlabs.noxapp`, имя `NOX`. Десктопная упаковка и подпись (DMG/MSIX/AppImage и т.п.) — **FUTURE**, в скелет не входят (см. `09-build-and-secrets-infra.md` §11a).

### Матрица десктопных fallback'ов (desktop fallback matrix)

Скелет компилируется на всех 5 таргетах, но ряд мобильных возможностей на десктопе ведёт себя иначе. Для Feature-001 это фиксируется **прозой** — кода для этих fallback'ов в скелете нет (FR-013). Правило: no-op/disabled-заглушка вводится с **первым десктопным потребителем** подсистемы, не раньше.

| Возможность | Windows | Linux | macOS |
|---|---|---|---|
| Push | no-op | no-op | no-op |
| Deep-links | placeholder | placeholder | native-capable |
| Secure-storage | placeholder | placeholder | native-capable |
| Flavor-secrets | disabled | disabled | disabled |

> **skeleton: проза-only, кода нет (FR-013).** Матрица описывает целевое поведение; реализация fallback'ов — за пределами скелета и подключается, когда соответствующая возможность станет реальной фичей.

**Команды.**

```bash
# Проверить флейворную сборку обоих (пример — Android):
mise run build:android:stage
mise run build:android:prod
# Десктоп — через Makefile-обёртки, напр.:
make build-macos-stage
```

**КОНТРОЛЬНАЯ ТОЧКА 14 — флейворные сборки**
- [ ] (Когда секреты подключены) расшифровка работает; расшифрованные артефакты в `.gitignore`.
- [ ] `app.flavor` доходит до `AppFlavor.getFlavor()` через `--dart-define-from-file=config/<flavor>.json`.
- [ ] Сборка обоих флейворов (`stage`/`prod`) проходит; `applicationId`/bundle = `com.cyphernetlabs.noxapp[.stage]`.

---

## Шаг 15 — Governance (CLAUDE.md + память)

**Действие.** Завести проектный `CLAUDE.md` и (опц.) память агента из скелета `08-conventions-and-constitution.md`. NOX — standalone-репозиторий с собственным корневым `CLAUDE.md`.

**Файлы** (см. `08-conventions-and-constitution.md` и `10-code-templates.md` → «Governance»):
- `CLAUDE.md` (проектный, в корне репозитория) — золотые правила, нейминг, HARD RULE форматирования на 140, инварианты single-package / Freezed-BLoC / single `$initGetIt` DI / offset-пагинация по умолчанию (`defaultPage = 1`) / light+dark тема / обязательный `LogRepository`, заметка о ведении `entity_converter.dart`. Архитектурный свод блюпринта — в `docs/blueprints/mobile/`; не путать с реальной Spec-Kit-конституцией NOX (`.specify/memory/constitution.md`, v1.1.0, пять принципов).
- `.claude/memory/MEMORY.md` — индекс памяти агента, если используете персистентную память.

**КОНТРОЛЬНАЯ ТОЧКА 15**
- [ ] `CLAUDE.md` фиксирует: single-package, Freezed-BLoC, offset-пагинация по умолчанию (`defaultPage = 1`), light+dark тема, обязательный `LogRepository`, форматирование 140.
- [ ] `.claude/memory/MEMORY.md` (если используется) индексирует проектные правила.

---

## Шаг 16 — Финальный E2E-гейт

**Действие.** Прогнать весь пайплайн из чистого состояния и подтвердить, что скелет плюс срез `Item` полностью работоспособны. Это шлюз перед объявлением скаффолда готовым. Дневной справочник команд — `12-dev-commands.md`.

**Команды.**

```bash
make generate                       # clean-ish: pub get + build_runner (один прогон)
make format                         # формат lib test на 140
make analyze                        # ноль ошибок
make test                           # все тесты зелёные
mise run build:android:stage        # stage собирается
mise run build:android:prod         # prod собирается
# (опц.) десктоп: make build-macos-stage / mise run build:windows:stage / build:linux:stage
```

**КОНТРОЛЬНАЯ ТОЧКА 16 — финальный гейт**
- [ ] `make gate` проходит end-to-end (один прогон build_runner).
- [ ] `fvm flutter analyze` чистый по всему пакету.
- [ ] Все тесты проходят.
- [ ] Обе флейворные сборки (`stage`/`prod`) компилируются; страница `Item` достижима из `AppRoot` (через `AppShell`), пагинация и pull-to-refresh работают.
- [ ] Обе флейворные debug-сборки компилируются на всех 5 таргетах (Win/Linux — compile-only).
- [ ] Нигде нет crypto / wallet / Rust / FFI / IPC / multi-window артефактов; нет трёх пакетов / path-зависимостей / цикла `domain↔data`.

---

## Частые ошибки (Common pitfalls)

- **Забыли зарегистрировать entity в `EntityConverter`** → рантайм `ArgumentError('No converter found for type ...')`. Добавляйте в ОБА — `fromJson` И `toJson`.
- **Положили JSON на доменную модель** → доменные модели только `@freezed` без JSON (`.freezed.dart`, никогда `.g.dart`); JSON живёт на entity.
- **`fromJson` на BLoC-типе** → BLoC State/Event только `.freezed.dart`, никогда `.g.dart`; никакого `@JsonSerializable`.
- **Форматирование всего репозитория как шаг задачи** → огромные диффы. Форматируйте только изменённые файлы на 140.
- **Side-effects в state BLoC** → навигация/снекбары идут через `PublishSubject`-стримы, не через поля state.
- **Cache-first для пагинируемых/one-shot эндпоинтов** → они NETWORK-ONLY (без DAO/subject); страничный `getItems` не бэкается `BehaviorSubject`.
- **Рантайм-ветвление по флейвору** → флейвор только compile-time (`String.fromEnvironment('app.flavor')`); значения через `--dart-define-from-file`.
- **Сырой `print` в `lib/`** → используйте `LogRepository` (единый обязательный канал).
- **Использование `PagingController`** → запрещено; пагинация v5 stateless — `PagingState`-in-bloc + extension `PagingStateExt.applyPage` (см. `07-pagination.md`).
- **Три пакета / path-зависимости / `$initDomainGetIt`** → это один пакет; ровно один `$initGetIt` и один `configure_dependencies.config.dart`.
- **Навигируемая страница без BLoC** → каждая `*Page` с `routeName`/`route()` обязана иметь собственный BLoC, **даже статичная/logic-less** (минимальный trio `Initializing`/`Initialized` или value-BLoC как `AppRootBloc`, Принцип 5.1). BLoC-less допустим **только** для переиспользуемых (ненавигируемых) виджетов.

---

## Definition of Done (скаффолд готов, когда)

- [ ] `.fvmrc` пинит Flutter 3.44.1; `fvm flutter --version` подтверждает; `.fvm/` в `.gitignore`.
- [ ] Один пакет `nox_app`: слои — папки в одном `lib/`; один `pubspec.yaml`; `pub get` чистый; нет path-зависимостей/цикла.
- [ ] `build.yaml` и `analysis_options.yaml` на месте; analyze исключает все генерируемые файлы; длина строки 140.
- [ ] Полный скелет директорий (`lib/{data,domain,presentation,di,general,design,resource}`; `lib/resource` зарезервирован, пуст — `.gitkeep`).
- [ ] База домена компилируется: `RepositoryResult<T>` (success/error), `match<R>`, `BaseRepositoryException`-маркер + `enum RepositoryException`, `RepositoryConfig` — без JSON.
- [ ] База данных компилируется: `ResponseEntity`, `EntityConverter`, `BaseMapper` (4 type-параметра), `ApiClient` (Dio), `BaseRepositoryHelper` с **обязательным** `LogRepository` (без типизированной иерархии исключений — `DioException → RepositoryException.internal`, прочее → `unknown` внутри `execute<TD>()`), env-scoped `AppDatabase` (Dev/Prod=IO, Test=memory).
- [ ] Single-tier DI: один `$initGetIt` + один `configure_dependencies.config.dart` (минимальное тело `configureDependencies`); `AppFlavor` + `AppConfig`/`AppConfigRepository`; `main.dart` с `runZonedGuarded` → `configureDependencies(env)` → `getIt.allReady()` → `runApp(AppRoot)` (ошибки логируются в `catch` через `LogRepository`, без BLoC-обсервера).
- [ ] Тема light+dark: `ThemeExtension<AppColors>`, `AppTheme.light()/dark()` (поверх сгенерированного хендоффа `nox_color_scheme`/`nox_text_theme`, не `fromSeed`), `context.appColors`, `themeMode` из `AppRootBloc`, четыре класса токенов (Spacing/TextStyle/Overlay/Images; `AppColorsTokens` нет) + flutter_gen, `flutter_screenutil` 360×779.
- [ ] База presentation: `BaseBloc`, `BaseStatePage`, `AppRootBloc` (Freezed), `AppRoot`, адаптивная `AppShell` (width-driven `NavigationBar`↔`NavigationRail` на 840dp; 2 destination'ы; центральный docked `+` FAB), `main.dart`. (Три общих state-виджета `AppProgressWidget`/`AppErrorWidget`/`AppEmptyContentWidget` и `AlertDialogHelper` — aspirational; в скелете нет, `ItemListPage` рендерит состояния inline.)
- [ ] Инвариант 3a: каждая навигируемая `*Page` с `routeName`/`route()` имеет собственный BLoC (logic-less — минимальный BLoC); переиспользуемые `widgets/` — без. (Скелет: `AppShell` и плейсхолдер-страницы — допустимые упрощения.)
- [ ] Полный срез `Item` end-to-end с пагинацией: модель+конфиг (`defaultPage = 1`)+контракт (домен, без JSON); entity (`ItemEntity` + `ItemsEntity{items,page,page_size,total}`)+mapper+api (`ResponseEntity<ItemsEntity>`)+impl (данные, NETWORK-ONLY список); Freezed-BLoC (`Initialize` + `LoadItems({reset})`, bare-имена) с `PagingState` + `PagedListView` v5 + pull-to-refresh; DI (`as: ItemRepository`, `[dev,prod,test]`).
- [ ] Оркестрация: `Makefile` (`deps`/`generate`/`format`/`analyze`/`test`/`gate` + `build-*-stage`) + `.mise.toml` (`build:<platform>:<flavor>`). Скриптов `script_*.sh` нет.
- [ ] Тесты: smoke `ItemListBloc` (`Initialize → Initialized`) + раунд-трип маппера + per-ID DAO; раскладка `test/` — глубокое зеркало `lib/`; бутстрап inline (`configureDependencies(Environment.test)` + `getIt.reset()`), общий `flutter_test_config.dart`/`tests_utils.dart` — aspirational.
- [ ] CI: `ci.yml` зеркалит локальный пайплайн (3.44.1, один build_runner, format@140, analyze, test) + `compile-check.yml` (5 per-platform джобов); без Rust/FFI/IPC/multi-window.
- [ ] Секреты SOPS+age+mise (конвенция; в скелете secrets-тасков ещё нет); флейворные сборки `stage`/`prod` (`com.cyphernetlabs.noxapp[.stage]`) через `config/<flavor>.json`; версионирование CalVer + shifted-epoch.
- [ ] `CLAUDE.md` + (опц.) `.claude/memory/MEMORY.md` фиксируют инварианты.
- [ ] `fvm flutter analyze` чистый, все тесты проходят, обе флейворные debug-сборки компилируются на всех 5 таргетах (Win/Linux — compile-only), страница `Item` достижима с рабочей пагинацией.

# 11 — План скаффолдинга

> **Назначение:** Главный пошаговый плейбук, по которому собирается приложение NOX с нуля — от пустого `lib/` до компилируемого скелета плюс один рабочий вертикальный срез (фича `Item`, end-to-end, с пагинацией). Каждый шаг закрыт контрольной точкой (VERIFICATION CHECKPOINT) и ссылается на конкретный шаблон в `10-code-templates.md`. **Когда читать:** Когда вы готовы скаффолдить проект и нужна точная упорядоченная последовательность действий, файлов и команд с проверкой после каждого крупного этапа. **Связанные документы:** `10-code-templates.md` (точные байты каждого файла), `00-architecture-overview.md` (общая картина и граф зависимостей), `01-stack-and-tooling.md` (стек/инструменты), `02-dependency-injection.md` (DI), `03-domain-layer.md`, `04-data-layer.md`, `05-presentation-layer.md`, `06-theming.md`, `07-pagination.md`, `08-conventions-and-constitution.md`, `09-build-and-secrets-infra.md`, `12-dev-commands.md`.

---

## Как пользоваться этим плейбуком

- Шаги **строго упорядочены**. Не забегайте вперёд — каждый шаг опирается на артефакты предыдущего. Сломанный фундамент множит ошибки.
- Каждый файл/конфиг, который вы создаёте, определён дословно в **`10-code-templates.md`**. Этот плейбук говорит, *какой* шаблон применить, *куда* и *когда*; точные байты — в файле шаблонов. **Никогда не выдумывайте и не перефразируйте шаблоны кода** — берите их verbatim, адаптируя только имена/пути.
- После каждого крупного шага идёт **КОНТРОЛЬНАЯ ТОЧКА**. Не переходите дальше, пока она не пройдена. Если не проходит — чините до перехода.
- Сквозной рабочий пример — фича **`Item`** (`ItemModel` / `ItemEntity` / `ItemRepository` / `ItemRepositoryImpl` / `ItemMapper` / `ItemDao` / `ItemListPage` / `ItemListBloc` / `ItemListEvent` / `ItemListState` / `GetItemsConfig`). Для пустых заготовок используйте плейсхолдеры `<Feature>` / `<feature>` / `<Model>`.
- **Первая РЕАЛЬНАЯ фича**, которую будете строить после скелета, — **список чатов** (открытые общие пространства): это server-owned, network-only пагинируемый список, поэтому carve-out «пагинируемые server-owned списки — NETWORK-ONLY» применяется к нему напрямую. По умолчанию используем offset-флейвор пагинации (`page` + `page_size` + `count`); cursor — задокументированная альтернатива (см. `07-pagination.md`). Конкретный контракт пагинации списка чатов финализируется позже с бэкендом NOX. Скелет на `Item` спроектирован так, чтобы список чатов лёг в него один-в-один (см. §10 и `07-pagination.md`).

### Соглашения по именам (зафиксированы для всего блюпринта)

| Сущность | Значение |
|---|---|
| Имя Dart-пакета | `nox_app` (все импорты — `package:nox_app/...`) |
| Отображаемое имя | NOX |
| Android `applicationId` / iOS bundle | `com.cyphernetlabs.noxapp` (stage: `com.cyphernetlabs.noxapp.stage`) |
| Флейворы | `stage`, `prod` |
| Flutter / Dart | Flutter 3.44.1 через FVM; Dart sdk `>=3.12.0 <4.0.0` |
| Длина строки форматтера | 140 |

### Ключевое архитектурное правило (single-package)

Этот скелет — **ОДИН Dart-пакет** (`nox_app`). Слои — это **папки** в одном `lib/`: `lib/data`, `lib/domain`, `lib/presentation`, плюс `lib/di`, `lib/general`, `lib/design`, `lib/resource`. **ОДИН** `pubspec.yaml`, **ОДИН** прогон `build_runner`, **ОДИН** `configureDependencies(String env)` с одним `@InjectableInit(initializerName: r'$initGetIt')` и одним сгенерированным `configure_dependencies.config.dart`. Никаких трёх пакетов, path-зависимостей, цикла `domain↔data`. Пути вида `domain/lib/src/...` или `data/lib/src/...` в этом блюпринте не используются — каноническая форма всегда `lib/domain/...` / `lib/data/...`.

### Одноразовое требование: инструменты на PATH

```bash
# FVM нужен каждому скрипту скелета.
brew install fvm   # macOS; для других платформ см. https://fvm.app
# (Опционально, для прод-инфры секретов и флейворных сборок) mise, sops, age.
```

---

## Шаг 1 — Закрепить Flutter SDK через FVM

**Действие.** Создать корень проекта `lib/`, закрепить точную версию SDK, чтобы каждый разработчик и CI-раннер использовали один Flutter. Все скрипты скелета вызывают `fvm flutter` / `fvm dart` — никогда захардкоженный путь к SDK.

**Файлы** (см. `10-code-templates.md` → «FVM»):
- `.fvmrc` — пинит `{"flutter": "3.44.1"}` (коммитится).

**Команды.**

```bash
# Из корня lib/:
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
fvm flutter create --org com.cyphernetlabs --project-name nox_app .

# Заменяем сгенерированный pubspec.yaml единым манифестом из шаблонов, затем:
fvm flutter pub get
```

**Ключевые зависимости (объединённый набор одного пакета).** Архитектурное ядро: `injectable`, `get_it`, `flutter_bloc`, `bloc_test`, `freezed_annotation` + `freezed`, `json_annotation` + `json_serializable`, `rxdart`, `dio`, `infinite_scroll_pagination: ^5.1.1`, `flutter_screenutil`, `intl`, `collection`, `uuid`. Persistence/инфра: `sembast`, `path_provider`, `shared_preferences`, `flutter_secure_storage`, `package_info_plus`, `logger`. Dev: `build_runner`, `injectable_generator`, `freezed`, `json_serializable`, `flutter_lints`, `mockito`.

**Не тянем (вне области этого блюпринта):** `ffi`, `flutter_rust_bridge`, `desktop_multi_window`, `yaru`, `flex_color_picker`, `decimal`, `custom_adaptive_scaffold`, любые crypto/wallet/RGB/FFI/multi-window зависимости.

**КОНТРОЛЬНАЯ ТОЧКА 2 — pub get clean**
- [ ] `fvm flutter pub get` проходит без конфликтов версий.
- [ ] `pubspec.lock` создан в корне.
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
├── lib/
│   ├── data/
│   │   ├── di/
│   │   ├── entity/
│   │   ├── exception/
│   │   ├── local/
│   │   ├── mapper/
│   │   ├── remote/
│   │   │   ├── api/
│   │   │   └── request_builder/base/
│   │   └── repository/
│   ├── domain/
│   │   ├── exception/
│   │   ├── models/
│   │   └── repository/base/
│   ├── presentation/
│   │   ├── app/bloc/
│   │   ├── base/
│   │   ├── pages/base/
│   │   ├── widgets/
│   │   ├── helpers/
│   │   └── extension/
│   ├── di/
│   ├── general/formatters/
│   ├── design/theme/
│   ├── resource/
│   └── main.dart
├── test/utils/
└── .github/workflows/
```

**Команды.**

```bash
mkdir -p \
  lib/data/di lib/data/entity lib/data/exception lib/data/local lib/data/mapper \
  lib/data/remote/api lib/data/remote/request_builder/base lib/data/repository \
  lib/domain/exception lib/domain/models lib/domain/repository/base \
  lib/presentation/app/bloc lib/presentation/base lib/presentation/pages/base lib/presentation/widgets lib/presentation/helpers lib/presentation/extension \
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

**Действие.** Собрать переиспользуемый фундамент `lib/data/`: унифицированный конверт ответа бэкенда NOX, реестр конвертеров entity, базовый маппер, реактивный Sembast DAO + env-scoped `AppDatabase`, Dio-клиент, типизированные исключения и `BaseRepositoryHelper` с **обязательным** `LogRepository`.

**Файлы** (см. `10-code-templates.md` → «Data base»; авторитетные шаблоны самого data-слоя — в `04-data-layer.md`):
- `lib/data/entity/base/response_entity.dart` — `ResponseEntity<T>`, разбор унифицированного конверта `{data, timestamp, trace_id, meta}` *(пример — бэкенд/протокол NOX ещё не выбран; форму конверта заменить на реальный контракт)*.
- `lib/data/entity/base/entity_converter.dart` — ручной реестр `EntityConverter<E>` (начинайте с пустого диспетчера, добавляйте entity по мере создания). Entity — **только базовые типы**: enum как `.name` String, DateTime как ISO-8601 String, вся коэрция в маппере.
- `lib/data/mapper/base/base_mapper.dart` — `abstract class BaseMapper<E, M>` (`toModel` / `toEntity` + list-хелперы).
- `lib/data/exception/dao_exception.dart` — `class DaoException implements Exception`.
- `lib/data/exception/api_exception.dart` — `enum ApiException` с `.map` в доменный `RepositoryException`.
- `lib/data/exception/base_repository_helper.dart` — `mixin BaseRepositoryHelper` с защищённым `execute<T>()`, который **всегда** логирует через `LogRepository` (единый канал, никаких сырых `print`).
- `lib/data/local/log_repository.dart` (+ impl) — **обязательный** единый канал логирования.
- `lib/data/local/app_database.dart` — `abstract class AppDatabase` + env-scoped провайдеры через `@LazySingleton(as: AppDatabase, env: [...])`: `AppDatabaseDev` / `AppDatabaseProd` (Sembast IO через `path_provider`) и `AppDatabaseTest` (Sembast memory).
- `lib/data/remote/api/base/api_client.dart` — Dio-обёртка `ApiClient`.
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

**Действие.** Свести единый DI-бутстрап. ОДИН `configureDependencies(String env)` с ОДНИМ `@InjectableInit(initializerName: r'$initGetIt')` и ОДНИМ сгенерированным `configure_dependencies.config.dart`. Плюс компиляционная изоляция флейворов, `AppConfigModel`, `global_aliases` и `main.dart`.

**Файлы** (см. `10-code-templates.md` → «DI» и «main.dart»):
- `lib/di/configure_dependencies.dart` — `@InjectableInit(initializerName: r'$initGetIt')`, единственная точка входа DI; env-scoped регистрация `AppDatabase` (через провайдеры `AppDatabaseDev/Prod/Test`) + async pre-resolve `PackageInfo`.
- `lib/di/global_aliases.dart` — удобные геттеры (стартовый набор: `logRepository`, `configRepository`; feature-геттеры добавятся на Шаге 10).
- `lib/domain/model/app_config/app_flavor_type.dart` + `lib/domain/model/app_config/app_flavor.dart` — `enum AppFlavorType { prod, stage }` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')`; маппинг флейвор→env: `prod → Environment.prod`, `stage → Environment.dev`.
- `lib/domain/model/app_config/app_config_model.dart` (+ impl) — держит конфиг флейвора (apiUrl, apiSignatureKey и пр. — *примерные поля; бэкенд/протокол NOX ещё не выбран, набор полей конфига заменить на реальный контракт*; см. `02-dependency-injection.md` §7.3).
- `lib/main.dart` — оборачивает в `runZonedGuarded` → `WidgetsFlutterBinding.ensureInitialized()` → определить flavor+env из `AppFlavor.getFlavor()` → `await configureDependencies(env)` → `await getIt.allReady()` → `await getIt<AppConfigRepository>().initialize(flavorType: flavor)` → `runApp(const AppRoot())`. Ошибки логируются в `catch` через `LogRepository` под `isRegistered`-guard — отдельного BLoC-обсервера нет. Канонический `main.dart` — `02-dependency-injection.md` §10.

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

**Действие.** Добавить фундамент темы: `ThemeExtension<AppColors>`, `AppTheme.light()`/`.dark()`, четыре класса токенов, `flutter_screenutil` (дизайн-размер 360×779), константы, утилиты платформы, форматтеры, общие виджеты и `AlertDialogHelper`.

**Файлы** (см. `10-code-templates.md` → «Theming» и `06-theming.md`):
- `lib/design/theme/app_colors.dart` — `AppColors extends ThemeExtension<AppColors>` с `LightAppColors` / `DarkAppColors` + extension `context.appColors`. Палитра — конкретные значения темы (см. `06-theming.md`).
- `lib/design/app_colors_tokens.dart`, `lib/design/app_spacing_tokens.dart`, `lib/design/app_text_style_tokens.dart`, `lib/design/app_overlay_style_tokens.dart` — четыре класса токенов (responsive через `flutter_screenutil`).
- `lib/resource/app_theme.dart` — `AppTheme.light()` / `AppTheme.dark()`, композирует Material-базу + `extensions: [LightAppColors()/DarkAppColors()]`. `themeMode` поставляется `AppRootBloc`.
- `lib/general/constants.dart` — `final class Constants` (приватный ctor, константы, regex'ы, `defaultNavTransitionTimeMilliseconds`).
- `lib/general/platform_utils.dart` — `PlatformUtils` (desktop/mobile).
- `lib/general/text_constants.dart` — `TextConstants` (имя приложения «NOX» + общие строки UI).
- `lib/general/formatters/date_formatter.dart`, `lib/general/formatters/value_formatter.dart` — статические форматтеры на `intl`.
- `lib/presentation/helpers/alert_dialog_helper.dart` — `AlertDialogHelper`.
- `lib/presentation/widgets/app_progress_widget.dart`, `app_error_widget.dart`, `app_empty_content_widget.dart` — три общих виджета.

**Команды.**

```bash
fvm flutter analyze lib/design lib/resource lib/general lib/presentation/widgets
```

**КОНТРОЛЬНАЯ ТОЧКА 8 — analyze clean (theming)**
- [ ] `fvm flutter analyze lib/design lib/resource lib/general lib/presentation/widgets` без ошибок.
- [ ] `AppTheme.light()` / `AppTheme.dark()` компилируются и регистрируют `AppColors` в `extensions`.
- [ ] Четыре класса токенов (`AppColorsTokens`, `AppSpacingTokens`, `AppTextStyleTokens`, `AppOverlayStyleTokens`) экспонируют свои шкалы.
- [ ] `context.appColors` резолвится из обеих тем (light/dark).

---

## Шаг 9 — База presentation (оболочка + AppRootBloc + Freezed-BLoC-конвенции)

**Действие.** Собрать фундамент presentation: `BaseBloc<E,S>`, `BaseStatePage<T>`, оболочка приложения `AppRoot` с `AppRootBloc` (тема + глобальное состояние, `themeMode`). Здесь же фиксируется **Freezed-BLoC-конвенция** для всех будущих BLoC. Отдельного BLoC-обсервера нет: логирование ошибок уже происходит на уровне репозиториев через обязательный `LogRepository` (`BaseRepositoryHelper.execute` всегда логирует), а ошибки BLoC-обработчиков оборачиваются `BaseBloc.executeLogic`.

**Файлы** (см. `10-code-templates.md` → «Presentation base» и `05-presentation-layer.md`):
- `lib/presentation/base/base_bloc.dart` — тонкий `BaseBloc<E,S>` с `executeLogic(..., onError: ...)` (try/catch-обёртка); все page-BLoC наследуют его (`extends BaseBloc<…>`), а не `Bloc<…>` напрямую.
- `lib/presentation/pages/base/base_state_page.dart` — `abstract class BaseStatePage<T extends StatefulWidget> extends State<T>` (scaffoldKey, drawer-хелперы, `buildAppBar()`).
- `lib/presentation/app/bloc/app_root_bloc.dart` + `app_root_state.dart` + `app_root_event.dart` — `AppRootBloc` на тонком `BaseBloc<E,S>`; `@freezed` Event sealed union; `AppRootState` — single-variant `@freezed abstract class` с полем `themeMode` (`const factory AppRootState({required ThemeMode themeMode}) = _AppRootState;`), без подсостояний `Initializing` / `Initialized` / `Error`. `MaterialApp` читает `state.themeMode`.
- `lib/presentation/app/app_root.dart` — корневой `MaterialApp` (`theme`/`darkTheme` из `AppTheme`, `themeMode` из `AppRootBloc`, `navigatorKey`, `onGenerateRoute`); обёрнут в `ScreenUtilInit(designSize: Constants.designSize` = `Size(360, 779)`, `minTextAdapt: true)` + двойной `MediaQuery` (`TextScaler.noScaling` / `TextScaler.linear(1.0)`) — нейтрализация OS-масштаба шрифта (UI-скейл, см. `06-theming.md` §3.2); `home` → `ItemListPage` (после Шага 10).

> **Freezed-BLoC-конвенция (фиксируется здесь, применяется ко всем BLoC).** `@freezed` sealed union для State и Event; тонкий `BaseBloc<E,S>` с `executeLogic` (try/catch); производная/вычисляемая логика — в **extension-геттерах** (не в `@freezed`-теле); переходы через `copyWith`; `sealed` для multi-variant union'ов, `abstract` для single-variant value-объектов; **никакого `fromJson` на BLoC-типах** (только `*.freezed.dart`, никогда `*.g.dart`). Это **жёсткое правило** блюпринта: State/Event всегда `@freezed`, без руками-написанных sealed+Equatable BLoC и без Equatable на стейтах — см. `05-presentation-layer.md` и `08-conventions-and-constitution.md`. Канонические имена подсостояний для **multi-variant** стейтов страниц (например `ItemListState`) — `Initializing` / `Initialized` / `Error`, как `const factory`. **Single-variant** value-объекты (например `AppRootState` с `themeMode`) — `@freezed abstract class` с одним конструктором, без трио.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze lib/presentation lib/main.dart
```

**КОНТРОЛЬНАЯ ТОЧКА 9 — analyze clean (presentation base)**
- [ ] `app_root_state.freezed.dart` / `app_root_event.freezed.dart` сгенерированы (и **нет** `.g.dart` для BLoC-типов).
- [ ] `fvm flutter analyze lib/presentation lib/main.dart` без ошибок (ссылка на `ItemListPage` из `AppRoot` резолвится после Шага 10 — временно роутите на заглушку, если строите presentation-базу первой).
- [ ] `BaseBloc`, `BaseStatePage`, `AppRootBloc`, `AppRoot`, `main.dart` компилируются.

---

## Шаг 10 — Первый вертикальный срез `Item` (с пагинацией, end-to-end)

**Действие.** Реализовать одну фичу сверху-вниз, чтобы доказать совместную работу всех слоёв, DI и пагинации. Это критерий приёмки «скелет работает». Срез включает **offset-пагинацию** (дефолтный флейвор: `PageMetadata{int? nextPage, int total}`) через `infinite_scroll_pagination ^5.1.1` (v5 stateless `PagingState`-in-bloc), pull-to-refresh. Порядок сборки: домен → данные → DI → presentation.

> Полный контракт пагинации — в `07-pagination.md`. Репозиторий возвращает `RepositoryResult<(List<T>, PageMetadata)>` (конверт `RepositoryResult` **сохраняем**, не используем сырой `Future`+try/catch); `result.exception` пробрасывается в `pagingState.error` для error-builder'ов v5.

### 10a — Домен: модель, конфиг, контракт

**Файлы** (см. `10-code-templates.md` → «Item slice: domain»):
- `lib/domain/models/item/item_model.dart` — `@freezed ItemModel` (поля `id:String`, `name:String`, `description:String?`, `status:ItemStatus`, `createdAt:DateTime`). **Без `fromJson`** (доменная модель — только `.freezed.dart`).
- `lib/domain/models/item/item_status.dart` — `enum ItemStatus { active, archived, draft }`.
- `lib/domain/repository/item/item_repository.dart` — `abstract class ItemRepository`; методы возвращают `RepositoryResult<...>`; страничный метод — `Future<RepositoryResult<(List<ItemModel>, PageMetadata)>> getItems({required GetItemsConfig config})`.
- `lib/domain/repository/item/get_items_config.dart` — единственный `@freezed abstract class GetItemsConfig implements RepositoryConfig` с фабриками `firstPage({String? search})` / `nextPage({required int page, String? search})` и константами `static const int pageSize = 20;` / `static const int defaultPage = 1;` (1-based). Никакого sealed-union `ItemRepositoryConfigs.list`-редиректа; конструировать как `GetItemsConfig.firstPage()` / `GetItemsConfig.nextPage(page: …)`.

### 10b — Данные: entity, api, dao, mapper, impl

**Файлы** (см. `10-code-templates.md` → «Item slice: data»; remote/REST — `04-data-layer.md`):
- `lib/data/entity/item/item_entity.dart` — `@freezed ItemEntity`, **только базовые типы**: `id:String`, `name:String`, `description:String?`, `status:String` (имя enum), `createdAt:String` (ISO-8601) + `fromJson`. Зарегистрировать в `EntityConverter` (и в `fromJson`, и в `toJson`).
- `lib/data/mapper/item/item_mapper.dart` — `@lazySingleton ItemMapper extends BaseMapper<ItemEntity, domain.ItemModel>` (string↔enum, ISO-string↔DateTime; раунд-трип `ItemModel` без потерь).
- `lib/data/remote/request_builder/item/get_items_api_request_builder.dart` — `@lazySingleton GetItemsApiRequestBuilder` (offset-параметры `page`/`page_size`).
- `lib/data/remote/api/item/get_items_api.dart` — `@lazySingleton GetItemsApi` (возвращает список `ItemEntity` + `PageMetadata` из конверта; для среза допустим mock-body).
- `lib/data/repository/item/item_repository_impl.dart` — `@LazySingleton(as: domain.ItemRepository, env: [Environment.dev, Environment.prod, Environment.test])`, миксует `BaseRepositoryHelper`, оборачивает каждый метод в `execute<T>()`. **Страничный список — NETWORK-ONLY** (без DAO/subject — server-owned пагинация). Если у фичи есть и кэшируемая часть (watch одной сущности) — она бэкается `BehaviorSubject` и DAO; для `getItems` — нет.
- `lib/data/local/item_dao.dart` — `@lazySingleton ItemDao` (Sembast store, `watch()` через `onSnapshots`, CRUD, `db.transaction()`) — только если фиче нужен кэш отдельной сущности; для чистого страничного списка DAO не требуется.

### 10c — Freezed-BLoC (с PagingState)

**Файлы** (см. `10-code-templates.md` → «Item slice: presentation» и `07-pagination.md`):
- `lib/presentation/pages/item_list_page/bloc/item_list_state.dart` — `@freezed sealed class ItemListState`; держит `PagingState<String, ItemModel>` (ключ `K = String` = id элемента, one-item-per-page; offset отслеживается через `PageMetadata.nextPage` (int) в state, не через `K`); подсостояния `Initializing` / `Initialized` / `Error` как `const factory`. Производные геттеры — в extension.
- `lib/presentation/pages/item_list_page/bloc/item_list_event.dart` — `@freezed sealed class ItemListEvent` (`Initialize`, `FetchNextPage`, `RefreshList`, `SelectItem`, `DeleteItem`).
- `lib/presentation/pages/item_list_page/bloc/item_list_bloc.dart` — `ItemListBloc extends BaseBloc<ItemListEvent, ItemListState>`; `getIt<domain.ItemRepository>()`; применяет страницу через переиспользуемый extension `PagingStateExt.applyPage`; `result.exception → pagingState.error`.

### 10d — Страница

**Файлы** (см. `10-code-templates.md` → «Item slice: presentation»):
- `lib/presentation/pages/item_list_page/item_list_page.dart` — `ItemListPage extends StatefulWidget` (статические `routeName` + `route()`); state наследует `BaseStatePage<ItemListPage>`; создаёт `ItemListBloc()..add(const ItemListEvent.initialize())` в `initState`, закрывает в `dispose`; `BlocProvider` + `BlocBuilder`; `PagedListView` (v5) + pull-to-refresh; рендерит `state` через `switch`/`map` с тремя общими виджетами (`AppProgressWidget`/`AppErrorWidget`/`AppEmptyContentWidget`).
- Завести `ItemListPage.route()` в роутинг `AppRoot` (как `home`/дефолтный маршрут на время сборки среза).

### 10e — DI-регистрация + алиасы

- Добавить `Item`-геттеры в `lib/di/global_aliases.dart` (`itemRepository`, `itemMapper`, `getItemsApi`, при наличии — `itemDao`).
- Убедиться, что `ItemRepositoryImpl` зарегистрирован `as: domain.ItemRepository` для `[dev, prod, test]`.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

**КОНТРОЛЬНАЯ ТОЧКА 10 — полный срез компилируется + analyze clean**
- [ ] build_runner завершился кодом 0 (`item_*.freezed.dart`, `item_entity.g.dart`, обновлён `configure_dependencies.config.dart`).
- [ ] `item_model.freezed.dart` есть, `item_model.g.dart` **нет** (доменная модель без JSON); `item_entity.g.dart` есть (entity — с JSON).
- [ ] `fvm flutter analyze` без ошибок.
- [ ] `ItemListPage` рендерит три состояния; `ItemListBloc` резолвит `getIt<domain.ItemRepository>()`, mapper/api резолвятся через DI.
- [ ] Пагинация работает: первая страница грузится, скролл подтягивает следующую через `FetchNextPage`, ошибка пробрасывается в error-builder, pull-to-refresh сбрасывает `PagingState`.
- [ ] Приложение собирается: `fvm flutter run --dart-define-from-file=...` (stage) показывает список `Item`.

---

## Шаг 11 — Tooling (Makefile / mise-задачи, скрипты)

**Действие.** Добавить скрипты/задачи, оркестрирующие кодоген, тесты, форматирование, версионирование. Все вызывают `fvm flutter` / `fvm dart`. Сделать исполняемыми.

**Файлы** (см. `10-code-templates.md` → «Scripts» / «Makefile» и `12-dev-commands.md`):
- `script_auto_generate.sh` — `fvm flutter clean`, затем `pub get` + `build_runner build --delete-conflicting-outputs` (один пакет — один прогон).
- `script_tests.sh` — прогон тестов с цветным выводом и ненулевым кодом при падении.
- `script_format_changed_files.sh` — форматирование изменённых Dart-файлов **`--line-length 140`** + `dart fix --apply --code=unused_import`; исключает генерируемые (`*.freezed.dart`, `*.g.dart`, `*.config.dart`, `*.mocks.dart`, `lib/design/gen/**`) и `build/`.
- `Makefile` / `mise`-задачи — обёртки над codegen/test/analyze/format/build (см. `09-build-and-secrets-infra.md`).

**Команды.**

```bash
chmod +x script_*.sh
bash -n script_auto_generate.sh script_tests.sh script_format_changed_files.sh
./script_auto_generate.sh
```

**КОНТРОЛЬНАЯ ТОЧКА 11 — скрипты запускаются**
- [ ] `bash -n script_*.sh` без синтаксических ошибок.
- [ ] `./script_auto_generate.sh` завершается: clean + pub get + build_runner (один прогон).
- [ ] `./script_format_changed_files.sh -a` форматирует in-scope файлы на 140 колонок, не трогая генерируемые.

---

## Шаг 12 — Test bootstrap + smoke-тест

**Действие.** Добавить глобальный test-bootstrap (мокнутый GetIt + `Environment.test`) и хотя бы один тест, чтобы CI было что гонять.

**Файлы** (см. `10-code-templates.md` → «Test bootstrap»):
- `test/flutter_test_config.dart` — `testExecutable`, вызывающий `TestsUtils.initializeMock()` в `setUpAll`.
- `test/utils/tests_utils.dart` — сбрасывает GetIt, регистрирует mock `PackageInfo`, вызывает `configureDependencies(Environment.test)`, `allowReassignment = true`, `allReady()`, регистрирует core-mock репозитория (`@GenerateMocks([ItemRepository])`).
- `test/item/item_list_bloc_test.dart` — `bloc_test` smoke (`Initialize → Initialized`).
- `test/data/item_mapper_test.dart` — раунд-трип маппера `ItemEntity ↔ ItemModel`.

**Команды.**

```bash
fvm dart run build_runner build --delete-conflicting-outputs   # сгенерировать моки @GenerateMocks
./script_tests.sh
```

**КОНТРОЛЬНАЯ ТОЧКА 12 — тесты проходят**
- [ ] `test/utils/tests_utils.mocks.dart` сгенерирован.
- [ ] `./script_tests.sh` зелёный.
- [ ] Smoke-тест `ItemListBloc` утверждает переход `Initialize → Initialized`.
- [ ] Раунд-трип маппера `ItemEntity ↔ ItemModel` без потерь.

---

## Шаг 13 — CI-воркфлоу

**Действие.** Добавить GitHub Actions, зеркалящие локальный пайплайн. Никаких Rust/FFI-шагов.

**Файлы** (см. `10-code-templates.md` → «CI» и `09-build-and-secrets-infra.md`):
- `.github/workflows/ci.yml` — на push/PR: `bash -n script_*.sh`; установка Flutter 3.44.1 (кэш pub-cache); `pub get`; один прогон `build_runner build`; проверка форматирования на 140 (исключая генерируемые); `flutter analyze`; `flutter test`.
- `.github/workflows/compile-check.yml` (опционально) — per-platform debug smoke-сборки **обоих флейворов** (`stage`/`prod`). Никаких Rust toolchain / cargo / `frb_*` шагов.

**Команды.**

```bash
for f in script_*.sh; do bash -n "$f"; done
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
fvm flutter test
```

**КОНТРОЛЬНАЯ ТОЧКА 13 — локальное зеркало CI зелёное**
- [ ] `ci.yml` ссылается на Flutter 3.44.1, один прогон build_runner, format@140, analyze, test.
- [ ] Никаких Rust/FFI/`frb_*` шагов.
- [ ] Полная локальная CI-последовательность зелёная.

---

## Шаг 14 — Секреты + флейворные нативные сборки

**Действие.** Подключить SOPS+age+mise для секретов и флейворные сборки Android/iOS с `dart-define-from-file`. Флейворы изолированы на компиляции (`AppFlavorType{prod,stage}`).

**Файлы** (см. `09-build-and-secrets-infra.md` и `10-code-templates.md` → «Secrets / Flavors»):
- `mise.toml`, `.sops.yaml`, `secrets/{stage,prod}.enc.yaml` — шифрованные секреты по флейворам.
- `android/app/build.gradle.kts` — flavor dimension, детект флейвора, выбор keystore, pre-build decrypt-хук; `applicationId` `com.cyphernetlabs.noxapp` (suffix `.stage`).
- iOS — schemes (`stage`/`prod`) + xcconfig-подстановка + bundle id `com.cyphernetlabs.noxapp[.stage]`.
- `dart-define-from-file` JSON'ы на флейвор (передают `app.flavor` → `String.fromEnvironment`).
- `.gitignore` исключает расшифрованные артефакты.
- Версионирование — CalVer + shifted-epoch (`YY.M.D+EPOCH`, без ведущих нулей), см. `09-build-and-secrets-infra.md`.

**Команды.**

```bash
# Проверить флейворную сборку обоих:
mise run build:android:stage
mise run build:android:prod
```

**КОНТРОЛЬНАЯ ТОЧКА 14 — флейворные сборки**
- [ ] Расшифровка секретов работает; расшифрованные артефакты в `.gitignore`.
- [ ] `app.flavor` доходит до `AppFlavor.getFlavor()` через `--dart-define-from-file`.
- [ ] Сборка обоих флейворов (`stage`/`prod`) проходит; `applicationId`/bundle = `com.cyphernetlabs.noxapp[.stage]`.

---

## Шаг 15 — Governance (CLAUDE.md + память)

**Действие.** Завести проектный `CLAUDE.md` и память агента из скелета `08-conventions-and-constitution.md`.

**Файлы** (см. `08-conventions-and-constitution.md` и `10-code-templates.md` → «Governance»):
- `CLAUDE.md` (скелет проекта `lib/`) — золотые правила, нейминг, HARD RULE форматирования на 140, single-package/Freezed-BLoC/pagination инварианты, заметка о ведении `entity_converter.dart`.
- `.claude/memory/MEMORY.md` — индекс памяти агента, если используете персистентную память.

**КОНТРОЛЬНАЯ ТОЧКА 15**
- [ ] `CLAUDE.md` фиксирует: single-package, Freezed-BLoC, offset-пагинация по умолчанию, light+dark тема, обязательный `LogRepository`, форматирование 140.
- [ ] `.claude/memory/MEMORY.md` (если используется) индексирует проектные правила.

---

## Шаг 16 — Финальный E2E-гейт

**Действие.** Прогнать весь пайплайн из чистого состояния и подтвердить, что скелет плюс срез `Item` полностью работоспособны. Это шлюз перед объявлением скаффолда готовым. Дневной справочник команд — `12-dev-commands.md`.

**Команды.**

```bash
./script_auto_generate.sh                 # clean + pub get + build_runner (один прогон)
./script_format_changed_files.sh -a       # формат всех in-scope на 140
fvm flutter analyze                        # ноль ошибок
./script_tests.sh                          # все тесты зелёные
mise run build:android:stage               # stage собирается
mise run build:android:prod                # prod собирается
```

**КОНТРОЛЬНАЯ ТОЧКА 16 — финальный гейт**
- [ ] `./script_auto_generate.sh` проходит end-to-end (один прогон build_runner).
- [ ] `fvm flutter analyze` чистый по всему пакету.
- [ ] Все тесты проходят.
- [ ] Обе флейворные сборки (`stage`/`prod`) компилируются; страница `Item` достижима из `AppRoot`, пагинация и pull-to-refresh работают.
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

---

## Definition of Done (скаффолд готов, когда)

- [ ] `.fvmrc` пинит Flutter 3.44.1; `fvm flutter --version` подтверждает; `.fvm/` в `.gitignore`.
- [ ] Один пакет `nox_app`: слои — папки в одном `lib/`; один `pubspec.yaml`; `pub get` чистый; нет path-зависимостей/цикла.
- [ ] `build.yaml` и `analysis_options.yaml` на месте; analyze исключает все генерируемые файлы; длина строки 140.
- [ ] Полный скелет директорий (`lib/{data,domain,presentation,di,general,design,resource}`).
- [ ] База домена компилируется: `RepositoryResult<T>` (success/error), `match<R>`, иерархия исключений, `RepositoryConfig` — без JSON.
- [ ] База данных компилируется: `ResponseEntity`, `EntityConverter`, `BaseMapper`, `ApiClient` (Dio), типизированные `DaoException`/`ApiException`, `BaseRepositoryHelper` с **обязательным** `LogRepository`, env-scoped `AppDatabase` (Dev/Prod=IO, Test=memory).
- [ ] Single-tier DI: один `$initGetIt` + один `configure_dependencies.config.dart`; `AppFlavor`/`AppConfigModel`; `main.dart` с `runZonedGuarded` → `configureDependencies(env)` → `getIt.allReady()` → `runApp(AppRoot)` (ошибки логируются в `catch` через `LogRepository`, без BLoC-обсервера).
- [ ] Тема light+dark: `ThemeExtension<AppColors>`, `AppTheme.light()/dark()`, `context.appColors`, `themeMode` из `AppRootBloc`, четыре класса токенов, `flutter_screenutil` 360×779.
- [ ] База presentation: `BaseBloc`, `BaseStatePage`, три общих виджета, `AppRootBloc` (Freezed), `AppRoot`, `main.dart`.
- [ ] Полный срез `Item` end-to-end с пагинацией: модель+конфиг+контракт (домен, без JSON); entity+mapper+api+impl (данные, NETWORK-ONLY список); Freezed-BLoC с `PagingState` + `PagedListView` v5 + pull-to-refresh; DI (`as: domain.ItemRepository`, `[dev,prod,test]`).
- [ ] Скрипты/задачи: `script_auto_generate.sh`, `script_tests.sh`, `script_format_changed_files.sh`, Makefile/mise.
- [ ] Test bootstrap (`flutter_test_config.dart`, `tests_utils.dart`) + smoke `ItemListBloc` + раунд-трип маппера.
- [ ] CI (`ci.yml`) зеркалит локальный пайплайн (3.44.1, один build_runner, format@140, analyze, test); без Rust/FFI/IPC/multi-window.
- [ ] Секреты SOPS+age+mise; флейворные сборки `stage`/`prod` (`com.cyphernetlabs.noxapp[.stage]`); версионирование CalVer + shifted-epoch.
- [ ] `CLAUDE.md` + (опц.) `.claude/memory/MEMORY.md` фиксируют инварианты.
- [ ] `fvm flutter analyze` чистый, все тесты проходят, обе флейворные debug-сборки компилируются, страница `Item` достижима с рабочей пагинацией.

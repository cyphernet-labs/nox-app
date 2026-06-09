# Tasks: Инициализация Flutter-проекта NOX (multi-platform skeleton)

**Input**: Design documents from `/specs/001-flutter-project-init/`

**Prerequisites**: plan.md, spec.md (US1–US4), research.md, data-model.md, contracts/, quickstart.md, constitution v1.1.0

**Tests**: Включены — baseline-тесты запрошены спекой (FR-009, SC-002, US3 Independent Test, Item-harness «bloc smoke + mapper round-trip»).

**Organization**: задачи сгруппированы по user story. Авторитет по «как» — блюпринт `docs/patterns/mobile/`; **пути файлов канонизированы по `data-model.md` / `contracts/`** (вложенно-singular: `domain/repository/base`, `domain/exception`, `domain/models/item`, `domain/repository/item`, `data/entity/item`, `data/mapper/item`, `data/local/item`, `data/repository/item`, `presentation/pages/item_list_page`).

## Format: `[ID] [P?] [Story] Description`

- **[P]** — можно параллелить (разные файлы, нет зависимостей от незавершённого).
- **[Story]** — только для фаз user story (US1–US4). Setup/Foundational/Polish — без метки.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: инициализация проекта и тулинга (блюпринт `11` шаги 1–4, `01`, `09`).

- [ ] T001 Сгенерировать пять нативных runner'ов: `fvm flutter create --org com.cyphernetlabs --project-name nox_app --platforms=android,ios,macos,windows,linux .`; убедиться, что есть `android/ ios/ macos/ windows/ linux/` и нет `web/`
- [ ] T002 [P] Заполнить `pubspec.yaml` (`name: nox_app`, `description: "NOX secure messenger."`, `environment.sdk '>=3.12.0 <4.0.0'` + `flutter: 3.44.1`; deps: `freezed_annotation`/`json_annotation`/`injectable`/`get_it`/`flutter_screenutil`/`infinite_scroll_pagination: ^5`/`sembast`/`rxdart`/`dio`[пример]/`flutter_gen`; dev: `build_runner`/`freezed`/`json_serializable`/`injectable_generator`/`flutter_gen_runner`/`flutter_lints`; `firebase_*` — mobile-only feature-gated) — блюпринт `01`
- [ ] T003 [P] Создать `.fvmrc` (`{"flutter":"3.44.1"}`) — блюпринт `09` §1
- [ ] T004 [P] Создать `analysis_options.yaml` (include `flutter_lints`, line length `140`, исключить `**/*.g.dart`/`**/*.freezed.dart`/`**/*.config.dart`/`lib/design/gen/**`) — блюпринт `01`/`08`
- [ ] T005 [P] Создать `build.yaml` (`freezed` + `json_serializable` + `injectable_generator` + `flutter_gen_runner`) — блюпринт `01`
- [ ] T006 [P] Создать `config/stage.json` и `config/prod.json` (`{"app.flavor":"stage|prod"}`, закоммичены, без секретов) — FR-010 / `contracts/build-flavors.md`
- [ ] T007 [P] Создать `.gitignore` (`.secrets-runtime/`, `.fvm/flutter_sdk`, расшифрованные нативные конфиги, keystores) — **blueprint-mandated infra (Принцип III), без прямого FR** — блюпринт `09` §10
- [ ] T008 [P] Поднять `.mise.toml` (пины инструментов + граф задач; desktop build-задачи БЕЗ `secrets:decrypt`), `.sops.yaml` и `Makefile` (**только build/secrets-обёртки**; dev-helper-таргеты добавляются позже в T052) — блюпринт `09` §3/§4
- [ ] T009 Создать каркас слоёв-папок `lib/{data,domain,presentation,di,general,design,resource}` (+ под-папки) — блюпринт `00`/`11`

**Checkpoint**: проект генерируется, тулинг на месте, пять таргетов без web.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: архитектурный спайн, от которого зависят ВСЕ user stories. **⚠️ Завершить до US1–US4.** (блюпринт `02`–`06`, `contracts/`)

- [ ] T010 [P] `lib/general/constants.dart` — `final class Constants` (`designSize = Size(360,779)`, `railBreakpoint = 840`, regex) — блюпринт `06` §8.1
- [ ] T011 [P] `lib/general/platform_utils.dart` — `PlatformUtils.isMobile/isDesktop/isAndroid/isIOS/isMacOS` — блюпринт `06` §8.2
- [ ] T012 [P] `lib/general/log_repository.dart` — `LogRepository` (интерфейс + impl); единственный канал логов, запрет `print`/`debugPrint` — FR-011 / блюпринт `04`
- [ ] T013 [P] `lib/general/formatters/value_formatter.dart` + `date_formatter.dart` — `@lazySingleton ValueFormatter` (intl) + `DateFormatter` — **blueprint-mandated infra (Принцип III)** — блюпринт `06` §8.3
- [ ] T014 [P] `lib/domain/model/app_config/app_flavor.dart` + `app_flavor_type.dart` — `enum AppFlavorType { prod, stage }` + `AppFlavor.getFlavor()` из `String.fromEnvironment('app.flavor')` (пусто/неизвестно → `prod`) — **линчпин FR-010**; `contracts/build-flavors.md` §1
- [ ] T015 [P] `lib/domain/repository/base/repository_result.dart` — `@freezed sealed RepositoryResult<T>` (`RepositoryResultSuccess`/`RepositoryResultError`, `success(data:)`/`error(exception:)`) + `match<R>` в `repository_result_handling.dart` — `contracts/repository-result.md` / FR-014
- [ ] T016 [P] Исключения: `lib/domain/exception/base_repository_exception.dart` — маркер `abstract class BaseRepositoryException {}`; `lib/domain/exception/repository_exception.dart` — **`enum RepositoryException implements BaseRepositoryException`** (`unknown`/`internal`/`authentication`/`connection`/`unauthenticated`/`notFound`); `lib/domain/repository/base/repository_config.dart` — маркер `abstract class RepositoryConfig {}`. **Типизированных `ApiException`/`DaoException` НЕТ** — они мапятся в `RepositoryException` в `BaseRepositoryHelper.execute` (data-model §3.2 / contract §4)
- [ ] T017 `AppConfigRepository`: контракт `lib/domain/repository/app_config/app_config_repository.dart` + модель `lib/domain/model/app_config/app_config.dart` + impl `lib/data/repository/app_config/app_config_repository_impl.dart`; `initialize(flavorType:)` поднимает флейвор-зависимый конфиг; в скелете несёт **только флейвор** (источник токена/`apiUrl` — **пример/TBD**) — `contracts/di-bootstrap.md` §3
- [ ] T018 `lib/data/local/app_database.dart` — env-scoped `Sembast AppDatabase` (`@LazySingleton(as: AppDatabase, env:[...])`, Dev/Prod = IO, Test = memory) — блюпринт `04`
- [ ] T019 `lib/data/remote/` — `ResponseEntity<T>` + `EntityConverter`-реестр (**пример/TBD**-конверт) + `ApiClient` (Dio + interceptors, **пример/TBD**) — блюпринт `04`/`14`
- [ ] T020 `lib/data/repository/base/base_repository_helper.dart` — `BaseRepositoryHelper.execute<T>()` (try/catch: `DioException → RepositoryException.internal`, иначе `→ unknown`; ВСЕГДА логирует через `LogRepository`); `lib/data/mapper/base/base_mapper.dart` — базовый `BaseMapper<E,M,...>` — блюпринт `04`
- [ ] T021 [P] `lib/presentation/base/base_bloc.dart` — тонкий `BaseBloc<E,S>` с `executeLogic` — блюпринт `05`
- [ ] T022 [P] `lib/presentation/pages/base/base_state_page.dart` — `BaseStatePage<T>` — блюпринт `05`
- [ ] T023 `lib/presentation/app/bloc/app_root_bloc.dart` (+ state/event) — `AppRootBloc` (`@freezed`, `themeMode`, дефолт `ThemeMode.system`) — блюпринт `05`
- [ ] T024 `lib/presentation/app/app_root.dart` — корневой `MaterialApp` (`themeMode` из `AppRootBloc`, `ScreenUtilInit(designSize)`, `navigatorKey`, `onGenerateRoute`); **временная** тема `ColorScheme.fromSeed(<teal>)` light+dark (полная токен-тема — в T055) — блюпринт `05`/`06`
- [ ] T025 `lib/di/configure_dependencies.dart` — `configureDependencies(String env)` + `@InjectableInit(initializerName: r'$initGetIt')` → `getIt.$initGetIt(environment: env)`; маппинг `prod→Environment.prod`/`stage→Environment.dev`/тесты→`Environment.test` — `contracts/di-bootstrap.md` §1/§2
- [ ] T026 `lib/main.dart` — `runZonedGuarded`; порядок: `WidgetsFlutterBinding.ensureInitialized()` → `flavor = AppFlavor.getFlavor()` → `env = flavor == AppFlavorType.prod ? Environment.prod : Environment.dev` → `await configureDependencies(env)` → `await getIt.allReady()` → `await getIt<AppConfigRepository>().initialize(flavorType: flavor)` → `runApp(const AppRoot())` — `contracts/di-bootstrap.md` §3 / FR-006
- [ ] T027 Прогнать `fvm dart run build_runner build --delete-conflicting-outputs` (один раз); `*.config.dart`/`*.freezed.dart` сгенерированы; `fvm flutter analyze` по foundation чист

**Checkpoint**: спайн готов (DI, general, domain-примитивы + AppFlavor, AppConfigRepository, data-база, presentation-база, AppRoot, main). Можно стартовать user stories.

---

## Phase 3: User Story 1 — Сборка под все пять платформ и запуск каркаса (Priority: P1) 🎯 MVP

**Goal**: сборка под 5 таргетов; адаптивный app shell запускается на macOS/iOS/Android, компилируется на Windows/Linux.

**Independent Test**: см. spec US1 / quickstart §4.

- [ ] T028 [US1] `lib/presentation/app/widgets/app_shell.dart` — `AppShell` (`LayoutBuilder`): width-driven `constraints.maxWidth >= Constants.railBreakpoint` (840dp), **не** `Platform`; mobile-ветка `Scaffold` + кастомный `BottomAppBar`(`CircularNotchedRectangle`) + `FloatingActionButton` в `centerDocked`; desktop-ветка `Row[NavigationRail(width:80, extended:false, labelType: NavigationRailLabelType.all, leading: FAB), VerticalDivider(width:1), Expanded(body)]`; 2 destination (`Chats`=`Icons.forum`, `Settings`=`Icons.settings`); тело `IndexedStack`; `+` = no-op snackbar — FR-004 / `contracts/app-shell.md`
- [ ] T029 [US1] `lib/presentation/pages/placeholder/` — плейсхолдер-страницы `Chats`/`Settings` (full-screen, EN-микрокопия) для `IndexedStack` оболочки (в US2 тело `Chats` переключается на `ItemListPage`)
- [ ] T030 [US1] Подключить `AppRoot` `home` → `AppShell` в `lib/presentation/app/app_root.dart`
- [ ] T031 [P] [US1] Android-идентичность: `applicationId com.cyphernetlabs.noxapp[.stage]`, label `NOX` в `android/app/build.gradle` + manifest — FR-003 / блюпринт `09` §6
- [ ] T032 [P] [US1] iOS-идентичность: bundle id + display name `NOX` через `ios/Runner` xcconfig/`Info.plist` — FR-003 / блюпринт `09` §7
- [ ] T033 [P] [US1] macOS-идентичность (prod-only): `PRODUCT_BUNDLE_IDENTIFIER = com.cyphernetlabs.noxapp` + `PRODUCT_NAME = NOX` в `macos/Runner/Configs/AppInfo.xcconfig` — FR-003 / блюпринт `09` §7a
- [ ] T034 [P] [US1] Windows-идентичность (prod-only): `set(BINARY_NAME "NOX")` в `windows/CMakeLists.txt` + ProductName/CompanyName + фикс. GUID в `windows/runner/Runner.rc`/`main.cpp` — FR-003 / блюпринт `09` §7a
- [ ] T035 [P] [US1] Linux-идентичность (prod-only): `set(APPLICATION_ID "com.cyphernetlabs.noxapp")` + `BINARY_NAME`/`.desktop Name=NOX` в `linux/CMakeLists.txt` — FR-003 / блюпринт `09` §7a
- [ ] T036 [US1] Проверка по `quickstart.md` §4: launch macOS (`fvm flutter run -d macos --dart-define-from-file=config/stage.json`) + iOS + Android (адаптивный shell); compile Windows/Linux (`fvm flutter build windows|linux --debug --dart-define-from-file=config/stage.json`); ровно 5 таргетов, web нет — SC-001 / SC-006

**Checkpoint**: MVP — запускаемый адаптивный shell на 5 таргетах.

---

## Phase 4: User Story 2 — Структура, готовая к разработке фич (Priority: P1)

**Goal**: слои/DI/`RepositoryResult`/токены/кодоген на месте; сквозной `Item`-harness собран, реструктуризация не нужна.

**Independent Test**: см. spec US2 / SC-004 / quickstart §6.

- [ ] T037 [P] [US2] `lib/domain/models/item/item_model.dart` — `ItemModel` (`@freezed`, без JSON; `id`/`name`/`description`/`status`/`createdAt`) + `lib/domain/models/item/item_status.dart` — `enum ItemStatus { active, archived, draft }` — data-model §2.1 / блюпринт `03`
- [ ] T038 [P] [US2] `lib/domain/repository/item/item_repository.dart` — контракт `ItemRepository` + `lib/domain/repository/item/get_items_config.dart` — `GetItemsConfig` (`@freezed abstract implements RepositoryConfig`) — data-model §2.5 / блюпринт `03`
- [ ] T039 [P] [US2] `lib/data/entity/item/item_entity.dart` — `ItemEntity` (`@freezed` + `json_serializable`, basic-types) + `lib/data/entity/item/items_entity.dart` — `ItemsEntity` (`{items, count}`); зарегистрировать в `EntityConverter` (обе цепочки) — data-model §2.2 / блюпринт `04`
- [ ] T040 [US2] `lib/data/mapper/item/item_mapper.dart` — `@lazySingleton ItemMapper extends BaseMapper` (Entity↔Model; enum→`.name`, `DateTime`↔ISO, пустой `description`→`null`; lossless round-trip) — data-model §2.3 / блюпринт `04`
- [ ] T041 [US2] `lib/data/local/item/item_dao.dart` — `ItemDao` (Sembast) для полноты шаблона; зафиксировать **network-only carve-out** (пагинированный список без DAO-записи) — data-model §2.4 / блюпринт `04`/`07`
- [ ] T042 [US2] `lib/data/remote/api/item/get_items_api.dart` — `GetItemsApi` mock-источник (mock-body; REST/envelope/endpoint — **пример/TBD**) — data-model §2.7
- [ ] T043 [US2] `lib/data/repository/item/item_repository_impl.dart` — `ItemRepositoryImpl` (network-only, MOCK-источник), возвращает `RepositoryResult<(List<ItemModel>, PageMetadata)>` через `BaseRepositoryHelper.execute` — data-model §2.8 / блюпринт `04`/`07`
- [ ] T044 [US2] `lib/presentation/pages/item_list_page/bloc/` — `ItemListBloc`/`ItemListEvent`/`ItemListState` (`@freezed` sealed; `Initializing`/`Initialized`/`Error`; `PagingState<String, ItemModel>`-в-bloc, `PagingStateExt.applyPage`) — data-model §2.6 / блюпринт `05`/`07`
- [ ] T045 [US2] `lib/presentation/pages/item_list_page/item_list_page.dart` — `ItemListPage` (`PagedListView`, infinite_scroll_pagination v5; три состояния); ЯВНО помечен scaffold-demo (FR-013)
- [ ] T046 [US2] Зарегистрировать `Item`-слайс в DI (`@LazySingleton(as: ItemRepository, env:[dev,prod,test])`, мапперы/bloc); подключить тело вкладки `Chats` → `ItemListPage` в `AppShell` (зависит от T028)
- [ ] T047 [US2] Прогнать `build_runner`; убедиться, что `Item`-слайс компилируется; **сверить направление зависимостей вручную** (`presentation → domain ← data`, `domain` ничего не импортирует) — мех. import-lint не вводим в скелете (принято; CV1) — SC-004

**Checkpoint**: структура и verification-harness доказывают готовность к фичам.

---

## Phase 5: User Story 3 — Зелёный code-gate и воспроизводимая среда (Priority: P2)

**Goal**: полный gate зелёный; окружение воспроизводимо.

**Independent Test**: см. spec US3 / SC-002 / quickstart §3.

### Tests for User Story 3 (baseline — запрошены спекой) ⚠️

- [ ] T048 [P] [US3] `test/presentation/pages/item_list_page/item_list_bloc_test.dart` — bloc smoke-тест `ItemListBloc` (`Initialize → Initialized`) — FR-009
- [ ] T049 [P] [US3] `test/data/mapper/item/item_mapper_test.dart` — round-trip тест `ItemMapper` (`ItemEntity ↔ ItemModel`)

### Implementation for User Story 3

- [ ] T050 [P] [US3] `.github/workflows/ci.yml` — format-check (`-l 140`) → один `build_runner` → `flutter analyze` → `flutter test`; `subosito/flutter-action` `3.44.1`; `paths: lib/**` — блюпринт `09` §8.1
- [ ] T051 [US3] `.github/workflows/compile-check.yml` — 5 debug-джобов (`compile-android`, `compile-ios` `--no-codesign`, `compile-macos`, `compile-windows`, `compile-linux` + GTK apt-deps `ninja-build libgtk-3-dev`); Win/Linux — compile-only; без секретов — блюпринт `09` §8.2 / SC-001
- [ ] T052 [P] [US3] Добавить dev-helper-таргеты (`generate`/`format`/`analyze`/`test`) в **существующий `Makefile`** (создан в T008) + `.claude/commands/` — блюпринт `12`
- [ ] T053 [US3] Прогнать полный gate по `quickstart.md` §3: кодоген (один прогон) → `fvm dart format -l 140` → `fvm flutter analyze` (ноль ошибок) → `fvm flutter test` (baseline проходит) — SC-002 / FR-009

**Checkpoint**: зелёный gate + CI на 5 таргетов.

---

## Phase 6: User Story 4 — Тема из дизайн-системы (light + dark) (Priority: P3)

**Goal**: токен-driven M3 light+dark из `nox-handoff`, системная по умолчанию, тёмный splash, ноль хардкода.

**Independent Test**: см. spec US4 / SC-005 / quickstart §5.

- [ ] T054 [P] [US4] Положить сгенерированный из токенов Dart в `lib/design/theme/` (`nox_color_scheme.dart`/`nox_tokens.dart`/`nox_brand.dart`/`nox_text_theme.dart`) из `docs/design/system/nox-handoff/` (регенерируется из токенов, не правится руками) — FR-005 / блюпринт `06`
- [ ] T055 [US4] `lib/design/theme/app_colors.dart` + `app_theme.dart` — `ThemeExtension<AppColors>` (`Light/DarkAppColors`, `context.appColors`) + `AppTheme.light()/dark()`; **заменить** временную тему в `AppRoot` (T024) на `AppTheme.light/dark` — блюпринт `06`
- [ ] T056 [P] [US4] Токен-классы: `lib/design/app_spacing_tokens.dart`, `app_text_style_tokens.dart`, `app_overlay_style_tokens.dart`, `app_images_tokens.dart` — блюпринт `06`
- [ ] T057 [P] [US4] Тёмный splash (brand-fixed) — нативный splash-конфиг тёмный на `android/ios/macos/windows/linux` — FR-005
- [ ] T058 [US4] Подтвердить `AppRootBloc.themeMode` дефолт = `system`; `MaterialApp` потребляет `AppTheme.light/dark` + `themeMode`; единая M3 на 5 платформах (без `yaru`)
- [ ] T059 [US4] Валидация по `quickstart.md` §5: системный toggle light↔dark (через токены); grep-аудит — ноль хардкод `Color`/`EdgeInsets`/`TextStyle`/`SystemUiOverlayStyle` в `lib/`; splash тёмный — SC-005

**Checkpoint**: токенизированная тема + brand-splash; ноль хардкода.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T060 [P] Подтвердить desktop-fallback (FR-012/SC-007): push=disabled, deep-links=no-op, secure-storage=задокументированы, flavor-secrets=skipped — **проза-only, кода нет**; сверить с блюпринтом `11` (fallback-matrix), `13`/`14`/`15` и `quickstart.md` §7
- [ ] T061 [P] Корневой `README.md` проекта — как поднять и запустить (ссылка на `quickstart.md`), пять таргетов, flavor через `--dart-define-from-file`
- [ ] T062 Финальный полный gate + компиляция на всех 5 таргетах; **SC-003 — проверяемая часть:** документированные шаги `quickstart` выполняются end-to-end на чистом клоне (порог «< 30 мин» — non-blocking target, не гейт)
- [ ] T063 [P] Подтвердить: аналитика НЕ подключена (opt-in по умолчанию off), ноль PII, `LogRepository` — единственный канал логов — Принцип I / FR-011

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** — без зависимостей.
- **Foundational (Phase 2)** — зависит от Setup; **БЛОКИРУЕТ все user stories**. Внутри: `AppFlavor` (T014) до `main.dart` (T026); `AppConfigRepository` (T017) до T026; `RepositoryResult`/исключения (T015/T016) до repo-слоя.
- **US1 (Phase 3, P1)** — после Foundational. MVP.
- **US2 (Phase 4, P1)** — после Foundational; T046 (wiring вкладки) зависит от US1 T028 (shell).
- **US3 (Phase 5, P2)** — после US2 (тесты на `Item`-слайсе) и US1 (есть что компилировать в CI).
- **US4 (Phase 6, P3)** — после Foundational; T055 заменяет временную тему из T024; no-hardcode-аудит покрывает весь код → ближе к концу.
- **Polish (Phase 7)** — после нужных stories.

### Within Each User Story

- Модели → мапперы/repo → BLoC → страница → wiring → проверка.
- US2: `ItemModel`+`ItemStatus`/`ItemRepository`+`GetItemsConfig`/`ItemEntity`+`ItemsEntity` ([P]) → `ItemMapper` → `ItemDao`/`GetItemsApi` → `ItemRepositoryImpl` → `ItemListBloc` → `ItemListPage` → DI/wiring → build_runner/structure-check.

### Parallel Opportunities

- **Setup**: T002–T008 ([P]) после T001; T009 после.
- **Foundational**: T010–T016 ([P], кроме связок) + T021–T022 ([P]) параллельно; T017–T020, T023–T026 — последовательно (общие зависимости); T027 в конце.
- **US1**: T031–T035 (platform identity, [P]) параллельно; T028→T029→T030; T036 в конце.
- **US2**: T037–T039 ([P]) параллельно; затем T040→T041/T042→T043→T044→T045; T046–T047 в конце.
- **US3**: T048–T049 (тесты, [P]) + T050/T052 ([P]); T051→T053.
- **US4**: T054/T056/T057 ([P]); T055→T058→T059.

---

## Implementation Strategy

### MVP First (US1)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & VALIDATE**: адаптивный shell собирается на 5 таргетах и запускается на macOS/iOS/Android.

### Incremental Delivery

1. Setup + Foundational → спайн готов (вкл. `AppFlavor`/`AppConfigRepository`).
2. + US1 → запускаемый адаптивный shell (MVP).
3. + US2 → структура + `Item`-harness.
4. + US3 → зелёный gate + CI на 5 таргетов.
5. + US4 → токенизированная тема + brand-splash.
6. + Polish → desktop-fallback'ы подтверждены, README, финальный gate.

> **Scope.** Первая РЕАЛЬНАЯ фича (открытый список чатов) — **отдельный spec-цикл** (FR-013). `Item`-слайс — verification harness на mock-данных.

---

## Notes

- `[P]` = разные файлы, нет зависимостей от незавершённого.
- **Пути файлов канонизированы по `data-model.md`/`contracts/`** (вложенно-singular); структура-чек US2/SC-004 сверяется против единого дерева.
- Сгенерированные файлы (`*.freezed.dart`/`*.g.dart`/`*.config.dart`/`lib/design/gen/**`) — не правятся руками, исключены из анализа; один прогон `build_runner`.
- Бэкенд/сеть/crypto — **пример/TBD**: `ApiClient`/`ResponseEntity`/`GetItemsApi`/`AppConfigRepository` token-source — заглушки-примеры.
- `RepositoryException` — **enum** (не иерархия типизированных классов); `Dao/ApiException` мапятся в него в `BaseRepositoryHelper.execute`.
- Коммиты/пуши — не автономно: стейдж → дифф → команда → явное подтверждение владельца.

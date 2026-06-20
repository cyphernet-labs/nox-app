# Tasks: Экраны этапа M1 — Splash и простые автономные экраны

**Input**: Design documents from `specs/004-splash-simple-screens/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: ВКЛЮЧЕНЫ — спека требует их явно (FR-007: каждый экран покрыт widget + golden тестами; DoD roadmap). Тесты пишутся вместе с экраном (golden-бейзлайн рендерится после готового виджета — не строгий TDD-first).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (разные файлы, нет незавершённых зависимостей)
- **[Story]**: US1–US6 из spec.md (фазы Setup/Foundational/Polish — без метки)
- Каждый таск содержит точный путь к файлу

## Path Conventions

Один пакет `nox_app`: код в `lib/`, тесты deep-mirror в `test/`. Страницы — `lib/presentation/pages/<page>_page/`; виджеты — `lib/presentation/widgets/{shell,settings}/`. Навигация — `Navigator.push(<Page>.route())` (роутера нет).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Базовая готовность; новые зависимости НЕ добавляются.

- [ ] T001 Проверить наличие M1-зависимостей (`package_info_plus`, `url_launcher`, `shared_preferences`) в `pubspec.yaml` и базовый зелёный `make gate` до изменений (никаких правок `pubspec.yaml`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Общая инфраструктура, нужная нескольким историям. ⚠️ Завершить до US3–US6.

- [ ] T002 [P] Добавить всю UI-микрокопию M1 (English) в `lib/general/text_constants.dart` — строки Splash (debug-метки/placeholder), Error (`errorGeneralTitle` уже есть; добавить сетевой текст, заголовки), Appearance, Language, Notifications, Terms, About.
- [ ] T003 [P] Создать `AppDetailScaffoldWidget` в `lib/presentation/widgets/shell/app_detail_scaffold_widget.dart` (мобайл `Scaffold`+`AppBar`(title,back) ↔ десктоп ≥840 width-capped `ConstrainedBox(maxWidth:640)` через `LayoutBuilder`+`Constants.railBreakpoint`). Контракт — `contracts/widgets.md`.
- [ ] T004 Widget-тест адаптивности `AppDetailScaffoldWidget` (<840 fullscreen / ≥840 width-cap) в `test/presentation/widgets/shell/app_detail_scaffold_widget_test.dart` (зависит от T003).

**Checkpoint**: фундамент готов — истории можно реализовывать.

---

## Phase 3: User Story 1 — Splash (Priority: P1) 🎯 MVP

**Goal**: Брендовый экран запуска с reveal-анимацией; по завершении — маршрутизация по заглушечному исходу.

**Independent Test**: Открыть Splash из Галереи (узкое/широкое окно, light/dark); лого+wordmark на тёмном фоне, reveal один раз ~400мс затем статика, экран пассивен; dev-контролом выбрать исход и убедиться в переходе.

- [ ] T005 [P] [US1] Создать `RoutePlaceholderPage` в `lib/presentation/pages/placeholder/route_placeholder_page.dart` (`route({required String destinationLabel})`, `RouteSettings('/placeholder')`, показывает метку назначения).
- [ ] T006 [US1] Создать `SplashPage` в `lib/presentation/pages/splash_page/splash_page.dart`: brand-fixed тёмный `Scaffold` (`NoxBrand.canvasDark`), центр — `Assets.png.logo` + `AppWordmarkWidget(color: NoxBrand.white)`, edge-to-edge `AnnotatedRegion<SystemUiOverlayStyle>`, `AnimationController`(`NoxDuration.splashIn`)+`FadeTransition`+`ScaleTransition`(0.85→1.0, `NoxEasing.emphasizedDecelerate`), один проход; пассивный ввод. `route()`→`/splash` (зависит от T002).
- [ ] T007 [US1] Добавить `SplashOutcome{hasId,noId,error}` + dev-контрол + координацию `animationDone && outcomeResolved` в `lib/presentation/pages/splash_page/splash_page.dart`: `hasId`→`RoutePlaceholderPage('Chats shell (4.1)')`, `noId`→`RoutePlaceholderPage('Login (2.1)')`, `error`→`RoutePlaceholderPage('Error (3.1)')` **временно** с `// TODO(US2): wire to AppErrorPage(blocking)`. Навигация — `Navigator.push` (НЕ `pushReplacement`) в превью из Галереи (см. `contracts/navigation.md`) + `// TODO(backend): pushReplacement в реальном cold-start` (зависит от T005, T006).
- [ ] T008 [US1] Активировать строку `1.1` (`route: SplashPage.route`) в `lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart` и добавить в `test/presentation/pages/screens_gallery_page/screens_gallery_page_test.dart` проверку навигации в `SplashPage` (зависит от T006).
- [ ] T009 [P] [US1] Widget-тест `SplashPage` в `test/presentation/pages/splash_page/splash_page_test.dart`: reveal-виджеты, пассивность, переход по каждому `SplashOutcome` (`tester.pump(NoxDuration.splashIn)`) (зависит от T006, T007).
- [ ] T010 [P] [US1] Golden-тест `SplashPage` (light/dark, `settle:false`) в `test/presentation/pages/splash_page/splash_page_golden_test.dart` + сгенерировать бейзлайны (`make golden-update FILE=...`) (зависит от T006).

**Checkpoint**: US1 функциональна и тестируема независимо (error-ветка пока на placeholder).

---

## Phase 4: User Story 2 — Универсальный экран ошибки (Priority: P2)

**Goal**: Параметризованный экран 3.1 (иконка/заголовок/сообщение/`Try again`), режимы blocking/embedded, loading-retry, десктоп-TitleBar.

**Independent Test**: Открыть Error из Галереи (`routeDemo`); проверить embedded(back)/blocking(без back), спиннер на `Try again`, десктоп TitleBar + крупная иконка.

- [ ] T011 [P] [US2] Создать `ErrorPageParams` + `ErrorPageMode{blocking,embedded}` + пресеты `fatal()`/`network()` в `lib/presentation/pages/error_page/error_page_params.dart` (иконка — `SvgGenImage` из `NoxIcons`). См. `data-model.md`.
- [ ] T012 [P] [US2] Создать `AppWindowTitlebarWidget` (faux desktop TitleBar) в `lib/presentation/widgets/shell/app_window_titlebar_widget.dart`. Контракт — `contracts/widgets.md`.
- [ ] T013 [US2] Создать `AppErrorPage` в `lib/presentation/pages/error_page/error_page.dart`: иконка(48/деск.96)+title+message+`Try again`(loading через `AppSpinnerWidget`); `embedded`→`AppBar`(back), `blocking`→без AppBar+`PopScope(canPop:false)`; десктоп — `AppWindowTitlebarWidget`; `route({required params})`+`routeDemo()` (зависит от T011, T012, T002).
- [ ] T014 [US2] Активировать строку `3.1` (`route: AppErrorPage.routeDemo`) в `screens_gallery_page.dart` + проверка навигации в gallery-тесте (зависит от T013).
- [ ] T015 [US2] Перевести error-ветку Splash на реальный `AppErrorPage(mode: blocking)` в `lib/presentation/pages/splash_page/splash_page.dart` (убрать временный placeholder из T007) и обновить splash-тест (зависит от T013, T007).
- [ ] T016 [P] [US2] Widget-тест `AppErrorPage` (оба режима, loading-retry) в `test/presentation/pages/error_page/error_page_test.dart` (зависит от T013).
- [ ] T017 [P] [US2] Golden-тест `AppErrorPage` (light/dark, blocking+embedded) в `test/presentation/pages/error_page/error_page_golden_test.dart` + бейзлайны (зависит от T013).
- [ ] T018 [P] [US2] Widget+golden тест `AppWindowTitlebarWidget` в `test/presentation/widgets/shell/` (зависит от T012).

**Checkpoint**: US2 независимо тестируема; Splash error-ветка теперь реальная.

---

## Phase 5: User Story 3 — Внешний вид / тема (Priority: P2)

**Goal**: Карточки System/Light/Dark; тап немедленно меняет тему всего приложения (через `AppRootBloc`).

**Independent Test**: Открыть Appearance из Галереи; тап по карточке мгновенно меняет тему; отмечена текущая.

- [ ] T019 [P] [US3] Создать `AppThemeOptionWidget` (карточка: мини-превью+label+`selected`+`onTap`) в `lib/presentation/widgets/settings/app_theme_option_widget.dart`. Контракт — `contracts/widgets.md`.
- [ ] T020 [US3] Создать `AppearancePage` в `lib/presentation/pages/appearance_page/appearance_page.dart`: три `AppThemeOptionWidget` (System/Light/Dark), читает/диспатчит `AppRootBloc` (`setTheme`), в `AppDetailScaffoldWidget`; `route()`→`/settings/appearance` (зависит от T019, T003, T002).
- [ ] T021 [US3] Активировать строку `7.3` (`route: AppearancePage.route`) в `screens_gallery_page.dart` + gallery-тест (зависит от T020).
- [ ] T022 [P] [US3] Widget-тест `AppearancePage`: выбор опции + живая смена темы через `AppRootBloc` в `test/presentation/pages/appearance_page/appearance_page_test.dart` (зависит от T020).
- [ ] T023 [P] [US3] Golden-тест `AppearancePage` (light/dark) + бейзлайны (зависит от T020).
- [ ] T024 [P] [US3] Widget+golden тест `AppThemeOptionWidget` в `test/presentation/widgets/settings/` (зависит от T019).

**Checkpoint**: US3 — единственная «живая» функция M1 — работает.

---

## Phase 6: User Story 4 — Язык (Priority: P3)

**Goal**: Выбор System/English/Українська radio-строками; выбор сессионный (l10n-перерисовка вне scope).

**Independent Test**: Открыть Language из Галереи; System по умолчанию; тап переносит выбор.

- [ ] T025 [P] [US4] Создать `enum AppLanguage { system, english, ukrainian }` в `lib/general/app_language.dart`.
- [ ] T026 [US4] Создать `LanguagePage` в `lib/presentation/pages/language_page/language_page.dart`: три `RadioListTile` (без флагов), локальный выбор, `AppDetailScaffoldWidget`, `// TODO(backend): LocaleController + l10n`; `route()`→`/settings/language` (зависит от T025, T003, T002).
- [ ] T027 [US4] Активировать строку `7.4` в `screens_gallery_page.dart` + gallery-тест (зависит от T026).
- [ ] T028 [P] [US4] Widget-тест `LanguagePage` (single-select) в `test/presentation/pages/language_page/language_page_test.dart` (зависит от T026).
- [ ] T029 [P] [US4] Golden-тест `LanguagePage` (light/dark) + бейзлайны (зависит от T026).

**Checkpoint**: US4 независимо тестируема.

---

## Phase 7: User Story 5 — Уведомления (Priority: P3)

**Goal**: Один push-переключатель + denied-баннер (mock-разрешение).

**Independent Test**: Открыть Notifications; тогглить переключатель; demo-контролом включить `denied` → info-баннер с «open settings».

- [ ] T030 [P] [US5] Создать `AppSettingsSwitchRowWidget` (`SwitchListTile`+supporting text) в `lib/presentation/widgets/settings/app_settings_switch_row_widget.dart`.
- [ ] T031 [P] [US5] Создать `AppInfoBannerWidget` (`MaterialBanner`-стиль: `NoxIcons`-иконка+текст+одно действие) в `lib/presentation/widgets/settings/app_info_banner_widget.dart`.
- [ ] T032 [US5] Создать `NotificationsPage` в `lib/presentation/pages/notifications_page/notifications_page.dart`: `AppSettingsSwitchRowWidget` + supporting text + mock `PermissionStatus{granted,denied}` + `AppInfoBannerWidget` при denied + demo-контрол; `AppDetailScaffoldWidget`; `route()`→`/settings/notifications` (зависит от T030, T031, T003, T002).
- [ ] T033 [US5] Активировать строку `7.2` в `screens_gallery_page.dart` + gallery-тест (зависит от T032).
- [ ] T034 [P] [US5] Widget-тест `NotificationsPage` (toggle + denied-баннер) в `test/presentation/pages/notifications_page/notifications_page_test.dart` (зависит от T032).
- [ ] T035 [P] [US5] Golden-тест `NotificationsPage` (light/dark, enabled+denied) + бейзлайны (зависит от T032).
- [ ] T036 [P] [US5] Widget+golden тест `AppSettingsSwitchRowWidget` и `AppInfoBannerWidget` в `test/presentation/widgets/settings/` (зависит от T030, T031).

**Checkpoint**: US5 независимо тестируема.

---

## Phase 8: User Story 6 — Terms и About (Priority: P3)

**Goal**: Terms (озаглавленные секции + version-footer) и About (version+build).

**Independent Test**: Открыть Terms — секции + версия в подвале; открыть About — строка version/build.

- [ ] T037 [P] [US6] Создать `AboutPage` в `lib/presentation/pages/about_page/about_page.dart`: строка `version (build N)` через `package_info_plus` (`FutureBuilder`), `AppDetailScaffoldWidget`; `route()`→`/settings/about` (зависит от T003, T002).
- [ ] T038 [P] [US6] Создать `TermsPage`+`TermsBody` в `lib/presentation/pages/terms_page/terms_page.dart`: озаглавленные placeholder-секции (`Text`/`RichText`) + version-footer (`package_info_plus`), ссылки через `url_launcher`, `AppDetailScaffoldWidget`; `route()`→`/settings/terms` (зависит от T003, T002).
- [ ] T039 [US6] Активировать строки `7.6` и `7.7` в `screens_gallery_page.dart` + gallery-тест (зависит от T037, T038).
- [ ] T040 [P] [US6] Widget-тесты `AboutPage` и `TermsPage` (версия/секции/футер) в `test/presentation/pages/{about_page,terms_page}/` (зависит от T037, T038).
- [ ] T041 [P] [US6] Golden-тесты `AboutPage` и `TermsPage` (light/dark) + бейзлайны (зависит от T037, T038).

**Checkpoint**: US6 независимо тестируема.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T042 [P] Обновить `docs/roadmap.md`: отметить 7 экранов M1 `[x]` в таблице этапа M1 и счётчик прогресса (7/17 экранов, ✅ M0+M1).
- [ ] T043 [P] Добавить M1-страницы в `test/presentation/widgets/accessibility_test.dart` (tap-targets ≥48, `textScaler 2.0` без overflow).
- [ ] T044 Полный `make gate` (analyze без ошибок, все widget-тесты) + `make golden-verify` для всех новых goldens; устранить дрейф. Дополнительно (FR-006/SC-006): grep-проверить, что у всех заглушек стоит маркер `TODO(backend):`, и что в UI-строках `lib/presentation` нет кириллицы (`grep -rPn "[\x{0400}-\x{04FF}]" lib/presentation` — допустимы только не-UI комментарии на латинице).
- [ ] T045 [P] Ручная проверка десктопа (≥840) для всех 7 экранов по `quickstart.md` (width-cap панель, Error TitleBar, Splash full-window).

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → истории (Phase 3–8) → **Polish (Phase 9)**.
- **Foundational блокирует US3–US6** (через `AppDetailScaffoldWidget` T003 и микрокопию T002). US1/US2 зависят только от T002.
- **Кросс-стори связь**: US1 error-ветка (T015) зависит от `AppErrorPage` (US2, T013) — до US2 ветка работает на placeholder (T007). Это единственная межисторийная зависимость; остальные истории независимы.
- **Общий файл `screens_gallery_page.dart`**: задачи активации (T008, T014, T021, T027, T033, T039) и его тест правят ОДИН файл — выполнять **последовательно** (не параллелить между историями).
- Порядок приоритетов: US1(P1) → US2(P2) → US3(P2) → US4(P3) → US5(P3) → US6(P3).

## Parallel Execution Examples

- **Foundational**: T002 ∥ T003 (разные файлы); затем T004.
- **US1**: T005 ∥ (T006→T007); тесты T009 ∥ T010 после кода.
- **US2**: T011 ∥ T012 → T013; затем T016 ∥ T017 ∥ T018; T014/T015 — последовательно (общий файл/зависимость).
- **US3**: T019 → T020; затем T022 ∥ T023 ∥ T024.
- **US5**: T030 ∥ T031 → T032; затем T034 ∥ T035 ∥ T036.
- **US6**: T037 ∥ T038 → T039; затем T040 ∥ T041.

## Implementation Strategy

- **MVP = User Story 1 (Splash)** — первая поставка (предпосылки: T001–T004). Открывается из Галереи, все исходы на placeholder, тесты зелёные.
- **Инкременты**: добавлять US2…US6 по одной истории; каждая — самостоятельный, тестируемый прирост, отмечаемый в `docs/roadmap.md`.
- После каждой истории — `make gate` зелёный + бейзлайны goldens сгенерированы. После US2 — дозавести error-ветку Splash (T015).
- Sweet-spot для одной сессии: Foundational + US1 (MVP), затем US2 (разблокирует реальную error-ветку Splash).

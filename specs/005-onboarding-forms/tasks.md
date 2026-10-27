# Tasks: Экраны этапа M2 — Онбординг-формы

**Input**: Design documents from `specs/005-onboarding-forms/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: ВКЛЮЧЕНЫ — спека требует их явно (FR-007: каждый экран покрыт widget + golden тестами; DoD roadmap) + `bloc_test` на каждый из трёх BLoC. Тесты пишутся вместе с экраном (golden-бейзлайн рендерится после готового виджета — не строгий TDD-first).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (разные файлы, нет незавершённых зависимостей)
- **[Story]**: US1–US4 из spec.md (фазы Setup/Foundational/Polish — без метки)
- Каждый таск содержит точный путь к файлу

## Path Conventions

Один пакет `nox_app`: код в `lib/`, тесты deep-mirror в `test/`. Страницы — `lib/presentation/pages/<page>_page/` (BLoC — в `bloc/` рядом); новые виджеты — `lib/presentation/widgets/{onboarding,qr}/`. Навигация — `Navigator.push(<Page>.route()/routeDemo())` (роутера нет).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Базовая готовность; новые зависимости НЕ добавляются.

- [ ] T001 Подтвердить, что новые зависимости не нужны (камера/QR/permission — Фаза 2; debounce на `stream_transform`/`rxdart`), что `Roboto Mono` уже в `pubspec.yaml` (раздел `fonts`), и снять базовый зелёный `make gate` до изменений (без правок `pubspec.yaml`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Общие блоки, нужные нескольким историям. ⚠️ Завершить до US1–US4.

- [ ] T002 [P] Добавить всю UI-микрокопию M2 (English) в `lib/general/text_constants.dart`, сгруппировав комментариями по экранам; **переиспользовать** существующие `tooltipBack`/`actionOpenSettings`/`errorNetworkMessage`/`comingSoon`. Новые: Login (`signIn`, `loginIdLabel`, `actionPaste`, `loginIdHint`, `loginInvalidId`), QR (`tooltipFlashlight`, `tooltipSwitchCamera`, `qrAimHint`, `qrEnterManually`, `qrPermissionTitle`, `qrPermissionMessage`, `qrInvalidSnackbar`, `qrDesktopTitle`, `qrDesktopHelper`), Username (`usernameLabel`, `usernameSubtitle`, `usernameHelper`, `usernameCharsetError`, `usernameTakenError`, `actionDone`, `actionSkip`), Create (`createChatNameLabel`, `createChatNameHint`, `createChatTakenError`, `actionCreate`, `actionCancel`), per-screen TitleBar (`NOX · Sign in`/`NOX · Set up`/`NOX · Scan QR`). См. research.md R12.
- [ ] T003 [P] Создать `OnboardingMockData` (`const` наборы) в `lib/general/onboarding_mock_data.dart`: `takenUsernames: Set<String>` (case-sensitive), `takenChatNames: Set<String>`, `registeredIds: Set<String>` — happy/taken-путь проверки доступности (research.md R3).
- [ ] T004 [P] Создать общий debounce-трансформер `EventTransformer<E> debounceRestartable<E>([Duration])` (~300мс, `debounce`+`switchMap` на `stream_transform`/`rxdart`) в `lib/presentation/base/bloc_transformers.dart` — для `SetUsernameBloc`/`CreateChatBloc` (research.md R2).
- [ ] T005 [P] Создать `AppOnboardCardWidget` в `lib/presentation/widgets/onboarding/app_onboard_card_widget.dart`: голова `Assets.png.logo` + `AppWordmarkWidget` + `AppSplashHairlineWidget` (reuse) + слот `child`; десктоп — `Center`→`ConstrainedBox(maxWidth: 440)`. Контракт — `contracts/widgets.md`. Переиспользуют US1/US2-denied/US3.
- [ ] T006 [P] Создать `AppLabeledFieldWidget` в `lib/presentation/widgets/onboarding/app_labeled_field_widget.dart`: `TextField` + `maxLength` (counter из темы) + `helperText`/`errorText` + suffix-`AppSpinnerWidget(size:18)` при `checking`. Контракт — `contracts/widgets.md`. Переиспользуют US3/US4.
- [ ] T007 [P] Widget+golden тест `AppOnboardCardWidget` (light/dark, мобайл/десктоп-карточка) в `test/presentation/widgets/onboarding/app_onboard_card_widget_*.dart` + бейзлайны (зависит от T005).
- [ ] T008 [P] Widget+golden тест `AppLabeledFieldWidget` (label/counter/errorText/checking-спиннер) в `test/presentation/widgets/onboarding/app_labeled_field_widget_*.dart` + бейзлайны (зависит от T006).

**Checkpoint**: общие блоки готовы — истории можно реализовывать.

---

## Phase 3: User Story 1 — Login / вход по идентификатору (Priority: P1) 🎯 MVP

**Goal**: Экран входа: моно ID-поле + `Paste`, `Sign in` (исход по debug-переключателю), `Scan QR` (заглушка); онбординг-хром на десктопе.

**Independent Test**: Открыть Login из Галереи (узкое/широкое, light/dark); `Sign in` enabled при непустом вводе (без валидации формата), `Paste` отражает буфер; debug-исход даёт placeholder(2.3)/placeholder(4.1)/inline-error/fatal(3.1).

- [ ] T009 [P] [US1] Добавить фактори `AppTextStyleTokens.monoBody({Color? color})` (поверх `noxMonoFamily` = `Roboto Mono`) в `lib/design/app_text_style_tokens.dart` — для моно ID-поля.
- [ ] T010 [US1] Создать `AppIdFieldWidget` в `lib/presentation/widgets/onboarding/app_id_field_widget.dart`: `TextField(maxLines: null)` моно (`monoBody`), suffix-`IconButton(NoxIcons.contentPaste)` (disabled при пустом буфере), placeholder `loginIdHint`; без клиентской валидации (FR-011). Контракт — `contracts/widgets.md` (зависит от T009, T002).
- [ ] T011 [US1] Создать `LoginBloc`-трио в `lib/presentation/pages/login_page/bloc/{login_state.dart,login_event.dart,login_bloc.dart}`: value-state (`id`/`status`/`outcome`/`canPaste`, геттер `canSubmit`), события `idChanged`/`clipboardChanged`/`pastePressed`/`signInPressed`/`setOutcome`; submit через `BaseBloc.executeLogic(onError:)` (фейк-`Future`); `// TODO(backend):`. См. data-model.md (зависит от T003).
- [ ] T012 [US1] Создать `LoginPage` в `lib/presentation/pages/login_page/login_page.dart`: `State extends BaseStatePage`; десктоп — `AppOnboardCardWidget` + `AppWindowTitlebarWidget('NOX · Sign in')`, мобайл — `Scaffold`+`AppBar`(wordmark+hairline); body — `AppIdFieldWidget` + `FilledButton` `Sign in` (спиннер в Loading) + `TextButton` `Scan QR`; `Clipboard.getData` для `Paste`; исходы → `RoutePlaceholderPage('Set username (2.3)')` / `RoutePlaceholderPage('Chats shell (4.1)')` / inline `errorText` / `AppErrorPage.route(ErrorPageParams.fatal())`; `Scan QR` → заглушка `// TODO(backend):`; `route()`/`routeDemo()`→`/onboarding/login` (зависит от T010, T011, T005, T002).
- [ ] T013 [US1] Активировать строку `2.1` (`route: LoginPage.routeDemo`, раздел `Onboarding`) в `lib/presentation/pages/screens_gallery_page/screens_gallery_page.dart` (+ import) и добавить проверку навигации в `test/presentation/pages/screens_gallery_page/screens_gallery_page_test.dart` (зависит от T012).
- [ ] T014 [P] [US1] `bloc_test` `LoginBloc` в `test/presentation/pages/login_page/bloc/login_bloc_test.dart`: `canSubmit` по вводу, `pastePressed`, исходы `setOutcome` (Error/fatal только при `onError`) (зависит от T011).
- [ ] T015 [P] [US1] Widget-тест `LoginPage` в `test/presentation/pages/login_page/login_page_test.dart`: empty/filled, `Sign in` enabled при вводе, debug-исходы пушат ожидаемый `RoutePlaceholderPage`/`AppErrorPage` (зависит от T012).
- [ ] T016 [P] [US1] Golden-тест `LoginPage` (light/dark, мобайл + десктоп-`OnboardCard`) в `test/presentation/pages/login_page/login_page_golden_test.dart` + бейзлайны (зависит от T012).
- [ ] T017 [P] [US1] Widget+golden тест `AppIdFieldWidget` (моно, Paste enabled/disabled) в `test/presentation/widgets/onboarding/app_id_field_widget_*.dart` (зависит от T010).

**Checkpoint**: US1 (MVP) функциональна и тестируема независимо.

---

## Phase 4: User Story 2 — Сканирование QR (Priority: P2)

**Goal**: Экран сканера 2.2: нейтральный плейсхолдер + brand-fixed overlay (прицел/маска/инструкция), permission-denied, debug-состояния; десктоп — оконный TitleBar + вьюфайндер + `OnboardCard`-denied. Без BLoC.

**Independent Test**: Открыть QR scan из Галереи; прицел #FAFAFA + маска #000@55% **одинаковы в light/dark**; debug-`SegmentedButton`: Scanning / Permission-denied / invalid(snackbar) / fatal; десктоп — `TitleBar('NOX · Scan QR')` + вьюфайндер ≈300dp + helper-ссылка.

- [ ] T018 [P] [US2] Добавить SVG-иконку `no_photography` по M1-конвейеру: положить `docs/design/system/nox-assets/icons/svg/no_photography.svg` (Material Symbols Rounded, w400/opsz24/grade0, FILL 0) → копия `assets/svg/icons/no_photography.svg` → запись в `docs/design/system/nox-assets/icons/icons.json` (+counts) → `make generate` → добавить `static SvgGenImage get noPhotography => Assets.svg.icons.noPhotography;` в `lib/design/nox_icons.dart` (research.md R11; SVG-only, без icon-шрифта).
- [ ] T019 [US2] Создать `AppQrOverlayWidget` в `lib/presentation/widgets/qr/app_qr_overlay_widget.dart`: прицел stroke `NoxBrand.white` (#FAFAFA) 3dp углы `NoxRadius.m`, маска `#000000`@55% (задокументированный brand-fixed `const`, ссылка `design-system.md` §9.9), инструкция `qrAimHint` текстом `NoxBrand.white`; ≈70% ширины. Контракт — `contracts/widgets.md` (зависит от T002).
- [ ] T020 [US2] Создать `QrScanPage` в `lib/presentation/pages/qr_scan_page/qr_scan_page.dart` (`StatefulWidget`, БЕЗ BLoC): мобайл — `Scaffold`+сплошной `AppBar`(back + actions фонарик `NoxIcons.flashlightOff`/`flashlightOnFill` + смена камеры `NoxIcons.cameraswitch`, тултипы; no-op `// TODO(backend):`) + нейтральный плейсхолдер (`surfaceContainerHighest`) + `AppQrOverlayWidget` + нижний `Enter manually`; десктоп — `AppWindowTitlebarWidget('NOX · Scan QR')` + вьюфайндер ≈300dp + `qrDesktopTitle` + `qrDesktopHelper` с manual-entry-ссылкой; `QrScanState{scanning,permissionDenied,inlineError,fatal}` через debug-`SegmentedButton` (`kDebugMode && demo`); permission-denied — непрозрачная `surface` (мобайл) / `AppOnboardCardWidget` с `NoxIcons.noPhotography`+`Open settings` (десктоп); invalid → snackbar `qrInvalidSnackbar`; fatal → `AppErrorPage`; успех single-shot → `RoutePlaceholderPage('Login auto-submit (2.1)')` `// TODO(backend):`; `route()`/`routeDemo()`→`/onboarding/qr-scan` (зависит от T019, T018, T005, T002).
- [ ] T021 [US2] Активировать строку `2.2` (`route: QrScanPage.routeDemo`, раздел `Onboarding`) в `screens_gallery_page.dart` (+import) + проверка навигации в gallery-тесте (зависит от T020).
- [ ] T022 [P] [US2] Widget-тест `QrScanPage` в `test/presentation/pages/qr_scan_page/qr_scan_page_test.dart`: состояния через debug-контрол, permission-denied панель/карточка, invalid-snackbar, fatal-навигация (зависит от T020).
- [ ] T023 [P] [US2] Golden-тест `QrScanPage` (light/dark, scanning + permission-denied; десктоп) в `test/presentation/pages/qr_scan_page/qr_scan_page_golden_test.dart` + бейзлайны; зафиксировать, что overlay-цвета не меняются между темами (зависит от T020).
- [ ] T024 [P] [US2] Widget+golden тест `AppQrOverlayWidget` (brand-fixed #FAFAFA/#000@55% идентичны light/dark) в `test/presentation/widgets/qr/app_qr_overlay_widget_*.dart` (зависит от T019).

**Checkpoint**: US2 независимо тестируема.

---

## Phase 5: User Story 3 — Установка имени пользователя (Priority: P2)

**Goal**: Экран 2.3: labeled-поле (32 + counter + спиннер), клиентская charset-валидация + debounced проверка занятости (case-sensitive); `Done`/`Skip`; онбординг-хром.

**Independent Test**: Открыть Set username; поле = `User<random>`; недопустимый символ → charset-ошибка; «занятое» имя из мок-набора (после debounce) → `This name is taken`; свободное → `Done` enabled; пусто → только `Skip`.

- [ ] T025 [US3] Создать `SetUsernameBloc`-трио в `lib/presentation/pages/set_username_page/bloc/{set_username_state.dart,set_username_event.dart,set_username_bloc.dart}`: value-state (`name`/`status`/`outcome`); `nameChanged` с `debounceRestartable()` → charset-валидация (`[A-Za-z0-9._-]`) → проверка занятости (мок, **case-sensitive**); `donePressed` через `executeLogic(onError:)`; `setOutcome`. См. data-model.md (зависит от T003, T004).
- [ ] T026 [US3] Создать `SetUsernamePage` в `lib/presentation/pages/set_username_page/set_username_page.dart`: десктоп — `AppOnboardCardWidget` + `AppWindowTitlebarWidget('NOX · Set up')`, мобайл — `Scaffold`+`AppBar`(wordmark+hairline); `AppLabeledFieldWidget(label:usernameLabel, maxLength:32, helperText:usernameHelper, controller=предзаполнен 'User…')`; `FilledButton` `Done` + `TextButton` `Skip`; исходы → `RoutePlaceholderPage('Chats shell (4.1)')` / race-taken inline / `AppErrorPage`; `route()`/`routeDemo()`→`/onboarding/set-username` (зависит от T005, T006, T025, T002).
- [ ] T027 [US3] Активировать строку `2.3` (`route: SetUsernamePage.routeDemo`, раздел `Onboarding`) в `screens_gallery_page.dart` (+import) + gallery-тест (зависит от T026).
- [ ] T028 [P] [US3] `bloc_test` `SetUsernameBloc` в `test/presentation/pages/set_username_page/bloc/set_username_bloc_test.dart`: charset-инвалид, debounce→checking→valid/taken (case-sensitive), race-taken/fatal (зависит от T025).
- [ ] T029 [P] [US3] Widget-тест `SetUsernamePage` в `test/presentation/pages/set_username_page/set_username_page_test.dart`: prefilled/charset/taken/empty/valid, `Done`/`Skip` (зависит от T026).
- [ ] T030 [P] [US3] Golden-тест `SetUsernamePage` (light/dark; prefilled/taken/charset/empty; десктоп-`OnboardCard`) + бейзлайны (зависит от T026).

**Checkpoint**: US3 независимо тестируема.

---

## Phase 6: User Story 4 — Создание чата (Priority: P3)

**Goal**: Экран 6.1: labeled-поле (64 + counter + спиннер, charset свободный) + debounced проверка уникальности; мобайл полноэкранный, десктоп — модальный `Dialog(460)` с `Cancel`+`Create`.

**Independent Test**: Открыть Create chat; «занятое» имя → `This name is taken`, свободное → `Create` enabled; debug submit: success/network/fatal; мобайл fullscreen / десктоп scrim+`Dialog(460)`.

- [ ] T031 [US4] Создать `CreateChatBloc`-трио в `lib/presentation/pages/create_chat_page/bloc/{create_chat_state.dart,create_chat_event.dart,create_chat_bloc.dart}`: value-state (`name`/`status`/`outcome`); `nameChanged` с `debounceRestartable()` → проверка уникальности (мок, charset свободный); `createPressed` через `executeLogic(onError:)`; `setOutcome`. См. data-model.md (зависит от T003, T004).
- [ ] T032 [US4] Создать `CreateChatPage` в `lib/presentation/pages/create_chat_page/create_chat_page.dart`: width-adaptive (`LayoutBuilder`/`Constants.railBreakpoint`) — мобайл полноэкранный `Scaffold`+`AppBar(title:createChat 'New chat', back)`; десктоп — `scrim` + центр. `Dialog(maxWidth≈460)` с заголовком, полем и `Cancel`(`TextButton`)+`Create`(`FilledButton`), закрытие по `Cancel`/scrim без подтверждения (`// TODO(M3): real showDialog from shell`); `AppLabeledFieldWidget(label:createChatNameLabel, maxLength:64, placeholder:createChatNameHint)`; исходы → `RoutePlaceholderPage('Chat thread (5.2)')` / network inline (`Create` enabled) / `AppErrorPage`; `route()`/`routeDemo()`→`/create/chat` (зависит от T006, T031, T002).
- [ ] T033 [US4] Активировать строку `6.1` (`route: CreateChatPage.routeDemo`, раздел `Create`) в `screens_gallery_page.dart` (+import) + gallery-тест (зависит от T032).
- [ ] T034 [P] [US4] `bloc_test` `CreateChatBloc` в `test/presentation/pages/create_chat_page/bloc/create_chat_bloc_test.dart`: debounce→checking→valid/taken, success/network/fatal (зависит от T031).
- [ ] T035 [P] [US4] Widget-тест `CreateChatPage` (мобайл fullscreen + десктоп `Dialog` с `Cancel`/`Create`/scrim-dismiss) в `test/presentation/pages/create_chat_page/create_chat_page_test.dart` (зависит от T032).
- [ ] T036 [P] [US4] Golden-тест `CreateChatPage` (light/dark; мобайл fullscreen + десктоп `Dialog`; taken/valid) + бейзлайны (зависит от T032).

**Checkpoint**: US4 независимо тестируема.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T037 [P] Обновить `docs/roadmap.md`: отметить `2.1`/`2.2`/`2.3`/`6.1` `[x]` в таблице этапа M2, обновить счётчик прогресса (7 → 11 / 17), добавить новые блоки в реестр §6 (онбординг-хром `AppOnboardCardWidget`, семейство полей-ввода `AppIdFieldWidget`/`AppLabeledFieldWidget`, QR-overlay `AppQrOverlayWidget`).
- [ ] T038 [P] Добавить 4 экрана M2 в `test/presentation/widgets/accessibility_test.dart` (tap-targets ≥48, `textScaler 2.0` без overflow).
- [ ] T039 Полный `make gate` (analyze без ошибок, все widget+bloc-тесты) + `make golden-verify` для всех новых goldens; устранить дрейф. Дополнительно (FR-006/SC-007): grep-проверить маркеры `TODO(backend):` у всех заглушек (камера/permission/submit/availability/Scan QR/create) и отсутствие кириллицы в UI-строках `lib/presentation` (`grep -rPn "[\x{0400}-\x{04FF}]" lib/presentation` — допустимы только не-UI английские комментарии).
- [ ] T040 [P] Ручная проверка десктопа (≥840) для 4 экранов по `quickstart.md`: Login/Username — `OnboardCard(440)`+`TitleBar`; QR — `TitleBar`+вьюфайндер≈300dp+`OnboardCard`-denied; Create — scrim+`Dialog(460)` с `Cancel`/`Create`.

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → истории (Phase 3–6) → **Polish (Phase 7)**.
- **Foundational блокирует все истории**: микрокопия (T002) — всем; `OnboardingMockData` (T003) — US1/US3/US4; debounce-helper (T004) — US3/US4; `AppOnboardCardWidget` (T005) — US1/US2/US3; `AppLabeledFieldWidget` (T006) — US3/US4.
- **Истории независимы между собой** (нет кросс-стори зависимостей кода) — реализуются и тестируются по отдельности после Foundational.
- **Общий файл `screens_gallery_page.dart`**: задачи активации (T013, T021, T027, T033) и его тест правят ОДИН файл — выполнять **последовательно** (не параллелить между историями).
- Внутри истории: BLoC/виджеты → страница → активация Галереи → тесты. Порядок приоритетов: US1(P1) → US2(P2) → US3(P2) → US4(P3).
- Каждая страница использует существующие M1 `RoutePlaceholderPage`/`AppErrorPage`/`AppWindowTitlebarWidget`/`AppWordmarkWidget`/`AppSplashHairlineWidget`/`AppSpinnerWidget` (уже в `lib/`, без новых задач).

## Parallel Execution Examples

- **Foundational**: T002 ∥ T003 ∥ T004 ∥ T005 ∥ T006 (разные файлы); затем T007 ∥ T008 (тесты виджетов).
- **US1**: T009 → T010; T011 ∥ (T009→T010); затем T012 → T013; тесты T014 ∥ T015 ∥ T016 ∥ T017.
- **US2**: T018 ∥ T019 → T020 → T021; тесты T022 ∥ T023 ∥ T024.
- **US3**: T025 → T026 → T027; тесты T028 ∥ T029 ∥ T030.
- **US4**: T031 → T032 → T033; тесты T034 ∥ T035 ∥ T036.
- **Polish**: T037 ∥ T038 ∥ T040; затем T039 (полный gate — последний).

## Implementation Strategy

- **MVP = User Story 1 (Login)** — первая поставка (предпосылки: Setup + Foundational T001–T008). Открывается из Галереи, моно ID-поле + `Paste`, исходы на placeholder/реальный 3.1, тесты зелёные. Вводит онбординг-хром (`AppOnboardCardWidget`) и первое поле семейства (`AppIdFieldWidget`) + первый продуктовый BLoC.
- **Инкременты**: US2 (QR scan, +`no_photography`, brand-fixed overlay) → US3 (Set username, charset+debounce) → US4 (Create chat, десктоп-`Dialog`). Каждая — самостоятельный тестируемый прирост, отмечаемый в `docs/roadmap.md`.
- После каждой истории — `make gate` зелёный + golden-бейзлайны сгенерированы (`make golden-update`).
- Sweet-spot для одной сессии: Foundational + US1 (MVP), затем по одной истории. BLoC-конвенция (`BaseBloc.executeLogic` всегда с `onError`; `bloc_test` ассертит bare-имена) — единая на US1/US3/US4.

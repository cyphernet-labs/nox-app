# Research — Этап M2 (Онбординг-формы)

Phase 0 плана. Технический контекст известен (стек запинен блюпринтом), открытых вопросов спеки нет (разрешены в `## Clarifications`). Ниже — зафиксированные технические решения по реализации. Формат: **Решение / Обоснование / Альтернативы**. Все ссылки на код проверены против реального `lib/` (research-проход 2026-06-20).

## R1. Управление состоянием: BLoC для 2.1/2.3/6.1, без BLoC для 2.2

- **Решение**: `LoginPage` (2.1), `SetUsernamePage` (2.3), `CreateChatPage` (6.1) получают **Freezed-BLoC** (`LoginBloc`/`SetUsernameBloc`/`CreateChatBloc`) — первые продуктовые BLoC в приложении. Форма «всегда живая», поэтому используется **single-variant value-state с `copyWith`** (как `AppRootState`: `@freezed abstract class <Page>State`), хранящий ввод + `enum`-статус + флаги (`canSubmit`/`canPaste`/availability). `QrScanPage` (2.2) — **без BLoC**: `StatefulWidget` + локальное состояние (mock permission/scan), управляемое debug-контролом.
- **Обоснование**: Блюпринт `05` §5.1 — навигабельная страница с реальной async-логикой обязана владеть BLoC; у форм 2.1/2.3/6.1 есть async (debounced проверка доступности, submit с loading), даже на фейковых `Future`. M1-carve-out (презентационные экраны без async) на них не распространяется. Roadmap M2 явно называет `LoginBloc`/`SetUsernameBloc`/`CreateChatBloc`. 2.2 не имеет async-валидации (камера заглушена, состояния — debug-переключатель), поэтому подпадает под carve-out 5.1 и остаётся `StatefulWidget`.
- **Паттерн привязки** (по `ItemListBloc`/`AppRootBloc`): BLoC **не** регистрируется в DI; `State extends BaseStatePage<Page>` держит `late final <Page>Bloc _bloc;`, создаёт в `initState` (`.._bloc = <Page>Bloc()..add(const Initialize())`), закрывает в `dispose`, рендерит `BlocProvider<…>.value(value:_bloc, child: BlocBuilder(...))` с `state.when/switch`. Репозитории-заглушки резолвятся **внутри** BLoC через `getIt` (в M2 их нет — логика на фейковых `Future`). `BaseBloc.executeLogic` вызывается **всегда с `onError`** (иначе исключение глотается) → эмит error/fatal-состояния.
- **Альтернативы**: оставить 2.1/2.3/6.1 на `StatefulWidget` без BLoC (как M1) — отклонено: у них реальная async-логика, это противоречит 5.1 и roadmap. Sealed-trio `Initializing/Initialized/Error` — отклонено для форм в пользу value-state+`copyWith` (форма не имеет фазы «инициализации», она сразу интерактивна; sealed-trio оставлено для будущих data-загрузочных страниц).

## R2. Debounce проверки доступности (2.3/6.1)

- **Решение**: Debounce ~300 мс реализуется **внутри BLoC** кастомным `EventTransformer` поверх уже доступного `stream_transform` (транзитивно через `bloc_concurrency`) либо `rxdart` (`debounceTime`): `EventTransformer<E> _debounce<E>() => (events, mapper) => events.debounce(const Duration(milliseconds: 300)).switchMap(mapper);` и регистрация `on<NameChanged>(_onNameChanged, transformer: _debounce())`. Сама проверка занятости — `BaseBloc.executeLogic(..., onError: ...)` с фейковым `Future.delayed` против мок-набора.
- **Обоснование**: В кодовой базе нет debounce-утилиты и нет `Timer` (grep пуст) — строим в BLoC, а не в виджете (никаких `Timer` в `State`). Зеркалит существующую конвенцию `on<LoadItems>(..., transformer: sequential())` (`item_list_bloc.dart`). `switchMap` отменяет устаревшие проверки (корректно при быстром вводе). Новых зависимостей не нужно.
- **Альтернативы**: `Timer`-debounce в `State` — отклонено (логика в виджете, против блюпринта). Новый пакет `easy_debounce` — отклонено (зависимость избыточна).

## R3. Заглушки серверо-зависимых состояний: мок-набор + debug-переключатель

- **Решение**: Два механизма (Clarifications): (а) **фиксированный мок-набор** — `const` множества «занятых» имён (2.3), «занятых» имён чатов (6.1) и «зарезервированных/зарегистрированных» ID (2.1) в `lib/general/onboarding_mock_data.dart`; debounced-проверка сверяется с ним → happy/taken-путь воспроизводится вводом конкретных значений (проверка **case-sensitive** для имён, FR-032). (б) **debug-переключатель исходов** — паттерн `routeDemo` из M1 (`AppErrorPage` Variant B): страница имеет `const <Page>Page({... this.demo = false})` + отдельный `static Route routeDemo()` (демо: `demo:true`); dev-контрол (`SegmentedButton`) виден только при `kDebugMode && demo` и эмитит debug-событие в BLoC (`setOutcome(...)`). Галерея активирует строку **через `routeDemo`**, чтобы контролы были доступны.
- **Обоснование**: Clarifications/FR-005. Мок-набор даёт «реалистичный» ввод; debug-`SegmentedButton` покрывает исходы input/submit (новый ID/зарегистрированный/inline-error/fatal; race-taken; network). Зеркалит три реальных M1-варианта debug-контролов (`SplashOutcome` enum-bar, `AppErrorPage` demo+`SegmentedButton`, `Notifications` mocked-enum+`SegmentedButton`), все за `kDebugMode`.
- **Альтернативы**: только debug-переключатель (без мок-набора) — отклонено (теряется реалистичная демонстрация ввода); только мок-набор — отклонено (исходы submit/fatal недетерминированно не показать).

## R4. Онбординг-хром — `AppOnboardCardWidget` + десктоп-`TitleBar`

- **Решение**: Новый виджет `AppOnboardCardWidget` — голова `logo (Assets.png.logo) + AppWordmarkWidget + AppSplashHairlineWidget` над слотом контента (`child`); на десктопе — центральная карточка `maxWidth ≈ 440` (`Center`→`ConstrainedBox`). Десктоп-оконный фрейм — существующий `AppWindowTitlebarWidget(title: ...)` (per-screen заголовок `NOX · Sign in` / `NOX · Set up` / `NOX · Scan QR`). Мобайл-вариант — обычный `Scaffold` + `AppBar`(wordmark `NOX`) с hairline под ним (паттерн M1 standalone). Переиспользуют 2.1, 2.3 и **desktop-denied 2.2**.
- **Обоснование**: Корпус `04-login.md`/`05-username.md`/`06-qr.md`: «Title bar (NOX · …) + centered OnboardCard (440): logo + wordmark + brand hairline + …». `AppWordmarkWidget({color})`, `AppSplashHairlineWidget()`, `AppWindowTitlebarWidget({title})` уже существуют (M1) — `OnboardCard` их компонует, не дублируя. FR-009/FR-015/FR-035/FR-026.
- **Альтернативы**: отдельные карточки на каждый экран — отклонено (дивергенция, FR-009 запрещает). Расширять `AppDetailScaffoldWidget` — отклонено (тот — для settings-leaf без логотипа/карточки).

## R5. Семейство полей-ввода — `AppIdFieldWidget` + `AppLabeledFieldWidget`

- **Решение**: M2 вводит **первый реальный текстовый ввод** в приложении (существующие `AppComposerWidget`/`AppSearchBarWidget` — display-only `Text`, не используются). Два новых виджета:
  - `AppIdFieldWidget` (2.1) — `TextField(maxLines: null)` (моно, многострочный, растёт по высоте), suffix-`IconButton` `Paste` (`NoxIcons.contentPaste`), placeholder `Paste or enter your ID`. Моно-стиль — новый фактори `AppTextStyleTokens.monoBody({color})` поверх `Roboto Mono` (семейство `noxMonoFamily`, **подтверждено в `pubspec.yaml:92`**). Без клиентской валидации формата (FR-011).
  - `AppLabeledFieldWidget` (2.3, 6.1) — `TextField` + `maxLength` (32 / 64) со встроенным counter (тема `noxInputDecorationTheme` уже задаёт `counterStyle`/`helperStyle`), постоянный `helperText`, `errorText`, suffix-`AppSpinnerWidget(size:18)` в состоянии Checking-availability. Параметры — `label`, `helperText`, `maxLength`, `controller`, `errorText`, `checking`, `onChanged`, `onSubmitted`.
- **Обоснование**: FR-009/FR-010/FR-030/FR-040. Плоский Material `TextField` тематизирован (`noxInputDecorationTheme`: `OutlineInputBorder` `NoxRadius.xs`, focused `primary` 2dp, error `cs.error`, themed counter/helper). `AppSpinnerWidget({size=24,color,strokeWidth=3})` уже есть. Моно через `copyWith(fontFamily: noxMonoFamily)`.
- **Альтернативы**: переиспользовать `AppComposerWidget`/`AppSearchBarWidget` — отклонено (display-only, не editable). Хардкод моно-стиля в виджете — отклонено в пользу токен-фактори (переиспользуемо, токен-дисциплина).

## R6. QR-overlay (2.2) — brand-fixed прицел/маска/инструкция

- **Решение**: Новый виджет `AppQrOverlayWidget` (прицел + затемняющая маска + верхняя инструкция) поверх **нейтрального плейсхолдера** (вместо живого видео — тематический `surfaceContainerHighest`-fill; камера заглушена). Brand-fixed значения (вне `ColorScheme`, `design-system.md` §9.9): прицел stroke `NoxBrand.white` (#FAFAFA), 3dp, углы `NoxRadius.m` (12), размер ≈70% ширины; инструкция текст `NoxBrand.white`; **маска `#000000` @ 55%** — задокументированный brand-fixed `const` внутри виджета overlay (виджет — санкционированное brand-fixed исключение, аналогично `lib/design/theme`/splash/QR-surface; `NoxBrand` чисто-чёрного @55% не содержит, генерируется из токенов — править его тяжело). `NoxBrand.white` уже даёт #FAFAFA.
- **Обоснование**: FR-021/FR-003/SC-006. `NoxBrand.white = 0xFFFAFAFA`, `NoxRadius.m = 12` — подтверждены. Token-дисциплина: единственный raw-литерал (`0x8C000000`) живёт в brand-fixed overlay-виджете с комментарием-ссылкой на §9.9.
- **Альтернативы**: `colorScheme.scrim` (#000000) для маски — отклонено (§9.9 требует brand-fixed, не из роли темы). Добавлять `NoxBrand.qrScrim` в генерируемый файл — отклонено (требует правки tokens JSON; избыточно для одного литерала).

## R7. Login (2.1)

- **Решение**: `LoginPage` (`route()`/`routeDemo()`). Body — `AppIdFieldWidget` + primary `FilledButton` `Sign in` (full-width, спиннер внутри в Loading) + secondary `TextButton` `Scan QR`. `Paste` — `Clipboard.getData(Clipboard.kTextPlain)` (`flutter/services.dart`, уже импортируется в `splash_page.dart`), disabled при пустом буфере. `Sign in` enabled при непустом вводе (FR-011). Десктоп — `AppOnboardCardWidget` + `AppWindowTitlebarWidget('NOX · Sign in')`; мобайл — `Scaffold`+`AppBar`(wordmark+hairline). Исход — `LoginBloc` по debug-переключателю: новый ID → `RoutePlaceholderPage('Set username (2.3)')`; зарегистрированный → `RoutePlaceholderPage('Chats shell (4.1)')`; inline-error (формат `Invalid identifier` / сеть) → `errorText`; fatal → `AppErrorPage.route(ErrorPageParams.fatal(blocking))`. `Scan QR` → заглушка (`// TODO(backend):`).
- **Обоснование**: FR-010…016. `RoutePlaceholderPage`/`AppErrorPage` уже есть (M1) — переиспользуем для исходов/fatal без дублирования.
- **Альтернативы**: клиентская валидация формата ID — отклонено (Clarifications: server-only).

## R8. QR scan (2.2)

- **Решение**: `QrScanPage` (`StatefulWidget`, без BLoC). Мобайл — `Scaffold` + сплошной `AppBar` (`surface`, адаптивный), back + actions `NoxIcons.flashlightOff`/`flashlightOnFill` (toggle, тултип `Flashlight`) и `NoxIcons.cameraswitch` (тултип `Switch camera`); body — нейтральный плейсхолдер + `AppQrOverlayWidget` + нижний `Enter manually`. Десктоп — `AppWindowTitlebarWidget('NOX · Scan QR')` + центрированный вьюфайндер ≈300dp + заголовок `Scan a QR code` + helper `Point your webcam at a code, or enter the ID manually.` с manual-entry-ссылкой; **permission-denied внутри `AppOnboardCardWidget`** (иконка `NoxIcons.noPhotography` + `Open settings`). Состояния (debug-`SegmentedButton`): Scanning / Permission-denied (непрозрачная `surface`/`OnboardCard`) / inline-error (snackbar `This QR code is invalid. Try another one.`, скан продолжается) / fatal → 3.1; успех — single-shot → debug-плейсхолдер. Фонарик/смена камеры/permission/deep-link — no-op (`// TODO(backend):`).
- **Обоснование**: FR-020…026 + Clarifications (десктоп по `06-qr.md`). Permission-prompt (OS-диалог) не воспроизводится (FR-022/SC-002). Камера (`mobile_scanner`) — Фаза 2.
- **Альтернативы**: реальная камера/скан сейчас — отклонено (плагин вне UI-scope). Статичное мок-фото — отклонено (Clarifications: нейтральный плейсхолдер, без выбросных ассетов).

## R9. Set username (2.3)

- **Решение**: `SetUsernamePage` + `SetUsernameBloc`. `AppLabeledFieldWidget(label:'Name', maxLength:32, helperText, controller=предзаполнен 'User<random>')`. **Клиентская charset-валидация** (`[A-Za-z0-9._-]`) → `errorText` charset; затем debounced (R2) проверка занятости (R3, **case-sensitive**) → suffix-спиннер → valid/taken. Пустое поле → `Done` disabled, `Skip` доступен, placeholder `How others will see you`. primary `Done` (спиннер в Loading-submit) + secondary `Skip`. Исход submit (debug): успех → `RoutePlaceholderPage('Chats shell (4.1)')`; race-taken → inline-error+фокус; fatal → 3.1. `Skip`/back → placeholder. Десктоп — `AppOnboardCardWidget` + `AppWindowTitlebarWidget('NOX · Set up')`. Зарезервированных имён нет (FR-031/Q5). Edit-аффорданс (если нужен) — `NoxIcons.edit`.
- **Обоснование**: FR-030…035. `User<random>` — заглушка значения (FR-030).
- **Альтернативы**: серверная charset-проверка (как у ID) — отклонено (спека 2.3: charset клиентский).

## R10. Create chat (6.1)

- **Решение**: `CreateChatPage` + `CreateChatBloc`. `AppLabeledFieldWidget(label:'Chat name', maxLength:64, placeholder:'e.g. Random thoughts')`, charset **не ограничен** (нет charset-ошибки), debounced проверка уникальности (R2/R3) → спиннер → valid/taken. primary `Create` (full-width, спиннер в Loading). **Width-adaptive** (`LayoutBuilder` по `Constants.railBreakpoint`): мобайл — полноэкранный `Scaffold` + `AppBar(title:'New chat', back)`; десктоп — `scrim` + центрированный `Dialog` (`ConstrainedBox maxWidth≈460`) с заголовком `New chat`, полем и парой `Cancel`(`TextButton`) + `Create`(`FilledButton`); `Cancel`/тап по scrim — закрытие без подтверждения. Исход (debug): успех → `RoutePlaceholderPage('Chat thread (5.2)')`; network-error (`Could not create chat…`, `Create` снова enabled); fatal → 3.1.
- **Обоснование**: FR-040…045 + `07-create.md`. Реального `showDialog` из шелла нет (нет шелла) — на этапе M2 модальный диалог **симулируется внутри pushed-route** (scrim + центр. карточка); реальный вызов `showDialog` из окна чатов — задача M3/флоу (`// TODO(M3):`). `noxDialogTheme` уже в теме.
- **Альтернативы**: `showModalBottomSheet` на мобайле — отклонено (спека 6.1: мобайл — полноэкранный push, не sheet). Реальный `showDialog` из несуществующего шелла — невозможно в standalone-превью.

## R11. Иконки — добавить `no_photography`

- **Решение**: Добавить **ровно один** SVG-глиф `no_photography` (для permission-denied 2.2) по M1-конвейеру (R5 фичи 004): источник Material Symbols Rounded (w400, opsz24, grade0, `viewBox 0 -960 960 960`, один `<path fill="currentColor">`, FILL 0) → `docs/design/system/nox-assets/icons/svg/no_photography.svg` → копия в `assets/svg/icons/no_photography.svg` (pubspec не правится — каталог глобится) → запись в `icons.json` (+counts) → `make generate` (→ `Assets.svg.icons.noPhotography`) → `static SvgGenImage get noPhotography => Assets.svg.icons.noPhotography;` в `NoxIcons`. Icon-шрифт не подключается (SVG-only).
- **Обоснование**: FR-026/Принцип IV. Все прочие M2-глифы уже есть в `NoxIcons` (`contentPaste`, `flashlightOff`/`flashlightOnFill`, `cameraswitch`, `qrCode`, `qrCodeScanner`, `arrowBack`, `check`, `error`) — добавлять не нужно.
- **Альтернативы**: `material_symbols_icons`/icon-шрифт — отклонено (SVG-only). Переиспользовать существующий глиф вместо `no_photography` — отклонено (корпус `06-qr.md` явно называет `no_photography`).

## R12. Микрокопия (`TextConstants`)

- **Решение**: Добавить EN-строки M2 в `lib/general/text_constants.dart`, сгруппированные комментариями по экранам (`// Login (2.1)`, `// QR scan (2.2)`, `// Set username (2.3)`, `// Create chat (6.1)`). **Переиспользовать** существующие: `tooltipBack` (`Back`), `actionOpenSettings` (`Open settings`), `errorNetworkMessage` (сетевые ошибки), `comingSoon`. Новые: Login — `signIn`, `loginIdLabel` (`Your ID`), `actionPaste`, `loginIdHint`, `loginInvalidId`; QR — `tooltipFlashlight`, `tooltipSwitchCamera`, `qrAimHint`, `qrEnterManually`, `qrPermissionTitle`, `qrPermissionMessage`, `qrInvalidSnackbar`, `qrDesktopTitle`, `qrDesktopHelper`; Username — `usernameLabel` (`Name`), `usernameSubtitle`, `usernameHelper`, `usernameCharsetError`, `usernameTakenError`, `actionDone`, `actionSkip`; Create — `createChatNameLabel`, `createChatNameHint`, `createChatTakenError`, `actionCreate`, `actionCancel`. Per-screen TitleBar-заголовки (`NOX · Sign in`/`NOX · Set up`/`NOX · Scan QR`) — отдельные константы.
- **Обоснование**: FR-004/Принцип V. Дублей избегаем (reuse существующих ключей).
- **Альтернативы**: строковые литералы в виджетах — отклонено (Принцип V/FR-004).

## R13. Навигация, заглушки переходов, активация Галереи

- **Решение**: Каждый экран — `static Route<void> route()` + `static Route<void> routeDemo()` → `MaterialPageRoute` с `RouteSettings(name)`: `/onboarding/login`, `/onboarding/qr-scan`, `/onboarding/set-username`, `/create/chat`. Галерея активируется добавлением `import` + заменой `route: null` → `<Page>.routeDemo` в существующих строках (id/title/section не менять): 2.1 `Login`/Onboarding, 2.2 `QR scan`/Onboarding, 2.3 `Set username`/Onboarding, 6.1 `Create chat`/**Create**. Заглушки переходов (исходы/`Scan QR`/`Done`/`Skip`/`Create`-success) → переиспользуемый M1 `RoutePlaceholderPage(destinationLabel:...)`; fatal → `AppErrorPage`.
- **Обоснование**: FR-001/FR-008 + конвенция M1 (`_ScreenEntry{id,title,route}`; `route==null` → `Coming soon`). Раздел Галереи для 6.1 — `Create` (не `Chats`).
- **Альтернативы**: роутер — отклонено (конвенция «без роутера»). Новые строки Галереи — отклонено (строки уже есть, только активируем).

## R14. Тестирование

- **Решение**: На каждый экран — `*_test.dart` (widget, через `pumpApp`, в `BlocProvider` где нужен BLoC) + `*_golden_test.dart` (`@Tags(['golden'])`, light+dark, демо-состояния через debug-контрол; бейзлайны `make golden-update`). На 4 новых виджета — widget+golden. На `LoginBloc`/`SetUsernameBloc`/`CreateChatBloc` — `bloc_test` (bare-имена сабстейтов; `Error` только при `onError`; debounce-тесты с `await`-задержкой). Спиннер-голдены — `settle: false`. Активацию 4 строк Галереи — в gallery-тесте. Перед сдачей — `make gate`.
- **Обоснование**: Конвенции `test/` + DoD roadmap; goldens локальные (macOS), вне CI; `bloc_test` против test-env DI.
- **Альтернативы**: только widget — отклонено (DoD требует golden light/dark + BLoC-логика требует bloc_test).

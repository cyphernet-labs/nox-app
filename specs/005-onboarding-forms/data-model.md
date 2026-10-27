# Data Model — Этап M2 (Онбординг-формы)

UI-only фаза: «модель» — это BLoC-состояния форм (Freezed value-state с `copyWith`), presentation-энумы, маленькие мок-наборы и наборы визуальных состояний по экранам. Нет персистентности и сетевых сущностей; «репозитории» — фейковые `Future` против `const` мок-наборов. Существующие энумы (`FileType`/`MessageStatus`/`AppTab`) и BLoC (`AppRootBloc`/`ItemListBloc`) не затрагиваются.

## BLoC-состояния и события (новые Freezed-типы)

Форма всегда интерактивна → **single-variant value-state** (`@freezed abstract class … with copyWith`), как `AppRootState`. Только `*.freezed.dart` (без `*.g.dart`). `Event` — `@freezed sealed`. Логика-геттеры — в `extension … on <Page>State`.

### Login (2.1) — `LoginBloc`

| Тип | Файл | Поля / значения | Назначение |
|---|---|---|---|
| `LoginStatus` (enum) | `bloc/login_state.dart` | `idle`, `loading`, `inlineErrorFormat`, `inlineErrorNetwork` | Текущий UI-статус формы входа. |
| `LoginOutcome` (enum, debug) | `bloc/login_state.dart` | `newId`, `registered`, `inlineErrorFormat`, `inlineErrorNetwork`, `fatal` | Заглушечный исход submit; выбирается debug-`SegmentedButton`. |
| `LoginState` | `bloc/login_state.dart` | `id: String`, `status: LoginStatus`, `outcome: LoginOutcome`, `canPaste: bool` | value-state. Геттеры (extension): `canSubmit => id.trim().isNotEmpty && status != loading`; `errorText` по `status`. |
| `LoginEvent` | `bloc/login_event.dart` | `initialize()`, `idChanged(String)`, `pastePressed()`, `signInPressed()`, `setOutcome(LoginOutcome)`, `clipboardChanged(bool hasText)` | Без клиентской валидации формата (FR-011). |

### Set username (2.3) — `SetUsernameBloc`

| Тип | Файл | Поля / значения | Назначение |
|---|---|---|---|
| `UsernameStatus` (enum) | `bloc/set_username_state.dart` | `prefilled`, `checking`, `valid`, `invalidCharset`, `taken`, `empty`, `submitting`, `raceTaken` | Полный вокабуляр состояний 2.3. |
| `UsernameOutcome` (enum, debug) | `bloc/set_username_state.dart` | `success`, `raceTaken`, `fatal` | Исход submit (debug). |
| `SetUsernameState` | `bloc/set_username_state.dart` | `name: String`, `status: UsernameStatus`, `outcome: UsernameOutcome` | value-state (предзаполнен `User<random>`). Геттеры: `canSubmit => status == valid \|\| status == prefilled`; `showSkipOnly => status == empty`; `errorText`. |
| `SetUsernameEvent` | `bloc/set_username_event.dart` | `initialize()`, `nameChanged(String)` (debounced ~300мс), `donePressed()`, `setOutcome(UsernameOutcome)` | charset — клиентский (FR-031); availability — мок (case-sensitive). |

### Create chat (6.1) — `CreateChatBloc`

| Тип | Файл | Поля / значения | Назначение |
|---|---|---|---|
| `CreateChatStatus` (enum) | `bloc/create_chat_state.dart` | `empty`, `checking`, `valid`, `taken`, `submitting`, `inlineErrorNetwork` | Вокабуляр 6.1 (charset-ошибки нет). |
| `CreateChatOutcome` (enum, debug) | `bloc/create_chat_state.dart` | `success`, `inlineErrorNetwork`, `fatal` | Исход submit (debug). |
| `CreateChatState` | `bloc/create_chat_state.dart` | `name: String`, `status: CreateChatStatus`, `outcome: CreateChatOutcome` | value-state. Геттеры: `canSubmit => status == valid`; `errorText`. |
| `CreateChatEvent` | `bloc/create_chat_event.dart` | `initialize()`, `nameChanged(String)` (debounced ~300мс), `createPressed()`, `setOutcome(CreateChatOutcome)` | charset не ограничен (FR-041); availability — мок. |

## Presentation-энумы и мок-данные (2.2 — без BLoC)

| Тип | Файл | Значения / поля | Назначение |
|---|---|---|---|
| `QrScanState` (enum) | `pages/qr_scan_page/qr_scan_page.dart` (private) | `scanning`, `permissionDenied`, `inlineError`, `fatal` | Состояния 2.2; переключаются debug-`SegmentedButton`. Permission-prompt (OS-диалог) НЕ воспроизводится (FR-022/SC-002). |
| `OnboardingMockData` | `lib/general/onboarding_mock_data.dart` | `takenUsernames: Set<String>` (case-sensitive), `takenChatNames: Set<String>`, `registeredIds: Set<String>` | `const` мок-наборы happy/taken-пути проверки доступности (R3); shared, без дивергенции. |

> Debug-исходы (`*Outcome` enum) — за `kDebugMode && demo`; в продуктовом флоу заменяются реальным репозиторием (`// TODO(backend):`).

## Состояния по экранам (визуальный вокабуляр)

Все состояния воспроизводимы на заглушках (мок-набор + debug-переключатель), кроме OS-owned Permission-prompt (2.2).

### 2.1 Login (`LoginPage` / `LoginBloc`)
- `Empty`: поле пустое, `Sign in` disabled, `Paste` disabled при пустом буфере, secondary `Scan QR`.
- `Filled`: непустой ввод → `Sign in` enabled; поле растёт многострочно.
- `Loading`: поле+кнопки disabled, спиннер внутри `Sign in`.
- `Inline-error`: формат `Invalid identifier` / сеть `Could not sign in. Check your connection and try again.` под полем.
- `Fatal` → `AppErrorPage(blocking)` (3.1).
- Десктоп: `OnboardCard(440)` + `TitleBar('NOX · Sign in')`; мобайл: `AppBar(wordmark+hairline)`.
- Исход (debug): новый ID→placeholder(2.3) · зарегистрированный→placeholder(4.1) · format/net→inline · fatal→3.1.

### 2.2 QR scan (`QrScanPage`, без BLoC)
- `Scanning`: нейтральный плейсхолдер + brand-fixed прицел (#FAFAFA,3dp) + маска (#000@55%) + инструкция + `Enter manually`; actions фонарик/смена камеры (no-op).
- `Permission-denied`: непрозрачная `surface` (мобайл) / `OnboardCard` (десктоп) — `Camera access needed` + message + `Open settings` (no-op).
- `Inline-error`: snackbar `This QR code is invalid. Try another one.`; скан продолжается.
- `Fatal` → 3.1. Успех: single-shot → debug-плейсхолдер.
- Десктоп: `TitleBar('NOX · Scan QR')` + вьюфайндер ≈300dp + `Scan a QR code` + helper с manual-entry-ссылкой.

### 2.3 Set username (`SetUsernamePage` / `SetUsernameBloc`)
- `Prefilled`: поле = `User<random>`, counter `N/32`, helperText, `Done` enabled, `Skip` доступен.
- `Checking-availability`: suffix-спиннер (после debounce).
- `Filled-invalid (charset)`: `errorText` charset, `Done` disabled.
- `Filled-invalid (taken)`: `This name is taken`, `Done` disabled.
- `Empty`: placeholder `How others will see you`, `Done` disabled, `Skip`.
- `Filled-valid`: `Done` enabled.
- `Loading-submit`: спиннер в `Done`.
- `Race-taken`: inline-error, фокус в поле. `Fatal` → 3.1.
- Десктоп: `OnboardCard` + `TitleBar('NOX · Set up')`.

### 6.1 Create chat (`CreateChatPage` / `CreateChatBloc`)
- `Empty`: `Create` disabled.
- `Checking-availability`: suffix-спиннер.
- `Filled-invalid (taken)`: `This name is taken`, `Create` disabled (charset-ошибки нет).
- `Filled-valid`: `Create` enabled.
- `Loading-submit`: спиннер в `Create`.
- `Inline-error (network)`: `Could not create chat. Check your connection and try again.`, `Create` снова enabled.
- `Fatal` → 3.1.
- Десктоп: scrim + `Dialog(460)` с `Cancel` + `Create`; мобайл: полноэкранный `Scaffold(New chat, back)`.

## Связи и инварианты

- BLoC создаётся в `initState`, закрывается в `dispose`; `BaseBloc.executeLogic` — **всегда с `onError`** (иначе исключение глотается) → эмит inline-error/fatal.
- Форма — value-state + `copyWith` (нет фазы «инициализации»; страница сразу интерактивна).
- `nameChanged` (2.3/6.1) — debounced ~300мс + `switchMap` (отмена устаревших проверок); проверка занятости 2.3 — **case-sensitive** (`Anna` ≠ `anna`).
- Все исходы submit/`Scan QR`/`Done`/`Skip`/`Create`-success → `RoutePlaceholderPage(destinationLabel)` (M1, переиспользуется); `fatal` → реально существующий `AppErrorPage(blocking)`.
- Brand-fixed overlay 2.2 (#FAFAFA / #000@55%) — вне `ColorScheme`; всё прочее темизируется.
- Мок-наборы (`OnboardingMockData`) — единственный источник happy/taken; debug-`*Outcome` — только исходы submit/fatal/permission.
- `CreateChatPage` — width-adaptive: <840 полноэкранный push, ≥840 scrim+`Dialog(460)`; реальный `showDialog` из шелла — `// TODO(M3):`.

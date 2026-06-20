# Implementation Plan: Экраны этапа M2 — Онбординг-формы

**Branch**: `005-onboarding-forms` | **Date**: 2026-06-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/005-onboarding-forms/spec.md`

## Summary

Реализовать визуальный слой четырёх экранов этапа M2 — **Login / вход по идентификатору (2.1)**, **QR scan / сканирование QR (2.2)**, **Set username / установка имени (2.3)**, **Create chat / создание чата (6.1)** — как самостоятельные Flutter-страницы, открываемые из «Галереи экранов» (M0), мультиплатформенно (мобайл + десктоп по ширине окна), на дизайн-токенах, со всеми визуальными состояниями на заглушечных данных. Этап вводит два переиспользуемых семейства блоков: **онбординг-хром** (`AppOnboardCardWidget` = логотип + wordmark + hairline + слот контента; десктоп-`TitleBar` через существующий `AppWindowTitlebarWidget`) и **семейство полей-ввода** (`AppIdFieldWidget` — моно многострочное ID-поле с `Paste`; `AppLabeledFieldWidget` — labeled `TextField` + counter + suffix-спиннер + `errorText`). Бэкенд вне scope: серверная валидация ID, проверка уникальности, исход входа, создание чата, реальная камера/QR-декод и разрешения ОС заглушены и помечены `// TODO(backend):`.

Технический подход: страницы по конвенции блюпринта (`lib/presentation/pages/<page>_page/`, статический `route()`/`routeDemo()` + `Navigator.push`, без роутера). **M2 вводит первые продуктовые Freezed-BLoC**: `LoginBloc` / `SetUsernameBloc` / `CreateChatBloc` (реальная асинхронная логика формы — debounced проверка доступности, submit с loading — подпадает под дефолт блюпринта `05` §5.1 «async → BLoC»; M1-carve-out на них не распространяется). `QrScanPage` остаётся **без BLoC** (`StatefulWidget`: камера заглушена, состояния permission/scan управляются debug-контролом — презентационный экран). Real-time проверка доступности — фиксированный мок-набор «занятых» имён/ID + debounce ~300 мс внутри BLoC; исходы/ошибки — debug-`SegmentedButton` (паттерн `routeDemo` из M1). Микрокопия EN через `TextConstants`; иконки — SVG `NoxIcons` (добавить ровно один глиф `no_photography`). **Новые зависимости не добавляются** (`mobile_scanner`/`qr_flutter`/`permission_handler` — Фаза 2; debounce строится на уже доступном `stream_transform`/`rxdart`).

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM-pinned), длина строки 140, стоковый `flutter_lints`.

**Primary Dependencies**: `flutter_bloc` 9.1.1, `bloc_concurrency` 0.3.0 (+ транзитивный `stream_transform`), `rxdart` 0.28.0 (доступен `debounceTime`), `freezed` 3.2.5 + `freezed_annotation`, `injectable`+`get_it`, `flutter_screenutil`, `flutter_svg`, `flutter_gen` (assets). **Новые зависимости не добавляются** — камера/QR/разрешения (`mobile_scanner`, `qr_flutter`, `permission_handler`, `app_settings`) откладываются на Фазу 2.

**Storage**: N/A для M2 — UI-only. BLoC-состояния форм — in-memory на время жизни страницы; мок «занятых» имён/ID — `const` наборы (`lib/general/onboarding_mock_data.dart`). Персистентность/Sembast/сеть — backend-фаза.

**Testing**: `flutter_test` + `bloc_test` (для `LoginBloc`/`SetUsernameBloc`/`CreateChatBloc`) + `mockito` (только; mocktail запрещён); golden через локальный харнес `test/utils/golden.dart` (Apple Silicon/macOS, тег `golden`, вне CI). Обязателен `pumpApp` (`test/utils/pump_app.dart`). BLoC-тесты ассертят **bare**-имена сабстейтов; `Error` эмитится только при переданном `onError`.

**Target Platform**: iOS, Android, Windows, Linux, macOS (web вне scope). Один пакет `nox_app`.

**Project Type**: Кросс-платформенное Flutter-приложение (single package), Clean Architecture слоями-папками (M2 затрагивает только presentation + точечно design/general).

**Performance Goals**: 60 fps; debounce проверки доступности ~300 мс (`switchMap` отменяет устаревшие проверки); спиннеры/переходы на `NoxDuration`/`NoxEasing`; никаких циклических анимаций.

**Constraints**: Токен-дисциплина (нет сырых `Color`/`EdgeInsets`/`TextStyle`/overlay-литералов вне `lib/design/theme/` и санкционированного brand-fixed QR-overlay); иконки только SVG `NoxIcons`; микрокопия EN через `TextConstants`; адаптив width-driven по `Constants.railBreakpoint` (840dp) через `LayoutBuilder`; **единственное brand-fixed исключение M2** — camera-overlay 2.2 (маска `#000000`@55%, прицел/инструкция `NoxBrand.white` #FAFAFA), вне `ColorScheme` (`design-system.md` §9.9).

**Scale/Scope**: 4 экрана + 3 BLoC + 4 новых переиспользуемых виджета (`AppOnboardCardWidget`, `AppIdFieldWidget`, `AppLabeledFieldWidget`, `AppQrOverlayWidget`) + 1 новый SVG-иконка (`no_photography`) + активация 4 строк Галереи; переиспользование M1-`RoutePlaceholderPage`/`AppErrorPage`/`AppWindowTitlebarWidget`/`AppWordmarkWidget`/`AppSplashHairlineWidget`/`AppSpinnerWidget`. Тесты widget+golden на каждый экран и виджет + bloc_test на каждый BLoC.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Экраны M2 не работают с содержимым/PII. ID/label/имя чата — вводятся, но не валидируются/не хранятся/не отправляются (заглушки). Нет аналитики/логов с PII. Реальная авторизация/E2EE — вне M2. |
| **II. Спека/дизайн-корпус — источник истины** | ✅ PASS | Строим строго по locked `docs/design/spec/screens/{login,qr-scan,set-username,create-chat}.md` + мобайл/десктоп-корпусам + `spec.md`. Пограничные решения — в `## Clarifications`. Дрейф разрешён в сторону корпуса (ID — server-only; brand-fixed QR-overlay §9.9; десктоп QR по `06-qr.md`; `Cancel`+scrim в 6.1). Out-of-scope не расширяется. |
| **III. Архитектурный блюпринт обязателен** | ✅ PASS | Страницы по конвенции (`pages/<page>_page/`, `route()`, токены, `NoxIcons`, `TextConstants`). **M2 вводит первые продуктовые Freezed-BLoC** (`LoginBloc`/`SetUsernameBloc`/`CreateChatBloc`) — это дефолт блюпринта `05` §5.1 (навигабельная страница с реальной async-логикой → `BaseBloc` + Freezed sealed/value-state, `onError` обязателен). M1-carve-out (презентационные экраны без BLoC) к ним не применяется, т.к. у них есть async (debounce/submit). `QrScanPage` — презентационный, без async → под carve-out 5.1 (`StatefulWidget`, debug-driven). BLoC не регистрируются в DI; репозитории-заглушки резолвятся внутри BLoC. |
| **IV. Верность дизайн-системе** | ✅ PASS | M3 light+dark, только токены; иконки — SVG `NoxIcons` (добавляется один `no_photography` как новый SVG, без icon-шрифтов — Clarifications/FR-026). Brand-fixed QR-overlay 2.2 (`#000000`@55% + #FAFAFA) соблюдён вне `ColorScheme` (§9.9). Моно-поле ID — `Roboto Mono` (уже в `pubspec`). |
| **V. Языковая дисциплина** | ✅ PASS | Спека/план — RU; код/идентификаторы/коммиты — EN; UI-микрокопия — EN (через `TextConstants`); RU в UI отсутствует. |

**Gate (до Phase 0): PASS.** Нарушений нет → раздел Complexity Tracking пуст. Введение первых BLoC — это следование блюпринту, а не отступление.

**Re-check (после Phase 1 design): PASS.** Design-артефакты не вводят новых зависимостей и не нарушают токен-дисциплину. BLoC-форма (value-state + copyWith, как `AppRootState`) и debounce-трансформер согласованы с блюпринтом `05`. Спека↔блюпринт↔код консистентны (Принцип II/III). Готово к `/speckit-tasks`.

## Project Structure

### Documentation (this feature)

```text
specs/005-onboarding-forms/
├── plan.md              # Этот файл (/speckit-plan)
├── research.md          # Phase 0 — технические решения
├── data-model.md        # Phase 1 — BLoC-состояния/энумы/визуальный вокабуляр
├── quickstart.md        # Phase 1 — как запустить и проверить
├── contracts/           # Phase 1 — UI-контракты
│   ├── navigation.md     #   route()/routeDemo()-фабрики, имена роутов, активация Галереи
│   └── widgets.md        #   публичные API новых виджетов + BLoC event/state контракты
├── checklists/
│   └── requirements.md  # из /speckit-specify + /speckit-clarify (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этим планом)
```

### Source Code (repository root)

```text
lib/presentation/pages/
├── login_page/
│   ├── login_page.dart                       # LoginPage: route()/routeDemo(); OnboardCard (десктоп) / AppBar+wordmark+hairline (мобайл); mono ID-поле + Paste + Sign in + Scan QR
│   └── bloc/
│       ├── login_bloc.dart                   # NEW BLoC: value-state + debug-outcome; submit (fake Future)
│       ├── login_event.dart                  # idChanged / pastePressed / signInPressed / setOutcome(debug)
│       └── login_state.dart                  # value-state: id, status, canSubmit, canPaste
├── qr_scan_page/
│   └── qr_scan_page.dart                      # QrScanPage (StatefulWidget, БЕЗ BLoC): overlay + permission-denied + debug switcher; десктоп — TitleBar+viewfinder+OnboardCard-denied
├── set_username_page/
│   ├── set_username_page.dart                 # SetUsernamePage: OnboardCard-хром; labeled-поле (32 + counter + spinner)
│   └── bloc/
│       ├── set_username_bloc.dart             # NEW BLoC: charset(client) + debounced availability(mock) + submit
│       ├── set_username_event.dart            # nameChanged(debounced) / donePressed / setOutcome(debug)
│       └── set_username_state.dart            # value-state: name, status, charsetValid, availability
└── create_chat_page/
    ├── create_chat_page.dart                  # CreateChatPage: width-adaptive — мобайл fullscreen / десктоп scrim+Dialog(460) с Cancel+Create
    └── bloc/
        ├── create_chat_bloc.dart              # NEW BLoC: debounced availability(mock, charset свободный) + submit
        ├── create_chat_event.dart             # nameChanged(debounced) / createPressed / setOutcome(debug)
        └── create_chat_state.dart             # value-state: name, status, availability

lib/presentation/widgets/
├── onboarding/
│   ├── app_onboard_card_widget.dart          # NEW: logo (Assets.png.logo) + AppWordmarkWidget + AppSplashHairlineWidget + слот контента; центр. 440 (десктоп)
│   ├── app_id_field_widget.dart              # NEW: моно многострочный TextField + suffix Paste (2.1)
│   └── app_labeled_field_widget.dart         # NEW: labeled TextField + counter + suffix-spinner + errorText (2.3, 6.1)
└── qr/
    └── app_qr_overlay_widget.dart            # NEW: прицел + затемняющая маска + инструкция (brand-fixed #FAFAFA / #000@55%)

lib/general/
├── text_constants.dart                       # + микрокопия M2 (EN); reuse tooltipBack/actionOpenSettings/errorNetworkMessage
└── onboarding_mock_data.dart                 # NEW: const наборы «занятых» имён / зарезервированных ID (2.1/2.3/6.1)

lib/design/
├── nox_icons.dart                            # + static get noPhotography
├── gen/assets.gen.dart                       # (regen) + Assets.svg.icons.noPhotography
└── app_text_style_tokens.dart               # + monoBody({color}) factory (Roboto Mono) — для моно ID-поля

assets/svg/icons/no_photography.svg            # NEW SVG (+ источник docs/design/system/nox-assets/icons/svg/ + запись icons.json)

lib/presentation/pages/screens_gallery_page/
└── screens_gallery_page.dart                 # активировать строки 2.1/2.2/2.3/6.1 (route: тер-оффы *.routeDemo)

# Переиспользуется (M1, без изменений): RoutePlaceholderPage (заглушки переходов), AppErrorPage/ErrorPageParams (fatal → 3.1),
# AppWindowTitlebarWidget, AppWordmarkWidget, AppSplashHairlineWidget, AppSpinnerWidget, AppInfoBannerWidget.

test/presentation/pages/<page>_page/          # widget + *_golden_test (light/dark) на каждый экран; bloc/ — bloc_test на 3 BLoC
test/presentation/widgets/{onboarding,qr}/    # widget + golden на 4 новых виджета
```

**Structure Decision**: Один пакет `nox_app`, Clean Architecture слоями-папками (M2 затрагивает только presentation + точечно `lib/design`/`lib/general`). Каждый экран — отдельная папка-страница со статическим `route()`/`routeDemo()`; навигация — `Navigator.push` (роутера нет). **2.1/2.3/6.1 владеют Freezed-BLoC** (`bloc/` рядом со страницей; `State extends BaseStatePage`, BLoC создаётся в `initState`, закрывается в `dispose`, `BlocProvider.value` + `BlocBuilder`); **2.2 — без BLoC** (`StatefulWidget`). Новые переиспользуемые виджеты — без BLoC, в `widgets/onboarding/` (хром + поля) и `widgets/qr/` (overlay). Мок-данные — `const` в `lib/general/onboarding_mock_data.dart`. Тесты deep-mirror под `test/`.

## Complexity Tracking

> Constitution Check без нарушений — раздел не заполняется. (Введение первых продуктовых BLoC — следование блюпринту `05` §5.1, а не усложнение: у форм есть реальная async-логика, требующая управляемого состояния.)

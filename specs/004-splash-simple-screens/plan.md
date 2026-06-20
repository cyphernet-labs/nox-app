# Implementation Plan: Экраны этапа M1 — Splash и простые автономные экраны

**Branch**: `004-splash-simple-screens` | **Date**: 2026-06-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/004-splash-simple-screens/spec.md`

## Summary

Реализовать визуальный слой семи экранов этапа M1 — **Splash (1.1)**, **универсальный экран ошибки (3.1)**, **Внешний вид (7.3)**, **Язык (7.4)**, **Уведомления (7.2)**, **Terms (7.6)**, **О приложении (7.7)** — как самостоятельные Flutter-страницы, открываемые из «Галереи экранов» (M0), мультиплатформенно (мобайл + десктоп по ширине окна), на дизайн-токенах, со всеми визуальными состояниями на заглушечных/локальных данных. Бэкенд вне scope: все серверные зависимости (состояние авторизации, разрешения ОС, доставка, персистентность, l10n) заглушены и помечены `// TODO(backend):`.

Технический подход: страницы по конвенции блюпринта (`lib/presentation/pages/<page>_page/`, статический `route()` + `Navigator.push`), визуал из существующих токенов/`NoxIcons`/UI-kit, новые переиспользуемые виджеты для settings-строк, theme-карточек, info-баннера, десктопного TitleBar и адаптивного detail-scaffold. Состояние — локальное (StatefulWidget/AnimationController) либо переиспользование существующего `AppRootBloc` (тема); полноценные Freezed-BLoC не вводятся, пока нет реальной асинхронной логики (см. Constitution Check). Новые зависимости не требуются — `package_info_plus`, `url_launcher`, `shared_preferences` уже в `pubspec.yaml`.

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM-pinned), длина строки 140, стоковый `flutter_lints`.

**Primary Dependencies**: `flutter_bloc` 9.1.1, `freezed` 3.x, `injectable`+`get_it`, `flutter_screenutil`, `flutter_svg`, `flutter_gen` (assets), `package_info_plus` ^10.1.0 (версия/билд), `url_launcher` 6.3.2 (ссылки Terms), `shared_preferences` ^2.5.5 (доступен; персистентность вне scope). **Новые зависимости не добавляются.**

**Storage**: N/A для M1 — UI-only. Тема — в `AppRootBloc` (in-memory); выбор языка/уведомлений — локальное состояние сессии; версия — `package_info_plus` (платформенная инфо). Sembast/`shared_preferences`-персистентность — backend-фаза.

**Testing**: `flutter_test` + `bloc_test` (где есть BLoC) + `mockito` (только); golden через локальный харнес `test/utils/golden.dart` (Apple Silicon/macOS, тег `golden`, вне CI). Обязателен `pumpApp` (`test/utils/pump_app.dart`).

**Target Platform**: iOS, Android, Windows, Linux, macOS (web вне scope). Один пакет `nox_app`.

**Project Type**: Кросс-платформенное Flutter-приложение (single package), Clean Architecture слоями-папками.

**Performance Goals**: Анимации 60 fps; Splash reveal — один проход ~400 мс (`NoxDuration.splashIn`), без циклов; переключение темы — мгновенно (один переход).

**Constraints**: Токен-дисциплина (нет сырых `Color`/`EdgeInsets`/`TextStyle`/overlay-литералов вне `lib/design/theme/`); иконки только SVG `NoxIcons`; микрокопия EN через `TextConstants`; адаптив width-driven по `Constants.railBreakpoint` (840dp); brand-fixed тёмный фон Splash вне `ColorScheme`.

**Scale/Scope**: 7 экранов + ~5 новых переиспользуемых виджетов + ~1 placeholder-страница; активация 7 строк Галереи; тесты widget+golden на каждый экран.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Экраны M1 не работают с содержимым/PII; нет аналитики/логов с PII. Реальный Logout/E2EE — вне M1. Notifications: реальные разрешения вне scope, заглушка флага. |
| **II. Спека/дизайн-корпус — источник истины** | ✅ PASS | Строим строго по `docs/design/spec/screens/` + мобайл/десктоп-корпусам и по `spec.md`; пограничные решения зафиксированы в `## Clarifications`. Out-of-scope не расширяется. |
| **III. Архитектурный блюпринт обязателен** | ✅ PASS | Страницы по конвенции блюпринта (`pages/<page>_page/`, `route()`, токены, `NoxIcons`, `TextConstants`). BLoC-на-страницу (5.1): экраны M1 — чисто презентационные, без репозитория/async, поэтому подпадают под **явный фазовый carve-out, зафиксированный в блюпринте `05` §5.1** (амендмент 2026-06-20; резолюция дрейфа по Принципу III — правится блюпринт) + отражённый в `CLAUDE.md`; Appearance переиспользует существующий `AppRootBloc`. Freezed-BLoC добавляются при подключении реального репозитория/async (backend-фаза). |
| **IV. Верность дизайн-системе** | ✅ PASS | M3 light+dark, только токены; иконки — SVG `NoxIcons` (недостающие добавляются как SVG, без icon-шрифтов — Clarifications/FR-025); brand-fixed тёмный Splash соблюдён. |
| **V. Языковая дисциплина** | ✅ PASS | Спека/план — RU; код/идентификаторы/коммиты — EN; UI-микрокопия — EN (через `TextConstants`); RU в UI отсутствует. |

**Gate (до Phase 0): PASS.** Нарушений нет → раздел Complexity Tracking пуст.

**Re-check (после Phase 1 design): PASS.** Design-артефакты не вводят новых зависимостей и не нарушают токен-дисциплину. BLoC-на-страницу (5.1) больше не «отступление»: исключение для UI-first презентационных экранов **кодифицировано в блюпринте `05` §5.1** (амендмент 2026-06-20) и отражено в `CLAUDE.md` — спека↔блюпринт консистентны (Принцип II). Готово к `/speckit-tasks`.

## Project Structure

### Documentation (this feature)

```text
specs/004-splash-simple-screens/
├── plan.md              # Этот файл (/speckit-plan)
├── research.md          # Phase 0 — технические решения
├── data-model.md        # Phase 1 — сущности/энумы/состояния
├── quickstart.md        # Phase 1 — как запустить и проверить
├── contracts/           # Phase 1 — UI-контракты
│   ├── navigation.md     #   route()-фабрики, имена роутов, активация Галереи
│   └── widgets.md        #   публичные API новых виджетов + параметры AppErrorPage
├── checklists/
│   └── requirements.md  # из /speckit-specify (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этим планом)
```

### Source Code (repository root)

```text
lib/presentation/pages/
├── splash_page/
│   └── splash_page.dart                    # SplashPage: brand-fixed dark, Fade+Scale reveal, debug-outcome routing
├── error_page/
│   ├── error_page.dart                     # AppErrorPage: параметризован, blocking/embedded, loading-retry, desktop TitleBar
│   └── error_page_params.dart              # ErrorPageParams + ErrorPageMode (+ пресеты)
├── appearance_page/
│   └── appearance_page.dart                # System/Light/Dark карточки тем; переиспользует AppRootBloc
├── language_page/
│   └── language_page.dart                  # System/English/Ukrainian radio-строки; AppLanguage
├── notifications_page/
│   └── notifications_page.dart             # push-переключатель + denied info-banner (mock-разрешение)
├── terms_page/
│   └── terms_page.dart                     # bundled озаглавленные секции + version-footer
├── about_page/
│   └── about_page.dart                     # строка version + build
└── placeholder/
    └── route_placeholder_page.dart         # NEW: generic «destination not built yet» (цели Splash has-ID/no-ID)

lib/presentation/widgets/
├── shell/
│   ├── app_detail_scaffold_widget.dart     # NEW: мобайл fullscreen ↔ десктоп width-capped panel
│   └── app_window_titlebar_widget.dart     # NEW: faux desktop TitleBar (Error desktop; НЕ нативный чром)
└── settings/
    ├── app_theme_option_widget.dart        # NEW: карточка выбора темы с мини-превью (Appearance)
    ├── app_settings_switch_row_widget.dart # NEW: SwitchListTile + supporting text (Notifications)
    └── app_info_banner_widget.dart         # NEW: MaterialBanner-style info-баннер (denied)

lib/general/
├── text_constants.dart                     # +микрокопия M1 (EN)
└── app_language.dart                       # NEW: enum AppLanguage { system, english, ukrainian }

lib/presentation/pages/screens_gallery_page/
└── screens_gallery_page.dart               # активировать 7 строк (route: тер-оффы)

test/presentation/pages/<screen>_page/      # widget + *_golden_test (light/dark) на каждый экран
test/presentation/widgets/{shell,settings}/ # widget + golden на новые виджеты
```

**Structure Decision**: Один пакет `nox_app`, Clean Architecture слоями-папками (для M1 затронут только presentation). Каждый экран — отдельная папка-страница со статическим `route()`; навигация — `Navigator.push` (роутера нет). Переиспользуемые виджеты — без BLoC, в `widgets/shell/` (адаптив/хром) и новой `widgets/settings/` (settings-строки). Энумы/параметры — рядом со страницей либо в `lib/general/`. Тесты deep-mirror под `test/`.

## Complexity Tracking

> Constitution Check без нарушений — раздел не заполняется.

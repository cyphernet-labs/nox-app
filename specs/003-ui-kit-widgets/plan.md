# Implementation Plan: UI-кит — библиотека виджетов представления

**Branch**: `003-ui-kit-widgets` | **Date**: 2026-06-15 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-ui-kit-widgets/spec.md`

## Summary

Собрать в `lib/presentation/widgets/` весь UI-кит NOX — все компоненты дизайн-системы из `docs/design/system/nox-handoff-2/` (примитивы, composite чата/сообщений, оболочка, обратная связь), реализованные как переиспользуемые **BLoC-less** виджеты по блюпринту (`docs/blueprints/mobile/05`,`06`,`10`) и конвенции нейминга `App*Widget`. Референсный Dart хендофа **адаптируется** под дисциплину дизайн-токенов (`ColorScheme`/`context.appColors`, `AppSpacingTokens`/`AppTextStyleTokens`, `NoxRadius`/`NoxElevation`, `NoxBrand`) — raw-значения и icon-шрифт заменяются токенами и SVG-реестром `NoxIcons` (Feature-002), `material_symbols_icons` не вводится. Сверх каталога: полный M3 component-theme wiring stock-виджетов в `app_theme.dart`, generic state-виджеты (`AppProgressWidget`/`AppErrorWidget`), реальные SVG-иллюстрации в empty-state. Для **каждого** виджета — golden-тест (кураторский набор 2–4 варианта × light/dark, локальный `matchesGoldenFile`-харнесс) и widget-тест; stock-виджеты покрываются одним сводным theme-showcase golden. Плюс dev-only галерея отдельной точкой входа `main_gallery.dart`.

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`; Flutter `3.44.1` (FVM-pinned, `.fvmrc`).

**Primary Dependencies**: `flutter/material` (M3); `flutter_svg ^2.3.0` + `lib/design/nox_icons.dart` (`NoxIcons`/`SvgGenImage`) для иконок и иллюстраций; `flutter_screenutil 5.9.3` (отзывчивые токены `AppSpacingTokens`/`AppTextStyleTokens`); тема и токены из `lib/design` (Feature-002). **Новых рантайм-зависимостей не вводится** — в частности, `material_symbols_icons` **не** добавляется (NOX рендерит SVG, не icon-шрифт). Тесты: `flutter_test` (widget) + плоские goldens (`matchesGoldenFile`); `bloc_test` неприменим (у виджетов нет BLoC).

**Storage**: N/A (нет персистентности, сети и рантайм-состояния — leaf-виджеты).

**Testing**: `flutter_test` widget-тесты (идут в CI) + **локальные** golden-тесты (`matchesGoldenFile`, `@Tags(['golden'])`, рендер только на M1/macOS, исключены из CI и `make test`; запуск через `make golden-update`/`make golden-verify`). Общий pump-хелпер `test/utils/pump_app.dart` (`ScreenUtilInit(designSize: Constants.designSize=360×779)` + `MaterialApp(AppTheme.light()/dark(), themeMode)`, фикс `textScaler`). `flutter_test_config.dart` нет; DI (`configureDependencies(Environment.test)`) виджетам кита не нужен (чистые виджеты без `getIt`). Гейт `make gate` (`generate → format → analyze → test`).

**Target Platform**: iOS, Android, Windows, Linux, macOS (web — вне scope).

**Project Type**: Кросс-платформенное Flutter-приложение, единый пакет `nox_app`; этот срез — **слой представления `lib/presentation/widgets/`** (UI-кит) + расширение темы (`lib/design/theme`) + dev-галерея. Data/domain не затрагиваются.

**Performance Goals**: Рантайм-перф не затрагивается. Виджеты — leaf, `const`-friendly, без подписок/таймеров. Goldens детерминированы при фиксированном surface 360×779 и `textScaler=1.0`.

**Constraints**: только дизайн-токены (никакого хардкод-`Color`/`EdgeInsets`/`TextStyle`/радиуса/elevation в коде виджетов — brand-fixed только через `NoxBrand`); виджеты **без собственного BLoC** (Принцип 5.1 блюпринта — переиспользуемым виджетам BLoC не нужен); нейминг `App*Widget`, enum'ы без `Nox`-префикса (`FileType`/`MessageStatus`/`AppTab`); полные `package:nox_app/...` импорты в коде (относительные — только в тестах); codegen-first (один прогон `build_runner` для `assets.gen`/`*.mocks.dart`); line length 140; ноль ошибок `flutter analyze`; на каждый виджет — golden (2–4 варианта × light/dark) + widget-тест; галерея — отдельный entrypoint, вне релизных сборок.

**Scale/Scope**: ~17 классов-виджетов `App*Widget` (4 примитива + 6 composite + 4 shell + 3 generic state), 2 feedback-хелпера (`showAppSnackBar`/`showAppBanner`), 3 enum (`FileType`/`MessageStatus`/`AppTab`) + 2 map-хелпера (`noxFileIcon`/`noxFileColor`), расширение `app_theme.dart` (≥14 component sub-themes, incl. switch/radio/listTile/progressIndicator), 1 dev-галерея + `main_gallery.dart`, `test/utils/pump_app.dart`, ~17 golden + ~17 widget тест-файлов + 1 theme-showcase golden. **0 продуктовых экранов / 0 бизнес-логики / 0 BLoC.**

## Constitution Check

*GATE: пройден до Phase 0; перепроверен после Phase 1 (см. ниже).*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Чистые UI-виджеты: ни сети, ни PII, ни логов, ни аналитики. Тесты и галерея используют синтетические образцы строк/имён (не реальные ID/имена чатов). Поверхность приватности не затрагивается. |
| **II. Спека и дизайн-корпус — источник истины** | ✅ PASS | Строим к каталогу `nox-handoff-2` + `docs/design/spec/`; пройден spec → clarify → plan. **Дрейф устранён в этом change-set:** `FR-007` исправлен с ошибочного `material_symbols_icons` на SVG-реестр `NoxIcons` (фактическая реальность Feature-002). Референсный Dart адаптируется (не копируется). Зафиксированный out-of-scope (экраны/навигация/бизнес-логика) не расширяется. |
| **III. Архитектурный блюпринт обязателен** | ✅ PASS | Строим по `docs/blueprints/mobile/05` (переиспользуемые виджеты без BLoC, нейминг `App*Widget`, полные импорты), `06` (токен-дисциплина, `context.appColors`), `10` (шаблоны). Реализуется FUTURE-директория `lib/presentation/widgets/` из `05 §1`. Новых пакетов/path-deps нет. Платформенно-специфичных нативных подсистем (push/deep-links/secure-storage) фича не касается — desktop-gap (Принцип III) не активируется; leaf-виджеты платформенно-нейтральны, desktop-адаптация — на уровне shell (вне scope). |
| **IV. Верность дизайн-системе** | ✅ PASS | Суть фичи. M3 light+dark; только токены; brand-fixed (splash-hairline-градиент, brand-teal иконка поиска, QR-поверхность) через `NoxBrand`; иконки из SVG-реестра `NoxIcons`; реальные иллюстрации `Assets.svg.illustrations.*`. |
| **V. Языковая дисциплина** | ✅ PASS | Spec/plan/research/артефакты — русский; код, идентификаторы, пути, ключи pubspec — английский; UI-микрокопи — English из `TextConstants`; русского в UI нет. |

**Вывод гейта:** нарушений нет → Complexity Tracking пуст. Исправление `FR-007` — приведение спеки к фактической реализации (Принцип II), а не нарушение.

## Project Structure

### Documentation (this feature)

```text
specs/003-ui-kit-widgets/
├── plan.md              # этот файл
├── research.md          # Phase 0 — решения: икон-механизм (SVG vs шрифт), адаптация токенов, golden-харнесс, нейминг, галерея
├── data-model.md        # Phase 1 — каталог виджетов: API (props/коллбэки), варианты, token-bindings, enum'ы
├── quickstart.md        # Phase 1 — верификация: gate, golden-update/verify, запуск галереи, маппинг экран→виджет
├── contracts/
│   └── ui-kit-api.md     # Phase 1 — публичная Dart-поверхность UI-кита (UI-контракт)
└── checklists/
    └── requirements.md  # из /speckit-specify
```

### Source Code (repository root)

```text
lib/presentation/widgets/                 # NEW — UI-кит (реализация FUTURE-директории блюпринта 05 §1)
├── primitives/
│   ├── app_icon_widget.dart              # AppIconWidget — SVG-глиф (NoxIcons) + ColorFilter + fill-вариант
│   ├── app_spinner_widget.dart           # AppSpinnerWidget — индетерминантный прогресс
│   ├── app_avatar_widget.dart            # AppAvatarWidget — генерируемый аватар (noxAvatarColor + инициалы/forum)
│   ├── app_file_glyph_widget.dart        # AppFileGlyphWidget — тип-иконка в тинтованном квадрате
│   └── file_type.dart                    # enum FileType + noxFileIcon()/noxFileColor() маппинги
├── chat/
│   ├── app_search_bar_widget.dart        # AppSearchBarWidget — persistent search (brand-teal иконка)
│   ├── app_chat_item_widget.dart         # AppChatItemWidget — строка чата + unread-бейдж
│   ├── app_file_chip_widget.dart         # AppFileChipWidget — чип-вложение (standalone/inBubble/removable)
│   ├── app_message_bubble_widget.dart    # AppMessageBubbleWidget + enum MessageStatus
│   ├── app_composer_widget.dart          # AppComposerWidget — инпут (attach/text/send)
│   └── app_segmented_widget.dart         # AppSegmentedWidget<T> — single-select segmented
├── shell/
│   ├── app_splash_hairline_widget.dart   # AppSplashHairlineWidget — brand-градиент-rule (PreferredSizeWidget)
│   ├── app_wordmark_widget.dart          # AppWordmarkWidget — «NOX» Bold 700 +0.12em
│   ├── app_bottom_bar_widget.dart        # AppBottomBarWidget + enum AppTab (BottomAppBar + notch)
│   └── app_create_fab_widget.dart        # AppCreateFabWidget — docked «+» FAB
└── state/
    ├── app_progress_widget.dart          # AppProgressWidget — состояние загрузки
    ├── app_error_widget.dart             # AppErrorWidget — ошибка + retry-CTA
    └── app_empty_content_widget.dart     # AppEmptyContentWidget — пустота (SVG-иллюстрация)

lib/presentation/helpers/                 # NEW — каналы обратной связи (блюпринт 05 §8)
└── app_feedback_helper.dart              # showAppSnackBar() (neutral/error) + showAppBanner() (offline)

lib/design/theme/
├── app_theme.dart                        # UPDATED — подключение component sub-themes
└── nox_component_themes.dart             # NEW — per-component M3 sub-themes из референс nox_theme.dart
                                          #   (inputDecoration/filledButton/textButton/iconButton/segmentedButton/
                                          #    switch/radio/listTile/progressIndicator/dialog/bottomSheet/card/snackBar/appBar)

lib/general/text_constants.dart           # UPDATED — дефолтная UI-микрокопи кита (Search/Message/Dismiss/ошибки)

lib/gallery/                              # NEW — dev-only галерея (вне продукта)
├── gallery_app.dart                      # GalleryApp — MaterialApp(AppTheme) + переключатель темы
└── gallery_page.dart                     # каталог всех виджетов × light/dark
lib/main_gallery.dart                     # NEW — отдельная dev-точка входа (runApp(GalleryApp))

test/utils/
└── pump_app.dart                         # NEW — общий pump-хелпер (ScreenUtilInit + AppTheme + themeMode)
test/presentation/widgets/                # NEW — deep-mirror lib/: <widget>_test.dart + <widget>_golden_test.dart
│   ├── primitives/ … chat/ … shell/ … state/
│   └── **/goldens/*.png                  # локальные M1-фикстуры (коммитятся; не gitignored)
test/design/theme/
└── theme_showcase_golden_test.dart       # NEW — один сводный golden stock-виджетов (light+dark)

pubspec.yaml                              # без изменений (новых deps нет; assets/fonts уже объявлены в Feature-002)
```

**Structure Decision**: Единый пакет `nox_app`. UI-кит ложится в `lib/presentation/widgets/` (реализация FUTURE-директории блюпринта `05 §1`), сгруппированный по семантике (`primitives`/`chat`/`shell`/`state`) — одна публичная вёрстка = один файл, имя файла snake_case = имя класса. Feedback-каналы — в `lib/presentation/helpers/` (блюпринт `05 §8`). Per-component M3 sub-themes выносятся в `lib/design/theme/nox_component_themes.dart` и подключаются из `app_theme.dart`, чтобы тот остался читаемым. Тесты **deep-mirror** дерево `lib/` под `test/presentation/widgets/...`; goldens — в `goldens/` рядом с тестом (локальные фикстуры). Dev-галерея изолирована в `lib/gallery/` с отдельной точкой входа `lib/main_gallery.dart` — ноль следа в продуктовом `lib/main.dart`/`AppRoot` и релизных сборках. Новых слоёв/пакетов/зависимостей нет.

## Complexity Tracking

> Нарушений Constitution Check нет — раздел не заполняется.

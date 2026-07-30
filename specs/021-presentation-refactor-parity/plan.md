# Implementation Plan: Рефакторинг presentation-слоя + паритет mobile/desktop

**Branch**: `021-presentation-refactor-parity` | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification + `docs/presentation-refactor-review.md` (backlog R1–R28)

## Summary

Рефакторинг presentation-слоя NOX по трём осям: (1) закрытие 5 реальных паритет-дефектов mobile↔desktop
(FR-001…FR-006 — единственные изменения поведения), (2) вынос 13 дублированных/inline UI-деревьев в
переиспользуемые виджеты (behavior-preserving), (3) 7 оптимизаций (токенизация magic-чисел, hoisting
`Theme.of`, снятие дублей). Технический подход: **golden-driven safety** — существующие голдены обеих
категорий (page-mobile 360 + page-desktop 1280×800) служат страховкой; behavior-preserving задачи держат
их байт-в-байт зелёными, паритет-фиксы осознанно перегенерируют baseline ранее-отстающей ветки И добавляют
тест/golden на закрытый gap. Выполнение по фазам P→E→O, по одной задаче на фич-бранч → merge в `develop`.

## Technical Context

**Language/Version**: Dart / Flutter 3.44.1 (FVM-pinned), line length 140, stock `flutter_lints`.
**Primary Dependencies**: Существующие — flutter_bloc, freezed, injectable+get_it, flutter_screenutil, дизайн-токены (`AppSpacingTokens`/`AppDimensionTokens`/`AppTextStyleTokens`). **Новых зависимостей НЕ вводится.**
**Storage**: N/A (presentation-only; данные не затрагиваются).
**Testing**: `flutter_test` — widget/unit тесты (`mockito`), голдены `matchesGoldenFile` (page-mobile `goldenTest` + page-desktop `goldenTestDesktop`), a11y (`accessibility_test.dart`). Гейты: `make gate` + `make golden-verify`.
**Target Platform**: iOS, Android, macOS, Windows, Linux (5 таргетов; web вне scope). Responsive-развилка по `constraints.maxWidth >= Constants.railBreakpoint`.
**Project Type**: Single Flutter package `nox_app`, Clean Architecture (presentation→domain←data).
**Performance Goals**: N/A (нет new-хот-путей); оптимизации O1–O7 снижают лишние `Theme.of`/rebuild, но не гонятся за метрикой.
**Constraints**: Behavior-preserving везде, ЕДИНСТВЕННОЕ исключение — паритет-фиксы FR-001…FR-006. Голдены обеих категорий зелёные на каждом merge. BLoC-логика не переписывается. Dev-only поверхности (ui_kit/screens_gallery/item_list) вне scope.
**Scale/Scope**: `lib/presentation/` (~117 product-файлов), из них 13 responsive; бэклог 28 задач (6 parity + 2 confirm-only + 13 extraction + 7 optimization).

## Constitution Check

*GATE: пройден. Рефакторинг УКРЕПЛЯЕТ конституцию, не нарушает её.*

- **I. Приватность и E2EE** — ✅ PASS. Не трогаем крипто/identity/secure-storage. FR-013 (account reveal/QR split)
  подтверждён владельцем как намеренное privacy-решение (desktop shared-screen) — сохраняется, НЕ унифицируется.
- **II. Спецификации и дизайн-корпус — источник истины** — ✅ PASS / УСИЛЕНИЕ. Паритет-фиксы сверяются с
  `nox-desktop-screens`/`nox-mobile-screens` (R6 явно требует сверки с `01-chats.md`); цель фичи — привести
  реализацию в соответствие с «one app, both platforms».
- **III. Архитектурный блюпринт** — ✅ PASS. Слои не меняются; extraction следует BLoC-less-виджет-конвенции
  (`App*Widget`); мульти-платформенный паритет — прямая цель Принципа III (desktop в scope).
- **IV. Верность дизайн-системе** — ✅ PASS / УСИЛЕНИЕ. O1–O2 переносят magic-opacity/геометрию в токены; extraction
  централизует токен-использование; raw-литералы остаются только в `lib/design/theme/`.
- **V. Языковая дисциплина** — ✅ PASS / УСИЛЕНИЕ. FR-003 чинит захардкоженный английский `'Chats'` → `context.l10n`
  (UI EN+UK). Код/коммиты — английские; эта спека/план — русские.

**Нарушений нет → Complexity Tracking пуст.**

## Project Structure

### Documentation (this feature)

```text
specs/021-presentation-refactor-parity/
├── spec.md                     # /speckit-specify + /speckit-clarify
├── plan.md                     # This file
├── research.md                 # Phase 0 — методология safety + подход к паритет-верификации
├── data-model.md               # Phase 1 — карта извлекаемых компонентов + токенов (не data)
├── quickstart.md               # Phase 1 — как валидировать (гейты + per-fix тест)
├── contracts/
│   └── parity-matrix.md        # Phase 1 — контракт паритета по 13 responsive-экранам
├── checklists/requirements.md  # spec-quality (16/16)
└── tasks.md                    # /speckit-tasks (Phase 2, НЕ этим командой)
```

### Source Code (затрагиваемые области `lib/presentation/`)

```text
lib/presentation/
├── pages/
│   ├── error_page/error_page.dart              # FR-001 (R1) — _wide ветвление по ErrorPageMode
│   ├── chats_list_page/chats_list_page.dart    # FR-006 (R6) hairline; O3 Theme.of; E4 ring
│   ├── chat_card_page/chat_card_page.dart       # E5 WatchChat; E4 ring
│   ├── chat_thread_page/chat_thread_page.dart   # E5 WatchChat; O7 title ellipsis
│   ├── create_chat_page/create_chat_page.dart   # FR-005 (R5) cancel-guard; E13 dropdown
│   ├── settings_root_page/settings_root_page.dart # E6 pane-header; E12 dev-rows; O4 dead-code
│   ├── login_page/…, set_username_page/…         # E1 button; E2 onboarding-scaffold
│   ├── qr_scan_page/qr_scan_page.dart            # E10 viewfinder; O2/O6 QR
│   ├── file_view_page/…, image_viewer_page/…     # E8 adaptive-lightbox; O1 scrim
│   ├── appearance_page/…, splash_page/…          # O2 scale-token
├── widgets/
│   ├── chat/app_message_bubble_widget.dart      # FR-002 (R2) local-width
│   ├── chat/app_thread_view_widget.dart          # E5/E7 helpers
│   ├── shell/tab_bar_shell_widget.dart           # FR-003 (R3) titlebar; O5 hairline
│   ├── shell/app_navigation_rail_widget.dart     # FR-004 (R4) Semantics; E11 sub-widgets; O5
│   ├── shell/app_window_titlebar_widget.dart     # FR-003 subtitle-param
│   ├── settings/app_identity_card_widget.dart    # O3 Theme.of
│   ├── state/app_notice_strip_widget.dart, settings/app_info_banner_widget.dart # E9 banner-shell
│   └── primitives/  (новые)  app_hairline_divider_widget.dart (E3), app_ringed_avatar_widget.dart (E4), app_primary_button_widget.dart (E1)
├── helpers/  (новый) adaptive_lightbox.dart (E8)
└── design/theme/ nox_opacity.dart (новый, O1)  # raw-opacity токены
```

**Structure Decision**: единый пакет, изменения только в `lib/presentation/` (+ 1 файл токенов в `lib/design/theme/`).
Новые извлечённые виджеты кладутся по существующим правилам (`App*Widget` под `widgets/<subsystem>/` или
`widgets/primitives/`; helper — под `presentation/helpers/`).

## Подход к реализации (safety-first)

1. **Порядок фаз:** **P** (паритет-дефекты R1–R6) → **E** (выносы R9–R21) → **O** (оптимизации R22–R28).
   R7/R8 закрыты как «confirmed intentional» (кода нет).
2. **Инвариант behavior-preserving (E/O):** перед задачей — baseline голдены зелёные; после — `make golden-verify`
   БЕЗ churn. Любой неожиданный diff = сигнал непреднамеренного изменения → разбирать, а не перегенерировать.
3. **Паритет-фиксы (P):** пишем тест/golden, который ПАДАЛ бы до фикса (fail-first), затем фикс, затем осознанная
   перегенерация baseline «отстающей» ветки. Каждый фикс сверяется с соответствующим desktop/mobile-корпусом.
4. **Гранулярность:** одна R-задача = один фич-бранч = один merge `--no-ff` в `develop`; adversarial-ревью на
   каждую поведение-меняющую (P) задачу; для чистых E/O — голдены + gate достаточны, ревью по объёму.
5. **Риск-контроль:** med-risk только у R1/R2/R3 (меняют desktop-layout/поведение) — им обязательны новые тесты;
   остальные low-risk.

## Complexity Tracking

*Нарушений конституции нет — раздел пуст.*

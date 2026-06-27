# Implementation Plan: Chats list — сверка с дизайном и golden-покрытие (mobile + desktop)

**Branch**: `011-chats-design-parity` | **Date**: 2026-06-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/011-chats-design-parity/spec.md`

## Summary

Привести экран **5.1 Chats list** (`lib/presentation/pages/chats_list_page/chats_list_page.dart`) в полное соответствие двум авторитетным макетам — `NOX - Mobile.html` (узкая ветка `_narrow`) и `NOX - Desktop.html` (широкая ветка `_wide`, list-detail) — в light и dark. Добавить **аккаунт-аватар** в нижней части десктопного `AppNavigationRailWidget` (визуал `AppAvatarWidget` — инициалы + цвет по хэшу; инициалы по account-правилу) с переходом на `Settings` → секцию `Account`. После приведения к дизайну зафиксировать весь функционал экрана golden-baseline в **двух** категориях: **page — mobile** (`goldenTest`, 360) и **page — desktop** (`goldenTestDesktop`, 1280×800).

Технический подход: чисто presentation-слой. Данные не трогаем (network-only mock `ChatsListBloc` остаётся). Точечно расширяем `AppAvatarWidget` (override инициалов), добавляем pure-util `noxAccountInitials`, расширяем `AppNavigationRailWidget` (trailing-аватар) и `TabBarShell` (загрузка label из `sessionRepository` + сигнал «приземлиться на Account» в `SettingsRootPage`, по образцу `scrollToTop`). Пиксельную сверку с HTML выполняем через claude_design MCP на этапе implement.

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM-pinned); line length 140.

**Primary Dependencies**: Flutter Material 3, `flutter_bloc` (существующий `ChatsListBloc`), `infinite_scroll_pagination` v5, design-токены (`AppSpacingTokens`/`AppDimensionTokens`/`AppTextStyleTokens`), `injectable`+`get_it` DI. Новых пакетов нет.

**Storage**: N/A для UI-правок. Label аватара читается из `sessionRepository.readSession()` → `SessionModel.label` (cache-only, без сети).

**Testing**: `flutter_test`, `bloc_test`, `mockito`; golden-харнесс `test/utils/golden.dart` (`goldenTest` / `goldenTestDesktop`), общий `pumpApp`. Mock-данные через `configureDependencies(Environment.test)`.

**Target Platform**: iOS, Android, Windows, Linux, macOS (web вне scope). Аватар присутствует только в широкой (rail) вёрстке — на всех трёх desktop-таргетах одинаково.

**Project Type**: Mobile/desktop Flutter app (один пакет `nox_app`, Clean Architecture слоями-папками).

**Performance Goals**: 60 fps; визуальное соответствие макету (golden-locked), без новых async-нагрузок в hot path.

**Constraints**: Только дизайн-токены (нет хардкод-цветов/отступов/типографики вне `lib/design/theme/`); M3 light+dark; multi-platform parity (`_narrow` ↔ mobile-корпус, `_wide` ↔ desktop-корпус); BLoC-per-page carve-out для shell сохраняется.

**Scale/Scope**: 1 продуктовый экран (2 вёрстки) + 1 новый элемент shell (rail-аватар) + golden-покрытие. Затрагиваемые файлы: ~4 prod + 1 pure-util + 2–3 тест-файла + 2 design-corpus-правки.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Приватность и E2EE.** Фича — чисто presentation. Инициалы аватара выводятся из локального display-label и **не покидают устройство**; в логи/аналитику ничего нового не пишется; PII не вводится. Сети/крипто не касаемся. → **PASS**.
- **II. Спецификации и дизайн-корпус — источник истины.** Авторитетный таргет — `NOX - Mobile/Desktop.html` (claude_design), сверяется с `docs/design/system/nox-mobile-screens/screens/5-1-chats.md` и `nox-desktop-screens/screens/01-chats.md`. Аккаунт-аватар в rail — **net-new** элемент, которого нет в desktop-корпусе (`01-chats.md` описывает «NavigationRail (80)» без аватара) → в этом же change-set **обновляем** `nox-desktop-screens/screens/01-chats.md` (drift-fix: добавить trailing account-аватар в анатомию + поведение перехода в Settings/Account). Out-of-scope не расширяется молча — scope зафиксирован в spec. → **PASS** (drift-fix запланирован).
- **III. Архитектурный блюпринт обязателен.** Строим по `docs/blueprints/mobile/`: один пакет, presentation-слой, дизайн-токены, codegen-first. `TabBarShell` остаётся BLoC-less (carve-out 05 §5.1): добавляемый one-shot read label из `sessionRepository` для display-only аватара — тривиальное локальное состояние, не требует BLoC (страница чисто презентационная, без мутаций/пагинации). Новых платформенно-нативных частей нет (аватар — чистый Flutter). → **PASS**.
- **IV. Верность дизайн-системе.** M3 light+dark; аватар переиспользует `AppAvatarWidget` (генерируемые аватары — явный пункт Принципа IV) + `noxAvatarColor`; только токены, без хардкода вне `lib/design/theme/`. Три golden-категории соблюдены (widget / page-mobile / page-desktop). → **PASS**.
- **V. Языковая дисциплина.** Spec/research/quickstart — русский; код, идентификаторы, UI-микрокопия (`Chats`, `Search`, `Select a chat`, …) — английский; коммиты/ветка — английский. → **PASS**.

**Итог гейта (до Phase 0): PASS** (без нарушений; Complexity Tracking не требуется). Единственное обязательство — drift-fix desktop-корпуса (Принцип II) в том же change-set.

**Пере-проверка после Phase 1 (design): PASS.** Артефакты (`research.md`, `data-model.md`, `contracts/`) не вводят новых пакетов, слоёв, сетевых/нативных частей или хардкода: `noxAccountInitials` — pure-util рядом с существующими; `AppAvatarWidget.initials` — обратносовместимый override; rail-аватар и сигналы `jumpToAccount`/`accountLabel` — presentation-only, по существующим паттернам (`scrollToTop`, `sessionRepository` alias). Принципы I–V соблюдены; нарушений нет.

## Project Structure

### Documentation (this feature)

```text
specs/011-chats-design-parity/
├── plan.md              # Этот файл (/speckit-plan)
├── spec.md              # Спецификация (+ Clarifications)
├── research.md          # Phase 0 — R1..R8 (решения)
├── data-model.md        # Phase 1 — сущности (ChatRow, AccountAvatar, состояния)
├── quickstart.md        # Phase 1 — как валидировать (run + golden)
├── contracts/           # Phase 1 — UI-контракты
│   ├── account-avatar.md   # API аватара + правило инициалов + цель перехода
│   ├── navigation.md       # rail→Settings/Account сигнал; row-tap parity
│   └── golden-coverage.md  # перечень golden (mobile + desktop) и состояния
└── checklists/
    └── requirements.md  # чек-лист качества spec (16/16)
```

### Source Code (repository root)

```text
lib/
├── design/theme/nox_brand.dart                       # + noxAccountInitials(label) (pure util; рядом с noxInitials)
├── presentation/widgets/primitives/
│   └── app_avatar_widget.dart                         # + optional `initials` override (визуал не меняется)
├── presentation/widgets/shell/
│   ├── app_navigation_rail_widget.dart                # + trailing аккаунт-аватар (pinned bottom) + onAccount
│   └── tab_bar_shell_widget.dart                      # load label из sessionRepository; onAccount → Settings tab + сигнал Account
├── presentation/pages/chats_list_page/chats_list_page.dart  # правки соответствия дизайну (_mobile / _desktop) по итогам аудита
└── presentation/pages/settings_root_page/settings_root_page.dart  # принять сигнал «jump to Account» (сброс _selected=account)

test/
├── presentation/pages/chats_list_page/
│   ├── chats_list_page_golden_test.dart               # NEW: page-mobile + page-desktop goldens по всем состояниям
│   ├── chats_list_page_test.dart                      # обновить при изменении дерева
│   └── goldens/                                        # NEW baseline PNG (light/dark + _desktop_)
├── presentation/widgets/shell/
│   └── app_navigation_rail_widget_golden_test.dart    # NEW/UPDATE: rail с аккаунт-аватаром (widget golden)
└── design/theme/nox_account_initials_test.dart        # NEW: unit-тест правила инициалов

docs/design/system/nox-desktop-screens/screens/01-chats.md  # drift-fix: rail account-аватар (Принцип II)
```

**Structure Decision**: один пакет `nox_app`, изменения в `presentation` + один pure-util в `design/theme`. Никаких новых слоёв/пакетов. Затрагиваемая «осиротевшая» папка `test/presentation/pages/chats_list_page/failures/` (от прежнего упавшего golden) удаляется при добавлении настоящего golden-теста.

## Complexity Tracking

> Не требуется — Constitution Check пройден без нарушений.

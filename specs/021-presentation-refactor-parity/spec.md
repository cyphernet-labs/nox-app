# Feature Specification: Рефакторинг presentation-слоя + паритет mobile/desktop

**Feature Branch**: `021-presentation-refactor-parity`
**Created**: 2026-07-28
**Status**: Draft
**Input**: Рефакторинг `lib/presentation/`: вынос дублей в переиспользуемые виджеты, оптимизация/чистка, и — главный приоритет — закрытие паритет-разрывов mobile↔desktop. Всё behavior-preserving, кроме паритет-фиксов. Страховка — голдены page-mobile + page-desktop. Полный бэклог и анализ — `docs/presentation-refactor-review.md` (R1–R28).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Полный паритет функций mobile ↔ desktop (Priority: P1)

Пользователь получает ОДИНАКОВЫЙ набор действий, аффордансов и состояний вне зависимости от платформы: доступное на мобильном доступно и на десктопе, и наоборот — кроме сознательно-платформенных исключений. Сейчас есть разрывы: fatal-ошибка на desktop закрывается системным «назад»; desktop-титлбар не локализуется и не отражает активный таб; отмена create-chat во время submit не заблокирована на mobile; desktop-rail без a11y-семантики.

**Why this priority**: user-visible дефекты корректности и консистентности между платформами — прямой запрос владельца («на десктопе есть, а на мобилке нет — это плохо»).

**Independent Test**: пройти каждый из 13 responsive-экранов на 360 (mobile) и 1280 (desktop), сверить перечень действий/состояний в `_narrow` и `_wide` ветках; каждый закрытый gap подтверждается новым тестом/голденом на ранее-отстающей ветке.

**Acceptance Scenarios**:

1. **Given** fatal-ошибка на desktop, **When** нажать системный «назад», **Then** экран НЕ закрывается (как на mobile через `PopScope`).
2. **Given** активен таб Settings на desktop, **When** смотрю на window-titlebar, **Then** subtitle = локализованный «Settings» (не захардкоженный «Chats»).
3. **Given** create-chat в процессе submit на mobile, **When** пытаюсь отменить/уйти назад, **Then** отмена заблокирована (как на desktop).
4. **Given** desktop navigation-rail, **When** активен скринридер, **Then** каждый пункт объявляется как button + selected-состояние.

### User Story 2 — Переиспользуемые виджеты вместо дублей (Priority: P2)

Повторяющиеся/inline UI-деревья вынесены в `App*Widget`/приватные виджеты; визуально ничего не меняется. Ценность: меньше дублей → меньше drift/багов, единые точки правки (примеры: общий full-width submit-button, onboarding-scaffold, hairline-divider, reactive-chat-name биндинг ×4, ringed-avatar, adaptive-lightbox).

**Why this priority**: maintainability-ценность для команды; для пользователя невидимо.

**Independent Test**: голдены всех затронутых экранов (mobile + desktop) остаются БАЙТ-в-байт зелёными до/после выноса.

**Acceptance Scenarios**:

1. **Given** вынесен общий виджет, **When** сравниваю голдены до/после, **Then** они идентичны.
2. **Given** N сайтов использовали дубль, **When** рефакторинг завершён, **Then** все используют один виджет (0 копий).

### User Story 3 — Токенизация и чистка (Priority: P3)

Magic-числа (opacity/геометрия) заменены дизайн-токенами; повторные `Theme.of`/`MediaQuery`-вызовы подняты в один; мёртвый код и рассинхронизированные значения (scrim 0.5 vs 0.55) сведены. Поведение неизменно.

**Why this priority**: чистота/консистентность кода; для пользователя невидимо.

**Independent Test**: голдены зелёные; значения токенов численно равны прежним литералам.

**Acceptance Scenarios**:

1. **Given** magic-opacity заменён токеном равного значения, **When** прогоняю голдены, **Then** без изменений.

### Edge Cases

- Паритет-фикс меняет layout ранее-отстающей ветки → её golden ОСОЗНАННО перегенерируется + добавляется тест на закрытый gap. Это единственный допустимый вид «изменения UI».
- Вынос виджета не должен менять const-ность/rebuild так, чтобы поехал golden — если поехал, это сигнал непреднамеренного изменения, разбирать.
- Длинные имена чата (до 64 симв.) — обрезка (`maxLines`/`ellipsis`) должна быть консистентна на всех surface.
- Изменение scrim 0.55→0.5 (если признано рассинхроном) — один desktop file-view baseline перегенерируется.

## Requirements *(mandatory)*

### Functional Requirements

**Паритет — behavioral fixes (единственные изменения поведения):**

- **FR-001**: `error_page` на desktop (`_wide`) MUST ветвиться по `ErrorPageMode`: blocking → `PopScope(canPop:false)` (неотменяем системным «назад»), embedded → back-аффорданс; titlebar сохраняется. [R1]
- **FR-002**: max-width message-bubble MUST вычисляться из локальной доступной ширины панели (`LayoutBuilder`/`BoxConstraints`), не из ширины окна. [R2]
- **FR-003**: desktop window-titlebar subtitle MUST быть локализованным (`context.l10n`) и отражать активный таб (Chats↔Settings). [R3]
- **FR-004**: desktop navigation-rail destinations MUST нести `Semantics(button, selected, label)` эквивалентно mobile bottom bar. [R4]
- **FR-005**: mobile create-chat MUST блокировать отмену/системный «назад» во время `isSubmitting` (паритет с desktop `barrierDismissible:false`). [R5]
- **FR-006**: desktop chats list-pane header MUST нести тот же hairline-сепаратор, что mobile-двойник и соседняя desktop settings-панель (после сверки с `nox-desktop-screens/screens/01-chats.md`). [R6]

**Инварианты рефакторинга (constraints на ВСЕ задачи):**

- **FR-007**: все НЕ-паритетные изменения MUST быть behavior-preserving — голдены page-mobile (360) и page-desktop (1280×800) остаются идентичными.
- **FR-008**: каждая задача MUST держать `make gate` + `make golden-verify` зелёными перед merge `--no-ff` в `develop`.
- **FR-009**: каждый паритет-фикс (FR-001…FR-006) MUST сопровождаться новым тестом/голденом, фиксирующим закрытый gap на ранее-отстающей ветке.
- **FR-010**: extraction MUST следовать конвенциям проекта: `App*Widget` под `lib/presentation/widgets/` либо приватный `StatelessWidget`; только дизайн-токены (raw-color/opacity литералы — исключительно в `lib/design/theme/`).
- **FR-011**: BLoC-логику MUST NOT переписывать; dev-only поверхности (`ui_kit_page`/`screens_gallery_page`/`item_list_page`) вне scope.

**Подтверждения владельца (гейтят 2 задачи):**

- **FR-012**: QR torch / switch-camera сейчас доступны только на mobile. [NEEDS CLARIFICATION: оставить намеренно (desktop macOS = windowed webcam, обычно без вспышки) или добавить camera-switch на desktop при нескольких камерах? (R7)]
- **FR-013**: Account identity: «раскрыть сырой ID» доступно только mobile, inline account-QR только desktop. [NEEDS CLARIFICATION: оставить намеренно (Принцип I — desktop shared-screen, минимизация раскрытия секрета) или унифицировать оба layout? (R8)]

### Key Entities

- **Responsive-экран**: страница/виджет с `_narrow`/`_wide` ветками по `constraints.maxWidth >= Constants.railBreakpoint` (13 файлов — цели паритет-сверки).
- **Извлекаемый компонент**: `App*Widget` или приватный `StatelessWidget` (E1–E13 в бэклоге).
- **Дизайн-токен**: `NoxOpacity.{scrim,disabled,ring}` + именованные геометрия-const (O1–O2).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Все 5 реальных паритет-дефектов (FR-001…FR-006, исключая подтверждения) закрыты; для каждого есть тест/golden, который ПАДАЛ бы до фикса и проходит после.
- **SC-002**: 0 непреднамеренных регрессий UI — все существующие голдены (кроме осознанно-перегенерированных паритет-baseline) остаются зелёными; `make gate` зелёный на КАЖДОМ merge.
- **SC-003**: Дубли UI-деревьев из E1–E13 сведены к единым виджетам — каждый источник использует один виджет (0 остаточных копий по grep).
- **SC-004**: Magic-opacity и геометрия-числа из O1–O2 заменены именованными токенами равного значения — 0 raw-opacity-литералов вне `lib/design/theme/` в затронутых файлах.
- **SC-005**: На каждом из 13 responsive-экранов перечень действий/состояний в `_narrow` и `_wide` совпадает (кроме подтверждённых намеренных исключений FR-012/FR-013).

## Assumptions

- Голдены обеих категорий (page-mobile + page-desktop) существуют для всех product-страниц и служат основной страховкой от регресса (проект-правило «3 golden-categories»).
- FR-012/FR-013 предполагаются НАМЕРЕННЫМИ (текущее поведение сохраняется) до подтверждения владельцем в `/speckit-clarify`.
- Полный обоснованный бэклог R1–R28 и первичный анализ — в `docs/presentation-refactor-review.md` (source of truth задач для `/speckit-tasks`).
- Constitution Принцип II (design-system fidelity) и V (language discipline) соблюдаются; Принцип I (privacy) — контекст FR-013.
- Работа НЕ зависит от бэкенда — целиком в рамках текущей UI-first фазы.

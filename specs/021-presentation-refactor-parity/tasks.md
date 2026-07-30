# Tasks: Рефакторинг presentation-слоя + паритет mobile/desktop

**Feature**: `021-presentation-refactor-parity` | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)
**Source backlog**: `docs/presentation-refactor-review.md` (R1–R28) | **Contract**: [parity-matrix](./contracts/parity-matrix.md)

**Гейт на КАЖДУЮ задачу перед merge:** `make gate` + `make golden-verify` зелёные; merge `--no-ff` в `develop` (без push). Behavior-preserving (US2/US3) → голдены БЕЗ churn; паритет (US1) → fail-first-тест + осознанная перегенерация baseline «отстающей» ветки. Одна задача = один фич-бранч.

---

## Phase 1: Setup

- [ ] T001 Зафиксировать baseline: прогнать `make gate` + `make golden-verify` на `develop`, убедиться, что всё зелёное (регресс-точка отсчёта для всех задач)

## Phase 2: Foundational

Явных блокирующих предпосылок нет — user stories независимы. Общие извлечённые примитивы (E3/E4/O1) вводятся внутри своих задач; зависящие задачи (R6↔E3, R22↔E4-ring) помечены в Dependencies ниже.

---

## Phase 3: User Story 1 — Паритет mobile↔desktop (Priority: P1) 🎯 MVP

**Goal**: закрыть 5 реальных паритет-дефектов; подтвердить 2 намеренных различия. **Independent test**: по каждой строке `contracts/parity-matrix.md` набор действий/состояний совпадает в `_narrow` и `_wide` (или отмечен ✔ intentional); каждый фикс имеет fail-first-тест.

- [x] T002 [P] [US1] R1 — `error_page.dart` `_wide` ветвление по `ErrorPageMode` (blocking → `PopScope(canPop:false)`, embedded → back-аффорданс, titlebar сохранить) в `lib/presentation/pages/error_page/error_page.dart`; fail-first widget-тест (`PopScope` в desktop-blocking-дереве) + desktop-golden на blocking
- [x] T003 [P] [US1] R2 — max-width message-bubble из локальной ширины панели (`LayoutBuilder`/`BoxConstraints`) в `lib/presentation/widgets/chat/app_message_bubble_widget.dart`; перегенерировать desktop thread page-golden + добавить golden на list-detail панель
- [x] T004 [P] [US1] R3 — desktop titlebar subtitle через `context.l10n` и per-tab из `_active` в `lib/presentation/widgets/shell/tab_bar_shell_widget.dart` (+ subtitle-param в `app_window_titlebar_widget.dart` при необходимости); новый desktop-golden на Settings-таб
- [x] T005 [P] [US1] R4 — `Semantics(button, selected, label)` на rail-destination в `lib/presentation/widgets/shell/app_navigation_rail_widget.dart`; a11y-тест в `test/presentation/widgets/accessibility_test.dart` (isButton+isSelected на rail)
- [x] T006 [P] [US1] R5 — mobile create-chat: guard `_cancel`/`PopScope` по `state.isSubmitting` в `lib/presentation/pages/create_chat_page/create_chat_page.dart` (`_narrow`); widget-тест (при submit leading disabled / pop подавлен)
- [x] T007 [US1] R6 — сверено с корпусом (`desktop-screens.jsx` `ChatsListPane`): desktop pane-header БЕЗ hairline by design (бренд-hairline — под window-titlebar; mobile — под AppBar). **НЕ дефект → код не менять**; отмечено ✔ intentional в review + parity-matrix. Существующий desktop chats golden уже фиксирует корректный header
- [x] T008 [P] [US1] R7 — подтвердить QR torch/switch mobile-only как намеренное: отметить ✔ в `docs/presentation-refactor-review.md` + `contracts/parity-matrix.md` (код НЕ менять) — владелец подтвердил (FR-012)
- [x] T009 [P] [US1] R8 — подтвердить account reveal/QR split как намеренное (Принцип I): отметить ✔ в `docs/presentation-refactor-review.md` + `contracts/parity-matrix.md` (код НЕ менять) — владелец подтвердил (FR-013)

**Checkpoint US1**: строки 1–5 parity-matrix → ✅ (fail-first-тест + golden), 6–8 → ✔ confirmed-intentional (R6 переклассифицирован по сверке с корпусом); SC-001/SC-005 выполнены.

---

## Phase 4: User Story 2 — Вынос в переиспользуемые виджеты (Priority: P2)

**Goal**: 13 дублей → единые виджеты, визуально без изменений. **Independent test**: голдены затронутых экранов (mobile+desktop) БАЙТ-в-байт зелёные до/после; grep подтверждает 0 остаточных копий.

- [x] T010 [P] [US2] E1 — `AppPrimaryButtonWidget{label,onPressed,loading}` в `lib/presentation/widgets/onboarding/app_primary_button_widget.dart`; заменить login_page:249 + set_username_page:172; widget-golden (idle+loading). onPressed pass-through (сохраняет разные enable-правила сайтов), убраны 2 ad-hoc Theme.of; login/username page-goldens БЕЗ churn
- [x] T011 [US2] E2 — `AppOnboardingScaffoldWidget{subtitle,field,actions,mobileActionsPadding?}` в `lib/presentation/widgets/onboarding/`; перевести login_page + set_username_page (зависит от T010); login/username mobile+desktop goldens без churn. Удалены `_narrow`/`_wide` из обеих страниц + 4 unused import каждая; login/username page-goldens БАЙТ-в-байт
- [x] T012 [P] [US2] E5 — `WatchChat{chatId,initial,builder}` виджет в `lib/presentation/widgets/chat/`; дедуп 4 `StreamBuilder<ChatModel?>` (app_thread_view:129, chat_thread_page:76, chat_card_page:119/217); thread/card goldens без churn. builder получает resolved chat (snapshot.data ?? initial); удалён unused global_aliases import в 3 файлах; goldens БЕЗ churn
- [x] T013 [P] [US2] E4 — `AppRingedAvatarWidget{name,size,initials?}` в `lib/presentation/widgets/primitives/` (ring 0.06 локальной const до R22); заменить ВСЕ 4 сайта (chat_card header + chats_list mobile account + app_chat_item row + nav_rail account), не только 2 из ревью; −4 unused app_avatar import, −2 unused colorScheme local; goldens БЕЗ churn (Container(decoration:)≡DecoratedBox)
- [x] T014 [P] [US2] E3 — `AppHairlineDividerWidget` (const) в `lib/presentation/widgets/primitives/`; заменить 11 `Divider(height: border.hairline)` (settings_root ×5/chat_card/notifications/item_list/thread_header/identity_card/settings_group); VerticalDivider'ы не тронуты (O5/R27); 2 unused dimension-import убраны; все затронутые goldens без churn
- [x] T015 [P] [US2] E6 — приватный `_SettingsPaneHeader{title,leading?,trailingInset?}` в `settings_root_page.dart` (menu/detail headers, delta right-inset s8/s16 сохранён через trailingInset); `Align→Row([?leading,Expanded(Text)])` пиксель-идентично; −2 textTheme/colorScheme local; desktop settings golden без churn
- [x] T016 [P] [US2] E7 — приватный `_attachmentPreview(attachment,{onColor,imageSize,onImageTap,onChipTap,onRemove})` в `app_thread_view_widget.dart` — единый image-thumbnail/type-chip dispatch для `_bubble` (tap→viewer/File view) и `_composerBar` (removable draft); inBubble/removable выводятся из callbacks; thread goldens без churn
- [x] T017 [P] [US2] E8 — `showAdaptiveLightbox(context,{dialogChild,route,insetPadding?,maxWidth?})` в `lib/presentation/helpers/adaptive_lightbox.dart`; перевести `showFileView` (maxWidth=contentMaxW, default inset) + `openImageViewer` (insetPadding=all(s24)); Dialog строится без insetPadding-арг когда не задан (null≠default); −1 unused import; оба viewer goldens (mobile+desktop) без churn
- [x] T018 [P] [US2] E9 — публичный `AppBannerShellWidget{padding,children,crossAxisAlignment?}` в `widgets/state/` (Material surfaceContainer/level3 + Padding + Row); notice-strip (center) + info-banner (start) переведены; −2 unused nox_tokens import; оба widget goldens без churn
- [x] T019 [P] [US2] E10 — приватный `_QrDesktopViewfinder{preview,onEnterManually}` вынесен из `_wide` в `qr_scan_page.dart`; camera-preview резолвится на call-site (ленивость сохранена); −1 textTheme local; qr goldens без churn
- [x] T020 [P] [US2] E11 — rail sub-trees → приватные StatelessWidget (`_NavRailCreateFab`/`_NavRailDestination{icon,selectedIcon,label,selected,onTap}`/`_NavRailAccountAvatar`) в `app_navigation_rail_widget.dart`; методы→классы, render идентичен; desktop shell/rail goldens + a11y rail-тест без churn
- [x] T021 [P] [US2] E12 — `_devMenuRows()` (List<Widget>, kDebug-gated) spread `..._devMenuRows()` в `_narrow` + `_menuPane` в `settings_root_page.dart`; идентичные строки, goldens без churn (тесты в debug-mode → dev-строки в goldens покрыты)
- [x] T022 [P] [US2] E13 — `AppDevScenarioDropdown<T extends Enum>{value,items:Map<T,String>,onChanged,label?,isExpanded}` в `lib/presentation/widgets/`; дедуп ВСЕХ 6 debug-dropdown (thread/card/list scenario + login/username/create outcome); null-guard+items-map+label-Row внутри; 0 остаточных DropdownButton вне виджета; goldens без churn (demo-only, не в goldens)

**Checkpoint US2**: SC-003 выполнен (0 копий по grep); все существующие goldens зелёные.

---

## Phase 5: User Story 3 — Токенизация и чистка (Priority: P3)

**Goal**: magic-числа → токены, hoisting `Theme.of`, снятие дублей/мёртвого кода; поведение неизменно. **Independent test**: голдены зелёные; значения токенов равны прежним литералам.

- [x] T023 [US3] O1/R22 — `NoxOpacity.{scrim=0.5,disabled=0.38,ring=0.06}` в `lib/design/theme/nox_opacity.dart`; заменены 6 magic-opacity (chat_card/file_view/side_sheet scrim + file_view/composer disabled + ringed_avatar ring); scrim 0.55→0.5 сведён (file_view desktop light+dark перегенерированы, только scrim-альфа, layout цел); прочие same-value → без churn
- [ ] T024 [P] [US3] O2/R23 — именованные геометрия-const (`_loadMoreThreshold=200` в app_thread_view:106, `qrDesktopReticleFraction=0.78` в qr_scan_page:389, splash reveal-scale `0.85` в splash_page:51); goldens без churn
- [ ] T025 [P] [US3] O3/R24 — hoisting `Theme.of` в один вызов: chats_list_page:360/379 (paged itemBuilder), app_identity_card_widget:89-90/114-115, shell-виджеты; goldens без churn
- [ ] T026 [US3] O4/R25 — снять dead `inShell`-ветку `_backOrNull` + консолидировать третий back-button в `settings_root_page.dart`; settings goldens без churn
- [ ] T027 [US3] O5/R26 — убрать двойной hairline rail↔body (один владелец края: rail-border ИЛИ `VerticalDivider` в `tab_bar_shell_widget.dart:213`); перегенерировать desktop shell golden (~1px)
- [ ] T028 [P] [US3] O6/R27 — `_neutralSurface(ColorScheme)` в `qr_scan_page.dart` (4 `ColoredBox(surfaceContainerHighest)` + `Theme.of` один раз, убрать per-frame в `errorBuilder`); qr goldens без churn
- [ ] T029 [P] [US3] O7/R28 — mobile thread AppBar title `maxLines:1 + TextOverflow.ellipsis` в `chat_thread_page.dart:81`; chat_thread golden без churn

**Checkpoint US3**: SC-004 выполнен (0 raw-opacity вне `lib/design/theme/` в затронутых файлах).

---

## Phase 6: Polish & cross-cutting

- [ ] T030 Финальная сверка `contracts/parity-matrix.md`: все 16 строк ✅/✔; прогнать mobile+desktop goldens затронутых экранов рядом
- [ ] T031 Финальный `make gate` + `make golden-verify` на `develop` после всех merge; отметить статусы R1–R28 в `docs/presentation-refactor-review.md`

---

## Dependencies

- **US1 (P1) — MVP**, независим и поставляется первым. T007 (R6) опционально переиспользует T014 (E3); если T014 ещё нет — inline-divider.
- **US2 (P2)**: T011 (E2) зависит от T010 (E1). T013 (E4 ring 0.06) — локальная const, позже токенизируется в T023.
- **US3 (P3)**: T023 (O1) завершает токенизацию ring из T013. Остальные O-задачи независимы.
- Между US1/US2/US3 нет жёстких зависимостей — можно поставлять инкрементально в порядке P→E→O.

## Parallel execution

- US1: T002, T003, T004, T005, T006, T008, T009 — разные файлы, `[P]` (T007 после/без T014).
- US2: T010, T012, T013, T014, T015, T016, T017, T018, T019, T020, T021, T022 — разные файлы, `[P]` (T011 после T010).
- US3: T024, T025, T028, T029 — `[P]`; T023/T026/T027 — точечно.

## Implementation strategy

- **MVP = US1 (паритет)** — user-visible дефекты, главный запрос владельца. Останов после US1 уже даёт ценность.
- Дальше US2 (снижает поверхность), затем US3 (косметика). Каждая задача — отдельный merge с зелёными гейтами.
- Порядок исполнения фаз: P (T002–T009) → E (T010–T022) → O (T023–T029) → Polish (T030–T031).

# NOX — ревью presentation-слоя: рефакторинг + паритет mobile/desktop

> **Отчёт + подготовленная задача (backlog).** Детальный обзор `lib/presentation/` на предмет
> (1) выноса в переиспользуемые виджеты, (2) оптимизации/чистоты, (3) — главный приоритет —
> **паритета mobile↔desktop** (фича/действие есть на одной платформе и нет на другой).
> Составлен 2026-07-28 многоагентным обзором (`wf_21837314`: 5 подсистемных агентов + выделенный
> паритет-свип по 13 responsive-файлам → синтез). Ключевые паритет-находки перепроверены вручную
> в коде (отмечено ✔).
>
> **Статус кода: не тронут.** Это подготовка; выполнение — по бэклогу R1…R28 ниже.

## Executive summary

36 сырых находок → **28 позиций бэклога**: **8 паритет-разрывов** (5 реальных дефектов, 3 намеренных —
нужно только подтверждение владельца), **13 выносов в виджеты**, **7 оптимизаций**.

Самый серьёзный — **PG-1 (`error_page`)**: на desktop полностью игнорируется `ErrorPageMode`, из-за чего
**fatal-ошибка на широком окне закрывается системным «назад»** (на mobile она блокирующая через
`PopScope(canPop:false)`). Это дефект корректности на боевом пути (login/splash/create_chat/set_username/
settings — все зовут `ErrorPageParams.fatal()`), а не косметика.

Остальное — чистые внутренние улучшения без изменения поведения.

## Guardrail (обязателен для КАЖДОЙ задачи бэклога)

- Каждое изменение держит голдены зелёными в **обеих** категориях: **page-mobile** (`goldenTest`, 360)
  и **page-desktop** (`goldenTestDesktop`, 1280×800) — плюс `make gate` + `make golden-verify` зелёные.
- Всё **behavior-preserving**. ЕДИНСТВЕННОЕ исключение — паритет-правки **R1–R6**: там baseline на «неверной»
  ветке осознанно перегенерируется (раньше golden фиксировал неправильный layout), и добавляется тест,
  ловящий именно закрытый gap.
- BLoC-логику не переписываем. Dev-only поверхности (`ui_kit_page`/`screens_gallery_page`/`item_list_page`)
  вне scope.
- Ритм на задачу: реализация → `make gate` + `make golden-verify` → adversarial-ревью → фикс → merge
  `--no-ff` в `develop` (никогда не push) → отметка в этом файле.

---

## 1. Паритет mobile ↔ desktop (высший приоритет)

### PG-1 ✔ `error_page` desktop игнорирует `ErrorPageMode` — РЕАЛЬНЫЙ ДЕФЕКТ
`error_page.dart:75-84`. `_wide`-ветка возвращает один `Scaffold(Column[AppWindowTitlebarWidget, Expanded(body)])`
для ОБОИХ режимов и `_mode` не читает. `_narrow` (85-98) ветвится: embedded → AppBar с back-arrow; blocking →
`PopScope(canPop:false)`.
- **Что где:** mobile — back (embedded) + подавление pop (blocking); desktop — ни того, ни другого.
- **Последствия:** (1) blocking/fatal на desktop закрывается system-back — терминальное состояние escapable
  (боевой путь: `login_page:152`, `splash_page:113`, `create_chat_page:86`, `set_username_page:77`,
  `settings_root_page:366`); (2) embedded-ошибка на широком окне без пути назад.
- **Fix:** в `_wide` тоже ветвиться по `_mode` (back для embedded, `PopScope(canPop:false)` для blocking),
  сохранив titlebar.

### PG-2 ✔ Ширина bubble считается от окна, а не от локальной панели — РЕАЛЬНЫЙ ДЕФЕКТ
`app_message_bubble_widget.dart:55`: `maxWidth: MediaQuery.sizeOf(context).width * 0.8`. На desktop thread-панель
ограничена (`threadReadingColumnW≈980`) и в list-detail сидит в панели много уже окна.
- **Что где:** на mobile 80%-«коридор» own/other работает; на desktop cap выходит шире панели → bubbles
  заполняют всю панель, коридор пропадает.
- **Fix:** брать ограничение из локальной доступной ширины (`LayoutBuilder`/`BoxConstraints`), не из окна.

### PG-3 ✔ Desktop titlebar subtitle — захардкоженный `'Chats'` — РЕАЛЬНЫЙ ДЕФЕКТ
`tab_bar_shell_widget.dart:202`: `const AppWindowTitlebarWidget(subtitle: 'Chats')`.
- **Что где:** (1) сырой английский литерал в обход l10n (весь остальной shell — через `context.l10n.chats/.settings`),
  на UK не локализуется; (2) статичный — переключение на Settings оставляет `NOX · Chats`, тогда как mobile
  имеет реальные per-tab app-bars.
- **Fix:** subtitle из `_active` (`_active == AppTab.chats ? context.l10n.chats : context.l10n.settings`),
  сверив формулировку с `nox-desktop-screens`.

### PG-4 Rail-destination на desktop без `Semantics`, которые даёт mobile bottom bar — a11y-дефект
`app_navigation_rail_widget.dart:110-137` — голый `InkWell + Column`; mobile `app_bottom_bar_widget.dart:79-82`
оборачивает каждый пункт в `Semantics(button:true, selected:selected, label:label)`.
- **Fix:** обернуть rail-destination в тот же `Semantics`.

### PG-5 ✔ Mobile create-chat не блокирует отмену во время submit — РЕАЛЬНЫЙ ДЕФЕКТ
`create_chat_page.dart:108` (mobile leading `onPressed:_cancel`, без guard) vs `:161` (desktop Cancel под
`state.isSubmitting`) + `:44` (`barrierDismissible:false`).
- **Что где:** на mobile можно отменить уже стартовавший create — гонка, которую desktop запрещает.
- **Fix:** guard `_cancel` (и/или `PopScope`) по `state.isSubmitting` в mobile-ветке.

### PG-6 Desktop chats list-pane header без hairline — визуальный паритет
`chats_list_page.dart:259-279` — desktop `_paneHeader` без `Divider`/hairline, тогда как mobile header несёт
brand-hairline (`:185`), а desktop settings menu-pane ставит `Divider` после header (`settings_root_page.dart:238`).
- **Fix:** сверить с `nox-desktop-screens/screens/01-chats.md`; если hairline ожидается — добавить (питается R11).
- **РЕЗОЛЮЦИЯ (T007, 2026-07-28): НЕ дефект — кода не менять.** Сверка с авторитетным корпусом
  `docs/design/system/nox-desktop-screens/_src/desktop-screens.jsx` (`ChatsListPane`): pane-header — это
  `<PaneHeader title="Chats" />` БЕЗ `border-bottom`; единственная граница панели — её `borderRight`
  (шов список↔тред, уже есть через `AppListDetailWidget`). Бренд-hairline (`AppSplashHairlineWidget`) на desktop
  живёт под **window-titlebar** (`desktop-shell.jsx:52` «signature brand-splash hairline — same motif as mobile
  app bars»), а на mobile — под AppBar каждого экрана (`chats_list_page.dart:185`). Т.е. hairline присутствует на
  обеих платформах, но на своём корпусном месте — это корректная per-platform адаптация, а не паритет-дефект.
  Добавление hairline под desktop pane-header было бы дивергенцией от корпуса (Принцип IV). Существующий
  desktop chats golden уже фиксирует корректный (без-hairline) header. Отметка ✔ intentional в parity-matrix.
  (Замечание на будущее, вне scope R6: desktop settings pane-header в коде несёт `Divider` после себя —
  стоит отдельно сверить с `SettingsListPane`, где такого шва под header тоже нет; это E6/O-территория.)

### PG-7 QR torch/switch-camera только на mobile — ПОДТВЕРДИТЬ (вероятно намеренно)
`qr_scan_page.dart:282-294` — camera actions только в mobile AppBar; desktop viewfinder их не даёт.
Задокументировано как намеренное (header-doc «Desktop macOS: windowed viewfinder, no camera actions» + FR-005).
- **Действие:** подтвердить намеренность (кода менять не требуется).
- **РЕЗОЛЮЦИЯ (T008, 2026-07-28): подтверждено владельцем — намеренно, mobile-only.** (Clarification к spec 021,
  FR-012: «Оставить mobile-only (намеренно)»; desktop использует системную webcam без torch/switch.) Код не менять;
  ✔ intentional в parity-matrix (строка 7).

### PG-8 Account identity: reveal raw-ID только mobile, inline QR только desktop — ПОДТВЕРДИТЬ (намеренно)
`settings_root_page.dart:188` (mobile `revealable:true, showInlineQr:false`) vs `:287` (desktop
`revealable:false, showInlineQr:true`). Задокументировано под Принципом I (desktop = shared screen, сырой ID
сознательно не показывается). Оба layout дают Copy + Show-QR.
- **Действие:** подтвердить приватностный сплит (риск изменения high — не менять).
- **РЕЗОЛЮЦИЯ (T009, 2026-07-28): подтверждено владельцем — намеренно (Принцип I).** (Clarification к spec 021,
  FR-013: «Оставить намеренно (Принцип I)»; desktop — общий экран, сырой ID сознательно не раскрывается, но базовый
  паритет Copy + Show-QR сохранён на обеих ветках.) Код не менять; ✔ intentional в parity-matrix (строка 8).

---

## 2. Вынос в виджеты (behavior-preserving)

- **E1 · `AppPrimaryButtonWidget{label,onPressed,loading}`** — `login_page.dart:249-257` ≡ `set_username_page.dart:172-180`
  (full-width submit со swap spinner↔label + лишний `Theme.of` ради `onPrimary`).
- **E2 · `AppOnboardingScaffoldWidget{subtitle,field,actions,mobileActionsPadding?}`** — `_narrow`/`_wide` login
  (`login_page.dart:181-223`) ≡ set_username (`105-144`); отличия только subtitle и mobile actions-padding. QR
  `_wide` может адоптировать.
- **E3 · `AppHairlineDividerWidget`** (const) — `Divider(height: border.hairline)` ×11 (`settings_root_page`,
  `app_identity_card_widget:63`, `notifications_body:95`). Единая точка правки, питает PG-6.
- **E4 · `AppRingedAvatarWidget`** — «subtle ring» вокруг `AppAvatarWidget` вручную в `chat_card_page.dart:226`
  и `chats_list_page.dart:216` (ring-token 0.06 из R22).
- **E5 · `WatchChat{chatId,initial,builder}`** — `StreamBuilder<ChatModel?>(watchChat…)` ×4 (`app_thread_view_widget:129`,
  `chat_thread_page:76`, `chat_card_page:119`, `:217`).
- **E6 · `_SettingsPaneHeader{title,leading?}`** — `_menuPane`/`_detailPane` headers (`settings_root_page.dart:227-238`
  / `300-307`), delta right-padding сохранить.
- **E7 · attachment-preview helper** — `canRender ? AppImageAttachmentWidget : AppFileChipWidget` дважды в
  `app_thread_view_widget.dart` (`_bubble` / `_composerBar`), параметризовать `onTap` vs `onRemove`.
- **E8 · `showAdaptiveLightbox`** — `showFileView` (`file_view_page.dart:24-39`) ≡ `openImageViewer`
  (`image_viewer_page.dart:14-27`).
- **E9 · `_ElevatedBannerShell` (тонкий)** — общий `Material(surfaceContainer, elevation:level3, icon-row)` у
  `AppNoticeStripWidget` / `AppInfoBannerWidget` (layouts различаются — shell держать тонким).
- **E10 · `_QrDesktopViewfinder`** — большое inline scanning-state desktop (`qr_scan_page.dart:371-403`) в приватный виджет.
- **E11 · rail sub-trees → приватные StatelessWidget** — `_createFab`/`_destination`/`_accountAvatar`
  (`app_navigation_rail_widget.dart:80-157`), по образцу `_Tab` в bottom bar.
- **E12 · `_devMenuRows()`** — идентичный dev-блок продублирован (`settings_root_page.dart:197-201` / `258-263`).
- **E13 · `AppDevScenarioDropdown<T extends Enum>`** — ~6 почти идентичных kDebug-dropdown (thread/card/list/create/
  login/set_username). Debug-only, голдены demo не покрывают — ниже по ценности.

---

## 3. Оптимизация / чистота (behavior-preserving)

- **O1 · `NoxOpacity.{scrim,disabled,ring}` + свести scrim к одному значению** — magic-opacity россыпью: scrim
  `0.5` vs `0.55` (`file_view_page.dart:207` — необъяснённая рассинхронизация), disabled `0.38`, ring `0.06`.
- **O2 · геометрия/scale → именованные const** — pagination `200` (`app_thread_view_widget.dart:106`), QR reticle
  `0.78` (`qr_scan_page.dart:389`), splash reveal-scale `0.85` (`splash_page.dart:51`).
- **O3 · hoisting `Theme.of` sweep** — per-row в paged itemBuilder (`chats_list_page.dart:360,379`), тройной
  re-fetch в identity card (`89-90,114-115`), двойной вызов в shell-виджетах.
- **O4 · dead code back-affordance в settings** — `_backOrNull` (`settings_root_page.dart:151-153`) недостижимая
  ветка + третий ручной back-button (175-181).
- **O5 ✔ двойной hairline rail↔body** — rail сам рисует правый `Border` (`app_navigation_rail_widget.dart:48-53`),
  shell добавляет `VerticalDivider` (`tab_bar_shell_widget.dart:213`) — два цвета в ~2px шов.
- **O6 · QR `_neutralSurface(ColorScheme)`** — `ColoredBox(surfaceContainerHighest)` ×4 + per-frame `Theme.of`
  в `errorBuilder` (`qr_scan_page.dart:261`).
- **O7 · mobile thread AppBar title `maxLines:1 + ellipsis`** — `Text(current.name)` (`chat_thread_page.dart:81`)
  без обрезки, в отличие от всех прочих chat-name.

---

## 4. Задача: приоритизированный бэклог (R1…R28)

Порядок: паритет (реальные дефекты → confirm-only) → низкорисковые высокоценные выносы → оптимизации.

> **✅ СТАТУС: ВЕСЬ БЭКЛОГ R1–R28 ЗАКРЫТ** (spec `021-presentation-refactor-parity`, ветка `021-…`, смёржено в `develop`).
> Каждый пункт — отдельный коммит с fail-first/golden-страховкой; `make gate` (732 теста) + `make golden-verify` (216 goldens) зелёные; три адверсариальных ревью на границах US1/US2/US3 (16 агентов суммарно) — 1 подтверждённая находка (R4 a11y-дубль), исправлена.
> - **R1–R5** — реальные паритет-дефекты, закрыты (US1 / T002–T006), каждый с fail-first-тестом + golden.
> - **R6–R8** — подтверждены намеренными (R6 сверен с корпусом — pane-header без hairline by design; R7/R8 — владелец, FR-012/FR-013). Кода не менялось.
> - **R9–R21 (E1–E13)** — 13 выносов в виджеты (US2 / T010–T022), behavior-preserving, page/widget-goldens байт-в-байт, 0 остаточных копий по grep.
> - **R22–R28 (O1–O7)** — 7 оптимизаций (US3 / T023–T029): `NoxOpacity`-токены (scrim 0.55→0.5), именованные геометрия-const, hoisting `Theme.of`, `_neutralSurface`, снятие dead-кода/двойного hairline, ellipsis mobile-thread-title. 2 осознанных pixel-изменения (scrim, hairline ~1px) — перегенерированы и заэйболены; прочее без churn.
>
> Детализация по задачам: `specs/021-presentation-refactor-parity/tasks.md` (T001–T031, все `[x]`); паритет-контракт: `contracts/parity-matrix.md` (16/16 ✅/✔).

| id | title | cat | eff | risk | safety net | acceptance |
|---|---|:--:|:--:|:--:|---|---|
| R1 | `error_page` `_wide` ветвится по `ErrorPageMode` (back / `PopScope`) | parity | M | med | desktop error-golden (blocking) + widget-тест на `PopScope` в wide | fatal на desktop неотменяем system-back; embedded имеет back |
| R2 | bubble max-width из локальной ширины панели (`LayoutBuilder`) | parity | M | med | desktop page-golden (перегенерить) + golden list-detail | коридор own/other виден в панели на desktop |
| R3 | desktop titlebar subtitle через l10n и per-tab из `_active` | parity | S | med | desktop-golden на Settings-таб (новый) | subtitle локализуется (UK) и меняется Chats↔Settings |
| R4 | rail-destination `Semantics(button,selected,label)` | parity·a11y | S | low | a11y-тест в `accessibility_test.dart` | скринридер объявляет selected+button на rail |
| R5 | mobile create-chat guard `_cancel`/`PopScope` по `isSubmitting` | parity | S | low | widget-тест: при submit leading disabled/pop подавлен | нельзя отменить create in-flight (как на desktop) |
| R6 | desktop chats `_paneHeader` hairline (после сверки с nox-desktop-screens) | parity | S | low | desktop chats golden | заголовок панели несёт тот же сепаратор |
| R7 | подтвердить QR torch/switch mobile-only | confirm | S | low | — | владелец подтвердил; не менять |
| R8 | подтвердить приватностный сплит account-card | confirm | S | high | — | владелец подтвердил Принцип I; не менять |
| R9 | `AppPrimaryButtonWidget` | extract | S | low | login+set_username goldens (idle+loading) | единый full-width submit; убраны 2 ad-hoc `Theme.of` |
| R10 | `AppOnboardingScaffoldWidget` | extract | M | low | login+set_username mobile+desktop goldens | обе onboarding-страницы из одного scaffold |
| R11 | `AppHairlineDividerWidget` (11 сайтов) | extract | S | low | затронутые goldens | один источник hairline; питает R6 |
| R12 | `AppRingedAvatarWidget` (ring из R22) | extract | S | low | chat_card + chats_list goldens | ring в одном месте |
| R13 | `WatchChat{chatId,initial,builder}` (дедуп ×4) | extract | M | low | thread/card/chats goldens + bloc/widget тесты | 4 reactive chat-name сайта на одном виджете |
| R14 | `_SettingsPaneHeader{title,leading?}` | extract | M | low | desktop settings golden | menu/detail из одного header |
| R15 | `_devMenuRows()` spread в обе ветки | extract | S | low | kDebug — ручная проверка | один источник dev-строк |
| R16 | attachment-preview helper (`onTap`/`onRemove`) | extract | M | low | thread page goldens | canRender/localPath/size в одном месте |
| R17 | `showAdaptiveLightbox` (file-view/image-viewer) | extract | M | low | оба viewer goldens (mobile+desktop) | breakpoint+dialog/push в одной точке |
| R18 | `_ElevatedBannerShell` (notice/info) | extract | S | low | оба widget goldens | Material/elevation/icon-row в одном месте |
| R19 | вынести `_QrDesktopViewfinder` | extract | M | low | qr page-desktop golden | `_wide` короче |
| R20 | rail sub-trees → приватные StatelessWidget | extract | M | low | desktop shell/rail goldens | единый локальный `Theme.of`; изоляция rebuild |
| R21 | `AppDevScenarioDropdown<T extends Enum>` (×6) | extract | M | low | demo не покрыт голденами — ручная проверка | ~60 строк дублей снято |
| R22 | `NoxOpacity.{scrim,disabled,ring}` + свести scrim | optim | S | low | desktop file-view golden (если 0.55→0.5) | все scrim одинаковы; токенизировано |
| R23 | токенизировать геометрию (200, 0.78, 0.85) | optim | S | low | thread/qr/splash goldens (значения те же) | нет magic-layout-чисел |
| R24 | hoisting `Theme.of` sweep | optim | S | low | затронутые goldens | один `Theme.of` на build |
| R25 | снять dead `inShell`-ветку + третий back-button | optim | S | low | settings goldens | одна точка back-affordance |
| R26 | убрать двойной hairline rail↔body | optim | S | low | desktop shell golden (~1px, перегенерить) | один шов rail↔body |
| R27 | QR `_neutralSurface(ColorScheme)` + `Theme.of` раз | optim | S | low | qr goldens | нет per-frame `Theme.of` в errorBuilder |
| R28 | mobile thread AppBar title `maxLines:1 + ellipsis` | optim | S | low | chat_thread golden | длинное имя обрезается как везде |

## Предлагаемые фазы выполнения

1. **Фаза P (паритет-дефекты):** R1 → R5 → R4 → R6 → R2 → R3. Каждый — с новым тестом/голденом, ловящим gap.
   R7/R8 — вопросы владельцу (подтвердить намеренность, кода не трогать).
2. **Фаза E (выносы, низкий риск):** R11 → R9 → R12 → R18 → R13 → R5-родственные; голдены = страховка «UI не изменился».
   R10/R14/R16/R17/R19/R20 — крупнее, но всё behavior-preserving.
3. **Фаза O (оптимизация):** R22 → R24 → R23 → R25 → R27 → R28 → R26. Значения/поведение неизменны; голдены ловят регресс.
4. **Debug-only (по желанию):** R15, R21 — голдены demo не покрывают, проверять вручную.

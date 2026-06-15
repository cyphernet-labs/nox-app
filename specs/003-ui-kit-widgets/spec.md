# Feature Specification: UI-кит — библиотека виджетов представления

**Feature Branch**: `003-ui-kit-widgets`

**Created**: 2026-06-15

**Status**: Draft

**Input**: User description: «В `lib/presentation/widgets` собрать весь UI-кит: реализовать все компоненты дизайн-системы (`docs/design/system`) по стандартам реализации из блюпринта (`docs/blueprints/mobile`). Для каждого нового виджета — golden-тест (через подготовленный скилл) и widget-тест.»

## Контекст и границы

NOX-приложение уже заскаффолжено (Feature-001), а дизайн-система ингестирована в `lib/design` + `assets/` (Feature-002): токены, тема (`ColorScheme`/`TextTheme`/`NoxBrand`), шрифты, 37 SVG-иконок, 3 empty-state-иллюстрации. Авторитетный каталог компонентов — `docs/design/system/nox-handoff-2/` (надмножество `nox-handoff/`: добавляет `spec/primitives.md` и референсный `flutter/widgets/*.dart` + живую галерею `preview.html`). До этой фичи в `lib/presentation/widgets/` нет ни одного компонента — слой существует только как заглушка (`.gitkeep`).

Эта фича реализует **все** компоненты дизайн-системы как переиспользуемые виджеты в `lib/presentation/widgets/`, строго по паттернам блюпринта (token-дисциплина, BLoC-less переиспользуемые виджеты, гейт качества). «Пользователь» этой фичи — **разработчик NOX**, собирающий экраны из кита. Сами продуктовые экраны/страницы — вне scope.

Решения по уточнениям (зафиксированы 2026-06-15):

- **Нейминг** — все виджеты кита следуют блюпринт-конвенции `App*Widget` (таблица нейминга, [05]/[08]); хелперы/enum/функции — обычный Dart-нейминг. Идентичность из дизайн-корпуса (`Nox*`) сохраняется как ссылка на источник, но **классы виджетов называются `App*Widget`**.
- **Scope сверх каталога** — дополнительно: (1) полный M3 component-theme wiring stock-виджетов в `app_theme.dart`; (2) generic state-виджеты (`AppProgressWidget` / `AppErrorWidget`); (3) реальные SVG-иллюстрации в empty-state.
- **Визуальная проверка** — обязательные golden + widget тесты на каждый виджет **плюс** dev-only in-app галерея.

## Clarifications

### Session 2026-06-15

- Q: Стратегия покрытия golden-тестами вариантов виджета (у некоторых много комбинаций)? → A: Кураторский набор — 2–4 ключевых варианта на виджет (не полная матрица комбинаций), каждый в light и dark.
- Q: Получают ли стилизуемые темой stock-виджеты (FilledButton, TextField, SegmentedButton, AlertDialog, SnackBar) собственные golden-тесты? → A: Нет — один сводный theme-showcase golden (light+dark) на все stock-виджеты; отдельные golden/widget-тесты только у кастомных `App*Widget`.
- Q: Как именовать enum'ы виджет-API кита (референс: NoxFileType / NoxMsgStatus / NoxTab)? → A: Без `Nox`-префикса, по App*-конвенции (`FileType` / `MessageStatus` / `AppTab`); design-layer токен-символы (`NoxBrand`/`NoxRadius`/`noxAvatarColor`/`noxFileColor`) сохраняют исходные имена.
- Q: Механизм исключения dev-галереи из релизных сборок и продуктовой навигации? → A: Отдельная dev-точка входа `main_gallery.dart` — ноль следа в продуктовом `main.dart` и релизных бинарниках.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Фундамент: примитивы, тема stock-виджетов, generic state-виджеты (Priority: P1)

Разработчик подключает тему NOX и собирает базовый экран: stock-виджеты (`FilledButton`, `TextField`, `SegmentedButton`, диалоги, snackbar) уже выглядят как NOX без кастом-классов; доступны примитивы (иконка, спиннер, аватар, файл-глиф) и виджеты состояний загрузки/ошибки/пустоты для `state.when(...)`.

**Why this priority**: без token-дисциплинированной темы и примитивов невозможно собрать ни один корректный экран; это минимальный жизнеспособный слой, на котором стоит весь остальной кит.

**Independent Test**: подключить `AppTheme.light()/dark()`, отрендерить стандартный набор stock-виджетов + примитивы + state-виджеты; golden-снапшоты (light+dark) и widget-тесты проходят; `flutter analyze` без ошибок.

**Acceptance Scenarios**:

1. **Given** подключённая `AppTheme`, **When** разработчик размещает stock `FilledButton`/`TextField`/`SegmentedButton`/`AlertDialog`/`SnackBar`, **Then** они отображаются с NOX-биндингами (форма, цвета, типографика) без кастомных классов — только через тему.
2. **Given** примитив `AppAvatarWidget(name:)`, **When** имя даёт валидные инициалы, **Then** показываются белые инициалы на детерминированном по хешу фоне; **When** валидных инициалов нет, **Then** показывается белый `forum`-глиф на том же фоне.
3. **Given** экран в состоянии загрузки/ошибки/пустоты, **When** используется `AppProgressWidget`/`AppErrorWidget`/`AppEmptyContentWidget`, **Then** рендерится соответствующее состояние; у `AppErrorWidget` есть retry-CTA, вызывающий переданный коллбэк.
4. **Given** любой примитив из этой истории, **When** запускаются тесты, **Then** для него существуют и проходят golden-тест (light+dark) и widget-тест.

---

### User Story 2 — Чат/сообщения: composite-виджеты (Priority: P2)

Разработчик собирает поверхности чата и списка чатов из готовых composite-виджетов: строка чата с unread-бейджем, пузырь сообщения (own/other, статусы, опц. файл-чип), файл-чип-вложение, композер ввода, search-бар, segmented-контрол.

**Why this priority**: это ядро продуктовой поверхности NOX (списки чатов и переписка); зависит от примитивов US1, но независимо демонстрируется и тестируется.

**Independent Test**: отрендерить список из `AppChatItemWidget` и тред из `AppMessageBubbleWidget` (own/other/со статусами/с файлом) + `AppComposerWidget` + `AppSearchBarWidget`; golden- и widget-тесты на все варианты проходят.

**Acceptance Scenarios**:

1. **Given** `AppChatItemWidget(unread:)`, **When** `unread == 0`, **Then** бейдж не рендерится; **When** `unread > 99`, **Then** бейдж показывает `99+`; при `unread > 0` — акцент (name полужирнее, time в `primary`).
2. **Given** `AppMessageBubbleWidget(isOwn:)`, **When** `isOwn == true`, **Then** заливка `primaryContainer`, нижне-правый угол скруглён до `xs`, при статусе — иконка `schedule`/`check`/`error`; **When** `isOwn == false`, **Then** заливка `surfaceContainerHigh`, нижне-левый угол `xs`, без статуса.
3. **Given** `AppComposerWidget`, **When** значение пустое, **Then** кнопка send неактивна (`onSurface`@38%); **When** есть текст (`sendActive`), **Then** send активна (`primary`, fill 1) и тап вызывает `onSend`.
4. **Given** `AppFileChipWidget(inBubble:)`, **When** `inBubble == true`, **Then** тинт выводится из цвета текста пузыря; **When** `removable == true`, **Then** есть `×` (tap-target ≥48), вызывающий `onRemove`.
5. **Given** любой composite-виджет этой истории, **When** запускаются тесты, **Then** для него существуют и проходят golden-тест (light+dark) и widget-тест (включая интерактивные коллбэки).

---

### User Story 3 — Оболочка и обратная связь (Priority: P2)

Разработчик собирает app-frame: нижний бар с двумя вкладками и центральным docked `+` FAB, brand-splash-hairline под AppBar, wordmark «NOX», транзиентный snackbar и persistent banner.

**Why this priority**: задаёт продуктовую навигационную оболочку NOX (3-элементный бар + FAB) и каналы обратной связи; независимо тестируема.

**Independent Test**: собрать `Scaffold` с `AppBottomBarWidget` + `AppCreateFabWidget` (centerDocked) и `AppSplashHairlineWidget`/`AppWordmarkWidget` в AppBar; вызвать snackbar/banner-хелперы; golden- и widget-тесты проходят.

**Acceptance Scenarios**:

1. **Given** `AppBottomBarWidget(active:)`, **When** активна вкладка, **Then** её иконка filled и в `primary`, неактивная — `onSurfaceVariant`; **When** тап по вкладке, **Then** вызывается `onSelect`; **`+` FAB виден на обеих вкладках** (действие, не вкладка) и докуется в notch.
2. **Given** snackbar-хелпер, **When** `error == false`, **Then** нейтральная пара `inverseSurface`/`onInverseSurface`; **When** `error == true`, **Then** `errorContainer`/`onErrorContainer`; banner-хелпер рендерит persistent `MaterialBanner` (`surfaceContainer`, action в `primary`).
3. **Given** `AppSplashHairlineWidget`, **When** размещён в `AppBar.bottom`, **Then** рендерит 3dp brand-градиент (teal→lime→gold→coral→red), фиксированный вне `ColorScheme`.
4. **Given** любой виджет/хелпер этой истории, **When** запускаются тесты, **Then** существуют и проходят golden-тест (где применимо) и widget-тест.

---

### User Story 4 — Dev-only галерея кита (Priority: P3)

Разработчик/ревьюер открывает dev-only экран-каталог, где каждый виджет показан во всех вариантах в light и dark, и сверяет его с референс-галереей (`preview.html`).

**Why this priority**: ускоряет ручное ревью и онбординг, но не входит в продукт; кит полезен и без него (golden-тесты — основная визуальная истина).

**Independent Test**: запустить приложение в dev-режиме, открыть галерею, убедиться, что отображается каждый виджет кита в обоих режимах темы; экран не достижим из продуктовой навигации и не входит в релизные сборки.

**Acceptance Scenarios**:

1. **Given** dev-сборка, **When** открыта галерея, **Then** видны все виджеты кита (примитивы, composite, shell, state-виджеты, stock-виджеты) с их ключевыми вариантами.
2. **Given** галерея, **When** переключается тема, **Then** каждый виджет корректно перерисовывается в light и dark.
3. **Given** релизная сборка / продуктовая навигация, **When** пользователь её использует, **Then** галерея недоступна.

---

### Edge Cases

- **Аватар**: имя без валидных инициалов → белый `forum`-глиф; пустое имя; очень длинное имя; не-латиница/emoji; детерминированность цвета по одному и тому же имени.
- **Unread-бейдж**: `0` → скрыт; `1..99` → число; `>99` → `99+`.
- **Пузырь сообщения**: только текст / только файл / текст+файл; own vs other (clip угла и заливка); статусы `pending`/`sent`/`error`; очень длинный текст (перенос, max-width 80%); `isLast` (интер-групповой отступ).
- **Файл-чип**: standalone vs `inBubble` (тинт от `onColor`); `removable`; очень длинное имя (ellipsis); неизвестный тип → `draft`-глиф.
- **Композер**: пусто (send disabled) vs есть текст (send active); с прикреплённым `AppFileChipWidget(removable: true)`.
- **Empty-state**: длинные headline/message; отсутствующий ассет иллюстрации (graceful fallback).
- **Search-бар**: с значением (текст `onSurface`) vs только hint (`onSurfaceVariant`).
- **Тема**: переключение light↔dark не ломает контраст; масштабирование текста (text scale 1.3–2.0) не ломает раскладку tap-таргетов.
- **Generic error-виджет**: с сообщением и без; повторные тапы retry.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Каждый компонент дизайн-системы из `nox-handoff-2` (примитивы + composite + shell/feedback) MUST быть реализован как переиспользуемый виджет в `lib/presentation/widgets/` по конвенции `App*Widget`. Enum'ы виджет-API кита именуются по App*-конвенции **без** `Nox`-префикса (`FileType` / `MessageStatus` / `AppTab`); функции-маппинги и design-layer токен-символы (`NoxBrand`/`NoxRadius`/`noxAvatarColor`/`noxFileColor`/`noxFileIcon`) сохраняют исходные имена.
- **FR-002**: Виджеты кита MUST быть переиспользуемыми и **без собственного BLoC**; их состоянием управляет страница-владелец (блюпринт [05] §5). Виджеты конфигурируются конструктор-параметрами и коллбэками, **не** обращаются к репозиториям/DI и не содержат бизнес-логики.
- **FR-003**: В коде виджетов MUST NOT быть хардкод-значений цвета, отступа, типографики, радиуса, elevation. Только токены: `ColorScheme`-роли + `context.appColors`, `AppSpacingTokens`, `Theme.textTheme`, `NoxRadius`/`NoxElevation`, и `NoxBrand` для brand-fixed. Референсный Dart адаптируется: raw-значения заменяются токенами; недостающие шаги токен-шкал расширяются в `lib/design`, оставаясь в дизайн-токен-дисциплине.
- **FR-004**: Token-bindings каждого виджета MUST соответствовать `nox-handoff-2/spec/components.md` и `primitives.md` (в т.ч.: иконки через `NoxIcons`-SVG с `fill` 0/1 как выбор `name`/`name-fill`; аватар = `noxAvatarColor(name)` + белые инициалы `titleMedium`-ish; радиус пузыря `NoxRadius.bubble(isOwn:)`; tap-таргеты 48).
- **FR-005**: Все виджеты MUST поддерживать light и dark темы.
- **FR-006**: Brand-fixed элементы MUST рендериться фиксированно вне `ColorScheme` через `NoxBrand`: splash-hairline-градиент (teal→lime→gold→coral→red), brand-teal иконка поиска, поверхность QR (`qrSurface`/`qrInk`) и splash-фон (`canvasDark`).
- **FR-007**: Иконки MUST рендериться из **SVG-реестра `NoxIcons`** (`flutter_svg`/`SvgGenImage`, Feature-002) через единый примитив-обёртку — **не** из icon-шрифта. Рекраска — на месте через `ColorFilter` (иконки ship `fill="currentColor"`); FILL-ось = выбор SVG-варианта (`name.svg` / `name-fill.svg`). Провенанс глифов — Material Symbols Rounded (weight 400 / optical 24 / grade 0); пакет `material_symbols_icons` **не** добавляется.
- **FR-008**: Empty-state-виджет MUST использовать реальные SVG-иллюстрации из `assets/svg/illustrations/` (Feature-002) через `flutter_svg`/сгенерированный `assets.gen`, а не placeholder-рамку референса; маппинг иллюстрации задаётся параметром/типом.
- **FR-009**: `lib/design/theme/app_theme.dart` MUST быть расширен полным M3 component-theme wiring stock-виджетов из референсного `nox_theme.dart` (как минимум `inputDecorationTheme`, `filledButtonTheme`, `textButtonTheme`, `iconButtonTheme`, `segmentedButtonTheme`, `switchTheme`, `radioTheme`, `listTileTheme`, `progressIndicatorTheme`, `dialogTheme`, `bottomSheetTheme`, `cardTheme`, `snackBarTheme`, `appBarTheme`), чтобы stock-виджеты выглядели как NOX без кастом-классов. Корректность темизации stock-виджетов подтверждается **одним сводным theme-showcase golden-тестом** (light+dark), охватывающим все stock-виджеты; отдельные golden/widget-тесты на stock-виджеты не создаются (они не новые классы).
- **FR-010**: MUST быть реализованы generic state-виджеты `AppProgressWidget` (загрузка) и `AppErrorWidget` (иконка ошибки + опц. сообщение + retry-CTA), а также `AppEmptyContentWidget` (пустота) — для потребления в `state.when(initializing/error)` и пустых списках страниц.
- **FR-011**: Транзиентная и persistent обратная связь MUST предоставляться хелперами (snackbar neutral/error; persistent offline-banner) в стиле канала блюпринта [05] §8, а не голыми вызовами в коде фич.
- **FR-012**: UI-микрокопия по умолчанию (hints/labels внутри виджетов, напр. `Search`/`Message`) MUST быть на English и браться из `TextConstants`; голых строк в виджетах быть не должно.
- **FR-013**: Для **каждого** нового виджета (`App*Widget`) MUST существовать golden-тест (сгенерированный подготовленным скиллом `golden-test`), покрывающий **кураторский набор из 2–4 ключевых вариантов** (а не полную матрицу комбинаций параметров), каждый в light и dark.
- **FR-014**: Для **каждого** нового виджета (`App*Widget`) MUST существовать widget-тест (сгенерированный подготовленным скиллом `widget-test`), проверяющий рендеринг, варианты состояний и интерактивные коллбэки (`onTap`/`onSend`/`onChanged`/`onRemove`/`onSelect`).
- **FR-015**: MUST быть реализован in-app экран-галерея (`UiKitPage`), рендерящий каждый виджет кита в light и dark, с переключателем темы (`AppThemeToggle` → `AppRootBloc`). На текущем этапе (реальных продуктовых фич ещё нет) стартовый экран приложения — **лаунчер `HomePage`** с кнопкой «Open UI Kit», открывающей `UiKitPage` (`Navigator.push`); лента/реальные экраны на старте не показываются, пока не появятся продуктовые фичи. *(Уточнено владельцем 2026-06-15: галерея открывается из продуктового лаунчера, а не отдельной dev-точкой входа — прежняя формулировка про `main_gallery.dart` отменена.)*
- **FR-016**: Виджеты MUST соблюдать доступность, **проверяемую тестами**: (a) интерактивные tap-таргеты ≥ 48×48 dp (icon actions, remove-`×`, вкладки бара, FAB, send/attach композера, search) — assert'ы размера в widget-тестах; (b) раскладка не ломается (нет overflow/обрезки) при `textScaler` до 2.0 — widget-тест на масштабирование; (c) осмысленные семантики (`Semantics`/`tooltip` у icon-only действий).
- **FR-017**: Виджеты MUST оставаться платформенно-нейтральными leaf-компонентами (без platform-specific API — `dart:io`/`Platform`/`defaultTargetPlatform`/`kIsWeb`), что проверяется grep'ом по `lib/presentation/widgets`; те же leaf-виджеты переиспользуются desktop-оболочкой (адаптация раскладки — на уровне shell, вне scope этой фичи).
- **FR-018**: Перед завершением MUST пройти гейт качества блюпринта: codegen один прогон → формат изменённых файлов (`-l 140`) → `flutter analyze` без ошибок → затронутые тесты зелёные. Сгенерированные файлы руками не правятся.

### Key Entities — каталог компонентов

Каждая запись: целевой класс (`App*Widget`) — назначение — ключевые варианты — источник в дизайн-корпусе.

**Примитивы**

- **`AppIconWidget`** — обёртка над `NoxIcons`/`SvgGenImage`: SVG-глиф с рекраской через `ColorFilter` (дефолт `onSurfaceVariant`) и выбором filled-варианта по `fill` 0/1. Провенанс — Material Symbols Rounded. *(← `NoxIcon`)*
- **`AppSpinnerWidget`** — индетерминантный прогресс-примитив; standalone → `primary`, внутри `FilledButton` → `onPrimary`. *(← `NoxSpinner`)*
- **`AppAvatarWidget`** — генерируемый аватар: детерминированный фон по хешу имени + белые инициалы либо белый `forum`-глиф; всегда круг. *(← `NoxAvatar`)*
- **`AppFileGlyphWidget`** — иконка типа файла в мягком тинтованном скруглённом квадрате. *(← `NoxFileGlyph`)*
- **Хелперы/enum (не виджеты):** `FileType` (enum, без `Nox`-префикса), `noxFileIcon`/`noxFileColor`, `noxAvatarColor`/`noxInitials` — маппинги типа файла и аватара.

**Composite (чат/сообщения)**

- **`AppSearchBarWidget`** — persistent search (brand-teal иконка, `surfaceContainerHigh`, stadium, elevation 2). *(← `NoxSearchBar`)*
- **`AppChatItemWidget`** — строка чата: аватар-ring + name + preview + time + unread-бейдж (скрыт при 0, cap `99+`), unread-акцент. *(← `NoxChatListItem`)*
- **`AppFileChipWidget`** — чип-вложение: тип-иконка + имя (ellipsis) + размер; standalone / `inBubble` (тинт от `onColor`); опц. remove-`×`. *(← `NoxFileChip`)*
- **`AppMessageBubbleWidget`** + **`MessageStatus`** (enum) — пузырь: own (`primaryContainer`) / other (`surfaceContainerHigh`), clip угла `NoxRadius.bubble(isOwn:)`, опц. файл-чип внутри, статус own `pending/sent/error`, max-width 80%. *(← `NoxMessageBubble`/`NoxMsgStatus`)*
- **`AppComposerWidget`** — инпут: attach + текст + send (active `primary` fill 1 / disabled 38%), опц. attachment-чип сверху. *(← `NoxComposer`)*
- **`AppSegmentedWidget<T>`** — single-select segmented (тонкая обёртка над `SegmentedButton`, стилизуется темой). *(← `NoxSegmented`)*

**Оболочка и обратная связь**

- **`AppSplashHairlineWidget`** — 3dp brand-градиент-rule под AppBar (`PreferredSizeWidget`). *(← `NoxSplashHairline`)*
- **`AppWordmarkWidget`** — заголовок «NOX» (Roboto Bold 700, letter-spacing +0.12em). *(← `NoxWordmark`)*
- **`AppBottomBarWidget`** + **`AppCreateFabWidget`** + **`AppTab`** (enum) — нижний бар (`BottomAppBar` + `CircularNotchedRectangle`, две вкладки) + docked `+` FAB (виден на обеих вкладках). *(← `NoxBottomBar`/`NoxCreateFab`/`NoxTab`)*
- **Feedback-хелперы:** `showAppSnackBar` (neutral/error) + `showAppBanner` (persistent offline). *(← `showNoxSnackBar`/`showNoxBanner`)*

**Generic state-виджеты (блюпринт; группа `state/`)**

- **`AppProgressWidget`** — центрированное состояние загрузки (оборачивает `AppSpinnerWidget`).
- **`AppErrorWidget`** — состояние ошибки: иконка `NoxIcons.error` + опц. message + retry-CTA.
- **`AppEmptyContentWidget`** — empty-state: реальная SVG-иллюстрация (`Assets.svg.illustrations.*`) + headline + message. *(← `NoxEmptyState`)*

**Тема и галерея**

- **`AppTheme` (расширение)** — per-component M3 sub-themes stock-виджетов (FR-009).
- **Dev-only галерея** — экран-каталог всех виджетов в light+dark (FR-015).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% новых виджетов кита имеют **и** golden-тест (light+dark), **и** widget-тест; все тесты зелёные.
- **SC-002**: Каждый визуальный компонент, встречающийся в экранах `docs/design/spec/screens/*`, собирается из кита **без** net-new ad-hoc виджетов (проверяется маппингом «компонент экрана → виджет кита»; покрытие 100%).
- **SC-003**: В `lib/presentation/widgets/` — ноль хардкод-значений цвета/отступа/типографики/радиуса/elevation вне токенов (проверяется ревью/grep по литералам `Color(`, `EdgeInsets`, числовым размерам и `TextStyle(` без токен-источника).
- **SC-004**: `flutter analyze` — 0 ошибок; затронутые тесты (`fvm flutter test`) зелёные; codegen — один прогон без правок сгенерированных файлов руками.
- **SC-005**: Каждый виджет визуально совпадает со своим референсом в `nox-handoff-2/flutter/widgets/preview.html` в light и dark — подтверждается чек-лист-сверкой dev-галереи с `preview.html` (по виджетам, оба режима темы; `quickstart §3`).
- **SC-006**: Stock-виджеты (`FilledButton`, `TextButton`, `IconButton`, `TextField`, `SegmentedButton`, `SwitchListTile`, `RadioListTile`, `LinearProgressIndicator`, `AlertDialog`, `SnackBar`, bottom sheet, `Card`) визуально соответствуют дизайн-спеке **только через тему**, без кастом-классов; подтверждается одним сводным theme-showcase golden-тестом (light+dark).

## Assumptions

- `docs/design/system/nox-handoff-2/` — авторитетный источник каталога компонентов и token-bindings (надмножество `nox-handoff/` v1); токены и тема в `lib/design` (Feature-002) синхронны с handoff и не правятся в обход токен-источника.
- Stock-виджеты (`FilledButton`, `TextButton`, `IconButton`, `TextField`, `SegmentedButton`, `SwitchListTile`, `RadioListTile`, `LinearProgressIndicator`, `AlertDialog`, `SnackBar`, bottom sheet, `Card` — полный канонический список в SC-006) **не** реоборачиваются кастом-классами — стилизуются темой (FR-009); тонкие generic-обёртки допускаются там, где упрощают вызов (напр. `AppSegmentedWidget`).
- RTL — вне scope (языки приложения English + Українська, оба LTR).
- Реальные продуктовые экраны/страницы, навигация и бизнес-логика — вне scope; кит = leaf-виджеты + тема stock-виджетов + dev-галерея. Экраны (splash, QR-scan, camera-overlay) — отдельные фичи; здесь предоставляются лишь нужные им виджеты и brand-fixed константы.
- Desktop-адаптация (NavigationRail, two-pane list-detail, lightbox, drawer) — на уровне shell в будущих фичах; те же leaf-виджеты переиспользуются без изменений.
- `AppSpacingTokens` при нехватке шагов (референс использует более мелкую 4dp-сетку) расширяется недостающими значениями в `lib/design`, оставаясь в дизайн-токен-дисциплине; `NoxBrand`/палитра аватаров уже доступны в `lib/design/theme`.
- golden- и widget-тесты генерируются подготовленными скиллами `golden-test` / `widget-test`; `bloc-test` не применяется (у виджетов кита нет BLoC). Конкретная golden-инфраструктура (тест-harness, тема в тесте) настраивается на этапе plan.
- Перевод исключений в текст (для `AppErrorWidget`/snackbar) и строки `TextConstants` дополняются по мере необходимости на English.

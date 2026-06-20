# Research — UI-кит (Phase 0)

Решения, снимающие неопределённости Technical Context. Формат: **Decision / Rationale / Alternatives considered**. Источники истины: каталог `docs/design/system/nox-handoff-2/` (`spec/components.md`, `spec/primitives.md`, `flutter/widgets/*.dart` — референс), блюпринт `docs/blueprints/mobile/05,06,10`, фактический код `lib/design` (Feature-002) и тест-скиллы `.claude/commands/{golden,widget}-test.md`.

---

## R1. Механизм рендера иконок — SVG-реестр `NoxIcons`, не icon-шрифт

**Decision.** `AppIconWidget` рендерит **SVG** через `NoxIcons` / `Assets.svg.icons.*` (`SvgGenImage` из `flutter_svg`, Feature-002). Цвет — `ColorFilter.mode(color, BlendMode.srcIn)` поверх `fill="currentColor"`; дефолт `onSurfaceVariant`. FILL-ось = выбор SVG-варианта (`name` → outlined, `nameFill` → filled), а **не** числовая ось шрифта. Пакет `material_symbols_icons` **не** добавляется.

**Rationale.** Референсный Dart хендофа (`NoxIcon` поверх `Icon(Symbols.*)`) — это icon-шрифтовый дефолт хендофа, но фактически Feature-002 занесла **37 SVG-иконок + семантический реестр `NoxIcons`** (`lib/design/nox_icons.dart`), а `pubspec` содержит `flutter_svg`, но **не** `material_symbols_icons`. Конституция (Принцип IV) и `icons.md` делают icon-реестр частью верности дизайн-системе. Сохранение SVG-пути: ноль новых зависимостей, единый канал ассетов (flutter_gen), filled-варианты уже забандлены (`forum-fill.svg`, `send-fill.svg`, `settings-fill.svg`, `flashlight_on-fill.svg`). Это исправляет дрейф spec `FR-007` (см. plan, Constitution Check II).

**Alternatives considered.** (a) Добавить `material_symbols_icons` и рендерить `Icon(Symbols.*, fill:)` — отвергнуто: новая зависимость + шрифт, дублирующий уже занесённые SVG, расхождение с Feature-002. (b) Стоковые `Icons.*` — отвергнуто: не Rounded-провенанс, нет точного FILL-контроля.

**Следствие для API.** `noxFileIcon(FileType)` возвращает `SvgGenImage` (а не `IconData`); статус-иконки пузыря (`schedule`/`check`/`error`), `add` FAB, табы (`forum`/`forumFill`, `settings`/`settingsFill`), `forum`-fallback аватара — всё через `NoxIcons`.

---

## R2. Адаптация референса под дисциплину дизайн-токенов

**Decision.** Референсный Dart **переписывается** под токены, не копируется дословно:

- **Цвет** → роли `Theme.of(context).colorScheme` + `context.appColors` (`AppColors` ThemeExtension); brand-fixed — только `NoxBrand.*`. Ни одного `Color(0x…)` в коде виджетов (brand-teal иконка поиска `0xFF12B4B4` → `NoxBrand.teal`; splash-градиент → `NoxBrand.teal/lime/gold/coral/red`).
- **Типографика** → роли `Theme.of(context).textTheme` (+ `AppTextStyleTokens` где нужен явный размер/`.sp`). Ни одного `TextStyle(fontSize:…)`; вордмарк-letter-spacing берётся как `style.copyWith(letterSpacing: …)` от роли, значение — именованная const по спеке.
- **Радиус/elevation** → `NoxRadius.*` / `NoxElevation.*` (включая `NoxRadius.bubble(isOwn:)`).
- **Spacing/паддинги по 4dp-сетке** → `AppSpacingTokens.sN` (отзывчивые, screenutil — мандат блюпринта `06 §4`). Недостающие шаги (`s2`,`s6`,`s10`,`s14`,`s20`,`s56`,…) **добавляются** в `lib/design/app_spacing_tokens.dart` по мере надобности.
- **Компонент-собственные размеры** (avatar 40, search-bar height 56, unread-badge 20, illustration-box 132, FAB-icon 26, hairline 3) → именованные `static const` внутри файла виджета с комментом-ссылкой на `nox-handoff-2/spec`. Их «источник токена» = спека компонента; голых неименованных чисел в layout нет (удовлетворяет `SC-003`).

**Rationale.** Блюпринт `06` и Принцип IV запрещают хардкод *тематических* значений; референс же изобилует raw-числами и хексами. Двухсистемность spacing (`NoxSpacing` фиксированный 4dp в `nox_tokens.dart` vs `AppSpacingTokens` отзывчивый) разрешается в пользу `AppSpacingTokens` для layout-гэпов (мандат блюпринта; детерминизм goldens обеспечен фиксированным surface 360×779, где scale=1 → значения = design-px). `NoxRadius`/`NoxElevation`/`NoxBrand` — единственный канал shape/elevation/brand.

**Alternatives considered.** (a) Дословный порт с `NoxSpacing`/raw-числами — отвергнуто: нарушает токен-дисциплину блюпринта и `SC-003`. (b) Полностью загнать все размеры в `AppSpacingTokens` — отвергнуто: компонент-собственные размеры (132, 56) — не члены spacing-шкалы, их место — именованные const компонента.

---

## R3. Переиспользуемые виджеты — без BLoC

**Decision.** Все виджеты кита — `StatelessWidget` (или `StatefulWidget` только для локальной анимации/контроллера ввода), **без** собственного BLoC, без `getIt`, без обращений к репозиториям. Состояние и коллбэки приходят сверху (props). Текст по умолчанию — из `TextConstants`.

**Rationale.** Блюпринт `05 §5` / Принцип 5.1: BLoC обязателен лишь для **навигируемых страниц**; переиспользуемым виджетам (`lib/presentation/widgets/`) BLoC **не нужен** — ими управляет страница-владелец. Это держит кит чистым и тестируемым widget-тестами без DI/моков.

**Alternatives considered.** Виджеты с внутренним стейтом-логикой — отвергнуто (противоречит блюпринту, усложняет тесты).

---

## R4. Golden-харнесс — плоский `matchesGoldenFile`, локальный, кураторский набор

**Decision.** Использовать существующий локальный golden-харнесс проекта (см. `.claude/commands/golden-test.md`, `dart_test.yaml`, `Makefile`):

- Плоские Flutter goldens (`expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/<widget>_<scenario>.png'))`), **без** `alchemist`/Docker/CI-джоба.
- `@Tags(['golden'])` + `library;` в шапке → исключение из CI и `make test`; запуск `make golden-update` / `make golden-verify`.
- Детерминизм: общий `test/utils/pump_app.dart` (`ScreenUtilInit(designSize: Constants.designSize=360×779)` + `MaterialApp(AppTheme.light()/dark(), themeMode)` + `textScaler=1.0`); фикс surface `tester.binding.setSurfaceSize(Constants.designSize)` с restore.
- **Кураторский набор 2–4 ключевых варианта на виджет** × light/dark (по уточнению), не полная матрица.
- DI виджетам кита **не нужен** (чистые виджеты) — pump без `configureDependencies`.
- `goldens/*.png` — коммитятся (фикстуры, не codegen).

**Rationale.** Согласуется с уже принятым в проекте подходом (один M1-рендер-сет, локальный regression-aid). Кураторский набор удерживает число снапшотов управляемым при полном покрытии значимых состояний (`SC-001`).

**Alternatives considered.** (a) `alchemist`/Docker для byte-stable cross-host — явно отвергнуто проектом. (b) Полная матрица вариантов — отвергнуто (взрыв файлов; уточнение зафиксировало кураторский набор).

---

## R5. Темизация stock-виджетов — `nox_component_themes.dart` + один theme-showcase golden

**Decision.** Перенести per-component M3 sub-themes из референсного `nox_theme.dart` в новый `lib/design/theme/nox_component_themes.dart` и подключить из `AppTheme._build(...)` (`inputDecorationTheme`, `filledButtonTheme`, `textButtonTheme`, `iconButtonTheme`, `segmentedButtonTheme`, `switchTheme`, `radioTheme`, `listTileTheme`, `progressIndicatorTheme`, `dialogTheme`, `bottomSheetTheme`, `cardTheme`, `snackBarTheme`, `appBarTheme`). Корректность — **один сводный `theme_showcase_golden_test.dart`** (light+dark), рендерящий все stock-виджеты (incl. `IconButton`, `SwitchListTile`, `RadioListTile`, `LinearProgressIndicator`, bottom sheet). Отдельных golden/widget-тестов на stock-виджеты нет (они не новые классы).

**Rationale.** Stock-виджеты (FilledButton/TextField/…) стилизуются темой, а не оборачиваются классами (`SC-006`, assumptions). Вынос sub-themes держит `app_theme.dart` читаемым. Один showcase-golden подтверждает биндинги без класс-на-виджет-взрыва (по уточнению).

**Alternatives considered.** (a) Sub-themes прямо в `app_theme.dart` — отвергнуто (раздувает файл). (b) Golden на каждый stock-виджет — отвергнуто уточнением.

---

## R6. Нейминг — `App*Widget`; enum'ы без `Nox`-префикса

**Decision.** Классы виджетов — `App*Widget` (мандат таблицы нейминга блюпринта `05/08`). Enum'ы виджет-API — без `Nox`: `FileType`, `MessageStatus`, `AppTab`. Design-layer токен-символы (`NoxBrand`, `NoxRadius`, `NoxElevation`, `NoxSpacing`, `noxAvatarColor`, `noxInitials`, `noxFileColor`, `noxFileIcon`, `NoxIcons`) сохраняют исходные имена (это слой `lib/design`/Feature-002, не виджет-API).

**Rationale.** Оба уточнения владельца (нейминг → `App*Widget`; enum'ы → без `Nox`). Единый публичный API кита; токен-слой не трогаем (стабильные сгенерированные/занесённые имена).

**Alternatives considered.** Сохранить `Nox*` на виджетах — отвергнуто уточнением.

---

## R7. Empty-state — реальные SVG-иллюстрации

**Decision.** `AppEmptyContentWidget` рендерит `Assets.svg.illustrations.*` (`emptyChats`/`emptyMessages`/`emptyFiles`, Feature-002) через `flutter_svg`, выбор иллюстрации — параметром виджета. Placeholder-рамка референса не используется.

**Rationale.** Уточнение владельца + `FR-008`; иллюстрации уже забандлены. Fallback-глифы `NoxIcons.chatBubble`/`folderOpen` остаются как graceful-fallback при отсутствии ассета.

**Alternatives considered.** Placeholder-рамка (как в референсе) — отвергнуто уточнением.

---

## R8. Галерея — экран в продуктовом приложении (лаунчер → `UiKitPage`)

**Decision.** Галерея — экран `UiKitPage` (`lib/presentation/pages/ui_kit_page/`), открываемый со стартового лаунчера `HomePage` (`lib/presentation/pages/home_page/`) кнопкой «Open UI Kit» (`Navigator.push(UiKitPage.route())`). `AppRoot` стартует с `HomePage` (вместо `Item`-харнесса). Переключатель темы — общий `AppThemeToggle` (`AppRootBloc.SetTheme`). Запуск: `fvm flutter run`.

**Rationale.** Уточнение владельца (2026-06-15): на текущем этапе (реальных продуктовых фич ещё нет) стартовый экран — простой лаунчер, открывающий каталог кита; лента/реальные экраны не показываются. Это **отменяет** прежнее решение про отдельную dev-точку входа `main_gallery.dart`.

**Alternatives considered.** (a) Отдельная dev-точка входа `lib/main_gallery.dart` — первоначально выбрано, затем отменено уточнением (нужен продуктовый старт-экран). (b) `kDebugMode`-гейт / build flavor — отвергнуто (сложнее, без выгоды на текущем этапе).

---

## R9. Каналы обратной связи — хелперы в `lib/presentation/helpers/`

**Decision.** `showAppSnackBar(context, {text, actionLabel, onAction, error})` и `showAppBanner(context, {text, icon, actionLabel, onAction})` — функции-хелперы в `lib/presentation/helpers/app_feedback_helper.dart` (биндинги: snackbar neutral `inverseSurface`/error `errorContainer`; banner `surfaceContainer`, action `primary`). Они **предпереводят** текст до показа (никакого сырого текста исключения).

**Rationale.** Блюпринт `05 §8` определяет каналы snackbar/диалогов как хелперы (`AlertDialogHelper`-паттерн), а не голые вызовы в фичах (`FR-011`). Виджет-тесты проверяют факт показа `SnackBar`/`MaterialBanner` и биндинги.

**Alternatives considered.** Хелперы как `Nox*`-виджеты — отвергнуто (это императивные каналы поверх `ScaffoldMessenger`, не виджеты).

---

## R10. UI-микрокопи — `TextConstants` (English)

**Decision.** Дефолтные строки кита (`Search`, `Message`, `Dismiss`, заголовок/сообщение ошибки, `Try again`) живут в `lib/general/text_constants.dart` (English, `static const`); виджеты принимают пользовательский текст параметрами и используют `TextConstants` лишь как дефолт. Голых строковых литералов в виджетах нет (`FR-012`).

**Rationale.** Блюпринт + Принцип V (UI-микрокопи — English) + единый источник строк; i18n-инфраструктуры нет (English + Українська — будущая работа, вне scope кита).

**Alternatives considered.** Хардкод дефолтов в виджетах — отвергнуто (`FR-012`).

---

## Сводка: открытых NEEDS CLARIFICATION не осталось

Все неизвестные Technical Context разрешены выше. Бэкенд/протокол не затрагиваются (leaf-виджеты). Платформенно-специфичные подсистемы не активируются. Можно переходить к Phase 1.

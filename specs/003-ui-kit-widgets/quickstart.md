# Quickstart — верификация UI-кита

Гайд проверки, что фича работает end-to-end. Все команды — из корня репо, через `fvm`. Детали API — в `contracts/ui-kit-api.md`, варианты/bindings — в `data-model.md`.

## Предпосылки

- Flutter `3.44.1` (FVM): `fvm use 3.44.1` (или по `.fvmrc`).
- Зависимости: `fvm flutter pub get`.
- Codegen (для `assets.gen.dart` / `*.mocks.dart`, один прогон): `make generate` (= `fvm dart run build_runner build --delete-conflicting-outputs`).
- Goldens рендерятся/верифицируются **только локально на Apple Silicon / macOS** (см. `.claude/commands/golden-test.md`).

## 1. Гейт кода (CI-эквивалент)

```bash
make gate        # generate → format(-l 140) → analyze(0 ошибок) → test(--exclude-tags golden)
```
Ожидаемо: `flutter analyze` без ошибок; все widget-тесты зелёные. (`SC-004`)

## 2. Golden-тесты (локально, M1)

```bash
make golden-update     # сгенерировать/обновить все goldens (--tags golden --update-goldens)
make golden-verify     # проверить goldens без обновления
# узко по файлу:
make golden-update FILE=test/presentation/widgets/chat/app_message_bubble_widget_golden_test.dart
make golden-verify FILE=test/presentation/widgets/chat/app_message_bubble_widget_golden_test.dart
```
Ожидаемо: на каждый `App*Widget` — golden-файлы под `goldens/` (кураторские варианты × light/dark), плюс `test/design/theme/theme_showcase_golden_test.dart` (stock-виджеты). `golden-verify` зелёный. Дифф пишется в gitignored `failures/`. `goldens/*.png` — коммитятся как фикстуры. (`SC-001`, `SC-005`, `SC-006`)

## 3. Запуск галереи (из продуктового лаунчера)

```bash
fvm flutter run        # старт → HomePage-лаунчер → кнопка «Open UI Kit» → UiKitPage
```
Ожидаемо: на старте — лаунчер (`HomePage`) с brand-hero и кнопкой «Open UI Kit»; по тапу открывается `UiKitPage` со всеми виджетами (Primitives / Chat & messaging / State / Feedback & stock); `AppThemeToggle` в app-bar переключает light↔dark; каждый виджет перерисовывается корректно. (`FR-015`) Сверить каждый виджет с референс-галереей `docs/design/system/nox-handoff-2/flutter/widgets/preview.html` (light/dark) — `SC-005`.

## 4. Проверка дисциплины дизайн-токенов (`SC-003`)

```bash
# Не должно быть голых тематических литералов в коде виджетов (brand-overrides — исключение):
grep -REn "Color\(0x|EdgeInsets\.|TextStyle\(" lib/presentation/widgets || echo "OK: токен-дисциплина соблюдена"
```
Ожидаемо: совпадений нет (цвет — роли/`NoxBrand`; spacing — `AppSpacingTokens`/именованные const; типографика — `textTheme`/`AppTextStyleTokens`; shape/elevation — `NoxRadius`/`NoxElevation`).

## 5. Маппинг «экран → виджет» (`SC-002`)

Подтвердить, что каждый визуальный компонент экранов `docs/design/spec/screens/*` собирается из кита без net-new ad-hoc виджетов:

| Экран | Виджеты кита |
|---|---|
| chats-list | `AppWordmarkWidget`, `AppSplashHairlineWidget`, `AppSearchBarWidget`, `AppChatItemWidget`, `AppBottomBarWidget`+`AppCreateFabWidget`, `AppEmptyContentWidget` |
| chat | `AppMessageBubbleWidget`, `AppFileChipWidget`, `AppComposerWidget`, `AppAvatarWidget`, состояния `AppProgress/Error/EmptyContentWidget` |
| create-chat / login / set-username | stock `TextField`/`FilledButton`/`TextButton` (тема), `AppSearchBarWidget`, `AppIconWidget` |
| appearance / language | `AppSegmentedWidget`, stock `RadioListTile`/`SwitchListTile` (тема) |
| settings-root / about | `AppAvatarWidget`, stock `Card`/`ListTile` (тема), `AppIconWidget` |
| file-view / file lists | `AppFileGlyphWidget`, `AppFileChipWidget` |
| error / splash / qr | `AppErrorWidget`, brand-fixed (`NoxBrand.canvasDark`/`qrSurface`), `AppIconWidget` |
| feedback (offline / транзиент) | `showAppBanner` / `showAppSnackBar` |

Ожидаемо: каждая строка покрыта; net-new ad-hoc виджетов в экранах не требуется (сами экраны — будущие фичи; здесь проверяется лишь покрытие каталога).

## 6. Соответствие требованиям

| Проверка | Требование |
|---|---|
| Все `App*Widget` реализованы в `lib/presentation/widgets/` | FR-001, FR-002 |
| Ноль хардкода (шаг 4) | FR-003, SC-003 |
| Bindings совпадают с `components.md`/`primitives.md` | FR-004 |
| light+dark у всех виджетов (галерея + goldens) | FR-005 |
| brand-fixed через `NoxBrand` | FR-006 |
| Иконки — SVG `NoxIcons` (нет `material_symbols_icons`) | FR-007 |
| Empty-state — реальные `Assets.svg.illustrations.*` | FR-008 |
| `app_theme.dart` + `nox_component_themes.dart` + theme-showcase golden | FR-009, SC-006 |
| `AppProgress/Error/EmptyContentWidget` | FR-010 |
| `showAppSnackBar`/`showAppBanner` | FR-011 |
| Дефолт-микрокопи из `TextConstants` (English) | FR-012 |
| golden-тест на каждый виджет (2–4 варианта × l/d) | FR-013, SC-001 |
| widget-тест на каждый виджет (рендер + коллбэки) | FR-014, SC-001 |
| Галерея отдельным entrypoint (шаг 3) | FR-015 |
| tap-таргеты ≥48 (assert) + раскладка при `textScaler=2.0` + семантика/`tooltip` icon-only действий (T070) | FR-016 |
| grep `dart:io`/`Platform.`/`defaultTargetPlatform`/`kIsWeb` пуст в `lib/presentation/widgets` (T071) | FR-017 |
| `make gate` зелёный | FR-018, SC-004 |

## Замечания

- `goldens/*.png` — фикстуры (не codegen): стейджить и коммитить (репо-правило no-auto-commit; ветка работы — `develop`/feature). Перед коммитом — `make golden-verify` локально (CI goldens не проверяет).
- `*.mocks.dart` виджетам кита не нужны (чистые виджеты без DI); `make generate` нужен лишь для `assets.gen.dart`.

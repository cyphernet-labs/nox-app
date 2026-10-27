# Quickstart: Верификация дизайн-системы — ассеты, токены, шрифты

**Feature**: `002-design-system-assets` | **Date**: 2026-06-15 | **Phase**: 1

Runnable-гайд, доказывающий, что все ресурсы заведены и согласованы. Реализация — в `tasks.md`; здесь — как проверить результат. Команды — FVM-based (`docs/blueprints/mobile/12-dev-commands.md`).

## Prerequisites

- Flutter `3.44.1` (FVM): `fvm flutter --version`.
- Принесены шрифтовые `.ttf` в `assets/fonts/` (Apache-2.0; единственный внешний артефакт).

## Setup (после реализации)

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs   # один проход: freezed/json/injectable/flutter_gen
```

## Сценарии верификации (= acceptance из spec.md)

### S1. Иконки заведены (US1 / FR-001..003, SC-001)
```bash
ls assets/svg/icons/*.svg | wc -l          # ожидается 37
fvm dart run build_runner build --delete-conflicting-outputs
grep -c "SvgGenImage" lib/design/gen/assets.gen.dart   # > 0, иконки в аксессорах
```
- **Expected**: 37 файлов; `Assets.svg.icons.*` и `NoxIcons.*` резолвятся; тест резолва иконок зелёный (нет `asset not found`).
- **Reconcile**: 35 используемых + 2 outlined (`flashlight_on.svg`, `send.svg`) = 37 (data-model §1.1).

### S2. Шрифты заведены (US2 / FR-004..005, SC-003)
```bash
ls assets/fonts/*.ttf                       # Roboto-Regular/Medium/Bold + RobotoMono-Regular
grep -A12 "fonts:" pubspec.yaml             # family Roboto (400/500/700) + Roboto Mono (400)
test -f assets/fonts/README.md              # источник + Apache-2.0
```
- **Expected**: `family`-имена точно `Roboto` / `Roboto Mono` (= `nox_text_theme.dart`); текст этих семейств рендерится забандленным шрифтом без silent fallback на всех целевых платформах.

### S3. Бренд и иллюстрации без битых ссылок (US3 / FR-006..007, SC-002, SC-007)
```bash
test -f assets/png/logo.png                 # есть
ls assets/svg/illustrations/*.svg | wc -l   # 3
test ! -f assets/png/logo-reference.png     # reference-only НЕ забандлен
grep -rn "AppImagesTokens" lib/             # пусто — удалён
```
- **Expected**: `Assets.png.logo`, `Assets.svg.illustrations.*` резолвятся; ни одного битого пути; pending-ассеты (вектор/launcher/финальные иллюстрации) отсутствуют и помечены вне scope.

### S4. Полнота и согласованность токенов (US4 / FR-008..010, SC-004)
```bash
# сверка с авторитетным хендофом (значения совпадают; допускается лишь формат)
for f in nox_color_scheme nox_text_theme nox_brand; do
  diff <(tr -s ' \n' ' ' < docs/design/system/nox-handoff/flutter/$f.dart) \
       <(tr -s ' \n' ' ' < lib/design/theme/$f.dart) && echo "OK $f"
done
fvm flutter test test/design/tokens_sync_test.dart      # репрезентативные значения (R6)
grep -c "static TextStyle" lib/design/app_text_style_tokens.dart   # 9 ролей
```
- **Expected**: color/text/brand совпадают; `nox_tokens` совпадает по значениям (формат — к источнику); `AppTextStyleTokens` = 9 ролей шкалы; brand-fixed (#0C2424 / #FFFFFF / #0C0C0C) и 8-цветовая палитра аватаров на месте.

### S5. Единый канал и синхрон блюпринта (US5 / FR-012, FR-014, SC-006)
```bash
grep -rn "'assets/" lib/ | grep -v "lib/design/gen/"    # нет сырых строк путей в коде
grep -n "nox_icons.dart\|AppImagesTokens" docs/blueprints/mobile/06-theming.md  # блюпринт обновлён
```
- **Expected**: flutter_gen — единственный канал; блюпринт §0/§1/§5/§7 отражает реальность (R9).

### S6. Гейт кода (FR-016, SC-005)
```bash
fvm dart format -l 140 $(git diff --name-only '*.dart')
fvm flutter analyze            # 0 ошибок
fvm flutter test               # затронутые тесты зелёные
```
- **Expected**: кодоген — один проход; analyze без ошибок; `lib/design/gen/` не редактирован руками; 0 виджетов/экранов добавлено.

## Definition of Done (сводка)

- [ ] 37 иконок + логотип + 3 иллюстрации забандлены и резолвятся (0 битых путей).
- [ ] Шрифты `Roboto` 400/500/700 + `Roboto Mono` 400 забандлены, объявлены, лицензия зафиксирована.
- [ ] 9 токен-сетов согласованы с `nox-handoff/`; `AppTextStyleTokens` = 9 ролей; `AppImagesTokens` удалён.
- [ ] flutter_gen — единственный канал путей; `NoxIcons` заведён.
- [ ] Блюпринт §0/§1/§5/§7 синхронизирован; кодоген/format/analyze/тесты зелёные; виджетов/экранов не добавлено.

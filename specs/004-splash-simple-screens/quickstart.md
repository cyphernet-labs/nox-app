# Quickstart — проверка экранов M1

Гайд по запуску и валидации фичи `004-splash-simple-screens`. Реализация — `tasks.md` (создаётся `/speckit-tasks`).

## Предпосылки

- FVM Flutter `3.44.1` (`fvm`), зависимости установлены: `make deps`.
- Новые зависимости не требуются (`package_info_plus`/`url_launcher`/`shared_preferences` уже в `pubspec.yaml`).
- Кодоген (если добавятся `*.g`/`*.freezed`): `make generate`.

## Запуск приложения

```bash
fvm flutter run --dart-define-from-file=config/stage.json            # мобайл (эмулятор/устройство)
fvm flutter run --dart-define-from-file=config/stage.json -d macos   # десктоп (или -d windows|linux)
```

Точка входа — `lib/main.dart` → `HomePage` (лаунчер).

## Ручная валидация (по user stories)

1. На `HomePage` нажать **Open Screens** → открывается `ScreensGalleryPage`.
2. Строки **1.1 / 3.1 / 7.2 / 7.3 / 7.4 / 7.6 / 7.7** активны (не `Coming soon`); 2.x/4.1/5.x/6.1 — ещё `Coming soon`.
3. Для каждого экрана проверить **обе темы** (тогл темы в AppBar) и **обе раскладки** (узкое/широкое окно — на десктопе менять ширину окна вокруг 840dp).

| Story | Экран | Что проверить |
|---|---|---|
| US1 | **Splash** | Лого+wordmark на тёмном фоне (одинаково в light/dark); reveal один раз (~400мс), затем статика; экран пассивен. Dev-контролом выбрать исход: `error`→реальный Error(blocking); `hasId`/`noId`→placeholder. |
| US2 | **Error** | `embedded` (есть back) и `blocking` (нет back); `Try again` показывает спиннер; десктоп — TitleBar + крупная иконка. |
| US3 | **Appearance** | Три карточки System/Light/Dark; тап **мгновенно** меняет тему всего приложения; отмечена текущая. |
| US4 | **Language** | Три radio-строки System/English/Українська; System по умолчанию; тап переносит выбор. |
| US5 | **Notifications** | Переключатель push + supporting text; demo-контролом включить `denied` → info-баннер с «open settings». |
| US6 | **Terms** | Прокручиваемые озаглавленные секции + версия в подвале. **About** | Строка `version (build N)`. |

Соответствие критериям — `spec.md` (Acceptance Scenarios, SC-001…007).

## Автоматическая проверка

```bash
# Гейт (codegen → format → analyze → widget-тесты, goldens исключены):
make gate

# Один экран:
make test FILE=test/presentation/pages/splash_page/splash_page_test.dart

# Golden-бейзлайны новых экранов/виджетов (локально, macOS/Apple Silicon):
make golden-update FILE=test/presentation/pages/splash_page/splash_page_golden_test.dart
make golden-verify FILE=test/presentation/pages/splash_page/splash_page_golden_test.dart
```

## Definition of Done (на каждый экран)

- [ ] Обе раскладки (мобайл <840 / десктоп ≥840) по спеке+корпусу.
- [ ] Все состояния (data-model.md) демонстрируемы на заглушках.
- [ ] Токены/`NoxIcons`/`TextConstants` (EN); нет сырых литералов.
- [ ] Строка активирована в Галерее; открывается в light/dark.
- [ ] Бэкенд-зависимости заглушены и помечены `// TODO(backend):`.
- [ ] widget + golden (light/dark) тесты.
- [ ] `make gate` зелёный.

После сдачи M1 — отметить экраны в `docs/roadmap.md` (таблица этапа M1, счётчик прогресса).

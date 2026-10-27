# Quickstart — проверка экранов M2 (онбординг-формы)

Гайд по запуску и валидации фичи `005-onboarding-forms`. Реализация — `tasks.md` (создаётся `/speckit-tasks`).

## Предпосылки

- FVM Flutter `3.44.1` (`fvm`), зависимости установлены: `make deps`.
- **Новые зависимости не требуются** (`mobile_scanner`/`qr_flutter`/`permission_handler` — Фаза 2; debounce на уже доступном `stream_transform`/`rxdart`; `Roboto Mono` уже в `pubspec`).
- Кодоген обязателен (новые `*.freezed.dart` для 3 BLoC + новый asset `no_photography` → `assets.gen.dart`): `make generate`.

## Запуск приложения

```bash
fvm flutter run --dart-define-from-file=config/stage.json            # мобайл (эмулятор/устройство)
fvm flutter run --dart-define-from-file=config/stage.json -d macos   # десктоп (или -d windows|linux)
```

Точка входа — `lib/main.dart` → `HomePage` (лаунчер).

## Ручная валидация (по user stories)

1. На `HomePage` нажать **Open Screens** → открывается `ScreensGalleryPage`.
2. Строки **2.1 Login / 2.2 QR scan / 2.3 Set username** (раздел `Onboarding`) и **6.1 Create chat** (раздел `Create`) активны (не `Coming soon`).
3. Для каждого экрана проверить **обе темы** (тогл темы в AppBar) и **обе раскладки** (узкое/широкое окно — на десктопе менять ширину вокруг 840dp).
4. Состояния — через debug-`SegmentedButton` (виден только в `kDebugMode`, строки Галереи открыты через `routeDemo`).

| Story | Экран | Что проверить |
|---|---|---|
| US1 | **Login (2.1)** | Моно многострочное `Your ID`, `Sign in` enabled при непустом вводе (без валидации формата), `Paste` отражает буфер. Debug-исход: новый ID→placeholder(2.3) · зарегистрированный→placeholder(4.1) · format/net→inline `errorText` · fatal→Error(blocking). Десктоп — `OnboardCard(440)`+`TitleBar('NOX · Sign in')`. |
| US2 | **QR scan (2.2)** | Нейтральный плейсхолдер + brand-fixed прицел (#FAFAFA) + маска (#000@55%, **одинаково в light/dark**) + инструкция + `Enter manually`; actions фонарик/смена камеры (no-op). Debug: Scanning / Permission-denied (`Camera access needed`+`Open settings`) / invalid (snackbar) / fatal. Десктоп — `TitleBar('NOX · Scan QR')`+вьюфайндер≈300dp+helper-ссылка; denied — в `OnboardCard`. |
| US3 | **Set username (2.3)** | Поле предзаполнено `User<random>`, counter `N/32`, helperText. Недопустимый символ→charset-ошибка; «занятое» имя из мок-набора (после debounce)→`This name is taken`; свободное→`Done` enabled; пусто→только `Skip`. Debug submit: success/race-taken/fatal. Десктоп — `OnboardCard`+`TitleBar('NOX · Set up')`. |
| US4 | **Create chat (6.1)** | Поле `Chat name` (counter `N/64`, charset свободный), «занятое»→`This name is taken`, свободное→`Create` enabled. Debug submit: success/network(`Create` снова enabled)/fatal. Мобайл — полноэкранный (`New chat`+back); десктоп — scrim+`Dialog(460)` с `Cancel`+`Create`. |

Соответствие критериям — `spec.md` (Acceptance Scenarios, SC-001…008).

## Автоматическая проверка

```bash
# Гейт (codegen → format → analyze → widget+bloc-тесты, goldens исключены):
make gate

# Один экран / один BLoC:
make test FILE=test/presentation/pages/login_page/login_page_test.dart
make test FILE=test/presentation/pages/login_page/bloc/login_bloc_test.dart

# Golden-бейзлайны новых экранов/виджетов (локально, macOS/Apple Silicon):
make golden-update FILE=test/presentation/pages/qr_scan_page/qr_scan_page_golden_test.dart
make golden-verify FILE=test/presentation/pages/qr_scan_page/qr_scan_page_golden_test.dart
```

## Definition of Done (на каждый экран)

- [ ] Обе раскладки (мобайл <840 / десктоп ≥840) по спеке+корпусу.
- [ ] Все состояния (data-model.md) демонстрируемы на заглушках (мок-набор + debug-переключатель).
- [ ] Токены/`NoxIcons`/`TextConstants` (EN); нет сырых литералов (кроме brand-fixed QR-overlay #000@55%).
- [ ] Строка активирована в Галерее (`routeDemo`); открывается в light/dark.
- [ ] Бэкенд-зависимости заглушены и помечены `// TODO(backend):`.
- [ ] BLoC (2.1/2.3/6.1): `BaseBloc.executeLogic` с `onError`; debounce-transformer на `*Changed`.
- [ ] Тесты: widget + golden (light/dark) на экран и новые виджеты; `bloc_test` на каждый BLoC.
- [ ] `make gate` зелёный.

После сдачи M2 — отметить экраны в `docs/roadmap.md` (таблица этапа M2, счётчик прогресса 7→11 / 17), добавить новые блоки в реестр §6 (онбординг-хром, поле-ввода, QR-overlay).

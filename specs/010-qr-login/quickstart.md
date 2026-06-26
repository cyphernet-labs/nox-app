# Quickstart: проверка QR-code login

**Feature**: `010-qr-login` | **Phase**: 1

Прогоняемые сценарии проверки фичи. Реализация — в `tasks.md` (создаётся `/speckit-tasks`). Интерфейсы — `contracts/`, модель — `data-model.md`.

## Предусловия

- FVM Flutter `3.44.1` (`fvm use`).
- `make deps` — после добавления `mobile_scanner ^7.2.0`, `permission_handler ^12.0.3`, `qr_flutter ^4.1.0` в `pubspec.yaml`.
- `make generate` — кодоген (`QrScanBloc`/`QrScanState`/`QrScanEvent` Freezed + `configure_dependencies.config.dart` с `CameraPermissionService`).
- **Нативные предусловия** (иначе камера крашит/не получает доступ): iOS `NSCameraUsageDescription` + Podfile `PERMISSION_CAMERA=1`; macOS `NSCameraUsageDescription` + `com.apple.security.device.camera` в обоих `*.entitlements`; Android `CAMERA`-пермишен. Camera-entitlement macOS безопасен (ad-hoc-подпись, без dev-team — `research.md` R12).
- Windows/Linux нативных правок не требуют (capability-fallback).

## Сборка/прогон

```bash
make gate                                                    # generate → format → analyze → test (goldens исключены)
make golden-verify                                           # widget + page-mobile + page-desktop goldens
fvm flutter run --dart-define-from-file=config/stage.json    # mobile (реальная камера)
fvm flutter run --dart-define-from-file=config/stage.json -d macos    # macOS _wide viewfinder
mise run build:windows:stage                                 # подтвердить: mobile_scanner НЕ ломает Windows build
mise run build:linux:stage                                   # то же для Linux (R2)
```

## Сценарий 1 — Вход сканированием (US1, SC-001/SC-002)

1. iOS/Android/macOS, свежая установка → Login (2.1).
2. Тап `Scan QR` → открывается 2.2, система запрашивает доступ к камере.
3. Выдать доступ; навести на QR из `nox://id/registered` (например, Show QR другого устройства/эмулятора).
4. **Ожидание**: камера останавливается (single-shot), 2.2 закрывается, id подставляется в поле 2.1 и сразу submit; `registered` → **Chats (4.1)**, новый id → **Set username (2.3)** — идентично ручному вводу. Без звука/вибрации/confirm.

## Сценарий 2 — Show QR ↔ скан (round-trip) (US2, SC-005)

1. Войти, Settings → карточка идентичности → `Show QR`.
2. **Ожидание**: показан настоящий сканируемый QR; сторонний сканер декодирует `nox://id/<тот самый identifier>`. В dark-теме поверхность остаётся светлой.
3. Отсканировать этот QR экраном 2.2 второго устройства.
4. **Ожидание**: второе устройство входит под идентификатором первого.

## Сценарий 3 — Пермишен и чужой QR (US3, SC-003/SC-004)

1. На 2.2 отклонить системный запрос камеры.
2. **Ожидание**: opaque surface `Camera access needed` + `Open settings` (без живого превью).
3. Тап `Open settings` → системные настройки; выдать доступ; вернуться в приложение.
4. **Ожидание**: на `resumed` 2.2 сам переходит в Scanning и стартует камеру — без повторного тапа (FR-006).
5. Навести камеру на сторонний QR (URL/Wi-Fi).
6. **Ожидание**: snackbar `This QR code is invalid. Try another one.`; сканирование продолжается; вход не выполняется.

## Сценарий 4 — Windows/Linux: сканера нет (US4, SC-006)

1. Запустить на Windows или Linux → Login (2.1).
2. **Ожидание**: кнопки `Scan QR` нет; 2.2 недостижим; ручной ввод работает.
3. Открыть `Show QR`.
4. **Ожидание**: настоящий QR отображается (генерация от камеры не зависит).

## Сценарий 5 — Приватность (SC-007)

1. Сканировать в авиарежиме/офлайн.
2. **Ожидание**: распознавание работает полностью офлайн; на диск изображения/кадры не пишутся (`returnImage:false`).

## Автотесты (привязка)

| Уровень | Что проверяет | Файл (целевой) |
|---|---|---|
| unit | `NoxQrEnvelope` round-trip + edge-кейсы | `test/general/nox_qr_envelope_test.dart` |
| unit | `QrScannerCapability` (override true/false) | `test/general/qr_scanner_capability_test.dart` |
| bloc | `QrScanBloc`: granted→scanning, denied→permissionDenied, detected(валид)→decodedId, detected(чужой)→invalid, resumed-авто-старт, unavailable→fatal | `test/presentation/pages/qr_scan_page/bloc/qr_scan_bloc_test.dart` |
| widget | inline-error snackbar; fatal→`AppErrorPage`; back/manual→pop(null); скрытая кнопка `Scan QR` при `debugOverride=false` | `test/presentation/pages/qr_scan_page/qr_scan_page_test.dart`, `test/presentation/pages/login_page/login_page_test.dart` |
| golden (widget) | реальный QR `AppQrSurfaceWidget` (light+dark, surface остаётся светлой) | `test/presentation/widgets/settings/app_qr_surface_widget_golden_test.dart` (regen) |
| golden (page-mobile) | `qr_scan_page` (scanning), `qr_scan_page_denied` | `test/presentation/pages/qr_scan_page/qr_scan_page_golden_test.dart` |
| golden (page-desktop) | `qr_scan_page_desktop` (`_wide` viewfinder), `qr_scan_page_desktop_denied` | там же (`goldenTestDesktop`) |
| golden (page) | `login_page_no_scan` (+ `_desktop`) — скрытая кнопка (`debugOverride=false`) | `test/presentation/pages/login_page/login_page_golden_test.dart` |

Тесты — против test-env DI (`configureDependencies(Environment.test)`); пути форсятся `mockito` (`CameraPermissionService`-double). Goldens рендерятся локально на Apple Silicon; camera-preview подменяется `previewBuilder`-seam'ом (`research.md` R13). Live-камера в тестах не используется.

# Research: QR-code login (вход по QR)

**Feature**: `010-qr-login` | **Date**: 2026-06-26 | **Phase**: 0 (Outline & Research)

Источник подхода — спека `specs/010-qr-login/spec.md` (+ её Clarifications) и дизайн-корпус `qr-scan.md` / `2-2-qr-scan.md` / `06-qr.md`. Формат: **Decision / Rationale / Alternatives**. Развилки реализации (пакеты, нативная конфигурация, BLoC, codec, capability-флаг, тест-seam, drift-fix) зафиксированы ниже как R1–R14; детали интерфейсов — в `contracts/`, модель — в `data-model.md`.

---

## R1. Пакеты: `mobile_scanner ^7.2.0` + `permission_handler ^12.0.3` + `qr_flutter ^4.1.0`

- **Decision**: добавить три рантайм-зависимости в `pubspec.yaml`:
  - `mobile_scanner: ^7.2.0` — камера-сканер QR (2.2), платформы **iOS / Android / macOS** (+ web, вне scope); Windows/Linux НЕ объявлены.
  - `permission_handler: ^12.0.3` — `Permission.camera` (status/request/`openAppSettings`); **iOS / Android only** (macOS не поддерживается — см. R3). В `pubspec.yaml` сейчас НЕ отдельная закомментированная версия, а имя в групповом комменте (`# permission_handler, file_picker, image_picker, connectivity_plus, mixpanel_flutter`) — **добавить новую запись `permission_handler: ^12.0.3` и убрать имя из группового коммента** (резолвит analyze I3); версию-пин `^12.0.0` в блюпринте `01` (l.110) бампнуть отдельно.
  - `qr_flutter: ^4.1.0` — реальный сканируемый QR для Show QR (7.1); pure-Dart painter, **все 5 платформ**.
- **Rationale**: все три резолвятся против Dart `>=3.12.0 <4.0.0` / Flutter `3.44.1` без `dependency_overrides` и без конфликта с `mockito <5.6.5` (рантайм-деп, не analyzer-coupled). `qr_flutter 4.1.0` — последняя (5.x нет), upper-bound `<4.0.0` на Dart резолвится. macOS Open settings берём на уже имеющемся `url_launcher` (см. R3) — `app_settings` НЕ добавляем (правило «никаких пакетов про запас»).
- **Alternatives**: `qr_code_scanner` (заброшен, старый Flutter) — отклонён; `app_settings` для Open settings — отклонён (url_launcher уже в pubspec); добавление `camera_windows`/v4l2-декодера ради Windows/Linux камеры — отклонено в спеке (документированный desktop-fallback, см. R2/R11).

---

## R2. Build-safety: `mobile_scanner` не ломает Windows/Linux compile-smoke

- **Decision**: `mobile_scanner` добавляется без per-platform exclusion и без `dependency_overrides`; Windows/Linux `--debug` compile-smoke (`compile-check.yml`) остаются зелёными.
- **Rationale**: `mobile_scanner` объявляет `flutter.plugin.platforms` только для android/ios/macos/web. Для Windows/Linux Flutter-тулинг **не генерирует** запись в `GeneratedPluginRegistrant` и **не компилирует** нативный код — реализации нет. Dart-сторона пакета (method-channel + `plugin_platform_interface`; web-код изолирован за `web` pluginClass) компилируется на всех таргетах. Это стандартное поведение camera/`image_picker`-класса плагинов: **сборка проходит; `MissingPluginException` только при рантайм-вызове**, которого на Windows/Linux не будет — capability-флаг (R7) скрывает кнопку `Scan QR` и делает 2.2 недостижимым, так что `MobileScannerController` там никогда не конструируется.
- **Alternatives**: условный per-platform dep / отдельный entrypoint — отклонено (не нужно, лишняя сложность). **Mitigation**: прогнать `mise run build:windows:stage` / `build:linux:stage` (или дождаться `compile-check.yml`) **рано — сразу после добавления зависимости (Phase 1/2), а не в конце US4** (резолвит analyze I2 — весь Win/Linux-fallback держится на этой проверке; ловить build-break нужно до того, как на нём построена вся фича).

---

## R3. macOS-пермишен: двух-бэкендовая модель (`permission_handler` ≠ macOS)

- **Decision**: пермишен камеры драйвится двумя бэкендами за единым интерфейсом `CameraPermissionService` (R6):
  - **iOS / Android** — `permission_handler`: `Permission.camera.status` / `.request()` (`granted` / `denied` / `permanentlyDenied` / `restricted`), `openAppSettings()`.
  - **macOS** — `permission_handler` НЕ поддерживается (умбрелла 12.x объявляет platforms android/ios/web/windows; вызов на macOS → `MissingPluginException`). Поэтому на macOS пермишен наблюдается через состояние самого `mobile_scanner` (`controller.value.hasCameraPermission` + `MobileScannerErrorCode.permissionDenied` в `errorBuilder`): `controller.start()` на `notDetermined`-приложении сам поднимает AVFoundation-промпт. Open settings на macOS — `url_launcher` → `x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`.
- **Rationale**: единая абстракция скрывает развилку от BLoC; нюанс `permanentlyDenied` (re-request vs Open settings) доступен на iOS/Android, на macOS промпт/состояние ведёт `mobile_scanner`. Подтверждено: `permission_handler_apple` — iOS-only, macOS-фича открыта (Baseflow #886).
- **Alternatives**: тянуть macOS-only permission-пакет — отклонено (лишний деп; `mobile_scanner` уже даёт сигнал). Считать macOS «как iOS» через permission_handler — невозможно (рантайм-исключение).

---

## R4. `mobile_scanner` v7 controller API: single-shot + ручной lifecycle

- **Decision**: страница владеет `MobileScannerController` (создаётся в `initState`, `autoStart: false`, `formats: const [BarcodeFormat.qrCode]`, `detectionSpeed: DetectionSpeed.noDuplicates`). Распознавание — `onDetect` / `barcodes`-стрим, читаем `capture.barcodes.first.rawValue`. **Single-shot**: на первом непустом `rawValue` ставим `_handled`-guard, `await controller.stop()`, поп 2.2 с decoded id (без звука/вибрации/confirm, FR-010). Lifecycle — **ручной** (`WidgetsBindingObserver` + `didChangeAppLifecycleState`): `resumed` → re-check + `start()`, `paused/inactive` → `stop()` + отписка. `dispose()` контроллера в `dispose()` страницы.
- **Rationale**: v7 не авто-управляет lifecycle; контроллер — `ValueNotifier<MobileScannerState>` во владении вызывающего (v6+). `LoginPage` уже доказывает этот scaffolding (`with WidgetsBindingObserver` + `didChangeAppLifecycleState` для клипборда, `login_page.dart` l.46/55/61/68-72) — зеркалим. Ветка `resumed` — точка реализации clarification «возврат из настроек → авто-старт без повторного тапа» (FR-006).
- **Alternatives**: копировать v3/v5-туториалы (`MobileScannerArguments`, авто-контроллер) — НЕ скомпилируется (breaking changes v6/v7: `switchCamera()` заменён на `ToggleLensType`/`SelectCamera`, `MobileScannerException.errorCode`/`errorBuilder` добавлены). Пинимся `^7.2.0`, следуем только v7-докам.

---

## R5. `QrScanBloc` — Freezed value-state, **чистый автомат**, без DI (резолвит analyze U2)

- **Decision**: 2.2 выходит из stub-статуса (реальный async/permission/camera-стейт) → по блюпринту `05 §5.1` обязан получить собственный Freezed-BLoC. `QrScanBloc extends BaseBloc<QrScanEvent, QrScanState>`:
  - State (value-object, bare-имена статусов): `QrScanStatus { initializing, scanning, permissionDenied, fatal }` + one-shot поля `String? decodedId`, `bool invalid`. (Схлопывает текущий `_QrPreview`-enum.)
  - Events: `Started`, `PermissionResolved(status)`, `Detected(raw)`, `SignalHandled` (см. `data-model.md §5`).
  - **Чистый автомат**: конструктор `QrScanBloc()` — БЕЗ параметров, БЕЗ `getIt`, БЕЗ сервиса/`demo`-флага. Камерой/пермишеном владеет виджет (R6) и кормит BLoC событием `PermissionResolved`. Это резолвит analyze U2 (предложенный ранее `_permission ?? getIt<...>()` жадно резолвил `getIt` даже в demo и ломал DI-less `pumpApp`/gallery-тесты — `LoginBloc` так не делает). Теперь demo/gallery просто шлёт BLoC-события → DI-less-тесты и SC-008 живут.
  - One-shot (`decodedId`/`invalid`) консьюмятся `BlocListener`'ом страницы и сбрасываются `SignalHandled` (паттерн `LoginEvent.navigationHandled`). `executeLogic` не нужен — BLoC внешних вызовов не делает.
- **Rationale**: house-style value-BLoC = `LoginState`; bare-имена статусов = инвариант `05`. Чистый BLoC тривиально юнит-тестируем (`bloc_test` шлёт `PermissionResolved`/`Detected`). Torch / switch-camera — widget-local на контроллере (тривиальный plugin-стейт, не bloc-worthy; только `_narrow`-ветка, FR-005).
- **Alternatives**: оставить `StatelessWidget`+enum — нарушает `05 §5.1`. BLoC, зависящий от `CameraPermissionService` через `getIt` в ctor — отклонено (U2: ломает DI-less demo).

---

## R6. `CameraPermissionService` — доменный интерфейс, потребляется **виджетом** (резолвит analyze U1)

- **Decision**: тонкая абстракция `CameraPermissionService` (domain) `{ status(); request(); openSettings(); }` → `CameraPermissionStatus`, impl `@LazySingleton(as: CameraPermissionService, env: [dev, prod, test])` (R3). Alias `cameraPermissionService` в `global_aliases.dart`. **Сервис резолвит и зовёт ВИДЖЕТ** (`_QrScanPageState`), где живёт `MobileScannerController`, а НЕ BLoC. iOS/Android: виджет зовёт `request()` → `bloc.add(PermissionResolved(status))`. macOS: `request()`/`status()` виджетом не вызываются (пермишен ведёт контроллер: `controller.start()` поднимает AVFoundation-промпт, `errorBuilder permissionDenied` → `bloc.add(PermissionResolved(permanentlyDenied))`); `openSettings()` на macOS работает (url_launcher).
- **Rationale**: резолвит analyze U1 — singleton-сервис не имеет хэндла к widget-owned контроллеру, поэтому macOS-пермишен не может вести сервис; его ведёт виджет через контроллер. Сервис остаётся mockito-testable (widget-тест подменяет fake `CameraPermissionService` через `@visibleForTesting`-инъекцию или DI test-env). Сервис **no-throw**, возвращает голый `CameraPermissionStatus` (не `RepositoryResult`, резолвит I5).
- **Alternatives**: BLoC зовёт сервис в ctor (`getIt`) — отклонено (U1/U2: macOS-несостыковка + жадный getIt). Полный `QrScannerController`-интерфейс с `buildPreview()` в domain — отклонено: контроллер — UI-плагин, держим его widget-owned; абстрагируем только пермишен + preview-seam (R13).

---

## R7. Capability-флаг `QrScannerCapability` — single source of truth FR-016/017

- **Decision**: `lib/general/qr_scanner_capability.dart` — `abstract final class QrScannerCapability` со static `bool get isAvailable => debugOverride ?? (PlatformUtils.isMobile || PlatformUtils.isMacOS)` и `@visibleForTesting static bool? debugOverride`. Один флаг управляет И видимостью кнопки `Scan QR` на 2.1, И достижимостью 2.2.
- **Rationale**: `PlatformUtils` (`lib/general/platform_utils.dart`) построен на `dart:io Platform` (не на `defaultTargetPlatform`), а `dart:io Platform` **не** оверрайдится `debugDefaultTargetPlatformOverride` — на golden-хосте (macOS) предикат всегда `true`. Поэтому для Windows/Linux-кейса (кнопка скрыта) нужен явный seam: тест ставит `QrScannerCapability.debugOverride = false`. Static-форма консистентна со static `PlatformUtils` и работает в DI-less `pumpApp`-тестах (`LoginPage(demo:true)`).
- **Alternatives**: injectable `ScannerCapability` + DI-override (`getIt.allowReassignment`) — рабочий, но ломает DI-less widget-тесты Login; static seam проще. `PlatformUtils.isMobile`-инлайн без флага — отклонено (нет single source of truth, FR-017; нет тест-override).

---

## R8. Login ↔ 2.2 wiring: `Route<String?>` + `pop(id)` → тот же путь, что ручной ввод

- **Decision**: `QrScanPage.route()` меняет тип `Route<void>` → **`Route<String?>`** (`routeDemo()` остаётся `Route<void>`). Success: `controller.stop(); Navigator.pop(decodedId)`. Back / системный back / `Enter manually`: `Navigator.pop(null)` (поле 2.1 сохранено, FR-013). `LoginPage._scanQr` (l.89-93):
  ```dart
  Future<void> _scanQr() async {
    final id = await Navigator.of(context).push(QrScanPage.route());
    if (id == null || !mounted) return;          // back / Enter manually → без submit
    _controller.text = id;
    _bloc.add(LoginEvent.idChanged(id));         // state.id, status:idle → canSubmit
    _submit();                                    // тот же путь: signInRequested → authRepository.signIn → спайн
  }
  ```
- **Rationale**: возврат значения через `Navigator.pop` консистентен со спайном 009 — 2.2 не владеет top-level-навигацией, отдаёт id наверх, Login кормит существующий `signInRequested`, спайн `pushAndRemoveUntil(…,(_)=>false)` чистит стек на Chats/Set-username (FR-012, SC-002). Корректность опирается на **последовательную (FIFO) обработку событий BLoC**: `idChanged` обрабатывается раньше `signInRequested`, который сам сверяется с `state.canSubmit` (резолвит analyze A3 — НЕ синхронное чтение `state.id` сразу после `add()`). Fatal (нет камеры) — НЕ поп: 2.2 сам пушит `AppErrorPage` (FR-007), как сейчас `_fireFatal`.
- **Alternatives**: push-with-callback / глобальный канал — отклонено (поп-значение проще и локально). Прямой вызов спайна из 2.2 — отклонено (2.2 не должен знать про навигацию верхнего уровня).

---

## R9. `NoxQrEnvelope` codec — pure util, percent-encode, без double-decode

- **Decision**: новый `lib/general/nox_qr_envelope.dart` — `abstract final class NoxQrEnvelope` со static `encode`/`decode`, общий для генератора (7.1) и парсера (2.2):
  ```dart
  static const String _scheme = 'nox';
  static const String _type = 'id';
  static String encode(String identifier) => '$_scheme://$_type/${Uri.encodeComponent(identifier)}';
  static String? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final Uri uri;
    try { uri = Uri.parse(trimmed); } on FormatException { return null; }
    if (uri.scheme != _scheme || uri.host != _type) return null;
    if (uri.pathSegments.length != 1) return null;
    final id = uri.pathSegments.first;   // Uri уже percent-декодирует РОВНО один раз
    return id.isEmpty ? null : id;
  }
  ```
- **Rationale**: `Uri.encodeComponent` (дословно по FR-009) кодирует `/ : ? #`, пробел, не-ASCII → путь всегда один сегмент. `uri.pathSegments.first` — точный инверс (UTF-8 percent-decode один раз). **Ловушка**: НЕ звать `Uri.decodeComponent` на `pathSegments.first` (это double-decode — испортит id с литеральным `%xx`). Round-trip `decode(encode(id)) == id` держится для любого **непустого** `id` и замыкает US2↔US1 (SC-005); `encode('')` = `nox://id/` → `decode` → `null` (резолвит analyze U3 — 7.1 не кодирует пустой identifier; гейт `rawId.isNotEmpty`). Не валидация формата id (009 FR-011 сохранён) — только распознавание конверта.
- **Alternatives**: полноценный `DeepLinkRepository`-конвейер (блюпринт `13`) — over-engineering: нет OS-доставки ссылки, нет стрима/навигации/`RepositoryResult`, это синхронный string↔string. `lib/domain` — нет (нет доменных типов; `domain` ни от чего не зависит). Сырой id без обёртки — отклонено в clarification (любой чужой QR ушёл бы в submit).

---

## R10. Show QR (7.1): `qr_flutter`-swap + реальный identifier из `SessionRepository`

- **Decision**: в `app_qr_surface_widget.dart` удалить `_FakeQrPainter` (l.42-90), заменить `CustomPaint` на `QrImageView(data: NoxQrEnvelope.encode(data), backgroundColor: NoxBrand.qrSurface, eyeStyle: QrEyeStyle(color: NoxBrand.qrInk), dataModuleStyle: QrDataModuleStyle(color: NoxBrand.qrInk), errorCorrectionLevel: QrErrorCorrectLevel.M, gapless: true, padding: EdgeInsets.zero)`. Brand-fixed light Container + quiet-zone + `Semantics` + `showIdQr`/`_IdQrContent` — без изменений. Источник id (FR-014): заменить const-stub `SettingsRootBloc.mockRawId` (l.33; 3 места: `settings_root_page.dart` l.112/312/321) на реальный `identifier` из `SessionRepository.readSession()` (спайн 009) — добавить alias `sessionRepository`, грузить в `SettingsRootBloc._onInitialize`, добавить `rawId` в `SettingsRootState`.
- **Rationale**: `data` уже сырой id, callers не меняются (encode внутри). `NoxBrand.qrSurface`/`qrInk` — вне `ColorScheme`, Container уже форсит light (FR-015 / SC: QR светлый и в dark). FR-014 требует «его identifier» → источник `SessionModel.identifier` (тот же, что вводился/сканировался при входе) замыкает round-trip.
- **Alternatives**: encode в callers — отклонено (3 точки, дублирование). Оставить `mockRawId` — нарушает FR-014 (QR должен кодировать реальный id). `barcode_widget` вместо `qr_flutter` — эквивалент, но `qr_flutter` уже выбран в R1.

---

## R11. Нативная конфигурация камеры (iOS / Android / macOS); Windows/Linux — без правок

- **Decision**: правки в том же change-set (FR-008, Принцип III):

  | Платформа | Файл | Правка |
  |---|---|---|
  | iOS | `ios/Runner/Info.plist` | + `NSCameraUsageDescription` (purpose string ниже) |
  | iOS | `ios/Podfile` | + `PERMISSION_CAMERA=1` в `GCC_PREPROCESSOR_DEFINITIONS` |
  | Android | `android/app/src/main/AndroidManifest.xml` | + `uses-permission CAMERA` + `uses-feature camera required=false` |
  | macOS | `macos/Runner/DebugProfile.entitlements` | + `com.apple.security.device.camera = true` |
  | macOS | `macos/Runner/Release.entitlements` | + `com.apple.security.device.camera = true` |
  | macOS | `macos/Runner/Info.plist` | + `NSCameraUsageDescription` (та же строка) |
  | Windows / Linux | — | нет правок (`compile-check.yml` не трогаем) |

  Camera purpose string (EN, общий iOS+macOS): `NOX uses the camera to scan a QR code containing a sign-in ID. Frames are processed on your device and are never stored or transmitted.`
- **Rationale**: iOS/macOS крашат приложение при доступе к камере без usage-string; `permission_handler` iOS стрипит код пермишена без `PERMISSION_CAMERA=1` (status всегда denied). Android `required=false` → устройства без камеры всё равно ставят приложение (согласуется с capability-флагом). Windows/Linux камеру не настраивают — документированный desktop-fallback, закрывает `TODO(design-desktop-qr)` (Принцип III: fallback). Linux apt-deps (камера) — ноль, `compile-check.yml` без изменений.
- **Alternatives**: добавлять микрофон/фото-library — не нужно (только скан). Настраивать Windows/Linux камеру — вне scope (R2).

---

## R12. macOS camera-entitlement БЕЗОПАСЕН (в отличие от 009 keychain)

- **Decision**: `com.apple.security.device.camera` добавляется напрямую в оба `macos/Runner/*.entitlements`; Dart-side-workaround НЕ нужен, откатов не ожидается.
- **Rationale**: это sandbox-**капабилити** того же семейства `com.apple.security.*`, что уже присутствующий `com.apple.security.network.server`. Не привязано к provisioning-профилю, работает с ad-hoc-подписью (`CODE_SIGN_IDENTITY "-"`), `DEVELOPMENT_TEAM` не требуется. Принципиально отличается от 009-го `keychain-access-groups`, который форсировал «entitlements require signing with a development certificate» и ломал `flutter build macos` (009 откатил его и закрыл gate Dart-side `MacOsOptions(usesDataProtectionKeychain:false)`).
- **Alternatives**: повторять 009-паттерн (Dart-workaround, откаты) — не нужно; camera-entitlement безопасен. Опустить entitlement и полагаться только на usage-string — недостаточно (sandbox-приложению нужна и капабилити, и TCC-строка).
- **Drift-fix (Принцип II)**: блюпринт `01` — добавить `mobile_scanner`/`qr_flutter` в манифест зависимостей + таблицу «Почему именно эти зависимости» (`mobile_scanner` = камера/QR, iOS/Android/macOS only, NO Windows/Linux, build-safe; `qr_flutter` = pure-Dart QR, все 5); раскомментировать `permission_handler` + бамп `^12.0.3`.

---

## R13. Camera test-seam: `previewBuilder` (`@visibleForTesting`) — goldens без реальной камеры

- **Decision**: живой `MobileScanner` нельзя рендерить в golden/widget-тесте (нужна `dart:io`-камера). Два конкретных `@visibleForTesting`-seam'а на `QrScanPage` (резолвит analyze U5 — `previewBuilder` один не даёт способа загнать состояние/детекцию в BLoC, т.к. убирает `onDetect`):
  - `@visibleForTesting WidgetBuilder? previewBuilder` — подмена живого `MobileScanner` на `ColoredBox`-плейсхолдер (Scanning-кадр).
  - `@visibleForTesting QrScanBloc? bloc` — инъекция пред-seed'нутого BLoC; widget-тест строит `QrScanBloc()..emit(QrScanState(status: permissionDenied))` (или шлёт `Detected('https://x')` для invalid) и проверяет рендер/snackbar/роутинг без камеры. (BLoC чистый → seed тривиален.)
- **Rationale**: `goldenTest`/`goldenTestDesktop` — `name`+`build`-thunk, один settled-кадр, без тапов → каждое состояние строится напрямую инъекцией seeded-BLoC + `previewBuilder`. Покрытие без камеры: Scanning (placeholder + overlay), Permission-denied (seed `permissionDenied` → opaque `_DeniedPanel`), Inline-error (seed BLoC + `Detected` чужого → snackbar `qrInvalidSnackbar`), Fatal (seed `fatal` → роутинг в `AppErrorPage`).
- **Alternatives**: полный `QrScannerController`-интерфейс с `buildPreview()` в DI — тяжелее; preview-seam на странице проще и аналогичен self-creating `const LoginPage()` golden.

---

## R14. Drift-fix `qr-scan.md` (permission-denied + macOS `_wide`) — Принцип II

- **Decision**: в том же change-set привести `docs/design/spec/screens/qr-scan.md` к реализованной форме (4 правки):
  - **A** (l.35) — Permission-denied: `Blocking-overlay` → «непрозрачный surface-экран (НЕ поверх камеры): глиф `no_photography`, `Camera access needed`, `Open settings`; `_narrow` — центр surface, `_wide` — в `OnboardCard`; авто-resume по `resumed`».
  - **B** (l.88) — Q4-строка таблицы решений: та же реконсиляция.
  - **C** (l.62-64) — заменить «overlay» на «surface-экран»; добавить компонент-ноту `Icon no_photography` + `FilledButton Open settings`.
  - **D** (новая подсекция после l.28) — «Адаптация по ширине (`_narrow` vs macOS `_wide`)»: full-screen feed + torch/switch + маска 55% на мобильном; оконный viewfinder 300×300 без torch/switch + helper + inline `Enter manually` на macOS; Windows/Linux — кнопка скрыта (FR-016/017). + строки микрокопии desktop (`Scan a QR code`, `Point your webcam at a code, or enter the ID manually.`). AppBar-строку l.22 квалифицировать «только `_narrow`».
- **Rationale**: реализованный корпус (`2-2-qr-scan.md` l.18, `06-qr.md` l.7/14) и код (`qr_scan_page.dart` `_DeniedPanel`) уже используют opaque surface; `qr-scan.md` описывает только мобильный. Принцип II: расхождение чинится приведением спеки к корпусу/коду.
- **Alternatives**: оставить расхождение — нарушает Принцип II. Привести код к старой спеке (overlay) — отклонено (корпус новее/реализован).

---

## Сводка нерешённого / отложенного (не блокирует план)

| # | Пункт | Статус |
|---|---|---|
| 1 | Реальный backend-чек `registeredIds` (authorized vs registrationPending) | TBD — наследуется из 009 (`OnboardingMockData.registeredIds`), вне scope 010 |
| 2 | Формат payload `nox://id/` при появлении реального протокола идентичности | TBD — клиентская конвенция, пересмотр с бэкендом NOX |
| 3 | macOS Open settings anchor `x-apple.systempreferences:…Privacy_Camera` устойчивость по версиям macOS | known-risk — если QA найдёт нестабильность, добавить `app_settings`; сейчас `url_launcher` |
| 4 | Windows/Linux камера (camera_windows/v4l2 + декодер) | отложено — документированный desktop-fallback (R2/R11), пересмотр позже |
| 5 | `qr_scan_page_invalid` page-golden (snackbar) | low-value — покрываем widget-тестом; page-golden опционален |
| 6 | Закрытие `TODO(design-desktop-qr)` в Sync Impact Report конституции (l.51) | partial — macOS = desktop-расширение (камера), Windows/Linux = документированный fallback; **остаётся частично открытым до Windows/Linux-камеры**. Правка comment-блока конституции — отдельный constitution-update вне scope этой фичи (резолвит analyze C1); зафиксировано задачей в `tasks.md` (Polish). |

Все `NEEDS CLARIFICATION` спеки закрыты на этапе `/speckit-clarify` (3 ответа в Session 2026-06-26); новых не возникло.

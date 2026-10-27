---
description: "Task list — 010-qr-login"
---

# Tasks: QR-code login (вход по QR)

**Input**: Design documents from `specs/010-qr-login/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md` (R1–R14), `data-model.md`, `contracts/{scanner,navigation}.md`, `quickstart.md`

**Tests**: включены — спека (`quickstart.md` «Автотесты») и конвенции проекта (`/bloc-test`, `/golden-test`, `/widget-test`, 3 категории goldens) требуют их.

**Organization**: задачи сгруппированы по user stories для независимой реализации и проверки. Codegen-first: после правки любого Freezed/injectable-класса — один прогон `make generate`.

## Format: `[ID] [P?] [Story] Описание + путь`

- **[P]**: можно параллельно (разные файлы, нет незавершённых зависимостей)
- **[Story]**: US1–US4 (фазы user-story); Setup/Foundational/Polish — без метки
- Каждая задача указывает точный путь файла

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: зависимости пакетов.

- [ ] T001 Добавить зависимости в `pubspec.yaml`: `mobile_scanner: ^7.2.0`, `qr_flutter: ^4.1.0`; **добавить новую запись** `permission_handler: ^12.0.3` и **убрать имя из группового коммента** (`# permission_handler, file_picker, …`) — это не отдельная закомментированная версия (резолвит analyze I3). Инлайн-комментарии: `mobile_scanner` = камера/QR, iOS/Android/macOS only, NO Windows/Linux (capability-gated, build-safe); `qr_flutter` = pure-Dart QR, все 5 платформ.
- [ ] T002 `make deps` (`fvm flutter pub get`) — резолв новых зависимостей.
- [ ] T002a **РАНО** подтвердить build-safety (резолвит analyze I2): `mise run build:windows:stage` и `mise run build:linux:stage` проходят с добавленным `mobile_scanner` (federated-plugin, `research.md` R2). Делать СЕЙЧАС, до построения фичи — не в конце US4.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: pure-util'ы, доменный сервис пермишена и DI — нужны всем сканирующим/генерирующим историям.

**⚠️ CRITICAL**: ни одна user story не стартует до завершения этой фазы.

- [ ] T003 [P] Создать `NoxQrEnvelope` (`abstract final class`, static `encode`/`decode`, **без double-decode** — `pathSegments.first` уже декодирован) в `lib/general/nox_qr_envelope.dart` (контракт — `contracts/scanner.md`).
- [ ] T004 [P] Unit-тест `NoxQrEnvelope` (round-trip на charset `/ : ? # space`/unicode/base64url + все edge-строки из `data-model.md §1`) в `test/general/nox_qr_envelope_test.dart` (чистый unit, без `@Tags`).
- [ ] T005 [P] Создать `QrScannerCapability` (`static bool get isAvailable => debugOverride ?? (PlatformUtils.isMobile || PlatformUtils.isMacOS)` + `@visibleForTesting static bool? debugOverride`) в `lib/general/qr_scanner_capability.dart` (FR-016/017 single source of truth).
- [ ] T006 [P] Unit-тест `QrScannerCapability` (`debugOverride` true/false/null) в `test/general/qr_scanner_capability_test.dart`.
- [ ] T007 [P] Создать enum `CameraPermissionStatus { granted, denied, permanentlyDenied, unavailable }` в `lib/domain/model/qr/camera_permission_status.dart`.
- [ ] T008 Создать интерфейс `CameraPermissionService` (`status()`/`request()`/`openSettings()`) в `lib/domain/repository/qr/camera_permission_service.dart` (зависит от T007).
- [ ] T009 Реализовать `CameraPermissionServiceImpl` (`@LazySingleton(as: CameraPermissionService, env: [dev, prod, test])`, двух-бэкендовый: `permission_handler` на iOS/Android, `mobile_scanner`-state + `url_launcher` на macOS; ошибки → `unavailable`, лог через `LogRepository`) в `lib/data/repository/qr/camera_permission_service_impl.dart` (зависит от T008).
- [ ] T010 `make generate` (`build_runner`) — регенерация `lib/di/configure_dependencies.config.dart` с `CameraPermissionService` (зависит от T009).
- [ ] T011 [P] Добавить alias `cameraPermissionService` в `lib/di/global_aliases.dart`.

**Checkpoint**: codec, capability-флаг и сервис пермишена готовы — user stories могут стартовать.

---

## Phase 3: User Story 1 — Вход сканированием QR (Priority: P1) 🎯 MVP

**Goal**: на iOS/Android/macOS пользователь жмёт `Scan QR`, выдаёт пермишен, наводит камеру на валидный `nox://id/`-QR и входит автоматически — тем же путём, что ручной ввод.

**Independent Test**: открыть 2.2 из 2.1, выдать доступ, навести на `nox://id/registered` → попадание в Chats (4.1); новый id → Set username (2.3). Без ручного набора.

### Tests for User Story 1 ⚠️ (написать первыми, убедиться что падают)

- [ ] T012 [P] [US1] `bloc_test` `QrScanBloc` (чистый, без mocks): `PermissionResolved(granted)`→`scanning`; `Detected(nox://id/<enc>)`→`decodedId`; single-shot (`Detected` после `decodedId!=null` → игнор) в `test/presentation/pages/qr_scan_page/bloc/qr_scan_bloc_test.dart`.
- [ ] T013 [P] [US1] Widget-тест `QrScanPage`: Scanning рендерится через `previewBuilder`-плейсхолдер (передать fake `CameraPermissionService`); back / `Enter manually` → `pop(null)` (без submit); **assert `MobileScannerController` сконструирован с `returnImage:false`** (G1 / SC-007 privacy-гард) в `test/presentation/pages/qr_scan_page/qr_scan_page_test.dart`.
- [ ] T014 [P] [US1] Widget-тест `LoginPage`: при `QrScannerCapability.debugOverride=true` кнопка `Scan QR` присутствует и `_scanQr` открывает реальный 2.2 → распознанный id уходит в `signInRequested` в `test/presentation/pages/login_page/login_page_test.dart`.

### Implementation for User Story 1

- [ ] T015 [US1] Создать `QrScanState` (`status`/`decodedId`/`invalid` + геттер `isScanning`) и `QrScanEvent` (`Started`/`PermissionResolved(status)`/`Detected`/`SignalHandled`) Freezed в `lib/presentation/pages/qr_scan_page/bloc/qr_scan_state.dart` + `qr_scan_event.dart` (`data-model.md §4/§5`).
- [ ] T016 [US1] Реализовать **чистый** `QrScanBloc extends BaseBloc` — ctor `QrScanBloc()` без DI/getIt/demo (резолвит analyze U2); хендлеры: `Started`→`initializing`; `PermissionResolved`→маппинг статуса (guard `decodedId!=null`); `Detected`→single-shot guard + `NoxQrEnvelope.decode`; `SignalHandled`→сброс — в `lib/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart` (зависит от T015).
- [ ] T017 [US1] `make generate` — Freezed для `QrScan*` (зависит от T016).
- [ ] T018 [US1] Переписать `QrScanPage`: владеет `QrScanBloc` + widget-owned `MobileScannerController` (`autoStart:false`, `formats:[BarcodeFormat.qrCode]`, `detectionSpeed:noDuplicates`, `returnImage:false`); виджет оркестрирует пермишен (`_resolvePermission`: iOS/Android `cameraPermissionService.request()`→`PermissionResolved`; macOS — контроллер+`errorBuilder`→`PermissionResolved`); `@visibleForTesting WidgetBuilder? previewBuilder` (дефолт `MobileScanner`, demo → `ColoredBox`) + `@visibleForTesting QrScanBloc? bloc` (seam для widget-тестов состояний, резолвит U5); `WidgetsBindingObserver` (`resumed`→`_resolvePermission`, `paused`→`controller.stop()`); `route()`→`Route<String?>`; success → `controller.stop(); Navigator.pop(decodedId)`; **demo dev-кнопки перевести на BLoC-события прямо здесь** (`PermissionResolved`/`Detected`, резолвит analyze U4 — `setState(_preview)` не скомпилируется после перехода на BLoC) в `lib/presentation/pages/qr_scan_page/qr_scan_page.dart` (зависит от T017).
- [ ] T019 [US1] Ветка `_narrow` (iOS/Android): live `MobileScanner`-feed + `AppQrOverlayWidget` (прицел + маска 55%) + AppBar `Flashlight`/`Switch camera` (widget-local `controller.toggleTorch()` / lens-switch, скрыты без железа) + инструкция + `Enter manually`-pill в `qr_scan_page.dart` (зависит от T018).
- [ ] T020 [US1] Ветка `_wide` (macOS): `AppWindowTitlebarWidget(subtitle:'Scan QR')` + заголовок `Scan a QR code` + viewfinder 300×300 (`size.qrScanWindow`, brand-белые углы, без маски/torch/switch) + helper + inline `Enter manually`-ссылка в `qr_scan_page.dart` (зависит от T018).
- [ ] T021 [US1] Проводка `LoginPage`: `_scanQr` (l.89-93) → `await Navigator.push(QrScanPage.route())`, при `id != null` → `_controller.text=id` + `idChanged` + `_submit`; обернуть кнопку `Scan QR` (l.203-205) в `if (QrScannerCapability.isAvailable)` в `lib/presentation/pages/login_page/login_page.dart`.
- [ ] T022 [P] [US1] iOS: добавить `NSCameraUsageDescription` (camera purpose string, `research.md` R11) в `ios/Runner/Info.plist`.
- [ ] T023 [P] [US1] iOS: добавить `PERMISSION_CAMERA=1` в `GCC_PREPROCESSOR_DEFINITIONS` в `ios/Podfile` (иначе `permission_handler` стрипит код камеры).
- [ ] T024 [P] [US1] Android: добавить `<uses-permission android:name="android.permission.CAMERA"/>` + `<uses-feature android:name="android.hardware.camera" android:required="false"/>` в `android/app/src/main/AndroidManifest.xml`.
- [ ] T025 [P] [US1] macOS: добавить `com.apple.security.device.camera=true` в `macos/Runner/DebugProfile.entitlements` И `macos/Runner/Release.entitlements` (безопасно — sandbox-капабилити, `research.md` R12).
- [ ] T026 [P] [US1] macOS: добавить `NSCameraUsageDescription` (та же purpose string) в `macos/Runner/Info.plist`.
- [ ] T027 [US1] Goldens Scanning: re-verify/regen `qr_scan_page` (page-mobile, `_narrow`) + `qr_scan_page_desktop` (page-desktop, `_wide`) через `previewBuilder`-плейсхолдер в `test/presentation/pages/qr_scan_page/qr_scan_page_golden_test.dart` (`make golden-update`).

**Checkpoint**: US1 полностью функциональна — реальный вход сканированием на iOS/Android/macOS. MVP готов.

---

## Phase 4: User Story 2 — Показ своего ID настоящим QR (Priority: P2)

**Goal**: вошедший пользователь видит свой `Your ID` как реальный сканируемый `nox://id/<id>` QR в Settings (7.1) на всех 5 платформах.

**Independent Test**: `Show QR` → сторонний сканер декодирует `nox://id/<тот самый id>`; поверхность остаётся светлой в dark-теме.

### Tests for User Story 2 ⚠️

- [ ] T028 [P] [US2] `bloc_test` `SettingsRootBloc`: `_onInitialize` грузит `rawId` из `sessionRepository.readSession()` (`@GenerateMocks([SessionRepository])`) в `test/presentation/pages/settings_root_page/bloc/settings_root_bloc_test.dart`.
- [ ] T029 [P] [US2] Golden-тест `AppQrSurfaceWidget` (реальный QR, light+dark, поверхность остаётся светлой в обоих) в `test/presentation/widgets/settings/app_qr_surface_widget_golden_test.dart`.

### Implementation for User Story 2

- [ ] T030 [P] [US2] Добавить alias `sessionRepository` в `lib/di/global_aliases.dart`.
- [ ] T031 [US2] Заменить `_FakeQrPainter` (l.42-90) на `QrImageView(data: NoxQrEnvelope.encode(data), backgroundColor: NoxBrand.qrSurface, eyeStyle/dataModuleStyle: NoxBrand.qrInk, errorCorrectionLevel: M, gapless: true, padding: zero)`, сохранив brand-light Container/quiet-zone/`Semantics`/`showIdQr` в `lib/presentation/widgets/settings/app_qr_surface_widget.dart`.
- [ ] T032 [US2] `SettingsRootBloc._onInitialize` → `sessionRepository.readSession()` развёрнуть через `RepositoryResult.match` (резолвит analyze U3): `onData(session)`→`rawId = session?.identifier ?? ''`; `onError`→`rawId=''`+лог. Добавить `rawId` в `SettingsRootState` в `lib/presentation/pages/settings_root_page/bloc/settings_root_bloc.dart` + `settings_root_state.dart` (зависит от T030).
- [ ] T033 [US2] `make generate` — Freezed для `SettingsRootState` (зависит от T032).
- [ ] T034 [US2] Заменить 3 ссылки `SettingsRootBloc.mockRawId` на `state.rawId` (l.112 `_copyId`, l.312 inline-QR, l.321 `onShowQr`) в `lib/presentation/pages/settings_root_page/settings_root_page.dart` (зависит от T033).
- [ ] T035 [US2] Регенерировать goldens `app_qr_surface_widget_{light,dark}.png` + затронутые page-7.1 goldens (`make golden-update`).

**Checkpoint**: US1 + US2 работают независимо; цикл показ↔скан замкнут end-to-end (SC-005).

---

## Phase 5: User Story 3 — Пермишен и ошибки (Priority: P2)

**Goal**: отказ пермишена → opaque surface + `Open settings` + авто-resume; чужой QR → snackbar и продолжение скана; камера недоступна → 3.1.

**Independent Test**: отклонить пермишен → блокирующее состояние с рабочим `Open settings`; навести на сторонний QR → snackbar, вход не происходит; вернуться из настроек с выданным доступом → авто-старт.

### Tests for User Story 3 ⚠️

- [ ] T036 [P] [US3] `bloc_test` `QrScanBloc` error-пути: `PermissionResolved(denied)`/`(permanentlyDenied)`→`permissionDenied`; `PermissionResolved(unavailable)`→`fatal`; `Detected(чужой/пустой)`→`invalid` (статус `scanning`); повторный `PermissionResolved(granted)` после `decodedId!=null` → игнор (guard) в `test/presentation/pages/qr_scan_page/bloc/qr_scan_bloc_test.dart`.
- [ ] T037 [P] [US3] Widget-тест `QrScanPage` (через `@visibleForTesting bloc`-seam): denied-surface (`qrPermissionTitle`/`qrPermissionMessage`) + `actionOpenSettings` вызывает `CameraPermissionService.openSettings()` (verify fake); `invalid` → snackbar `qrInvalidSnackbar`; `fatal` → push `AppErrorPage` в `test/presentation/pages/qr_scan_page/qr_scan_page_test.dart`.

### Implementation for User Story 3

- [ ] T038 [US3] Подключить permission-denied opaque surface (`_DeniedPanel`: `noPhotography` + `qrPermissionTitle` + `qrPermissionMessage` + `actionOpenSettings`-кнопка → виджет зовёт `cameraPermissionService.openSettings()`, НЕ событие BLoC) к состоянию `permissionDenied`; `_narrow` — центр surface, `_wide` — в `AppOnboardCardWidget` в `lib/presentation/pages/qr_scan_page/qr_scan_page.dart` (зависит от T018).
- [ ] T039 [US3] Подключить inline-error: `BlocListener` на `invalid` → snackbar `This QR code is invalid. Try another one.` + `SignalHandled`-сброс; скан продолжается в `qr_scan_page.dart`.
- [ ] T040 [US3] Подключить `fatal` → `Navigator.push(AppErrorPage.route(...))` (3.1, FR-007) в `qr_scan_page.dart`.
- [ ] T041 [US3] Goldens denied: добавить `qr_scan_page_denied` (page-mobile) + `qr_scan_page_desktop_denied` (page-desktop, `_wide` OnboardCard) в `test/presentation/pages/qr_scan_page/qr_scan_page_golden_test.dart`.

**Checkpoint**: пермишен/ошибки/авто-resume надёжны; US1–US3 независимо функциональны.

---

## Phase 6: User Story 4 — Windows/Linux: сканера нет (Priority: P2)

**Goal**: на Windows/Linux кнопка `Scan QR` скрыта, 2.2 недостижим, ручной вход работает; `Show QR` доступен.

**Independent Test**: при `QrScannerCapability.debugOverride=false` на 2.1 кнопки `Scan QR` нет; `mobile_scanner` не ломает сборку Windows/Linux.

### Tests for User Story 4 ⚠️

- [ ] T042 [P] [US4] Widget-тест `LoginPage`: `debugOverride=false` → `find.text(loginScanQr)` `findsNothing`; `tearDown` сбрасывает override в `null` в `test/presentation/pages/login_page/login_page_test.dart`.
- [ ] T043 [P] [US4] Golden `login_page_no_scan` (page-mobile) + `login_page_no_scan_desktop` (page-desktop), форсируя `QrScannerCapability.debugOverride=false`, в `test/presentation/pages/login_page/login_page_golden_test.dart`.

### Implementation / Verification for User Story 4

- [ ] T044 [US4] Финально подтвердить build-safety (уже проверено рано в T002a, резолвит analyze I2): `mise run build:windows:stage` / `build:linux:stage` зелёные после полной фичи. Гейт capability (T021) скрывает рантайм-вызов.

> Сценарий «`Show QR` доступен на Windows/Linux» (US4 AC3) обеспечивается US2 (`qr_flutter` — pure-Dart, все 5 платформ) — отдельной задачи не требует.

**Checkpoint**: все 4 истории независимо функциональны.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: drift-fix доков (Принцип II), demo-split, финальные гейты.

- [ ] T045 [P] Drift-fix `docs/design/spec/screens/qr-scan.md`: permission-denied `Blocking-overlay`→opaque surface (правки A/B/C: l.35, l.88, l.62-64) + новая подсекция «Адаптация по ширине (`_narrow` vs macOS `_wide`)» (правка D после l.28) + строки микрокопии desktop (`research.md` R14).
- [ ] T046 [P] Drift-fix `docs/blueprints/mobile/01-stack-and-tooling.md`: добавить `mobile_scanner`/`qr_flutter` в манифест зависимостей + таблицу «Почему именно эти зависимости»; `permission_handler` → `^12.0.3` (R12).
- [ ] T047 Demo-split (зеркалит 009 SC-008; резолвит analyze I4 — SC-008 не локальный для 010, см. `navigation.md §6`): **верифицировать** перепроводку dev-кнопок `_devControl` на BLoC-события (реализована в T018): success `Detected(NoxQrEnvelope.encode('registered'))`, invalid `Detected('https://example.com')`, scanning/denied/fatal `PermissionResolved(...)`; `routeDemo()` остаётся `Route<void>`; gallery не трогает камеру/хранилище.
- [ ] T047a [P] Зафиксировать частичное закрытие `TODO(design-desktop-qr)` (резолвит analyze C1): обновить Sync Impact Report конституции (`.specify/memory/constitution.md` l.51) — пометить «macOS desktop-расширение камеры выполнено; Windows/Linux — документированный fallback; остаётся открытым до Windows/Linux-камеры». Минимальная правка comment-блока (отдельный constitution-update).
- [ ] T048 [P] Обновить a11y-проверки (tooltips `Back`/`Flashlight`/`Switch camera`, semantics denied-surface) в `test/presentation/widgets/accessibility_test.dart`.
- [ ] T049 `make gate` (`generate` → `format -l 140` → `analyze` без ошибок → `test` без goldens) — зелёный.
- [ ] T050 `make golden-verify` — все goldens (widget / page-mobile / page-desktop) зелёные.
- [ ] T051 Прогон `quickstart.md` сценариев 1–5 (реальная камера на iOS/Android/macOS; Win/Linux без кнопки; round-trip Show QR↔скан; приватность офлайн).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001–T002)**: без зависимостей — стартует сразу; блокирует всё.
- **Foundational (T003–T011)**: после Setup — **блокирует все user stories**.
- **US1 (T012–T027)**: после Foundational — MVP, без зависимостей от других историй.
- **US2 (T028–T035)**: после Foundational — независима от US1 (использует только `NoxQrEnvelope` из Foundational).
- **US3 (T036–T041)**: после US1 (расширяет `QrScanBloc`/`QrScanPage`, созданные в T016/T018).
- **US4 (T042–T044)**: после US1 (тестирует гейт `Scan QR` из T021 и сборку с `mobile_scanner`).
- **Polish (T045–T051)**: после нужных историй.

### Parallel Opportunities

- **Setup**: T001 → T002 (последовательно).
- **Foundational**: T003+T004, T005+T006, T007 — параллельны; затем T008→T009→T010 (цепочка DI), T011 [P].
- **US1**: тесты T012/T013/T014 [P]; нативная конфигурация T022/T023/T024/T025/T026 [P] (разные файлы) — параллельны имплементации; ветки T019/T020 после T018.
- **US2 ∥ US1**: после Foundational US2 (T028–T035) можно вести параллельно US1 (разные файлы: Settings/widgets vs qr_scan_page/login).
- **Polish**: T045/T046/T048 [P] (разные доки/тест-файлы).

---

## Parallel Example: User Story 1

```bash
# Тесты US1 вместе (пишутся первыми, падают):
Task: "bloc_test QrScanBloc happy-path в test/.../qr_scan_page/bloc/qr_scan_bloc_test.dart"
Task: "widget-тест QrScanPage scanning/back в test/.../qr_scan_page/qr_scan_page_test.dart"
Task: "widget-тест LoginPage Scan QR → real 2.2 в test/.../login_page/login_page_test.dart"

# Нативная конфигурация US1 вместе (разные файлы):
Task: "iOS NSCameraUsageDescription в ios/Runner/Info.plist"
Task: "iOS PERMISSION_CAMERA=1 в ios/Podfile"
Task: "Android CAMERA в android/app/src/main/AndroidManifest.xml"
Task: "macOS camera entitlement в macos/Runner/{DebugProfile,Release}.entitlements"
Task: "macOS NSCameraUsageDescription в macos/Runner/Info.plist"
```

---

## Implementation Strategy

### MVP First (только US1)

1. Phase 1 Setup → Phase 2 Foundational (КРИТИЧНО — блокирует всё).
2. Phase 3 US1 (камера + decode + submit + нативная конфигурация).
3. **STOP & VALIDATE**: проверить вход сканированием независимо (quickstart Сценарий 1).
4. Демо MVP.

### Incremental Delivery

1. Setup + Foundational → фундамент готов.
2. US1 → тест → демо (MVP: вход сканированием).
3. US2 → тест → демо (Show QR замыкает цикл).
4. US3 → тест → демо (надёжность пермишена/ошибок).
5. US4 → тест → демо (Windows/Linux корректность).
6. Polish → drift-fix доков + финальные гейты.

---

## Notes

- [P] = разные файлы, нет незавершённых зависимостей.
- Codegen-first: `make generate` после каждой пачки Freezed/injectable-правок (T010, T017, T033).
- Тесты пишутся первыми и падают до реализации; goldens рендерятся локально на Apple Silicon (camera-preview подменяется `previewBuilder`-seam'ом — живая камера в тестах не нужна).
- Перед завершением — `make gate` И `make golden-verify` (CI временно отключён, локальный гейт обязателен).
- Коммиты — после логических групп, по явному подтверждению владельца (не автономно).

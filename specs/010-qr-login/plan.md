# Implementation Plan: QR-code login (вход по QR)

**Branch**: `010-qr-login` | **Date**: 2026-06-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-qr-login/spec.md`

## Summary

Подключаем заготовку сканера QR (2.2 `QrScanPage`) к реальной камере и вливаем результат в существующий sign-in путь 009. На iOS/Android/macOS `QrScanPage` получает собственный **чистый** Freezed `QrScanBloc` (статусы `initializing`/`scanning`/`permissionDenied`/`fatal` + one-shot `decodedId`/`invalid`; события `Started`/`PermissionResolved`/`Detected`/`SignalHandled`, без DI/getIt) и widget-owned `MobileScannerController` (`mobile_scanner ^7.2.0`, single-shot, ручной lifecycle). Пермишен и камеру оркестрирует **виджет** (не BLoC) через доменный `CameraPermissionService` с двух-бэкендовой реализацией: `permission_handler ^12.0.3` на iOS/Android и состояние `mobile_scanner` + `url_launcher` на macOS (`permission_handler` macOS не поддерживает); виджет кормит BLoC событием `PermissionResolved`. Распознанный валидный конверт `nox://id/<percent-encoded id>` декодируется общим pure-util `NoxQrEnvelope` и через `Navigator.pop(id)` → `LoginEvent.idChanged` + `_submit` идёт ровно тем же путём, что ручной ввод (`authRepository.signIn` → спайн). Обратная сторона замыкается: Show QR (7.1) переводится с фейкового `_FakeQrPainter` на реальный `qr_flutter ^4.1.0` `QrImageView`, кодирующий реальный `SessionModel.identifier`. Платформенный scope — единый static `QrScannerCapability` (iOS/Android/macOS = есть; Windows/Linux = нет): на Windows/Linux кнопка `Scan QR` скрыта и 2.2 недостижим (документированный desktop-fallback, Принцип III). Нативная конфигурация камеры добавляется на iOS/Android/macOS; macOS camera-entitlement безопасен (sandbox-капабилити, ad-hoc-подпись) — в отличие от 009 keychain, Dart-workaround не нужен. Технический подход и развилки зафиксированы в [research.md](research.md) (R1–R14); модель — [data-model.md](data-model.md); интерфейсы — [contracts/](contracts/).

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM), line length 140, стоковый `flutter_lints`.

**Primary Dependencies**: `mobile_scanner: ^7.2.0` (NEW — камера/QR, iOS/Android/macOS only, NO Windows/Linux), `permission_handler: ^12.0.3` (раскомментировать feature-gated-плейсхолдер + бамп; iOS/Android only), `qr_flutter: ^4.1.0` (NEW — pure-Dart QR-рендер, все 5 платформ), `url_launcher` (уже в `pubspec.yaml` — macOS Open settings). `app_settings` НЕ добавляем. Freezed + injectable + `build_runner` — как есть.

**Storage**: своего хранилища фича не вводит; реальный `Your ID` для 7.1 читается из 009 `SessionRepository` (`flutter_secure_storage`).

**Testing**: `flutter_test`, `bloc_test`, `mockito` (`CameraPermissionService`-double); goldens — `matchesGoldenFile` через `goldenTest`/`goldenTestDesktop`; camera-preview подменяется `previewBuilder`-seam'ом (без живой камеры).

**Target Platform**: iOS, Android, macOS (камера-сканер) + Windows, Linux (только Show QR + ручной вход; web — вне scope).

**Project Type**: кросс-платформенное Flutter-приложение, один пакет `nox_app`, Clean Architecture слоями-папками.

**Performance Goals**: happy-path вход сканированием за ~5 с от открытия сканера (SC-001); UI 60 fps.

**Constraints**: приватность без компромиссов — `returnImage:false`, кадры на устройстве, ничего не хранится/передаётся (Принцип I, FR-018/SC-007); только design-токены; backend/протокол NOX ещё не выбран → `nox://id/`-конверт помечен как клиентская конвенция/TBD.

**Scale/Scope**: ~6 новых файлов (`qr_scan_bloc`/`event`/`state`, `nox_qr_envelope`, `qr_scanner_capability`, `camera_permission_service` + impl) + правки 2.2/2.1/7.1/Settings-bloc/pubspec/DI + 5 нативных файлов + drift-fix `qr-scan.md`/блюпринт `01`. Малая-средняя фича.

**Unknowns**: нет блокирующих `NEEDS CLARIFICATION` — спека прошла `/speckit-clarify` (3 ответа); отложенное (Windows/Linux камера, реальный backend-чек, macOS Open-settings anchor) зафиксировано в `research.md` как non-blocking.

## Constitution Check

*GATE: пройден до Phase 0; перепроверен после Phase 1.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | Камера обрабатывается на устройстве (`returnImage:false`); кадры/изображения не хранятся и не передаются (FR-018/SC-007). Идентификатор остаётся анонимным/непрозрачным — `NoxQrEnvelope` распознаёт конверт, но НЕ валидирует формат id (009 FR-011). Никаких PII в логах. |
| **II. Спека/дизайн — источник истины** | ✅ PASS | Spec прошла clarify (16/16 чеклист). Drift-fix в том же change-set: `qr-scan.md` (permission-denied overlay → opaque surface; +macOS `_wide`-подсекция, `research.md` R14) и блюпринт `01` (новые deps, R12) приводятся к реализованной форме. Зафиксированный out-of-scope (Windows/Linux камера) не расширяется. |
| **III. Блюпринт обязателен** | ✅ PASS (с расширением подсистемы) | Строим по `05` (Freezed `QrScanBloc`, BLoC-per-page `05 §5.1`), `02` (DI `CameraPermissionService`), `06` (design-токены), `04` (impl/log). **Desktop-native gate**: камера — новая нативная подсистема; по Принципу III iOS/Android/macOS получают реальную конфигурацию пермишена, Windows/Linux — **документированный desktop-fallback** (camera недоступна, кнопка скрыта capability-флагом). Это **частично закрывает** отложенный `TODO(design-desktop-qr)` (macOS = desktop-расширение камеры; Windows/Linux = fallback) — формальная отметка в Sync Impact Report конституции (l.51) выполняется отдельным constitution-update (резолвит analyze C1; зафиксировано задачей в Polish), не молчаливо. macOS camera-entitlement безопасен (ad-hoc-подпись), в отличие от 009 keychain (`research.md` R12). См. T-задачи нативной конфигурации. |
| **IV. Верность дизайн-системе** | ✅ PASS | M3 light+dark; токены overlay/прицела/viewfinder (`NoxScrims.qrMask`, `size.qrScanWindow`, `border.heavy`, `NoxRadius.m`). Brand-fixed исключение соблюдено: QR-поверхность 7.1 остаётся светлой вне зависимости от темы (`NoxBrand.qrSurface`/`qrInk`, FR-015). Реальный QR (`qr_flutter`) заменяет фейковый паттерн без отхода от токенов. |
| **V. Языковая дисциплина** | ✅ PASS | Артефакты спеки/доков — RU; код/идентификаторы/нативные ключи — EN; UI-микрокопия — EN (`Scan QR`, `Camera access needed`, `Open settings`, `This QR code is invalid. Try another one.`, camera purpose string). Новых пользовательских языков нет. |

**Tech-context конституции**: backend/протокол/криптоядро ещё не выбраны → `nox://id/`-конверт явно помечен как **клиентская конвенция/TBD** (пересмотр с реальным форматом идентичности); `OnboardingMockData.registeredIds`-чек наследуется из 009 как пример. Сетевой контракт не изобретается.

**Итог гейта**: нарушений нет → **Complexity Tracking пуст**. (Перепроверка после Phase 1: интерфейсы (`contracts/`) и модель (`data-model.md`) не вводят новых нарушений — гейт остаётся PASS; desktop-native-расширение задокументировано как fallback.)

## Project Structure

### Documentation (this feature)

```text
specs/010-qr-login/
├── plan.md              # Этот файл (/speckit-plan)
├── research.md          # Phase 0 — R1–R14 (Decision/Rationale/Alternatives)
├── data-model.md        # Phase 1 — типы (NoxQrEnvelope, CameraPermission*, QrScan*, QrScannerCapability)
├── quickstart.md        # Phase 1 — сценарии проверки 1–5 + привязка автотестов
├── contracts/
│   ├── scanner.md       # CameraPermissionService, QrScanBloc, NoxQrEnvelope, QrScannerCapability, DI
│   └── navigation.md    # Login ↔ 2.2 ↔ Show QR wiring, capability-гейт, demo-split, acceptance
├── checklists/
│   └── requirements.md  # Чеклист качества спеки (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этой командой)
```

### Source Code (repository root)

```text
lib/
├── general/
│   ├── nox_qr_envelope.dart            # NEW — encode/decode 'nox://id/<percent-encoded>'
│   └── qr_scanner_capability.dart      # NEW — static isAvailable + @visibleForTesting debugOverride (FR-016/017)
├── domain/
│   ├── model/qr/camera_permission_status.dart   # NEW — enum granted/denied/permanentlyDenied/unavailable
│   └── repository/qr/camera_permission_service.dart  # NEW — интерфейс status/request/openSettings
├── data/
│   └── repository/qr/camera_permission_service_impl.dart  # NEW — @LazySingleton, двух-бэкендовый (permission_handler / mobile_scanner+url_launcher)
├── presentation/
│   └── pages/
│       ├── qr_scan_page/
│       │   ├── qr_scan_page.dart       # EDIT: stub → BLoC + MobileScannerController + previewBuilder-seam; route()→Route<String?>
│       │   └── bloc/
│       │       ├── qr_scan_bloc.dart   # NEW
│       │       ├── qr_scan_event.dart  # NEW (part)
│       │       └── qr_scan_state.dart  # NEW (part)
│       ├── login_page/login_page.dart  # EDIT: _scanQr → реальный 2.2 (l.89-93); capability-гейт кнопки (l.203-205)
│       └── settings_root_page/
│           ├── settings_root_page.dart # EDIT: mockRawId → state.rawId (l.112/312/321)
│           └── bloc/settings_root_bloc.dart  # EDIT: _onInitialize → sessionRepository.readSession(); +rawId в state
├── presentation/widgets/settings/app_qr_surface_widget.dart  # EDIT: удалить _FakeQrPainter; QrImageView(NoxQrEnvelope.encode(data))
└── di/
    ├── global_aliases.dart             # EDIT: +sessionRepository (+ опц. cameraPermissionService)
    └── configure_dependencies.config.dart  # GENERATED — регистрация CameraPermissionService (build_runner)

test/
├── general/nox_qr_envelope_test.dart            # NEW (unit — round-trip + edge)
├── general/qr_scanner_capability_test.dart      # NEW (unit — override)
├── presentation/pages/qr_scan_page/
│   ├── bloc/qr_scan_bloc_test.dart              # NEW (bloc_test)
│   ├── qr_scan_page_test.dart                   # EDIT — re-point на fake controller; +manual/back, fatal, invalid
│   └── qr_scan_page_golden_test.dart            # EDIT — +denied (mobile+desktop), re-verify scanning
├── presentation/pages/login_page/               # EDIT — +hidden-button (debugOverride=false) widget+golden
└── presentation/widgets/settings/app_qr_surface_widget_golden_test.dart  # REGEN — реальный QR

# Native (Принцип III / FR-008, тот же change-set):
ios/Runner/Info.plist                            # EDIT: +NSCameraUsageDescription
ios/Podfile                                      # EDIT: +PERMISSION_CAMERA=1
android/app/src/main/AndroidManifest.xml         # EDIT: +CAMERA + uses-feature camera required=false
macos/Runner/DebugProfile.entitlements           # EDIT: +com.apple.security.device.camera
macos/Runner/Release.entitlements                # EDIT: +com.apple.security.device.camera
macos/Runner/Info.plist                          # EDIT: +NSCameraUsageDescription
# Windows/Linux — без правок (capability-fallback; compile-check.yml не трогаем)

# Docs (drift-fix, Принцип II):
docs/design/spec/screens/qr-scan.md              # EDIT: permission-denied → opaque surface; +macOS _wide (R14)
docs/blueprints/mobile/01-stack-and-tooling.md   # EDIT: +mobile_scanner/qr_flutter; permission_handler ^12.0.3 (R12)
pubspec.yaml                                      # EDIT: +mobile_scanner/qr_flutter; uncomment+bump permission_handler
```

**Structure Decision**: один пакет `nox_app`, слои-папки. Сканер — page-фича в `presentation` (BLoC-per-page без DI); пермишен — доменный интерфейс + data-impl (DI, mockito-testable); codec и capability-флаг — pure-util в `lib/general` (без DI/codegen, доменно-нейтральны, импортируются обоими presentation-call-site'ами 2.2/7.1). Camera — нативная подсистема: реальная конфигурация на iOS/Android/macOS, документированный fallback на Windows/Linux.

## Complexity Tracking

> Constitution Check без нарушений — таблица не заполняется.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Phase 1 — Agent context

Managed-секция Spec Kit в `CLAUDE.md` (между `<!-- SPECKIT START -->` / `<!-- SPECKIT END -->`, если присутствует) обновляется указателем на этот план; иначе — через опциональный хук `/speckit-agent-context-update` после плана. Активная фича в CLAUDE.md «Active feature» переводится на **010-qr-login — planned**.

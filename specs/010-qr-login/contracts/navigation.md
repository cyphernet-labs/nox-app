# Contract: Навигация и проводка (Login ↔ 2.2 ↔ Show QR)

**Feature**: `010-qr-login` | **Phase**: 1

Как распознанный идентификатор проходит из сканера (2.2) в существующий sign-in путь (2.1 → спайн 009), как capability-флаг гейтит вход в 2.2, и как замыкается обратная сторона (Show QR 7.1). Интерфейсы — в `scanner.md`.

---

## 1. Точка входа и гейт (`Scan QR` на 2.1)

`lib/presentation/pages/login_page/login_page.dart` — кнопка `Scan QR` (`_actions`, l.203-205) оборачивается в capability-гейт:

```text
if (QrScannerCapability.isAvailable)
  SizedBox(width: double.infinity,
    child: TextButton(onPressed: state.isLoading ? null : _scanQr,
                      child: const Text(TextConstants.loginScanQr)));
```

| Платформа | `QrScannerCapability.isAvailable` | Кнопка `Scan QR` | 2.2 |
|---|---|---|---|
| iOS / Android / macOS | `true` | показана | достижим |
| Windows / Linux | `false` | **скрыта** | недостижим (FR-016) |

Единый флаг → нет рассинхрона видимости и достижимости (FR-017).

---

## 2. Wiring `_scanQr` (2.1 → 2.2 → submit)

`QrScanPage.route()` меняет тип на **`Route<String?>`** (`routeDemo()` остаётся `Route<void>`).

```text
Future<void> _scanQr() async {
  final id = await Navigator.of(context).push(QrScanPage.route());   // Route<String?>
  if (id == null || !mounted) return;            // back / Enter manually → без submit, поле сохранено (FR-013)
  _controller.text = id;
  _bloc.add(LoginEvent.idChanged(id));           // ставит state.id, status:idle
  _submit();                                      // LoginEvent.signInRequested — ТОТ ЖЕ путь, что ручной ввод
}
```

- Корректность опирается на **последовательную (FIFO) обработку событий BLoC**: `idChanged` обрабатывается раньше `signInRequested`, который сам сверяется с `state.canSubmit` (резолвит analyze A3 — не синхронное чтение `state.id` после `add()`).
- Real-режим: `signInRequested` → `authRepository.signIn(identifier: state.id)` → `SessionRepository.saveIdentifier` → `AppStateRepository.fetchAppState()` → спайн `pushAndRemoveUntil(…,(_)=>false)` чистит стек (включая уже-popped Login) на Chats (4.1) / Set username (2.3). Идентично ручному вводу той же строки (FR-012, SC-002).

---

## 3. Внутри 2.2: оркестрация и исходы

`lib/presentation/pages/qr_scan_page/qr_scan_page.dart` — `_QrScanPageState` владеет `QrScanBloc` (чистый) + `MobileScannerController` + `CameraPermissionService` (non-demo).

**Оркестрация пермишена** `_resolvePermission()`:
- iOS/Android: `bloc.add(PermissionResolved(await cameraPermissionService.request()))`.
- macOS: `bloc.add(PermissionResolved(granted))` (контроллер поднимает промпт); `MobileScanner.errorBuilder` `permissionDenied` → `bloc.add(PermissionResolved(permanentlyDenied))`.

**Lifecycle**: `initState` → `addObserver` + `Started` + `_resolvePermission()`; `resumed` → `_resolvePermission()` (авто-resume, FR-006); `paused` → `controller.stop()`; `dispose` → `removeObserver` + `controller.dispose()` + `bloc.close()`. Паттерн зеркалит `LoginPage` (l.46-72).

**`BlocListener<QrScanBloc>` исходы**:

| Состояние | Действие |
|---|---|
| `decodedId != null` | `controller.stop(); Navigator.pop(decodedId)` |
| `invalid == true` | snackbar `qrInvalidSnackbar`; камера сканирует дальше → `SignalHandled` |
| `status == permissionDenied` | opaque surface `qrPermissionTitle` + `actionOpenSettings` (живого превью нет) |
| `status == fatal` | `Navigator.push(AppErrorPage.route(params: ErrorPageParams.fatal()))` (3.1, FR-007) |
| Back / системный back / `Enter manually` | `Navigator.pop(null)` → 2.1 без submit, поле сохранено (FR-013) |

`onDetect` `MobileScanner` → `bloc.add(Detected(raw: capture.barcodes.first.rawValue ?? ''))`. Torch/switch — widget-local на контроллере (`controller.toggleTorch()` / lens-switch).

---

## 4. Адаптация по ширине (`_narrow` vs `_wide`)

Ветка выбирается по **ширине** `constraints.maxWidth >= Constants.railBreakpoint` (840) — стандартный responsive-паттерн NOX (как все экраны; не по платформе). Goldens рендерят обе ветки на macOS-хосте (360 → `_narrow`, 1280 → `_wide`).

| | `_narrow` (узкая ширина — iOS/Android-телефоны) | `_wide` (широкая — macOS-окно / десктоп) |
|---|---|---|
| Камера | full-screen feed | viewfinder 300×300 (`size.qrScanWindow`) на `surface`-фоне |
| Overlay | прицел + маска `#000` @ 55% (`NoxScrims.qrMask`) | brand-белые углы, без полноэкранной маски/инструкции |
| AppBar | прозрачный, back + `Flashlight` + `Switch camera` | `AppWindowTitlebarWidget(subtitle:'Scan QR')`, без действий |
| Заголовок/хелпер | top `qrAimHint` | `qrDesktopTitle` + helper `qrDesktopHelper` |
| Manual fallback | нижняя `qrEnterManually`-pill | inline `qrEnterManually`-`TextButton` в helper-области |
| Permission-denied | opaque surface, центр | opaque surface в `AppOnboardCardWidget` |

**Torch/switch (FR-005, резолвит analyze A1)**: показываются **только в `_narrow`-ветке** и **gracefully no-op** на устройстве без вспышки/второй камеры (mobile_scanner `toggleTorch()`/lens-switch — безопасный no-op). В `_wide`-ветке их нет (десктопный корпус `06-qr.md`). Width-based-выбор ветки сохранён (а не platform-based): узкое окно macOS легитимно показывает `_narrow` (torch/switch там no-op на webcam без вспышки); широкий планшет — `_wide`-viewfinder. macOS-clarify «= `_wide`» выполняется тем, что macOS-окна обычно ≥840.

**macOS manual fallback (резолвит analyze A2)**: в `_wide` ручной возврат — `TextButton` с лейблом `qrEnterManually` (`Enter manually`) под helper-текстом `qrDesktopHelper` (`Point your webcam at a code, or enter the ID manually.`). Спан «enter the ID manually» внутри helper'а — описательный, **tappable-аффорданс — отдельная кнопка** `qrEnterManually`.

---

## 5. Обратная сторона: Show QR (7.1) — реальный QR

`lib/presentation/widgets/settings/app_qr_surface_widget.dart`: `_FakeQrPainter` → `QrImageView(data: NoxQrEnvelope.encode(data), ... NoxBrand.qrInk/qrSurface)`. Brand-fixed light Container + `showIdQr`/`_IdQrContent` — без изменений.

Источник `data` (FR-014): реальный `identifier` из `SessionRepository.readSession()` (спайн 009), не const-stub:
- `lib/di/global_aliases.dart` — `+sessionRepository`.
- `SettingsRootBloc._onInitialize` — `sessionRepository.readSession()` через `RepositoryResult.match` (резолвит analyze U3):
  - `onData(session)`: `rawId = session?.identifier ?? ''`.
  - `onError`: `rawId = ''` + лог (Show QR в Settings достижим только в `authorized`, значит identifier непуст; пустой `rawId` — defensive fallback, при нём Show QR-кнопку гейтить как `rawId.isNotEmpty`).
- `settings_root_page.dart` — `SettingsRootBloc.mockRawId` → `state.rawId` (l.112 `_copyId`, l.312 inline-QR, l.321 `onShowQr`).

Round-trip: устройство A показывает `nox://id/<enc(idA)>`; устройство B сканирует → `decode` → `idA` → `signIn` (SC-005).

---

## 6. Demo-vs-real split (зеркалит 009 SC-008)

> Прим. (резолвит analyze I4): SC-008 — критерий **009**, не локальный для 010 (в 010 только SC-001..007). Demo-split в 010 обоснован Edge Case «Demo-маршрут 2.2» + Assumptions «Demo-vs-real split», зеркалящими 009 SC-008.

| Поверхность | Real-режим | Demo-режим (dev-галерея) |
|---|---|---|
| 2.2 `QrScanPage` | `route()` `Route<String?>`, реальная камера/пермишен, `pop(id)` | `routeDemo()` `Route<void>`, ColoredBox-плейсхолдер (без камеры), dev-кнопки шлют BLoC-события |
| Dev-кнопки 2.2 (`kDebugMode && demo`) | — | scanning → `PermissionResolved(granted)`; denied → `PermissionResolved(permanentlyDenied)`; fatal → `PermissionResolved(unavailable)`; success → `Detected(NoxQrEnvelope.encode('registered'))`; invalid → `Detected('https://example.com')` |
| 7.1 Show QR | реальный `state.rawId` из сессии | существующее demo-поведение сохранено |

Demo-перепроводка dev-кнопок на BLoC-события выполняется **внутри rewrite `QrScanPage`** (резолвит analyze U4 — иначе `setState(_preview=…)` не скомпилируется после перевода на BLoC). `screens_gallery_page.dart` l.144 (`'2.2' … QrScanPage.routeDemo`) — без изменений.

---

## 7. UI-микрокопия (все строки уже существуют)

Все строки уже в `text_constants.dart` — **новых Dart-строк не требуется** (резолвит analyze I1, имена сверены с кодом):

| Назначение | Константа |
|---|---|
| Кнопка на 2.1 | `loginScanQr` (`Scan QR`) |
| Инструкция `_narrow` | `qrAimHint` (`Aim your camera at a QR code`) |
| Manual fallback | `qrEnterManually` (`Enter manually`) |
| Denied title | `qrPermissionTitle` (`Camera access needed`) |
| Denied body | `qrPermissionMessage` (`To scan a QR code, allow camera access in system settings.`) |
| Open settings | `actionOpenSettings` (`Open settings`) |
| Inline-error | `qrInvalidSnackbar` (`This QR code is invalid. Try another one.`) |
| Desktop title | `qrDesktopTitle` (`Scan a QR code`) |
| Desktop helper | `qrDesktopHelper` |
| Torch/switch tooltips | `tooltipFlashlight` / `tooltipSwitchCamera` |

**Новая** — только camera purpose string в нативных конфигах (`NSCameraUsageDescription`, EN, см. `research.md` R11).

---

## 8. Acceptance-привязка

| Сценарий спеки | Контракт |
|---|---|
| US1 / SC-001 / SC-002 (вход сканированием) | §1 (гейт) → §2 (wiring) → §3 (decodedId) → спайн 009 |
| US2 / SC-005 (Show QR ↔ скан, round-trip) | §5 (генерация) + `scanner.md` `NoxQrEnvelope` |
| US3 / SC-003 / SC-004 (пермишен, чужой QR, fatal) | §3 (invalid/permissionDenied/fatal) + `scanner.md` `CameraPermissionService`/`QrScanBloc` |
| US4 / SC-006 (Windows/Linux без кнопки) | §1 (capability-гейт) + `scanner.md` `QrScannerCapability` |
| FR-013 (back/manual без submit) | §2/§3 (`pop(null)`) |
| FR-018 / SC-007 (приватность) | `returnImage:false`, кадры на устройстве (`scanner.md`/`research.md` R4); регрессионный assert в widget-тесте |

# Data Model: QR-code login (вход по QR)

**Feature**: `010-qr-login` | **Date**: 2026-06-26 | **Phase**: 1 (Design)

Новые типы фичи — Freezed (**только `.freezed.dart`**, без `.g.dart` на BLoC-типах) плюс два pure-Dart-хелпера в `lib/general/` (codec + capability-флаг) и тонкий доменный сервис-контракт. Доменный слой ни от чего не зависит (`presentation → domain ← data`). Детали интерфейсов — в `contracts/`.

---

## 1. `NoxQrEnvelope` (pure-Dart codec)

**Файл**: `lib/general/nox_qr_envelope.dart` (`abstract final class`, без DI/codegen)

Источник истины формата `nox://id/<percent-encoded identifier>` — общий для генератора (7.1) и парсера (2.2); гарантирует round-trip (FR-009, SC-005).

| Член | Сигнатура | Поведение |
|---|---|---|
| `encode` | `static String encode(String identifier)` | `nox://id/${Uri.encodeComponent(identifier)}` — путь всегда один сегмент для любого charset |
| `decode` | `static String? decode(String raw)` | конверт → identifier, или `null` для невалидного/чужого/пустого (никогда не бросает) |

**Правила `decode`** (каждый `null` → caller показывает inline-snackbar, FR-011):

| Вход | Результат | Причина |
|---|---|---|
| `''` / только пробелы | `null` | `trim().isEmpty` |
| `https://…`, `WIFI:…`, vCard | `null` | `scheme != 'nox'` (или `FormatException` → caught) |
| `nox://other/x` | `null` | `host != 'id'` |
| `nox://id/` (пустой путь) | `null` | `pathSegments.length != 1` / пустой id |
| `nox://id/a/b` | `null` | `pathSegments.length != 1` |
| `nox://id/a%2Fb` (id был `a/b`) | `'a/b'` | один сегмент, **один** decode |
| валидный `nox://id/<enc>` | identifier | happy path → single-shot sign-in (FR-010/FR-012) |

**Ключевой инвариант**: `pathSegments.first` уже percent-декодирован ровно один раз — **не** звать `Uri.decodeComponent` повторно (double-decode испортит id с литеральным `%xx`). `decode` НЕ валидирует формат идентификатора (009 FR-011) — только распознаёт конверт. Round-trip `decode(encode(id)) == id` держится для любого **непустого** id; `encode('')` = `nox://id/` → `decode` → `null` (несканируемо), поэтому 7.1 не кодирует пустой identifier (резолвит analyze U3; Show QR в Settings достижим только в `authorized` → identifier непуст, плюс defensive `rawId.isNotEmpty`-гейт).

---

## 2. `CameraPermissionStatus` (enum)

**Файл**: `lib/domain/model/qr/camera_permission_status.dart`

```text
enum CameraPermissionStatus { granted, denied, permanentlyDenied, unavailable }
```

| Значение | Смысл | Переход в `QrScanStatus` |
|---|---|---|
| `granted` | доступ выдан | `scanning` |
| `denied` | отклонён (можно перезапросить) | `permissionDenied` |
| `permanentlyDenied` | отклонён навсегда (только Open settings) | `permissionDenied` |
| `unavailable` | камеры нет на уровне устройства | `fatal` → 3.1 (FR-007) |

Нормализованная проекция бэкендов: `permission_handler` (iOS/Android) даёт `granted/denied/permanentlyDenied/restricted`; на macOS статус выводится из `mobile_scanner` (`hasCameraPermission` / `MobileScannerErrorCode.permissionDenied`). `restricted` мапится в `permanentlyDenied` (тот же UX — Open settings).

---

## 3. `QrScanStatus` (enum)

**Файл**: `lib/presentation/pages/qr_scan_page/bloc/qr_scan_state.dart` (`part`)

```text
enum QrScanStatus { initializing, scanning, permissionDenied, fatal }
```

| Значение | Смысл | Top-level отрисовка 2.2 |
|---|---|---|
| `initializing` | запрос/проверка пермишена | нейтральный кадр (без живого превью) |
| `scanning` | камера активна, прицел/viewfinder | feed + overlay (`_narrow`) / windowed viewfinder (`_wide`) |
| `permissionDenied` | доступ отклонён | opaque surface-экран (`no_photography` + `Open settings`) |
| `fatal` | камера недоступна аппаратно | передача в `AppErrorPage` (3.1) |

Схлопывает текущий `_QrPreview { scanning, permissionDenied }` в полноценный статус-юнион.

---

## 4. `QrScanState` (Freezed value-object)

**Файл**: `lib/presentation/pages/qr_scan_page/bloc/qr_scan_state.dart`

| Поле | Тип | Default | Описание |
|---|---|---|---|
| `status` | `QrScanStatus` | `initializing` | текущая фаза экрана (см. §3) |
| `decodedId` | `String?` | `null` | **one-shot**: валидный конверт распознан → страница `pop`'ает id в Login (2.1) и сбрасывает `SignalHandled` |
| `invalid` | `bool` | `false` | **one-shot**: чужой/пустой QR → snackbar `This QR code is invalid. Try another one.`, скан продолжается |

Computed-геттеры (extension): `bool get isScanning => status == QrScanStatus.scanning`. One-shot-поля консьюмятся `BlocListener`'ом страницы (поп id / снэкбар / push 3.1) и сбрасываются `SignalHandled` (паттерн `LoginEvent.navigationHandled`).

---

## 5. `QrScanEvent` (Freezed sealed union)

**Файл**: `lib/presentation/pages/qr_scan_page/bloc/qr_scan_event.dart`

`QrScanBloc` — **чистый автомат** (без DI/сервиса); пермишеном и камерой владеет виджет и кормит BLoC событием `PermissionResolved` (резолвит analyze U1/U2, см. `contracts/scanner.md`).

| Конструктор | Параметры | Семантика |
|---|---|---|
| `Started` | — | открытие экрана → `initializing` (виджет затем оркестрирует пермишен, FR-002) |
| `PermissionResolved` | `CameraPermissionStatus status` | результат пермишена от виджета (iOS/Android — `permission_handler`; macOS — состояние контроллера); авто-resume по lifecycle тоже шлёт это событие (FR-006) |
| `Detected` | `String raw` | сырое значение QR из контроллера/demo → `NoxQrEnvelope.decode` (FR-010/FR-011) |
| `SignalHandled` | — | страница консьюмила `decodedId`/`invalid` → сброс one-shot |

**Логика хендлеров** (BLoC чистый — `executeLogic` не нужен, side-effect'ов нет):
- `Started` → `emit(status: initializing)`.
- `PermissionResolved(status)` → guard `if (state.decodedId != null) return;` (analyze A4: поздний resume не перезапускает камеру у уходящей страницы); `granted` → `scanning`; `denied`/`permanentlyDenied` → `permissionDenied`; `unavailable` → `fatal`.
- `Detected(raw)` → single-shot guard (`if (state.decodedId != null) return;`); `decode(raw)` non-null → `decodedId: id`; null → `invalid: true` (остаётся `scanning`).
- `SignalHandled` → `copyWith(decodedId: null, invalid: false)`.
- Открытие настроек и lifecycle — НЕ события BLoC (это side-effect'ы виджета: `cameraPermissionService.openSettings()`, `controller.stop()`).

---

## 6. `QrScannerCapability` (static предикат)

**Файл**: `lib/general/qr_scanner_capability.dart` (`abstract final class`, без DI)

| Член | Сигнатура | Поведение |
|---|---|---|
| `isAvailable` | `static bool get isAvailable` | `debugOverride ?? (PlatformUtils.isMobile \|\| PlatformUtils.isMacOS)` |
| `debugOverride` | `@visibleForTesting static bool? debugOverride` | тест-seam (Windows/Linux-кейс: `= false`) |

Единственный источник истины FR-016/FR-017: камера-сканер только на iOS/Android/macOS. Один флаг управляет видимостью кнопки `Scan QR` (2.1) И достижимостью 2.2. Тест-override обязателен, т.к. `PlatformUtils` на `dart:io Platform` не оверрайдится в `flutter_test` (см. `research.md` R7).

---

## 7. `SettingsRootState` — расширение (реальный `Your ID` для 7.1)

**Файл**: `lib/presentation/pages/settings_root_page/bloc/settings_root_state.dart`

| Поле | Тип | Default | Описание |
|---|---|---|---|
| `rawId` *(new)* | `String` | `''` | реальный `identifier` пользователя из `SessionRepository.readSession()`, кодируемый в QR (FR-014) |

`SettingsRootBloc._onInitialize` заменяет 300 ms-stub на `sessionRepository.readSession()`, развёрнутый через `RepositoryResult.match` (резолвит analyze U3 — `readSession()` возвращает `RepositoryResult<SessionModel?>`, не голое поле):
- `onData(session)` → `rawId = session?.identifier ?? ''`.
- `onError` → `rawId = ''` (+ лог). Settings достижим только в `authorized` → identifier непуст; пустой `rawId` — defensive fallback, при нём Show QR-аффорданс гейтить `rawId.isNotEmpty`.

Три места `settings_root_page.dart` (l.112 `_copyId`, l.312 inline-QR, l.321 `onShowQr`) переходят с const `SettingsRootBloc.mockRawId` на `state.rawId`. `mockRawId` остаётся только как тест-дефолт.

---

## 8. Доменные/сервисные контракты (сводно; детали — `contracts/`)

| Контракт | Файл | Члены |
|---|---|---|
| `CameraPermissionService` | `lib/domain/.../camera_permission_service.dart` | `status()`, `request()`, `openSettings()` → `CameraPermissionStatus` |
| `QrScanBloc` | `lib/presentation/pages/qr_scan_page/bloc/` | events/state выше; BLoC-per-page, без DI |
| `NoxQrEnvelope` | `lib/general/nox_qr_envelope.dart` | `encode` / `decode` (§1) |
| Login ↔ 2.2 wiring | — | `Route<String?>` + `pop(id)` → `idChanged` + `_submit` (`contracts/navigation.md`) |

---

## 9. Ошибки

`CameraPermissionService` — **no-throw** (резолвит analyze I5): не возвращает `RepositoryResult`, не бросает; любая ошибка платформенного канала мапится внутри сервиса в `CameraPermissionStatus.unavailable` и логируется `LogRepository` (никаких сырых `print`). Виджет получает `unavailable` → шлёт `PermissionResolved(unavailable)` → BLoC `fatal`. `QrScanBloc` — чистый автомат без внешних вызовов, поэтому `executeLogic`/`onError` ему не нужен. Отдельной иерархии исключений фича не вводит; `RepositoryResult`/`BaseRepositoryException` к сервису пермишена не применяются (он возвращает голый `CameraPermissionStatus`).

---

## 10. Валидационные правила (из требований)

- **FR-009**: `encode`/`decode` — точный percent-encoded round-trip; единственный источник — `NoxQrEnvelope` (§1).
- **FR-010/FR-011**: валиден только `nox://id/<непустой>`-конверт; всё прочее → `invalid` (snackbar, скан продолжается). Это **не** валидация формата id (009 FR-011).
- **FR-016/FR-017**: видимость `Scan QR` и достижимость 2.2 — единый `QrScannerCapability.isAvailable` (§6).
- **FR-014/FR-015**: 7.1 кодирует реальный `SessionModel.identifier`; QR-поверхность brand-fixed светлая (§7, `NoxBrand.qrSurface`/`qrInk` вне `ColorScheme`).
- **FR-006/FR-007**: `denied`/`permanentlyDenied` → `permissionDenied` + Open settings; `unavailable` → `fatal` → 3.1; авто-resume — виджет на lifecycle `resumed` пере-оркестрирует пермишен и шлёт `PermissionResolved` (BLoC сам lifecycle не слушает).
- **FR-018 / Принцип I**: кадры — на устройстве; `returnImage:false`, никакого хранения/передачи изображений.

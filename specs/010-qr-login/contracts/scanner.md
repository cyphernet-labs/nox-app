# Contract: Сканер, пермишен камеры, codec, capability

**Feature**: `010-qr-login` | **Phase**: 1

Интерфейсы и инварианты сканирующей стороны (2.2): pure-state-machine `QrScanBloc`, доменный `CameraPermissionService`, pure-util `NoxQrEnvelope` и capability-флаг `QrScannerCapability`. Навигация и проводка с Login (2.1) / Show QR (7.1) — в `navigation.md`.

> **Разделение ответственности (резолвит analyze U1/U2).** BLoC — **чистый автомат состояний** без DI: он не знает про `permission_handler`/`mobile_scanner`. Камерой и оркестрацией пермишена владеет **виджет** (`_QrScanPageState`), где живёт `MobileScannerController`; виджет резолвит `CameraPermissionService` из `getIt` только на non-demo-пути и кормит BLoC событием `PermissionResolved`. Так BLoC не резолвит `getIt` в конструкторе (DI-less demo/gallery-тесты живут, SC-008), а macOS-пермишен (где `permission_handler` отсутствует) ведётся через состояние контроллера в виджете.

---

## `CameraPermissionService`

`lib/domain/repository/qr/camera_permission_service.dart`

```dart
abstract class CameraPermissionService {
  /// Текущий статус без системного промпта. Зовётся виджетом ТОЛЬКО на iOS/Android.
  Future<CameraPermissionStatus> status();

  /// Запросить доступ (системный промпт, если notDetermined). iOS/Android only.
  Future<CameraPermissionStatus> request();

  /// Открыть системные настройки приложения (deep-link). Все платформы со сканером:
  /// iOS/Android — permission_handler.openAppSettings(); macOS — url_launcher
  /// (x-apple.systempreferences:com.apple.preference.security?Privacy_Camera).
  Future<void> openSettings();
}
```

**Контракт поведения**:
- `status()`/`request()` возвращают нормализованный `CameraPermissionStatus` (`granted`/`denied`/`permanentlyDenied`/`unavailable`); `restricted`/`limited` (iOS) → `permanentlyDenied`.
- **No-throw**: любая ошибка платформенного канала мапится в `unavailable` (→ виджет шлёт `PermissionResolved(unavailable)` → BLoC `fatal`), и логируется `LogRepository`. Сервис НЕ возвращает `RepositoryResult` и НЕ бросает (это не репозиторий данных — резолвит analyze I5).
- **macOS**: `status()`/`request()` на macOS виджетом не вызываются (пермишен ведёт контроллер, см. ниже); реализация на macOS возвращает `granted` как benign-default. `openSettings()` на macOS работает (url_launcher).

**Реализация** (`lib/data/repository/qr/camera_permission_service_impl.dart`, `@LazySingleton(as: CameraPermissionService, env: [dev, prod, test])`):
- iOS/Android: `Permission.camera` (`permission_handler`).
- Не использует `BaseRepositoryHelper`/`execute` (нет `RepositoryResult`); ловит исключения сама → `unavailable` + `logRepository`.

**Тесты-контракта**: mockito-double подменяет каждый статус; проверяется, что виджет/BLoC переходит в нужный `QrScanStatus`; `openSettings()` — verify-вызов.

---

## `QrScanBloc` — чистый автомат (без DI)

`lib/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart` (+ `qr_scan_event.dart`, `qr_scan_state.dart`)

```dart
class QrScanBloc extends BaseBloc<QrScanEvent, QrScanState> {
  QrScanBloc() : super(const QrScanState()) {            // НЕТ getIt, НЕТ сервиса, НЕТ demo-флага
    on<Started>(_onStarted);
    on<PermissionResolved>(_onPermissionResolved);
    on<Detected>(_onDetected);
    on<SignalHandled>(_onSignalHandled);
  }
}
```

| Событие | Параметры | Семантика |
|---|---|---|
| `Started` | — | открытие/`initializing` (виджет затем оркестрирует пермишен) |
| `PermissionResolved` | `CameraPermissionStatus status` | результат пермишена (от виджета): `granted`→`scanning`; `denied`/`permanentlyDenied`→`permissionDenied`; `unavailable`→`fatal` |
| `Detected` | `String raw` | сырое значение QR (от контроллера/demo) → `NoxQrEnvelope.decode` |
| `SignalHandled` | — | страница консьюмила `decodedId`/`invalid` → сброс one-shot |

**Контракт поведения**:
- `Started` → `emit(status: initializing)`.
- `PermissionResolved(status)` → guard `if (state.decodedId != null) return;` (резолвит analyze A4 — поздний resume не перезапускает камеру у уходящей страницы), затем маппинг статуса.
- `Detected(raw)` → single-shot guard `if (state.decodedId != null) return;`; `NoxQrEnvelope.decode(raw)` non-null → `emit(decodedId: id)`; null → `emit(invalid: true)` (статус остаётся `scanning`, FR-011).
- `SignalHandled` → `emit(copyWith(decodedId: null, invalid: false))`.
- BLoC **чистый**: не вызывает `permission_handler`/`mobile_scanner`/`getIt`; всё внешнее приходит событиями. → DI-less `pumpApp`-тесты и demo/gallery работают (SC-008).

**Тесты-контракта** (`bloc_test`, без DI): bare-имена статусов; `PermissionResolved(granted)`→`scanning`, `(denied/permanentlyDenied)`→`permissionDenied`, `(unavailable)`→`fatal`; `Detected(валидный nox://id/…)`→`decodedId`; `Detected(чужой)`→`invalid`+`scanning`; `Detected` после `decodedId!=null` → игнор (single-shot).

---

## Виджет-оркестрация (где живёт камера/пермишен)

`_QrScanPageState` (контракт поведения, реализация — `navigation.md §3`):
- Владеет `MobileScannerController` (`autoStart:false`, `formats:[BarcodeFormat.qrCode]`, `detectionSpeed:noDuplicates`, `returnImage:false`).
- `@visibleForTesting WidgetBuilder? previewBuilder` — подмена живого `MobileScanner` плейсхолдером в goldens; `@visibleForTesting QrScanBloc? bloc` — инъекция пред-seed'нутого BLoC для widget-тестов состояний denied/invalid/fatal (резолвит analyze U5).
- `превью` = `previewBuilder?.call(context) ?? (demo ? ColoredBox-плейсхолдер : MobileScanner(controller, onDetect, errorBuilder))` — demo камеру НЕ трогает (SC-008).
- Оркестрация пермишена `_resolvePermission()` (non-demo):
  - **iOS/Android**: `status = await cameraPermissionService.request()` → `bloc.add(PermissionResolved(status))`.
  - **macOS**: `bloc.add(PermissionResolved(granted))` (оптимистично) → `MobileScanner.errorBuilder`/`controller.value.error.errorCode == permissionDenied` → `bloc.add(PermissionResolved(permanentlyDenied))`. Пермишен на macOS ведёт контроллер.
- Lifecycle: `resumed` → `_resolvePermission()` (авто-resume, FR-006); `paused` → `controller.stop()`.
- Открытие настроек: `_openSettings()` → `cameraPermissionService.openSettings()`.

---

## `NoxQrEnvelope`

`lib/general/nox_qr_envelope.dart`

```dart
abstract final class NoxQrEnvelope {
  const NoxQrEnvelope._();
  static const String _scheme = 'nox';
  static const String _type = 'id';

  /// id -> 'nox://id/<Uri.encodeComponent(id)>'. Путь всегда один сегмент.
  /// Пустой id даёт несканируемый 'nox://id/' — callers (7.1) не должны звать encode('')
  /// (резолвит analyze U3: Show QR доступен только в authorized → identifier непуст).
  static String encode(String identifier) => '$_scheme://$_type/${Uri.encodeComponent(identifier)}';

  /// Конверт -> identifier, или null (чужой/пустой/малформед). Никогда не бросает.
  static String? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException {
      return null;
    }
    if (uri.scheme != _scheme || uri.host != _type) return null;
    if (uri.pathSegments.length != 1) return null;
    final id = uri.pathSegments.first; // Uri уже percent-декодирует РОВНО один раз
    return id.isEmpty ? null : id;
  }
}
```

**Контракт поведения**:
- `decode(encode(id)) == id` для любого **непустого** `id` (round-trip, FR-009, SC-005). Для `id == ''` инвариант не держится (`encode('')` = `nox://id/`, `decode` → `null`) — пустой id на стороне 7.1 не кодируется (резолвит analyze U3).
- Не валидация формата id (009 FR-011) — только распознавание конверта.
- **Запрет double-decode**: не звать `Uri.decodeComponent` на `pathSegments.first`.

**Тесты-контракта** (чистый unit, без harness/`@Tags`): round-trip на наборе charset (`/ : ? # space`, unicode, base64url); каждая строка edge-таблицы (`data-model.md §1`) → ожидаемый `null`/значение; явный кейс `encode('')`→`'nox://id/'`→`decode`→`null`.

---

## `QrScannerCapability`

`lib/general/qr_scanner_capability.dart`

```dart
abstract final class QrScannerCapability {
  const QrScannerCapability._();

  @visibleForTesting
  static bool? debugOverride;

  /// FR-017 single source of truth: камера-сканер только на iOS/Android/macOS.
  static bool get isAvailable => debugOverride ?? (PlatformUtils.isMobile || PlatformUtils.isMacOS);
}
```

**Контракт поведения**:
- Один предикат управляет видимостью `Scan QR` (2.1) И достижимостью 2.2 (FR-016/FR-017).
- `debugOverride` — единственный способ протестировать Windows/Linux-кейс (на golden-хосте `dart:io Platform` всегда macOS).

**Тесты-контракта**: `debugOverride=false` → кнопка `Scan QR` отсутствует на 2.1; `debugOverride=true` → присутствует. **Test hygiene** (резолвит analyze U6): общий `tearDown`-сброс `debugOverride = null` (в harness/`setUp`), а не точечно, чтобы статик не утекал между тестами.

---

## DI / алиасы

- `CameraPermissionServiceImpl` — `@LazySingleton(as: CameraPermissionService, env: [dev, prod, test])`; регистрация в сгенерированном `configure_dependencies.config.dart` (`make generate`).
- Alias `cameraPermissionService` в `lib/di/global_aliases.dart` (резолвится виджетом, не BLoC).
- Alias `sessionRepository` в `lib/di/global_aliases.dart` (для 7.1 — реальный `Your ID`, см. `navigation.md`).
- `QrScanBloc`, `NoxQrEnvelope`, `QrScannerCapability` — **без DI** (page-BLoC / static-util).
- `MobileScannerController` — **widget-owned** (создаётся в `initState` страницы), не в DI и не в `RegisterModule`.

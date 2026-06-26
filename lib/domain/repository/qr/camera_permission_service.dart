import 'package:nox_app/domain/model/qr/camera_permission_status.dart';

/// Thin camera-permission abstraction consumed by the scanner WIDGET (not the
/// BLoC — the widget owns the `MobileScannerController`). No-throw: a
/// platform-channel failure maps to [CameraPermissionStatus.unavailable]. Returns
/// a bare status (not a `RepositoryResult`) — this is not a data repository.
///
/// Two backends behind one interface: `permission_handler` on iOS/Android;
/// macOS permission is driven by the controller, so [status]/[request] are called
/// by the widget only on iOS/Android (macOS returns `granted` benignly).
/// [openSettings] works on all scanner platforms.
abstract class CameraPermissionService {
  /// Current status without raising the OS prompt. Called by the widget on
  /// iOS/Android only.
  Future<CameraPermissionStatus> status();

  /// Request access (raises the OS prompt if notDetermined). iOS/Android only.
  Future<CameraPermissionStatus> request();

  /// Open the app's system settings (deep-link): permission_handler on
  /// iOS/Android, url_launcher on macOS.
  Future<void> openSettings();
}

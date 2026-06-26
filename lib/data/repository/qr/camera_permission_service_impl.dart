import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/domain/repository/qr/camera_permission_service.dart';
import 'package:nox_app/general/platform_utils.dart';

/// Two-backend camera permission. iOS/Android: `permission_handler`
/// (`Permission.camera`). macOS: `permission_handler` is unsupported (it would
/// throw `MissingPluginException`), so [status]/[request] return `granted` — the
/// widget drives the macOS prompt through the `MobileScannerController` and reads
/// the controller's `permissionDenied` error. [openSettings] uses `url_launcher`
/// on macOS. No-throw: any platform-channel failure maps to `unavailable` and is
/// logged via `LogRepository`.
@LazySingleton(as: CameraPermissionService, env: [Environment.dev, Environment.prod, Environment.test])
class CameraPermissionServiceImpl implements CameraPermissionService {
  static const String _macSettingsUrl = 'x-apple.systempreferences:com.apple.preference.security?Privacy_Camera';

  @override
  Future<CameraPermissionStatus> status() => _guard(() async {
    if (!PlatformUtils.isMobile) return CameraPermissionStatus.granted; // macOS: controller-driven
    return _map(await Permission.camera.status);
  });

  @override
  Future<CameraPermissionStatus> request() => _guard(() async {
    if (!PlatformUtils.isMobile) return CameraPermissionStatus.granted; // macOS: controller-driven
    return _map(await Permission.camera.request());
  });

  @override
  Future<void> openSettings() async {
    try {
      if (PlatformUtils.isMacOS) {
        await launchUrl(Uri.parse(_macSettingsUrl));
      } else {
        await openAppSettings();
      }
    } catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
    }
  }

  Future<CameraPermissionStatus> _guard(Future<CameraPermissionStatus> Function() run) async {
    try {
      return await run();
    } catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
      return CameraPermissionStatus.unavailable;
    }
  }

  CameraPermissionStatus _map(PermissionStatus status) {
    if (status.isGranted || status.isProvisional) return CameraPermissionStatus.granted;
    if (status.isPermanentlyDenied || status.isRestricted || status.isLimited) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }
}

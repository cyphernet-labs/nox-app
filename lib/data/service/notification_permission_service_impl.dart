import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/service/notification_permission_service.dart';
import 'package:nox_app/general/platform_utils.dart';

/// Real OS notification-permission (feature P5). iOS/Android: `permission_handler`
/// (`Permission.notification`). Desktop has no runtime notification-permission model, so
/// [status] returns `granted`; [openSettings] deep-links via `url_launcher` on macOS and
/// is a no-op on Windows/Linux. No-throw: any platform-channel failure maps to `granted`
/// (the banner is a soft nudge, not a gate) and is logged via `LogRepository`.
@LazySingleton(as: NotificationPermissionService, env: [Environment.dev, Environment.prod, Environment.test])
class NotificationPermissionServiceImpl implements NotificationPermissionService {
  static const String _macSettingsUrl = 'x-apple.systempreferences:com.apple.preference.notifications';

  @override
  Future<NotificationPermissionStatus> status() async {
    try {
      if (!PlatformUtils.isMobile) return NotificationPermissionStatus.granted; // desktop: no runtime model
      final status = await Permission.notification.status;
      return (status.isGranted || status.isProvisional) ? NotificationPermissionStatus.granted : NotificationPermissionStatus.denied;
    } catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
      return NotificationPermissionStatus.granted; // benign: don't nag on an indeterminate query
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      if (PlatformUtils.isMacOS) {
        await launchUrl(Uri.parse(_macSettingsUrl));
      } else if (PlatformUtils.isMobile) {
        await openAppSettings();
      }
      // Windows/Linux: no per-app notification settings deep-link → no-op.
    } catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
    }
  }
}

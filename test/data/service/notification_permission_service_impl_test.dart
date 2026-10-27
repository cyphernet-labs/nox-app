import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/notification_permission_service_impl.dart';
import 'package:nox_app/domain/service/notification_permission_service.dart';

// Host is macOS/desktop (Platform.isMobile == false), so status() hits the desktop
// short-circuit and returns granted WITHOUT touching permission_handler. The mobile-only
// path (Permission.notification.status + the isGranted mapping), the no-throw catch, and
// openSettings (launchUrl/openAppSettings + the LogRepository fallback) need
// method-channel/DI mocks and are NOT host-testable — openSettings is instead covered by
// the widget test against the mock service. Scope here stays on the desktop short-circuit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationPermissionServiceImpl service;

  setUp(() => service = NotificationPermissionServiceImpl());

  test('status returns granted on the desktop host without touching permission_handler', () async {
    expect(await service.status(), NotificationPermissionStatus.granted);
  });
}

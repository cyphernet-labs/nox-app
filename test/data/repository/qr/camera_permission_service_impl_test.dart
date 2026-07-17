import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/qr/camera_permission_service_impl.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';

// Host is macOS (Platform.isMobile == false), so status()/request() hit the
// desktop short-circuit and return granted WITHOUT touching permission_handler.
// The mobile-only paths — _map() over a real PermissionStatus, the _guard ->
// unavailable catch, and the openSettings macOS launchUrl branch — need a
// permission_handler/url_launcher method-channel mock and are NOT host-testable;
// do NOT try to force them via Permission.camera here. Scope stays on the
// desktop short-circuit only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPermissionServiceImpl service;

  setUp(() {
    service = CameraPermissionServiceImpl();
  });

  test('status returns granted on the desktop host without touching permission_handler', () async {
    expect(await service.status(), CameraPermissionStatus.granted);
  });

  test('request returns granted on the desktop host without touching permission_handler', () async {
    expect(await service.request(), CameraPermissionStatus.granted);
  });
}

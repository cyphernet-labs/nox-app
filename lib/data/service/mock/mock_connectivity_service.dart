import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';

/// Test-env [ConnectivityService] — always online (no platform channel in unit tests,
/// so the real plugin can't be reached). Feature F3 tests that need the offline path
/// override this binding with a fake that emits offline.
@LazySingleton(as: ConnectivityService, env: [Environment.test])
class MockConnectivityService implements ConnectivityService {
  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> watchOnline() => Stream<bool>.value(true);
}

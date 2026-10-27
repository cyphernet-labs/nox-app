import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';

/// Real [ConnectivityService] over `connectivity_plus` (dev/prod). Test uses
/// [MockConnectivityService] (always online) — the real plugin needs a platform channel.
@LazySingleton(as: ConnectivityService, env: [Environment.dev, Environment.prod])
class ConnectivityServiceImpl implements ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  bool _online(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> watchOnline() async* {
    yield await isOnline(); // seed the current value (onConnectivityChanged does not replay it)
    yield* _connectivity.onConnectivityChanged.map(_online).distinct();
  }
}

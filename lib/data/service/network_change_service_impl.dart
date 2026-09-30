import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/service/network_change_service.dart';

/// Network changes from `connectivity_plus` (dev and prod).
///
/// The first report after listening is the current state, not a change, on
/// some platforms; it is dropped. After that, any difference in the set of
/// active transports is one change.
@LazySingleton(as: NetworkChangeService, env: [Environment.dev, Environment.prod])
class NetworkChangeServiceImpl implements NetworkChangeService {
  final Connectivity _connectivity = Connectivity();

  @override
  Stream<void> watchChanges() async* {
    List<ConnectivityResult>? last = await _connectivity.checkConnectivity();
    await for (final results in _connectivity.onConnectivityChanged) {
      final sorted = [...results]..sort((a, b) => a.index.compareTo(b.index));
      if (last != null && const ListEquality<ConnectivityResult>().equals(last, sorted)) continue;
      last = sorted;
      yield null;
    }
  }
}

/// No changes - the test environment has no network to watch.
@LazySingleton(as: NetworkChangeService, env: [Environment.test])
class QuietNetworkChangeService implements NetworkChangeService {
  @override
  Stream<void> watchChanges() => const Stream<void>.empty();
}

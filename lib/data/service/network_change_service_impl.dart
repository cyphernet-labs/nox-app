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
    // Bounded: on some simulators the first answer never comes, and a stream
    // still waiting on it can be neither used nor cancelled. Unknown is fine -
    // the next report is then a change, which costs one extra check.
    var last = _sorted(await _connectivity.checkConnectivity().timeout(_firstAnswer, onTimeout: () => const <ConnectivityResult>[]));
    await for (final results in _connectivity.onConnectivityChanged) {
      final sorted = _sorted(results);
      if (const ListEquality<ConnectivityResult>().equals(last, sorted)) continue;
      last = sorted;
      yield null;
    }
  }

  static const Duration _firstAnswer = Duration(seconds: 3);

  /// Both sides of the comparison in one order: a platform that lists the
  /// same transports in another order has not changed network.
  static List<ConnectivityResult> _sorted(List<ConnectivityResult> results) => [...results]..sort((a, b) => a.index.compareTo(b.index));
}

/// No changes - the test environment has no network to watch.
@LazySingleton(as: NetworkChangeService, env: [Environment.test])
class QuietNetworkChangeService implements NetworkChangeService {
  @override
  Stream<void> watchChanges() => const Stream<void>.empty();
}

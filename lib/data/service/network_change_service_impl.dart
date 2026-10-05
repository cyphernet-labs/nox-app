import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/service/network_change_service.dart';

/// Network changes from `connectivity_plus` (dev and prod).
///
/// The first report after listening is the current state, not a change, on
/// some platforms; it is dropped. After that, any difference in the set of
/// active transports is one change.
@LazySingleton(as: NetworkChangeService, env: [Environment.dev, Environment.prod])
class NetworkChangeServiceImpl implements NetworkChangeService {
  NetworkChangeServiceImpl() : _connectivity = Connectivity();

  @visibleForTesting
  NetworkChangeServiceImpl.forTest(this._connectivity);

  final Connectivity _connectivity;

  /// Built from stream operators rather than an `async*` generator: a
  /// generator suspended on an await cannot finish a cancel until that await
  /// completes, and the platform's next report may never come.
  @override
  Stream<void> watchChanges() {
    return Stream<List<ConnectivityResult>>.fromFuture(_firstAnswerOrUnknown()).asyncExpand((first) {
      var last = _sorted(first);
      // A platform error is one report lost, not the end of the watch: let
      // through, it would end the stream, and the path would stop hearing
      // about networks for the rest of the session.
      return _connectivity.onConnectivityChanged
          .handleError((Object _) {})
          .map(_sorted)
          .where((sorted) {
            if (const ListEquality<ConnectivityResult>().equals(last, sorted)) return false;
            last = sorted;
            return true;
          })
          .map<void>((_) {});
    });
  }

  /// Bounded, and never fatal: on some simulators the first answer never
  /// comes. Unknown is fine - the next report is then a change, which costs
  /// one extra check.
  Future<List<ConnectivityResult>> _firstAnswerOrUnknown() async {
    try {
      return await _connectivity.checkConnectivity().timeout(_firstAnswer);
    } on Object {
      return const <ConnectivityResult>[];
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

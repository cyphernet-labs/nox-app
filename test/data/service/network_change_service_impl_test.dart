import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/network_change_service_impl.dart';

/// The platform's network reports, scripted.
class _Connectivity implements Connectivity {
  _Connectivity({required this.first});

  final Future<List<ConnectivityResult>> Function() first;
  final StreamController<List<ConnectivityResult>> reports = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() => first();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => reports.stream;
}

/// Network changes feed the path selector's return to the direct path (phase
/// 040, FR-003); a watch that ends on one platform error stops it for the
/// rest of the session.
void main() {
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('a first check that fails does not end the watch', () async {
    final platform = _Connectivity(first: () async => throw PlatformException(code: 'unavailable'));
    var changes = 0;
    final sub = NetworkChangeServiceImpl.forTest(platform).watchChanges().listen((_) => changes++);
    await settle();

    platform.reports.add(const [ConnectivityResult.wifi]);
    await settle();

    expect(changes, 1, reason: 'unknown before, so the first report is a change');
    await sub.cancel();
  });

  test('a platform error between reports is skipped, and the watch goes on', () async {
    final platform = _Connectivity(first: () async => const [ConnectivityResult.wifi]);
    var changes = 0;
    Object? surfaced;
    final sub = NetworkChangeServiceImpl.forTest(platform).watchChanges().listen((_) => changes++, onError: (Object e) => surfaced = e);
    await settle();

    platform.reports.addError(PlatformException(code: 'unavailable'));
    platform.reports.add(const [ConnectivityResult.mobile]);
    await settle();

    expect(surfaced, isNull);
    expect(changes, 1);
    await sub.cancel();
  });

  test('a cancel finishes while the platform has nothing to say', () async {
    // The path selector ends its session by cancelling this watch; a cancel
    // that waited for the next report wedged the channel restart.
    final platform = _Connectivity(first: () => Completer<List<ConnectivityResult>>().future);
    final sub = NetworkChangeServiceImpl.forTest(platform).watchChanges().listen((_) {});
    await settle();

    await sub.cancel().timeout(const Duration(seconds: 1));
  });

  test('the same transports in another order are not a change', () async {
    final platform = _Connectivity(first: () async => const [ConnectivityResult.wifi, ConnectivityResult.vpn]);
    var changes = 0;
    final sub = NetworkChangeServiceImpl.forTest(platform).watchChanges().listen((_) => changes++);
    await settle();

    platform.reports.add(const [ConnectivityResult.vpn, ConnectivityResult.wifi]);
    await settle();

    expect(changes, 0);
    await sub.cancel();
  });
}

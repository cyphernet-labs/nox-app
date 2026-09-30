import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:rxdart/rxdart.dart';

/// The test environment's Tor: unsupported unless a test says otherwise, so
/// the app's own tests behave exactly as before phase 040 - direct only - and
/// never load the native library. Tests that exercise the Tor path construct
/// one and script it.
@LazySingleton(as: TorService, env: [Environment.test])
class FakeTorService implements TorService {
  FakeTorService();

  bool supported = false;

  /// What start() moves to; tests set it before the path selector runs.
  TorStatus afterStart = const TorStatus(state: TorState.ready, bootstrapPercent: 100);

  final BehaviorSubject<TorStatus> _status = BehaviorSubject<TorStatus>.seeded(TorStatus.stopped);

  int starts = 0;
  int stops = 0;
  int wipes = 0;
  final List<bool> dormancy = <bool>[];
  ({String host, int port, Uint8List key})? target;

  @override
  bool get isSupported => supported;

  @override
  TorStatus get status => _status.value;

  @override
  Stream<TorStatus> watchStatus() => _status.stream.distinct();

  void emit(TorStatus status) => _status.add(status);

  @override
  TorBridgeEndpoint? get bridge =>
      target == null ? null : TorBridgeEndpoint(port: 9150, secret: Uint8List.fromList(List<int>.filled(32, 7)));

  @override
  Future<void> start() async {
    if (!supported) return;
    starts++;
    emit(afterStart);
  }

  @override
  Future<void> stop() async {
    stops++;
    target = null;
    emit(TorStatus.stopped);
  }

  @override
  Future<void> wipe() async {
    wipes++;
    await stop();
  }

  @override
  void setTarget({required String onionHost, required int port, required Uint8List clientKey}) {
    target = (host: onionHost, port: port, key: clientKey);
  }

  @override
  void clearTarget() => target = null;

  @override
  void setDormant(bool dormant) => dormancy.add(dormant);

  @override
  String? onionFromPublicKey(Uint8List publicKey) => supported ? '${'a' * 56}.onion' : null;
}

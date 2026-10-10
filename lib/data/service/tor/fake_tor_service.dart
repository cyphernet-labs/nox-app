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

  /// Holds start() until completed - how a test lands something in the middle
  /// of a bring-up.
  Completer<void>? startGate;

  final BehaviorSubject<TorStatus> _status = BehaviorSubject<TorStatus>.seeded(TorStatus.stopped);

  int starts = 0;
  int stops = 0;
  int wipes = 0;
  int targetSets = 0;
  int targetClears = 0;
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
  Future<void> start() async {
    if (!supported) return;
    starts++;
    await startGate?.future;
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

  /// What setTarget answers; a test sets false to have the client refuse.
  bool takesTargets = true;

  @override
  bool setTarget({required String onionHost, required int port, required Uint8List clientKey}) {
    targetSets++;
    if (!takesTargets) return false;
    target = (host: onionHost, port: port, key: clientKey);
    return true;
  }

  @override
  void clearTarget() {
    targetClears++;
    target = null;
  }

  @override
  void setDormant(bool dormant) => dormancy.add(dormant);

  @override
  String? onionFromPublicKey(Uint8List publicKey) => supported ? '${'a' * 56}.onion' : null;
}

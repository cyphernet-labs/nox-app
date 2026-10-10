import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/service/tor/nox_tor_api.dart';
import 'package:nox_app/data/service/tor/tor_capability.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_tor/nox_tor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Tor client built into the app, over `package:nox_tor` (dev and prod).
///
/// The native side never blocks and never calls back; this service polls its
/// status snapshot - often while Tor comes up, rarely once it is there - and
/// publishes the changes. The snapshot's error is also where the channel's
/// onion connects report a refused access key (phase 044), as the bridge
/// reported it before.
@LazySingleton(as: TorService, env: [Environment.dev, Environment.prod])
class NativeTorService implements TorService {
  NativeTorService(this._prefs)
    : _api = const NoxTorApi(),
      _directoriesOf = _platformDirectories,
      _supported = null,
      _wipeRetryPause = const Duration(milliseconds: 200);

  @visibleForTesting
  NativeTorService.forTest(
    this._prefs, {
    required this._api,
    required Future<(String, String)> Function() directories,
    bool this._supported = true,
    this._wipeRetryPause = Duration.zero,
  }) : _directoriesOf = directories;

  final SharedPreferences _prefs;
  final NoxTorApi _api;
  final Future<(String, String)> Function() _directoriesOf;
  final bool? _supported;
  final Duration _wipeRetryPause;

  /// The Tor client the network refused (FR-026), by the version the library
  /// reports. It is not started again: Arti would read the same consensus and
  /// try to exit. Being refused is a property of the CLIENT, so an update that
  /// ships a newer one clears it, and one that ships the same one does not -
  /// the network would refuse it again. Keyed on the app's build number it
  /// could never clear: that number does not move with every release.
  static const String kObsoleteClient = 'tor.obsolete_client';

  static const Duration _fastPoll = Duration(milliseconds: 250);
  static const Duration _slowPoll = Duration(seconds: 2);

  /// How many times a directory that will not delete is tried again.
  static const int _wipeAttempts = 5;

  final BehaviorSubject<TorStatus> _status = BehaviorSubject<TorStatus>.seeded(TorStatus.stopped);
  Timer? _poll;
  Duration? _pollEvery;

  /// Counts stops, so a start still awaiting its preparations sees that the
  /// session it was for has ended meanwhile.
  int _stops = 0;

  @override
  bool get isSupported => _supported ?? TorCapability.isAvailable;

  @override
  TorStatus get status => _status.value;

  @override
  Stream<TorStatus> watchStatus() {
    unawaited(_announceObsolete());
    return _status.stream.distinct();
  }

  bool _obsoleteChecked = false;

  /// A build the Tor network refused says so from the first look, not only
  /// once something tries to start Tor: the request to update is shown on the
  /// direct path too (FR-026).
  Future<void> _announceObsolete() async {
    if (_obsoleteChecked || !isSupported) return;
    _obsoleteChecked = true;
    if (_obsoleteClient()) _publish(const TorStatus(state: TorState.obsolete, error: TorError.softwareDeprecated));
  }

  @override
  Future<void> start() async {
    if (!isSupported) return;
    final stops = _stops;
    if (_obsoleteClient()) {
      _publish(const TorStatus(state: TorState.obsolete, error: TorError.softwareDeprecated));
      return;
    }
    final (stateDir, cacheDir) = await _directories();
    // Stopped - or wiped by a logout - while the directories were looked up:
    // starting now would bring Tor up for nobody and write back the very
    // directories the wipe just removed.
    if (stops != _stops) return;
    try {
      _api.start(stateDir: stateDir, cacheDir: cacheDir);
    } on NoxTorException catch (e) {
      logRepository.debug(target: this, message: 'tor: start refused (${e.code})');
    }
    _tick();
  }

  @override
  Future<void> stop() async {
    _stops++;
    _poll?.cancel();
    _poll = null;
    _pollEvery = null;
    if (!isSupported) return;
    _api.stop();
    _tick(schedule: false);
  }

  @override
  Future<void> wipe() async {
    await stop();
    if (!isSupported) return;
    final (stateDir, cacheDir) = await _directories();
    for (final path in [stateDir, cacheDir]) {
      await _delete(Directory(path));
    }
  }

  /// Tried again for a moment before giving up. `stop` returns before the
  /// client's tasks have let go of their files - its lock files and its
  /// directory database - and Windows will not delete a file that is open.
  Future<void> _delete(Directory dir) async {
    for (var attempt = 1; ; attempt++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } on FileSystemException catch (e) {
        if (attempt >= _wipeAttempts) {
          logRepository.error(target: this, error: 'tor: a directory would not delete (${e.osError?.errorCode})');
          return;
        }
        await Future<void>.delayed(_wipeRetryPause);
      }
    }
  }

  @override
  bool setTarget({required String onionHost, required int port, required Uint8List clientKey}) {
    if (!isSupported) return false;
    var taken = true;
    try {
      _api.setTarget(onionHost: onionHost, port: port, clientKey: clientKey);
    } on NoxTorException catch (e) {
      taken = false;
      logRepository.debug(target: this, message: 'tor: target refused (${e.code})');
    }
    _tick();
    return taken;
  }

  @override
  void clearTarget() {
    if (!isSupported) return;
    try {
      _api.clearTarget();
    } on NoxTorException {
      // Not started: there is no target to clear.
    }
    _tick();
  }

  @override
  void setDormant(bool dormant) {
    if (!isSupported) return;
    _api.setDormant(dormant);
    _tick();
  }

  /// Not gated on [isSupported]: the address is the module's arithmetic, and
  /// the module is there on every platform (phase 044) - including the one
  /// where Tor itself is not offered yet. Where the library is absent the
  /// lookup fails, and the answer is null.
  @override
  String? onionFromPublicKey(Uint8List publicKey) {
    try {
      return _api.onionFromPublicKey(publicKey);
    } on Object {
      return null;
    }
  }

  void _tick({bool schedule = true}) {
    final snapshot = _api.status();
    final next = TorStatus(
      state: TorState.values[snapshot.state.index],
      bootstrapPercent: snapshot.bootstrapPercent,
      error: TorError.values[snapshot.error.index],
    );
    _publish(next);
    if (next.isObsolete) unawaited(_recordObsolete());
    if (!schedule) return;
    final idle = next.state == TorState.stopped || next.isObsolete;
    if (idle) {
      _poll?.cancel();
      _poll = null;
      _pollEvery = null;
      return;
    }
    final every = next.state == TorState.bootstrapping ? _fastPoll : _slowPoll;
    if (_pollEvery != every) {
      _poll?.cancel();
      _pollEvery = every;
      _poll = Timer.periodic(every, (_) => _tick());
    }
  }

  void _publish(TorStatus next) {
    // Final for the build: a later `stopped` from a library that was never
    // started must not take the request to update off the screen.
    if (_status.value.isObsolete) return;
    if (_status.value != next) _status.add(next);
  }

  Future<(String, String)> _directories() => _directoriesOf();

  static Future<(String, String)> _platformDirectories() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    return ('${support.path}${Platform.pathSeparator}nox_tor_state', '${cache.path}${Platform.pathSeparator}nox_tor_cache');
  }

  bool _obsoleteClient() => _prefs.getString(kObsoleteClient) == _api.version();

  Future<void> _recordObsolete() async {
    final client = _api.version();
    if (_prefs.getString(kObsoleteClient) == client) return;
    await _prefs.setString(kObsoleteClient, client);
    logRepository.debug(target: this, message: 'tor: the network no longer accepts this client');
  }
}

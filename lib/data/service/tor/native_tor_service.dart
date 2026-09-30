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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Tor client built into the app, over `package:nox_tor` (dev and prod).
///
/// The native side never blocks and never calls back; this service polls its
/// status snapshot - often while Tor comes up, rarely once it is there - and
/// publishes the changes.
@LazySingleton(as: TorService, env: [Environment.dev, Environment.prod])
class NativeTorService implements TorService {
  NativeTorService(this._prefs)
    : _api = const NoxTorApi(),
      _directoriesOf = _platformDirectories,
      _buildOf = _platformBuild,
      _supported = null;

  @visibleForTesting
  NativeTorService.forTest(
    this._prefs, {
    required this._api,
    required Future<(String, String)> Function() directories,
    required Future<String> Function() build,
    bool this._supported = true,
  }) : _directoriesOf = directories,
       _buildOf = build;

  final SharedPreferences _prefs;
  final NoxTorApi _api;
  final Future<(String, String)> Function() _directoriesOf;
  final Future<String> Function() _buildOf;
  final bool? _supported;

  /// The build in which the Tor network refused this client (FR-026). Tor is
  /// not started again in that build: Arti would read the same consensus and
  /// try to exit. A new build clears it by having a different number.
  static const String kObsoleteBuild = 'tor.obsolete_build';

  static const Duration _fastPoll = Duration(milliseconds: 250);
  static const Duration _slowPoll = Duration(seconds: 2);

  final BehaviorSubject<TorStatus> _status = BehaviorSubject<TorStatus>.seeded(TorStatus.stopped);
  Timer? _poll;
  Duration? _pollEvery;
  TorBridgeEndpoint? _bridge;
  String? _buildNumber;

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
    if (await _obsoleteInThisBuild()) _publish(const TorStatus(state: TorState.obsolete, error: TorError.softwareDeprecated));
  }

  @override
  TorBridgeEndpoint? get bridge => _bridge;

  @override
  Future<void> start() async {
    if (!isSupported) return;
    if (await _obsoleteInThisBuild()) {
      _publish(const TorStatus(state: TorState.obsolete, error: TorError.softwareDeprecated));
      return;
    }
    final (stateDir, cacheDir) = await _directories();
    try {
      _api.start(stateDir: stateDir, cacheDir: cacheDir);
    } on NoxTorException catch (e) {
      logRepository.debug(target: this, message: 'tor: start refused (${e.code})');
    }
    _tick();
  }

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    _pollEvery = null;
    _bridge = null;
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
      final dir = Directory(path);
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } on FileSystemException catch (e) {
        logRepository.debug(target: this, message: 'tor: a directory would not delete (${e.osError?.errorCode})');
      }
    }
  }

  @override
  void setTarget({required String onionHost, required int port, required Uint8List clientKey}) {
    if (!isSupported) return;
    try {
      _api.setTarget(onionHost: onionHost, port: port, clientKey: clientKey);
      // The secret rotates with every target; read it now, not per connection.
      final snapshot = _api.status();
      _bridge = snapshot.port == null ? null : TorBridgeEndpoint(port: snapshot.port!, secret: _api.bridgeSecret());
    } on NoxTorException catch (e) {
      _bridge = null;
      logRepository.debug(target: this, message: 'tor: target refused (${e.code})');
    }
    _tick();
  }

  @override
  void clearTarget() {
    _bridge = null;
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

  @override
  String? onionFromPublicKey(Uint8List publicKey) {
    if (!isSupported) return null;
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
      port: snapshot.port,
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

  static Future<String> _platformBuild() async => (await PackageInfo.fromPlatform()).buildNumber;

  Future<String> _build() async => _buildNumber ??= await _buildOf();

  Future<bool> _obsoleteInThisBuild() async => _prefs.getString(kObsoleteBuild) == await _build();

  Future<void> _recordObsolete() async {
    final build = await _build();
    if (_prefs.getString(kObsoleteBuild) == build) return;
    await _prefs.setString(kObsoleteBuild, build);
    logRepository.debug(target: this, message: 'tor: the network no longer accepts this client');
  }
}

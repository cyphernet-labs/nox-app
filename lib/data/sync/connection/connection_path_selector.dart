import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_target_provider.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:rxdart/rxdart.dart';

/// What the path selector is doing, for the connection status (phase 040).
@immutable
class PathSelection {
  const PathSelection({this.active = false, this.path, this.roundFailed = false});

  static const PathSelection idle = PathSelection();

  /// A session is running: the selector was started and not stopped since.
  final bool active;

  /// The path being brought up or in use; null while the direct addresses are
  /// being tried and nothing is chosen yet.
  final ConnectionPath? path;

  /// The last whole round found no way to the server. Held through the retries
  /// that follow until a connection is greeted, so «No connection» does not
  /// blink on every rung of the ladder (research decision 12).
  final bool roundFailed;

  PathSelection copyWith({bool? active, ConnectionPath? path, bool clearPath = false, bool? roundFailed}) => PathSelection(
    active: active ?? this.active,
    path: clearPath ? null : (path ?? this.path),
    roundFailed: roundFailed ?? this.roundFailed,
  );

  @override
  bool operator ==(Object other) =>
      other is PathSelection && other.active == active && other.path == path && other.roundFailed == roundFailed;

  @override
  int get hashCode => Object.hash(active, path, roundFailed);

  @override
  String toString() => 'PathSelection(active: $active, path: ${path?.name}, roundFailed: $roundFailed)';
}

/// Chooses how the socket reaches this person's server, before every attempt
/// (phase 040, research decision 8).
///
/// Direct first - the address that answered last, the server's list, the
/// link's address - each checked by TLS, the leaf's key and `/health` within
/// five seconds (FR-001, FR-002). Only when none answers, and only where Tor
/// can work at all, the Tor client built into the app is brought up towards
/// the server's onion address (FR-007). While on Tor the direct path is looked
/// at again on every network change and every two minutes, and the socket
/// moves back to it the moment it answers; Tor then stops (FR-003, FR-006).
///
/// Lossless by the protocol rather than by holding two sockets: the new path
/// is verified before the old connection is closed, the replay resumes from the
/// cursor, a duplicate falls to its `seq`, and a resent command is idempotent
/// under its own key (FR-004).
@LazySingleton(env: [Environment.dev])
class ConnectionPathSelector implements SocketTargetProvider {
  ConnectionPathSelector(this._prober, this._tor, this._addresses, this._keys, this._network, this._lifecycle, this._socket)
    : _forceTor = resolveForceTor(debug: kDebugMode, requested: const bool.fromEnvironment('nox.forceTor')),
      _mobile = PlatformUtils.isMobile,
      _recheckEvery = const Duration(minutes: 2),
      _torReadyBudget = const Duration(seconds: 90),
      _resumeReadyBudget = const Duration(seconds: 10);

  @visibleForTesting
  ConnectionPathSelector.forTest(
    this._prober,
    this._tor,
    this._addresses,
    this._keys,
    this._network,
    this._lifecycle,
    this._socket, {
    this._forceTor = false,
    this._mobile = true,
    this._recheckEvery = const Duration(minutes: 2),
    this._torReadyBudget = const Duration(seconds: 90),
    this._resumeReadyBudget = const Duration(seconds: 10),
  });

  final DirectProber _prober;
  final TorService _tor;
  final ServerAddressesRepository _addresses;
  final AccessKeyRepository _keys;
  final NetworkChangeService _network;
  final AppLifecycleService _lifecycle;
  final NoxSocketClient _socket;

  /// Skips the direct addresses - how the Tor path is tried at home. A debug
  /// build's switch only (`--dart-define=nox.forceTor=true`): a release build
  /// that could be told to ignore its own network would be a support trap.
  final bool _forceTor;
  final bool _mobile;
  final Duration _recheckEvery;
  final Duration _torReadyBudget;
  final Duration _resumeReadyBudget;

  /// The debug switch, decided once: only a debug build may honour it.
  static bool resolveForceTor({required bool debug, required bool requested}) => debug && requested;

  final BehaviorSubject<PathSelection> _selection = BehaviorSubject<PathSelection>.seeded(PathSelection.idle);

  String? _linkAddress;
  String? _fingerprint;
  bool _active = false;

  StreamSubscription<void>? _networkSub;
  StreamSubscription<AppVisibility>? _visibilitySub;
  StreamSubscription<ServerAddresses>? _addressesSub;
  StreamSubscription<TorStatus>? _torSub;
  Timer? _recheck;

  /// Counts rounds; a stop, or a newer round, makes an older one stale.
  int _round = 0;

  /// What the current round handed the socket, and how it went.
  Uri? _handedOut;
  String? _handedOutAddress;
  ConnectionPath? _handedOutPath;
  bool _handedOutGreeted = false;
  bool _handedOutWasSwitch = false;

  /// A direct address a background check verified a moment ago. The next
  /// round hands it over without asking again: that is the switch.
  String? _verified;

  bool _bringingUpTor = false;
  bool _probing = false;
  _TorTarget? _torTarget;
  TorError _lastTorError = TorError.none;

  PathSelection get selection => _selection.value;

  /// The current selection on listen, then every change.
  Stream<PathSelection> watchSelection() => _selection.stream.distinct();

  /// The path of the connection that was greeted; null while none is.
  ConnectionPath? get currentPath => _handedOutGreeted ? _handedOutPath : null;

  @override
  bool get bringingUpSlowPath => _bringingUpTor;

  /// Starts serving a session: [linkAddress] is the address the pairing link
  /// carried, [fingerprint] the key every path is checked against.
  void begin({required String linkAddress, required String fingerprint}) {
    _linkAddress = linkAddress;
    _fingerprint = fingerprint;
    if (_active) return;
    _active = true;
    _publish(_selection.value.copyWith(active: true, roundFailed: false, clearPath: true));
    _networkSub = _network.watchChanges().listen((_) => unawaited(_onNetworkChanged()));
    // Desktop does not sleep in the background (FR-025 is about phones).
    if (_mobile) _visibilitySub = _lifecycle.watchVisibility().listen(_onVisibility);
    // The first value is what is stored now; only a CHANGE is news.
    _addressesSub = _addresses.watch().skip(1).listen((_) => unawaited(_recheckDirect(reason: 'new addresses')));
    _torSub = _tor.watchStatus().listen(_onTorStatus);
  }

  /// Ends the session: no more rounds and no more checks. Tor stops too,
  /// unless [keepTor] - a restart of the channel, which the next round would
  /// only answer by bringing it up again.
  Future<void> end({bool keepTor = false}) async {
    _active = false;
    _round++;
    _recheck?.cancel();
    _recheck = null;
    await _networkSub?.cancel();
    await _visibilitySub?.cancel();
    await _addressesSub?.cancel();
    await _torSub?.cancel();
    _networkSub = null;
    _visibilitySub = null;
    _addressesSub = null;
    _torSub = null;
    _forgetHandedOut();
    _verified = null;
    _probing = false;
    _publish(PathSelection.idle);
    if (!keepTor) await _stopTor();
  }

  @override
  Future<Uri?> nextTarget() async {
    if (!_active) return null;
    final round = ++_round;
    // Asked again with the last target never greeted: that round failed. A
    // switch that did not take is not a failed round - the path it left is
    // tried again right now.
    if (_handedOut != null && !_handedOutGreeted && !_handedOutWasSwitch) _markFailed();
    _forgetHandedOut();
    final fingerprint = _fingerprint;
    if (fingerprint == null || fingerprint.isEmpty) return _noPath();

    final verified = _verified;
    _verified = null;
    if (verified != null) return _hand(verified, ConnectionPath.direct, switching: true);

    final addresses = await _readAddresses();
    if (!_current(round)) return null;
    if (!_forceTor) {
      _publish(_selection.value.copyWith(clearPath: true));
      final result = await _prober.probe(addresses.candidates(_linkAddress), fingerprint: fingerprint);
      if (!_current(round)) return null;
      if (result.notHome.isNotEmpty) {
        logRepository.debug(target: this, message: 'path: ${result.notHome.length} direct address(es) answered with another key');
      }
      final address = result.address;
      if (address != null) return _hand(address, ConnectionPath.direct);
    }
    final onion = await _bringUpTor(addresses, round);
    if (!_current(round)) return null;
    if (onion != null) {
      _handedOut = onion;
      _handedOutPath = ConnectionPath.tor;
      _publish(_selection.value.copyWith(path: ConnectionPath.tor));
      return onion;
    }
    return _noPath();
  }

  @override
  void reportGreeted(Uri url) {
    if (url != _handedOut) return;
    _handedOutGreeted = true;
    _publish(_selection.value.copyWith(path: _handedOutPath, roundFailed: false));
    if (_handedOutPath == ConnectionPath.direct) {
      final address = _handedOutAddress;
      if (address != null) unawaited(_addresses.recordLastGood(address));
      _recheck?.cancel();
      _recheck = null;
      // On the direct path Tor is stopped (FR-006). The connection through it
      // was closed by the switch, so nothing is lost by stopping now.
      unawaited(_stopTor());
      logRepository.debug(target: this, message: 'path: direct');
    } else {
      _recheck ??= Timer.periodic(_recheckEvery, (_) => unawaited(_recheckDirect(reason: 'periodic')));
      logRepository.debug(target: this, message: 'path: tor');
    }
  }

  @override
  void reportPinRefused(Uri url) {
    // Nothing to remember beyond the log: the next round probes again, and the
    // probe passes over an address that answers with another key.
    logRepository.debug(target: this, message: 'path: a direct address answered with another key at the dial');
  }

  bool _current(int round) => _active && round == _round;

  Uri _hand(String address, ConnectionPath path, {bool switching = false}) {
    final url = Uri.parse('wss://$address/ws');
    _handedOut = url;
    _handedOutAddress = address;
    _handedOutPath = path;
    _handedOutWasSwitch = switching;
    _publish(_selection.value.copyWith(path: path));
    return url;
  }

  void _forgetHandedOut() {
    _handedOut = null;
    _handedOutAddress = null;
    _handedOutPath = null;
    _handedOutGreeted = false;
    _handedOutWasSwitch = false;
  }

  Uri? _noPath() {
    _markFailed();
    return null;
  }

  void _markFailed() {
    if (!_active) return;
    _publish(_selection.value.copyWith(roundFailed: true, clearPath: true));
  }

  void _publish(PathSelection next) {
    if (_selection.value != next) _selection.add(next);
  }

  Future<ServerAddresses> _readAddresses() async => (await _addresses.read()).data ?? ServerAddresses.empty;

  /// Brings Tor up towards the server's onion address and returns the address
  /// to dial, or null when there is no way through Tor right now.
  Future<Uri?> _bringUpTor(ServerAddresses addresses, int round) async {
    // Linux, or a build without the library (FR-007, FR-031).
    if (!_tor.isSupported) return null;
    // The Tor network refused this build (FR-026): direct only until an update.
    if (_tor.status.isObsolete) return null;
    final target = await _torTargetFor(addresses);
    if (target == null || !_current(round)) return null;
    _bringingUpTor = true;
    _publish(_selection.value.copyWith(path: ConnectionPath.tor));
    try {
      await _tor.start();
      if (!_current(round) || _tor.status.isObsolete) return null;
      if (_torTarget != target) {
        _tor.setTarget(onionHost: target.host, port: target.port, clientKey: target.key);
        _torTarget = target;
      }
      if (!await _waitForTor(_torReadyBudget) || !_current(round)) return null;
      return Uri(scheme: 'wss', host: target.host, port: target.port == 443 ? null : target.port, path: '/ws');
    } finally {
      _bringingUpTor = false;
    }
  }

  /// The onion address and the key that opens it: this device's own key once
  /// the server has it (FR-016), else the one-time key a version-2 link lent
  /// for its pairing (FR-020).
  Future<_TorTarget?> _torTargetFor(ServerAddresses addresses) async {
    final host = addresses.onionHost;
    if (host != null && ((await _keys.isRegistered()).data ?? false)) {
      final own = (await _keys.deviceKey()).data;
      if (own != null) return _TorTarget(host: host, port: addresses.onionPort, key: own.privateKey, invite: false);
    }
    final invite = (await _keys.invite()).data;
    if (invite == null) return null;
    final lent = ServerAddresses(onion: invite.onion);
    final lentHost = lent.onionHost;
    if (lentHost == null) return null;
    return _TorTarget(host: lentHost, port: lent.onionPort, key: invite.oneTimeKey, invite: true);
  }

  /// Whether Tor is bootstrapped with the bridge open, within [budget].
  Future<bool> _waitForTor(Duration budget) async {
    bool ready(TorStatus status) => status.isReady && _tor.bridge != null;
    if (ready(_tor.status)) return true;
    try {
      await _tor.watchStatus().firstWhere((s) => ready(s) || s.isObsolete || !_active).timeout(budget);
    } on TimeoutException {
      return false;
    } on StateError {
      return false;
    }
    return ready(_tor.status);
  }

  Future<void> _stopTor() async {
    _torTarget = null;
    if (_tor.status.state == TorState.stopped || _tor.status.isObsolete) return;
    _tor.clearTarget();
    await _tor.stop();
  }

  void _onTorStatus(TorStatus status) {
    final error = status.error;
    final entered = error != _lastTorError;
    _lastTorError = error;
    final target = _torTarget;
    if (!entered || error != TorError.wrongClientAuth || target == null) return;
    // The onion service does not list the key we offered (T039). Our own key:
    // mark it unregistered - Tor is not tried again until the next direct
    // greeting has registered it. A lent key: the invite is spent or gone, and
    // keeping it would only retry a door that will not open.
    if (target.invite) {
      logRepository.debug(target: this, message: 'path: the invite key no longer opens the server');
      unawaited(_keys.clearInvite());
    } else {
      logRepository.debug(target: this, message: 'path: the server does not know this device key, Tor waits for a direct greeting');
      unawaited(_keys.markRegistered(false));
    }
  }

  Future<void> _onNetworkChanged() async {
    if (!_active) return;
    final phase = _socket.currentPhase;
    if (phase.isTerminal) return;
    if (!_greeted(phase)) {
      // A new network is a reason to try now, not at the next rung.
      await _socket.reconnect();
      return;
    }
    switch (currentPath) {
      case ConnectionPath.tor:
        await _recheckDirect(reason: 'network change');
      case ConnectionPath.direct:
        await _checkCurrentDirect();
      case null:
        break;
    }
  }

  /// On the direct path: does the address still lead home on this network?
  Future<void> _checkCurrentDirect() async {
    final address = _handedOutAddress;
    final fingerprint = _fingerprint;
    if (address == null || fingerprint == null || _probing) return;
    _probing = true;
    try {
      final result = await _prober.probe([address], fingerprint: fingerprint);
      if (!_active || _handedOutAddress != address || result.address != null) return;
      logRepository.debug(target: this, message: 'path: the direct address stopped answering, choosing again');
      await _socket.reconnect();
    } finally {
      _probing = false;
    }
  }

  /// While on Tor: does a direct address answer again? Then move to it.
  Future<void> _recheckDirect({required String reason}) async {
    if (!_active || _probing || _forceTor || currentPath != ConnectionPath.tor) return;
    final fingerprint = _fingerprint;
    if (fingerprint == null) return;
    _probing = true;
    try {
      final addresses = await _readAddresses();
      final result = await _prober.probe(addresses.candidates(_linkAddress), fingerprint: fingerprint);
      final address = result.address;
      if (address == null || !_active || currentPath != ConnectionPath.tor) return;
      logRepository.debug(target: this, message: 'path: the direct path answers again ($reason), switching');
      _verified = address;
      await _socket.reconnect();
    } finally {
      _probing = false;
    }
  }

  void _onVisibility(AppVisibility visibility) {
    if (!_active) return;
    final usingTor = _torTarget != null;
    if (visibility == AppVisibility.background) {
      if (usingTor) _tor.setDormant(true);
      return;
    }
    if (usingTor) {
      _tor.setDormant(false);
      unawaited(_reviveTor());
    }
    // Back in front: the path is chosen again rather than waited for (FR-025).
    final phase = _socket.currentPhase;
    if (!phase.isTerminal && !_greeted(phase)) unawaited(_socket.reconnect());
  }

  /// A Tor client that is not ready soon after the return is started again
  /// from the same directories - a warm start, half a second (research
  /// decision 7).
  Future<void> _reviveTor() async {
    final target = _torTarget;
    if (target == null) return;
    if (await _waitForTor(_resumeReadyBudget)) return;
    if (!_active || _torTarget != target) return;
    logRepository.debug(target: this, message: 'path: Tor did not wake up, restarting it');
    await _tor.stop();
    await _tor.start();
    if (!_active || _tor.status.isObsolete) return;
    _tor.setTarget(onionHost: target.host, port: target.port, clientKey: target.key);
    _torTarget = target;
  }

  static bool _greeted(SessionPhase phase) => phase == SessionPhase.live || phase == SessionPhase.catchingUp;
}

/// Where the bridge points and with which key.
@immutable
class _TorTarget {
  const _TorTarget({required this.host, required this.port, required this.key, required this.invite});

  final String host;
  final int port;
  final Uint8List key;

  /// The key is a version-2 link's one-time key, not this device's own.
  final bool invite;

  @override
  bool operator ==(Object other) =>
      other is _TorTarget && other.host == host && other.port == port && other.invite == invite && listEquals(other.key, key);

  @override
  int get hashCode => Object.hash(host, port, invite, Object.hashAll(key));
}

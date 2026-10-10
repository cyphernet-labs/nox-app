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
/// Direct first - the address that answered last, the person's own, the
/// public one, the server's list, the link's address - each probed by opening
/// a channel to it, which proves the server's key or does not, within five
/// seconds (FR-001, FR-002; phase 044). Only when none answers, only when the
/// person turned `Use Tor` on, and only when an onion address is known, the
/// Tor client built into the app is brought up and the socket dials the
/// server's onion address (phase 045, FR-011, FR-012); the connection through
/// it is a channel of the same module, and no access key opens it. With `Use
/// Tor` off nothing is ever opened through Tor (SC-006). While on Tor the
/// direct path is looked at again on every network change and every two
/// minutes, and the socket moves back to it the moment it answers; Tor then
/// stops (FR-003, FR-006).
///
/// Lossless by the protocol rather than by holding two sockets: the new path
/// is verified before the old connection is closed, the replay resumes from the
/// cursor, a duplicate falls to its `seq`, and a resent command is idempotent
/// under its own key (FR-004).
@LazySingleton(env: [Environment.dev])
class ConnectionPathSelector implements SocketTargetProvider {
  ConnectionPathSelector(this._prober, this._tor, this._addresses, this._network, this._lifecycle, this._socket)
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
  final NetworkChangeService _network;
  final AppLifecycleService _lifecycle;
  final NoxSocketClient _socket;

  /// Skips the direct addresses - how the Tor path is tried at home. A debug
  /// build's switch only (`--dart-define=nox.forceTor=true`): a release build
  /// that could be told to ignore its own network would be a support trap.
  /// It does not override `Use Tor`: with it off there is simply no path.
  final bool _forceTor;
  final bool _mobile;
  final Duration _recheckEvery;
  final Duration _torReadyBudget;
  final Duration _resumeReadyBudget;

  /// The debug switch, decided once: only a debug build may honour it.
  static bool resolveForceTor({required bool debug, required bool requested}) => debug && requested;

  final BehaviorSubject<PathSelection> _selection = BehaviorSubject<PathSelection>.seeded(PathSelection.idle);

  String? _linkAddress;

  /// The two keys a probe opens its channels with: the server's, which the
  /// probe checks, and the device's, which the server checks. Copies, wiped
  /// when the session ends.
  Uint8List? _serverKey;
  Uint8List? _deviceSeed;
  bool _active = false;

  StreamSubscription<void>? _networkSub;
  StreamSubscription<AppVisibility>? _visibilitySub;
  StreamSubscription<ServerAddresses>? _addressesSub;
  StreamSubscription<TorStatus>? _torSub;
  Timer? _recheck;

  /// Counts rounds; a stop, or a newer round, makes an older one stale.
  int _round = 0;

  /// Ticks with every new round, so a stale one stops waiting on Tor at once
  /// instead of holding its wait for the whole budget.
  final StreamController<void> _roundChanged = StreamController<void>.broadcast();

  /// What the current round handed the socket, and how it went.
  Uri? _handedOut;
  String? _handedOutAddress;
  ConnectionPath? _handedOutPath;
  bool _handedOutGreeted = false;
  bool _handedOutWasSwitch = false;

  /// The attempt was cut short by a network change before it could answer -
  /// interrupted, not failed: its round never finished.
  bool _handedOutInterrupted = false;

  /// A direct address a background check verified a moment ago. The next
  /// round hands it over without asking again: that is the switch.
  String? _verified;

  /// The round that is bringing Tor up, if any. A round, not a flag: a
  /// stale round finishing its bring-up must not clear the mark of the round
  /// that replaced it, or a command sent meanwhile would fail on the short
  /// timeout.
  int? _torRound;
  bool _probing = false;

  /// The visibility last seen. Only a CHANGE is news: the lifecycle service
  /// replays the current value to a new listener, and treating that as a
  /// return from the background restarted the very attempt a sign-in was
  /// waiting on.
  AppVisibility _visibility = AppVisibility.foreground;

  /// The onion service Tor was brought up for; null while Tor is not in use.
  _TorTarget? _torTarget;

  /// The connection settings last seen on the watch, so a change can be told
  /// from the value that was there - `Use Tor` turned off above all.
  ServerAddresses? _seenAddresses;

  /// How long the Tor client this selector last started has been coming up
  /// (phase 042). A restart of the channel keeps a client still within its
  /// readiness budget - a second press of Try again must not throw its
  /// progress away - and stops one past it, which is not coming up but stuck.
  /// Null once it is ready or stopped.
  Stopwatch? _torBoot;

  PathSelection get selection => _selection.value;

  /// The current selection on listen, then every change.
  Stream<PathSelection> watchSelection() => _selection.stream.distinct();

  /// The path of the connection that was greeted; null while none is.
  ConnectionPath? get currentPath => _handedOutGreeted ? _handedOutPath : null;

  /// Only the CURRENT round's bring-up counts: a stale round still waiting on
  /// Tor says nothing about the path the socket is on now.
  @override
  bool get bringingUpSlowPath => _torRound != null && _torRound == _round;

  /// Starts serving a session: [linkAddress] is the address the pairing link
  /// carried, [serverKey] the key every path must prove and [deviceSeed] the
  /// key this device proves itself with. Both are copied.
  void begin({required String linkAddress, required Uint8List serverKey, required Uint8List deviceSeed}) {
    _linkAddress = linkAddress;
    _wipeKeys();
    _serverKey = Uint8List.fromList(serverKey);
    _deviceSeed = Uint8List.fromList(deviceSeed);
    if (_active) return;
    _active = true;
    _publish(_selection.value.copyWith(active: true, roundFailed: false, clearPath: true));
    _networkSub = _network.watchChanges().listen((_) => unawaited(_onNetworkChanged()));
    // Desktop does not sleep in the background (FR-025 is about phones).
    _visibility = _lifecycle.visibility;
    if (_mobile) _visibilitySub = _lifecycle.watchVisibility().listen(_onVisibility);
    // The first value is what is stored now; only a CHANGE is news - of where
    // the server can be found, or of `Use Tor` - not the path this device
    // last took.
    _seenAddresses = null;
    _addressesSub = _addresses.watch().listen(_onAddresses);
    _torSub = _tor.watchStatus().listen(_onTorStatus);
  }

  /// Ends the session: no more rounds and no more checks. Tor stops too,
  /// unless [keepTor] - a restart of the channel, which the next round would
  /// only answer by bringing it up again.
  Future<void> end({bool keepTor = false}) async {
    _active = false;
    _nextRound();
    _recheck?.cancel();
    _recheck = null;
    // Not awaited. A cancel can take as long as its source wants - an `async*`
    // source waits for its generator to reach the next yield - and a restart
    // of the channel waits on this method. Every handler checks `_active`
    // first, so nothing a late event could do reaches the next session.
    unawaited(_networkSub?.cancel());
    unawaited(_visibilitySub?.cancel());
    unawaited(_addressesSub?.cancel());
    unawaited(_torSub?.cancel());
    _networkSub = null;
    _visibilitySub = null;
    _addressesSub = null;
    _torSub = null;
    _forgetHandedOut();
    _verified = null;
    _probing = false;
    _torRound = null;
    _seenAddresses = null;
    // A restart is still a session coming up: shown as idle, the gap before
    // the next begin() would read as "no connection" and flash the banner on
    // every rename.
    _publish(keepTor ? const PathSelection(active: true) : PathSelection.idle);
    _wipeKeys();
    if (keepTor) {
      final worthKeeping = _torWorthKeeping();
      // Read, not remembered: the restart may be the one a change of `Use
      // Tor` asked for, and a client kept for a person who has just turned
      // Tor off would go on talking to the Tor network (SC-006).
      if (worthKeeping && (await _readAddresses()).useTor) return;
      // Failed, or coming up for longer than any start takes: kept, it would
      // hold every round after the restart on a client that will not answer -
      // what relaunching the app used to be the only cure for.
      if (!worthKeeping) logRepository.debug(target: this, message: 'path: restarting a Tor client that did not come up');
      await _stopTor();
      return;
    }
    await _stopTor();
  }

  /// The device seed is this device's private key; it does not outlive the
  /// session it was handed over for.
  void _wipeKeys() {
    final seed = _deviceSeed;
    if (seed != null) seed.fillRange(0, seed.length, 0);
    _deviceSeed = null;
    _serverKey = null;
  }

  /// Whether a restart of the channel may keep the Tor client (phase 042):
  /// ready, asleep in the background, or still within its readiness budget.
  bool _torWorthKeeping() {
    final status = _tor.status;
    if (status.isReady || status.state == TorState.dormant) return true;
    if (status.state != TorState.bootstrapping) return false;
    final boot = _torBoot;
    return boot == null || boot.elapsed < _torReadyBudget;
  }

  @override
  Future<Uri?> nextTarget() async {
    if (!_active) return null;
    final round = _nextRound();
    // Asked again with the last target never greeted: that round failed. A
    // switch that did not take is not a failed round - the path it left is
    // tried again right now - and neither is an attempt a network change cut
    // short.
    if (_handedOut != null && !_handedOutGreeted && !_handedOutWasSwitch && !_handedOutInterrupted) _markFailed();
    _forgetHandedOut();
    final serverKey = _serverKey;
    final deviceSeed = _deviceSeed;
    if (serverKey == null || deviceSeed == null) return _noPath();

    final verified = _verified;
    _verified = null;
    if (verified != null) return _hand(verified, ConnectionPath.direct, switching: true);

    final addresses = await _readAddresses();
    if (!_current(round)) return null;
    // Away from home the last time: Tor comes up while the direct addresses
    // are tried, not after them (T053) - only if the person still wants Tor.
    if (!_forceTor && addresses.viaTorLast && addresses.useTor) unawaited(_warmTor(addresses, round));
    if (!_forceTor) {
      _publish(_selection.value.copyWith(clearPath: true));
      final result = await _prober.probe(addresses.candidates(_linkAddress), serverKey: serverKey, deviceSeed: deviceSeed);
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
      unawaited(_addresses.recordGreetedViaTor());
      _recheck ??= Timer.periodic(_recheckEvery, (_) => unawaited(_recheckDirect(reason: 'periodic')));
      logRepository.debug(target: this, message: 'path: tor');
    }
  }

  @override
  void reportWrongServer(Uri url) {
    // Nothing to remember beyond the log: the next round probes again, and the
    // probe passes over an address that answers with another key.
    logRepository.debug(target: this, message: 'path: a direct address answered with another key at the dial');
  }

  bool _current(int round) => _active && round == _round;

  int _nextRound() {
    _round++;
    _roundChanged.add(null);
    return _round;
  }

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
    _handedOutInterrupted = false;
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
    // The person's choice comes first (FR-011): with `Use Tor` off nothing
    // here may even start the client (SC-006).
    if (!addresses.useTor) return _noTor('Use Tor is off');
    // A build without the library (FR-007, FR-031).
    if (!_tor.isSupported) return _noTor('not on this platform');
    // The Tor network refused this build (FR-026): direct only until an update.
    if (_tor.status.isObsolete) return _noTor('this build is obsolete');
    final target = _torTargetFor(addresses);
    if (target == null) return _noTor('no onion address');
    _torRound = round;
    _publish(_selection.value.copyWith(path: ConnectionPath.tor));
    final watch = Stopwatch()..start();
    logRepository.debug(target: this, message: 'path: bringing Tor up');
    try {
      // A client whose bootstrap failed is started afresh rather than reused:
      // it has stopped trying, and waiting on it would spend the whole budget
      // of every round that follows on a client that will never be ready.
      if (_tor.status.state == TorState.failed) await _stopTor();
      if (!_current(round)) return null;
      if (_tor.status.state == TorState.stopped) _torBoot = Stopwatch()..start();
      await _tor.start();
      if (!_current(round) || _tor.status.isObsolete) return null;
      // A start that did not take - refused by the library, or overtaken by a
      // stop - leaves nothing to wait for; waiting would spend the whole budget.
      if (_tor.status.state == TorState.stopped) return _noTor('it did not start');
      // Nothing is handed to the client in advance: the channel dials the
      // onion address itself, and no key opens the service (phase 045).
      _torTarget = target;
      final ready = await _waitForTor(_torReadyBudget, round: round);
      logRepository.debug(
        target: this,
        message: 'path: Tor ${ready ? 'ready' : 'not ready'} after ${watch.elapsedMilliseconds} ms (${_tor.status.state.name})',
      );
      if (!ready || !_current(round)) return null;
      return Uri(scheme: 'wss', host: target.host, port: target.port == 443 ? null : target.port, path: '/ws');
    } finally {
      if (_torRound == round) _torRound = null;
    }
  }

  /// Starts Tor for a device that was away from home the last time, while the
  /// direct addresses are still being tried - a warm start is about a second,
  /// a cold one several, and both used to come after the probe's seconds. A
  /// direct answer still wins: its greeting stops Tor (FR-006), so back home
  /// this costs one Tor start of a few seconds.
  Future<void> _warmTor(ServerAddresses addresses, int round) async {
    if (!addresses.useTor || !_tor.isSupported || _tor.status.isObsolete || _tor.status.state != TorState.stopped) return;
    final target = _torTargetFor(addresses);
    if (target == null || !_current(round)) return;
    _torBoot = Stopwatch()..start();
    await _tor.start();
    // The direct greeting may have come while Tor was starting, when there
    // was nothing yet for it to stop.
    if (!_active || currentPath == ConnectionPath.direct) await _stopTor();
  }

  /// Says why Tor is not an option this round - the reason only, never the
  /// address.
  Uri? _noTor(String reason) {
    logRepository.debug(target: this, message: 'path: no Tor ($reason)');
    return null;
  }

  /// The onion service to reach, when the server has one. Open to whoever
  /// knows the address (phase 045): the channel's check of the server key is
  /// what lets anyone further.
  _TorTarget? _torTargetFor(ServerAddresses addresses) {
    final host = addresses.onionHost;
    return host == null ? null : _TorTarget(host: host, port: addresses.onionPort);
  }

  /// Whether Tor is bootstrapped, within [budget].
  ///
  /// Ends early when there is nothing left to wait for: the client failed or
  /// was refused as obsolete, the session ended, or - given its [round] - a
  /// newer round took over.
  Future<bool> _waitForTor(Duration budget, {int? round}) async {
    bool ready(TorStatus status) => status.isReady;
    bool settled() {
      final status = _tor.status;
      return ready(status) ||
          status.isObsolete ||
          status.state == TorState.failed ||
          status.state == TorState.stopped ||
          !_active ||
          (round != null && round != _round);
    }

    if (settled()) return ready(_tor.status);
    try {
      await Rx.merge<Object?>([_tor.watchStatus(), _roundChanged.stream]).firstWhere((_) => settled()).timeout(budget);
    } on TimeoutException {
      return false;
    } on StateError {
      return false;
    }
    return ready(_tor.status);
  }

  Future<void> _stopTor() async {
    _torTarget = null;
    _torBoot = null;
    if (_tor.status.state == TorState.stopped || _tor.status.isObsolete) return;
    await _tor.stop();
  }

  void _onTorStatus(TorStatus status) {
    if (status.isReady) _torBoot = null;
  }

  /// A change of the connection settings (phase 045). The first value is what
  /// is stored now and says nothing new.
  void _onAddresses(ServerAddresses next) {
    final previous = _seenAddresses;
    _seenAddresses = next;
    if (!_active || previous == null) return;
    if (previous.useTor && !next.useTor) unawaited(_torTurnedOff());
    final placesChanged =
        !listEquals(previous.direct, next.direct) ||
        previous.public != next.public ||
        previous.manualAddress != next.manualAddress ||
        previous.effectiveOnion != next.effectiveOnion;
    if (placesChanged) unawaited(_recheckDirect(reason: 'new addresses'));
  }

  /// `Use Tor` was just turned off: Tor stops now, not at the next round
  /// (SC-006), and a connection that went through it is dropped so the next
  /// round goes direct only.
  Future<void> _torTurnedOff() async {
    final throughTor = currentPath == ConnectionPath.tor || _handedOutPath == ConnectionPath.tor || _torRound != null;
    logRepository.debug(target: this, message: 'path: Use Tor turned off, stopping Tor');
    await _stopTor();
    if (throughTor && _active) await _socket.reconnect();
  }

  Future<void> _onNetworkChanged() async {
    if (!_active) return;
    final phase = _socket.currentPhase;
    if (phase.isTerminal) return;
    if (!_greeted(phase)) {
      // A new network is a reason to try now, not at the next rung. An
      // attempt still under way is cut short, which is not a failed round.
      if (phase == SessionPhase.connecting) _handedOutInterrupted = true;
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
    final serverKey = _serverKey;
    final deviceSeed = _deviceSeed;
    if (address == null || serverKey == null || deviceSeed == null || _probing) return;
    _probing = true;
    try {
      final result = await _prober.probe([address], serverKey: serverKey, deviceSeed: deviceSeed);
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
    final serverKey = _serverKey;
    final deviceSeed = _deviceSeed;
    if (serverKey == null || deviceSeed == null) return;
    _probing = true;
    try {
      final addresses = await _readAddresses();
      final result = await _prober.probe(addresses.candidates(_linkAddress), serverKey: serverKey, deviceSeed: deviceSeed);
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
    final previous = _visibility;
    _visibility = visibility;
    if (!_active || visibility == previous) return;
    final usingTor = _torTarget != null;
    if (visibility == AppVisibility.background) {
      if (usingTor) _tor.setDormant(true);
      return;
    }
    if (usingTor) {
      _tor.setDormant(false);
      unawaited(_reviveTor());
    }
    // Back in front with the socket waiting out a rung of the ladder: the path
    // is chosen again now rather than at the next rung (FR-025). An attempt
    // already under way is left alone - restarting it would only lose its
    // progress.
    if (_socket.currentPhase == SessionPhase.disconnected) unawaited(_socket.reconnect());
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
    _torBoot = Stopwatch()..start();
    await _tor.start();
  }

  static bool _greeted(SessionPhase phase) => phase == SessionPhase.live || phase == SessionPhase.catchingUp;
}

/// The onion service Tor was brought up for.
@immutable
class _TorTarget {
  const _TorTarget({required this.host, required this.port});

  final String host;
  final int port;

  @override
  bool operator ==(Object other) => other is _TorTarget && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:rxdart/rxdart.dart';

/// The live answer (phase 040): the socket's phase, the path selector's round
/// and the Tor client's status, folded into one [ConnectionStatus].
///
/// Offline is smoothed (research decision 12). `disconnected` on the socket is
/// a rung of the reconnect ladder as often as it is an outage, so it reads as
/// `connecting` until a whole round of path selection has failed, and as
/// `offline` from then until a connection is greeted - the banner neither
/// blinks on every retry nor waits for a network the device does not have.
@LazySingleton(as: ConnectionStatusService, env: [Environment.dev])
class LiveConnectionStatusService implements ConnectionStatusService {
  LiveConnectionStatusService(this._socket, this._selector, this._tor) {
    _subscription = Rx.combineLatest3<SessionPhase, PathSelection, TorStatus, ConnectionStatus>(
      _socket.phase,
      _selector.watchSelection(),
      _tor.watchStatus(),
      fold,
    ).listen(_publish);
  }

  final NoxSocketClient _socket;
  final ConnectionPathSelector _selector;
  final TorService _tor;

  final BehaviorSubject<ConnectionStatus> _status = BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.initial);
  // ignore: unused_field
  late final StreamSubscription<ConnectionStatus> _subscription;

  @override
  ConnectionStatus get status => _status.value;

  @override
  Stream<ConnectionStatus> watchStatus() => _status.stream.distinct();

  void _publish(ConnectionStatus next) {
    if (_status.value != next) _status.add(next);
  }

  /// The fold itself, pure, so the smoothing rule is testable without a socket.
  static ConnectionStatus fold(SessionPhase phase, PathSelection selection, TorStatus tor) {
    final obsolete = tor.isObsolete;
    final state = switch (phase) {
      SessionPhase.live => LinkState.online,
      SessionPhase.catchingUp => LinkState.catchingUp,
      SessionPhase.serverMismatch => LinkState.serverMismatch,
      SessionPhase.unsupported => LinkState.unsupported,
      // No session running at all - nothing is trying, so nothing is coming.
      SessionPhase.connecting || SessionPhase.disconnected when !selection.active => LinkState.offline,
      SessionPhase.connecting || SessionPhase.disconnected => selection.roundFailed ? LinkState.offline : LinkState.connecting,
    };
    final path = switch (state) {
      LinkState.online || LinkState.catchingUp || LinkState.connecting => selection.path,
      _ => null,
    };
    return ConnectionStatus(state: state, path: path, torObsolete: obsolete);
  }
}

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// The live answer: the socket's own phase.
@LazySingleton(as: SessionPhaseService, env: [Environment.dev])
class SocketSessionPhaseService implements SessionPhaseService {
  SocketSessionPhaseService(this._socket);

  final NoxSocketClient _socket;

  @override
  SessionPhase get phase => _socket.currentPhase;

  @override
  Stream<SessionPhase> watchPhase() => _socket.phase;
}

/// The answer where there is no socket (mock-backed flavors).
///
/// Deliberately NOT a hard-coded `live`: the prod flavor still runs the real
/// `connectivity_plus` service, and pinning the phase would silently delete the
/// offline banner that tracker F3 shipped. Device connectivity projects onto
/// the two phases that can be told apart without a connection.
@LazySingleton(as: SessionPhaseService, env: [Environment.prod, Environment.test])
class ConnectivitySessionPhaseService implements SessionPhaseService {
  ConnectivitySessionPhaseService();

  SessionPhase _last = SessionPhase.live;

  @override
  SessionPhase get phase => _last;

  /// Resolved per subscription rather than held: this service is a singleton
  /// and the connectivity source can be replaced underneath it (the debug
  /// scenarios and the tests both do exactly that), so capturing one instance
  /// would freeze the answer at whatever was registered first.
  @override
  Stream<SessionPhase> watchPhase() => getIt<ConnectivityService>().watchOnline().map((online) {
    _last = online ? SessionPhase.live : SessionPhase.disconnected;
    return _last;
  });
}

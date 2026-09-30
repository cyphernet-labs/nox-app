import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// The connection status where there is no path selector (prod and test):
/// read straight off [SessionPhaseService]. There is no Tor here and no ladder
/// to smooth over - the mock-backed phase is device connectivity, so "not
/// current" already means offline.
///
/// The phase service is resolved per call rather than held, like
/// `ConnectivitySessionPhaseService` resolves its source: this is a singleton,
/// and the debug scenarios and the tests replace the phase source underneath
/// it.
@LazySingleton(as: ConnectionStatusService, env: [Environment.prod, Environment.test])
class PhaseConnectionStatusService implements ConnectionStatusService {
  PhaseConnectionStatusService();

  @override
  ConnectionStatus get status => fromPhase(getIt<SessionPhaseService>().phase);

  @override
  Stream<ConnectionStatus> watchStatus() => getIt<SessionPhaseService>().watchPhase().map(fromPhase).distinct();

  static ConnectionStatus fromPhase(SessionPhase phase) => ConnectionStatus(
    state: switch (phase) {
      SessionPhase.live => LinkState.online,
      SessionPhase.catchingUp => LinkState.catchingUp,
      SessionPhase.connecting => LinkState.connecting,
      SessionPhase.disconnected => LinkState.offline,
      SessionPhase.serverMismatch => LinkState.serverMismatch,
      SessionPhase.unsupported => LinkState.unsupported,
    },
  );
}

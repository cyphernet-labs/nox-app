import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/service/phase_connection_status_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/connection_status_service_impl.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';

/// How the socket's phase, the path selector's round and Tor's status fold
/// into what the corner and the banners show (phase 040, research decision 12).
void main() {
  const active = PathSelection(active: true);
  const fold = LiveConnectionStatusService.fold;

  test('a rung of the ladder reads as Connecting, not as No connection', () {
    for (final phase in [SessionPhase.disconnected, SessionPhase.connecting]) {
      expect(fold(phase, active, TorStatus.stopped).state, LinkState.connecting, reason: phase.name);
    }
  });

  test('a whole failed round is offline, and stays so through the retries', () {
    const failed = PathSelection(active: true, roundFailed: true);
    expect(fold(SessionPhase.disconnected, failed, TorStatus.stopped).state, LinkState.offline);
    expect(fold(SessionPhase.connecting, failed, TorStatus.stopped).state, LinkState.offline, reason: 'a retry does not clear it');
  });

  test('a greeting clears it: catching up, then online', () {
    const greeted = PathSelection(active: true, path: ConnectionPath.direct);
    expect(fold(SessionPhase.catchingUp, greeted, TorStatus.stopped).state, LinkState.catchingUp);
    expect(fold(SessionPhase.live, greeted, TorStatus.stopped).state, LinkState.online);
  });

  test('no session running is offline: nothing is trying', () {
    expect(fold(SessionPhase.disconnected, PathSelection.idle, TorStatus.stopped).state, LinkState.offline);
  });

  test('the path rides along while it matters, and never on offline', () {
    const tor = PathSelection(active: true, path: ConnectionPath.tor);
    expect(fold(SessionPhase.connecting, tor, TorStatus.stopped).path, ConnectionPath.tor, reason: 'Connecting… with the badge');
    expect(fold(SessionPhase.live, tor, TorStatus.stopped).showsTorBadge, isTrue);
    const failedOnTor = PathSelection(active: true, path: ConnectionPath.tor, roundFailed: true);
    expect(fold(SessionPhase.disconnected, failedOnTor, TorStatus.stopped).path, isNull);
  });

  test('the terminal phases pass straight through', () {
    expect(fold(SessionPhase.serverMismatch, active, TorStatus.stopped).state, LinkState.serverMismatch);
    expect(fold(SessionPhase.unsupported, active, TorStatus.stopped).state, LinkState.unsupported);
  });

  test('a refused Tor client is reported whatever the path (FR-026)', () {
    const obsolete = TorStatus(state: TorState.obsolete, error: TorError.softwareDeprecated);
    const direct = PathSelection(active: true, path: ConnectionPath.direct);
    final status = fold(SessionPhase.live, direct, obsolete);
    expect(status.torObsolete, isTrue);
    expect(status.state, LinkState.online);
  });

  group('why there is no connection (phase 045)', () {
    test('the failed round\'s problem rides with offline', () {
      const failed = PathSelection(active: true, roundFailed: true, problem: ConnectionProblem.turnOnTor);
      final status = fold(SessionPhase.disconnected, failed, TorStatus.stopped);
      expect(status.state, LinkState.offline);
      expect(status.problem, ConnectionProblem.turnOnTor);
      expect(status.showsNoConnection, isTrue);
    });

    test('another server behind the onion address is its own problem', () {
      expect(fold(SessionPhase.serverMismatch, active, TorStatus.stopped).problem, ConnectionProblem.otherServer);
    });

    test('no problem while connected, coming up, or refused for good', () {
      const stale = PathSelection(active: true, problem: ConnectionProblem.torNetwork);
      expect(fold(SessionPhase.live, stale, TorStatus.stopped).problem, isNull);
      expect(fold(SessionPhase.connecting, stale, TorStatus.stopped).problem, isNull, reason: 'not a failed round');
      expect(fold(SessionPhase.unsupported, stale, TorStatus.stopped).problem, isNull);
    });

    test('where there is no path selector, the phase names only another server', () {
      expect(PhaseConnectionStatusService.fromPhase(SessionPhase.serverMismatch).problem, ConnectionProblem.otherServer);
      expect(PhaseConnectionStatusService.fromPhase(SessionPhase.disconnected).problem, isNull);
    });
  });
}

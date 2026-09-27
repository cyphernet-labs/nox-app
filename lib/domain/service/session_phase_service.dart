import 'package:nox_app/domain/model/session/session_phase.dart';

/// Where the app's connection to the client server stands, as a domain concept.
///
/// This is the single source the UI's connection indication derives from
/// (FR-005). It exists as its own service rather than as a getter on the
/// transport so the mock-backed flavors can answer it too — there is no socket
/// there, but there is still a truthful answer.
abstract class SessionPhaseService {
  SessionPhase get phase;

  /// Emits the current phase on listen, then every change.
  Stream<SessionPhase> watchPhase();

  /// Brings the channel up again, from the beginning.
  ///
  /// Here rather than on the transport because a terminal phase
  /// ([SessionPhase.isTerminal]) has no ladder left to climb: without a way to
  /// ask for one more attempt, an app that once refused a server never comes
  /// back, not even after the cause is fixed and not even after a reconnect.
  /// The screens that show the refusal are the ones that must offer the way
  /// out, and this is the seam they reach it through.
  Future<void> reconnect();
}

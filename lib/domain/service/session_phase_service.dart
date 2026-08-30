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
}

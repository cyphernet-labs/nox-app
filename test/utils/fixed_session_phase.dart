import 'dart:async';

import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

/// A [SessionPhaseService] a widget test sets by hand: the current [phase] on
/// listen, then every [emit], and a count of the attempts a screen asked for.
///
/// Under the test environment the screens' connection status is derived from
/// this phase (`PhaseConnectionStatusService`), so `disconnected` raises «No
/// connection» and `unsupported` raises it without anything to try.
class FixedSessionPhaseService implements SessionPhaseService {
  FixedSessionPhaseService([this._phase = SessionPhase.live]);

  SessionPhase _phase;
  final StreamController<SessionPhase> _changes = StreamController<SessionPhase>.broadcast();

  int reconnects = 0;

  void emit(SessionPhase next) {
    _phase = next;
    _changes.add(next);
  }

  @override
  SessionPhase get phase => _phase;

  @override
  Stream<SessionPhase> watchPhase() async* {
    yield _phase;
    yield* _changes.stream;
  }

  @override
  Future<void> reconnect() async => reconnects++;
}

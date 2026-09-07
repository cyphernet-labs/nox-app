import 'dart:async';

import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:rxdart/rxdart.dart';

/// Canonical test identifier (a long key-like string) — a stable `Your ID` for the
/// identity card / Show QR surface in tests.
const String kTestIdentifier = 'NOX-7c1f9a4e2b8d40f3-a6e5c2179bd0e83f-9f2a7c4e1b6d8a30';

const SessionModel kTestSession = SessionModel(
  identifier: kTestIdentifier,
  // The server-minted public id. Distinct from the identifier slot, which now
  // holds the pairing token - a credential, never shown as "Your ID".
  authorId: 'u_test0000000001',
  // Ownership is deliberately NOT stated here. A shared fixture that claims it
  // makes every consumer inherit a badge they never asked about - and makes the
  // watch emit at construction in tests that are not about ownership at all.
  // The two settings-page golden groups state it explicitly instead.
  onboardingComplete: true,
);

/// Hand-written session double — callers exercise [readSession] plus the feature-015
/// label channel ([watchLabel] / [updateLabel]).
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({this.session = kTestSession, this.fail = false}) : _label = session?.label;

  final SessionModel? session;
  final bool fail;

  String? _label;
  final StreamController<String?> _labelController = StreamController<String?>.broadcast();
  final BehaviorSubject<bool?> _ownership = BehaviorSubject<bool?>();

  @override
  Future<RepositoryResult<SessionModel?>> readSession() async {
    if (fail) return const RepositoryResult<SessionModel?>.error(exception: RepositoryException.unknown);
    return RepositoryResult<SessionModel?>.success(data: session);
  }

  @override
  Future<RepositoryResult<bool>> adoptServerIdentity({required String authorId, required String label, bool? isOwner}) =>
      throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> updateLabel({required String label}) async {
    _label = label;
    labelDirty = true;
    _labelController.add(label);
    return const RepositoryResult<bool>.success(data: true);
  }

  @override
  Stream<bool?> watchOwnership() {
    // Mirrors the real one: a shared subject that replays its latest value and
    // does NOT complete. The generator this replaced closed after a single
    // event, which made the behaviour the channel exists for - an answer
    // arriving after the screen was built - unreachable through the fake.
    if (!_ownership.hasValue) _ownership.add(session?.isOwner);
    return _ownership.stream;
  }

  /// Pushes a new ownership answer, the way a greeting would.
  void emitOwnership(bool? isOwner) => _ownership.add(isOwner);

  @override
  Stream<String?> watchLabel() async* {
    yield _label;
    yield* _labelController.stream;
  }

  @override
  Future<RepositoryResult<bool>> saveIdentifier({required String identifier, required bool onboardingComplete, String? label}) =>
      throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label}) => throw UnimplementedError();

  @override
  Future<RepositoryResult<String>> deviceSecret() async =>
      const RepositoryResult<String>.success(data: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=');

  @override
  Future<RepositoryResult<bool>> saveServer({required String address, required String serverKey}) async =>
      const RepositoryResult<bool>.success(data: true);

  @override
  Future<RepositoryResult<String?>> serverAddress() async => const RepositoryResult<String?>.success(data: '127.0.0.1:8080');

  /// Raised by [updateLabel] the way the real store raises it: a greeting states
  /// a name only after a rename.
  bool labelDirty = false;

  @override
  Future<RepositoryResult<bool>> advanceOnboardingIfKnown({required bool created}) async =>
      const RepositoryResult<bool>.success(data: false);

  @override
  Future<RepositoryResult<bool>> forgetAuthorId() async => const RepositoryResult<bool>.success(data: true);

  @override
  void noteOnboardingStartedHere() {}

  @override
  Future<RepositoryResult<bool>> discardSignIn() => throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> clear() => throw UnimplementedError();
}

/// Registers a [FakeSessionRepository] into the DI container so blocs/pages that
/// resolve the `sessionRepository` alias work in otherwise DI-less tests. Pair with
/// `tearDown(getIt.reset)`.
void registerFakeSession({SessionModel? session = kTestSession, bool fail = false}) {
  getIt.allowReassignment = true;
  getIt.registerSingleton<SessionRepository>(FakeSessionRepository(session: session, fail: fail));
}

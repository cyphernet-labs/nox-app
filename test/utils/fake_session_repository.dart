import 'dart:async';

import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Canonical test identifier (a long key-like string) — a stable `Your ID` for the
/// identity card / Show QR surface in tests.
const String kTestIdentifier = 'NOX-7c1f9a4e2b8d40f3-a6e5c2179bd0e83f-9f2a7c4e1b6d8a30';

const SessionModel kTestSession = SessionModel(identifier: kTestIdentifier, onboardingComplete: true);

/// Hand-written session double — callers exercise [readSession] plus the feature-015
/// label channel ([watchLabel] / [updateLabel]).
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({this.session = kTestSession, this.fail = false}) : _label = session?.label;

  final SessionModel? session;
  final bool fail;

  String? _label;
  final StreamController<String?> _labelController = StreamController<String?>.broadcast();

  @override
  Future<RepositoryResult<SessionModel?>> readSession() async {
    if (fail) return const RepositoryResult<SessionModel?>.error(exception: RepositoryException.unknown);
    return RepositoryResult<SessionModel?>.success(data: session);
  }

  @override
  Future<RepositoryResult<bool>> adoptServerIdentity({required String authorId, required String label}) => throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> updateLabel({required String label}) async {
    _label = label;
    labelDirty = true;
    _labelController.add(label);
    return const RepositoryResult<bool>.success(data: true);
  }

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
  Future<RepositoryResult<String>> deviceId() async => const RepositoryResult<String>.success(data: 'test-device');

  @override
  Future<RepositoryResult<bool>> isLabelDirty() async => RepositoryResult<bool>.success(data: labelDirty);

  /// Raised by [updateLabel] the way the real store raises it: a greeting states
  /// a name only after a rename.
  bool labelDirty = false;

  @override
  Future<RepositoryResult<bool>> markLabelDirty() async {
    labelDirty = true;
    return const RepositoryResult<bool>.success(data: true);
  }

  @override
  Future<RepositoryResult<bool>> forgetAuthorId() async => const RepositoryResult<bool>.success(data: true);

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

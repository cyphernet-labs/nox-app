import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

/// Canonical test identifier (a long key-like string) — a stable `Your ID` for the
/// identity card / Show QR surface in tests.
const String kTestIdentifier = 'NOX-7c1f9a4e2b8d40f3-a6e5c2179bd0e83f-9f2a7c4e1b6d8a30';

const SessionModel kTestSession = SessionModel(identifier: kTestIdentifier, onboardingComplete: true);

/// Hand-written session double — callers only exercise [readSession].
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({this.session = kTestSession, this.fail = false});

  final SessionModel? session;
  final bool fail;

  @override
  Future<RepositoryResult<SessionModel?>> readSession() async {
    if (fail) return const RepositoryResult<SessionModel?>.error(exception: RepositoryException.unknown);
    return RepositoryResult<SessionModel?>.success(data: session);
  }

  @override
  Future<RepositoryResult<bool>> saveIdentifier({required String identifier, required bool onboardingComplete, String? label}) =>
      throw UnimplementedError();

  @override
  Future<RepositoryResult<bool>> setOnboardingComplete({String? label}) => throw UnimplementedError();

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

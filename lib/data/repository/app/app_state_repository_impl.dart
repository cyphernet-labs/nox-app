import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:rxdart/rxdart.dart';

/// In-memory derived app state — a `BehaviorSubject` fed imperatively in
/// [fetchAppState], NO Sembast DAO (it is a projection, not stored). Adapts the
/// blueprint reactive-repo shape (04 §8.1) without DAO. Singleton (subject must
/// outlive every page).
@LazySingleton(as: AppStateRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AppStateRepositoryImpl implements AppStateRepository {
  AppStateRepositoryImpl(this._sessionRepository);

  final SessionRepository _sessionRepository;
  final BehaviorSubject<RepositoryResult<AppStateModel>> _subject = BehaviorSubject<RepositoryResult<AppStateModel>>();

  @override
  AppStateType? get currentState => _subject.valueOrNull?.match(onData: (model) => model.state, onError: (_) => null);

  @override
  Stream<RepositoryResult<AppStateModel>> watchAppState() async* {
    // Lazy first resolution; BehaviorSubject then replays the latest to this
    // subscription and forwards every subsequent push.
    if (!_subject.hasValue) {
      await fetchAppState();
    }
    yield* _subject.stream;
  }

  @override
  Future<RepositoryResult<AppStateModel>> fetchAppState({bool sessionExpired = false}) async {
    // Cache-only resolution. readSession() is itself error-wrapped (never throws) and
    // match is total, so this always yields a success result → the subject always emits
    // (FR-015). The single fail-safe lives in match's onError below.
    final sessionResult = await _sessionRepository.readSession();
    final model = sessionResult.match<AppStateModel>(
      onData: (session) {
        if (session == null || session.identifier.isEmpty) return _unauthorized(sessionExpired);
        if (!session.onboardingComplete) return AppStateModel(state: AppStateType.registrationPending, session: session);
        return AppStateModel(state: AppStateType.authorized, session: session);
      },
      // Fail-safe: any storage read error resolves to unauthorized, never crashes.
      onError: (_) => _unauthorized(sessionExpired),
    );
    final result = RepositoryResult<AppStateModel>.success(data: model);
    _subject.add(result);
    return result;
  }

  AppStateModel _unauthorized(bool sessionExpired) =>
      AppStateModel(state: AppStateType.unauthorized, session: null, sessionExpired: sessionExpired);
}

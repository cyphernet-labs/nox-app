import 'package:injectable/injectable.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';

/// Mutate source-of-truth (session) → re-derive app state. Single logout path;
/// only forced logout passes `sessionExpired`. Sign-in is a stub (backend TBD).
@LazySingleton(as: AuthRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AuthRepositoryImpl with BaseRepositoryHelper implements AuthRepository {
  AuthRepositoryImpl(this._sessionRepository, this._appStateRepository);

  final SessionRepository _sessionRepository;
  final AppStateRepository _appStateRepository;

  @override
  Future<RepositoryResult<bool>> signIn({required String identifier}) {
    // Normalize once: derive the outcome from AND persist the SAME value so the
    // stored identity can't diverge from the id that was matched (e.g. a pasted
    // "registered\n"). This is normalization, not format validation (FR-011).
    final id = identifier.trim();
    final onboardingComplete = OnboardingMockData.registeredIds.contains(id);
    return _deriveAfter(() => _sessionRepository.saveIdentifier(identifier: id, onboardingComplete: onboardingComplete));
  }

  @override
  Future<RepositoryResult<bool>> completeOnboarding({String? label}) {
    return _deriveAfter(() => _sessionRepository.setOnboardingComplete(label: label));
  }

  @override
  Future<RepositoryResult<bool>> logout({bool forced = false}) {
    // Gate the re-derive on a successful wipe: a failed clear() (e.g. a secure-storage
    // PlatformException) must NOT report success while the identifier survives —
    // otherwise the user silently stays authorized (Constitution I: logout fully wipes).
    return _deriveAfter(_sessionRepository.clear, sessionExpired: forced);
  }

  /// The single home of the "mutate the source of truth → re-derive app state"
  /// contract: run [mutate]; on success re-derive via `fetchAppState`, on failure
  /// propagate the mutation error unchanged (no re-derive, no false success).
  Future<RepositoryResult<bool>> _deriveAfter(Future<RepositoryResult<bool>> Function() mutate, {bool sessionExpired = false}) {
    return execute<bool>(() async {
      final mutated = await mutate();
      if (!mutated.hasData) return mutated;
      await _appStateRepository.fetchAppState(sessionExpired: sessionExpired);
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}

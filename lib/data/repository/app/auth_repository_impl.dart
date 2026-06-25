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
    return execute<bool>(() async {
      // Stub: registeredIds resolve to an already-onboarded account → authorized;
      // any other id → registrationPending (Set username 2.3). No client validation.
      final onboardingComplete = OnboardingMockData.registeredIds.contains(identifier.trim());
      final saved = await _sessionRepository.saveIdentifier(identifier: identifier, onboardingComplete: onboardingComplete);
      if (!saved.hasData) return RepositoryResult<bool>.error(exception: saved.exception!);
      await _appStateRepository.fetchAppState();
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> completeOnboarding({String? label}) {
    return execute<bool>(() async {
      final done = await _sessionRepository.setOnboardingComplete(label: label);
      if (!done.hasData) return RepositoryResult<bool>.error(exception: done.exception!);
      await _appStateRepository.fetchAppState();
      return const RepositoryResult<bool>.success(data: true);
    });
  }

  @override
  Future<RepositoryResult<bool>> logout({bool forced = false}) {
    return execute<bool>(() async {
      await _sessionRepository.clear();
      await _appStateRepository.fetchAppState(sessionExpired: forced);
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}

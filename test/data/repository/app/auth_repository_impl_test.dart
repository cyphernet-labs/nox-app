import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/repository/app/auth_repository_impl.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

import 'auth_repository_impl_test.mocks.dart';

@GenerateMocks([SessionRepository, AppStateRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));
  provideDummy<RepositoryResult<AppStateModel>>(RepositoryResult<AppStateModel>.success(data: AppStateModel.init()));

  late MockSessionRepository session;
  late MockAppStateRepository appState;
  late AuthRepositoryImpl repository;

  setUp(() {
    session = MockSessionRepository();
    appState = MockAppStateRepository();
    repository = AuthRepositoryImpl(session, appState);

    when(
      session.saveIdentifier(
        identifier: anyNamed('identifier'),
        onboardingComplete: anyNamed('onboardingComplete'),
        label: anyNamed('label'),
      ),
    ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(session.setOnboardingComplete(label: anyNamed('label'))).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(session.clear()).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(
      appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')),
    ).thenAnswer((_) async => RepositoryResult<AppStateModel>.success(data: AppStateModel.init()));
  });

  test('signIn under a registered identifier persists onboardingComplete=true', () async {
    await repository.signIn(identifier: 'registered');
    verify(session.saveIdentifier(identifier: 'registered', onboardingComplete: true)).called(1);
    verify(appState.fetchAppState()).called(1);
  });

  test('signIn under a new identifier persists onboardingComplete=false', () async {
    await repository.signIn(identifier: 'someoneNew');
    verify(session.saveIdentifier(identifier: 'someoneNew', onboardingComplete: false)).called(1);
  });

  test('signIn trims the identifier before matching and persisting', () async {
    await repository.signIn(identifier: '  registered\n');
    verify(session.saveIdentifier(identifier: 'registered', onboardingComplete: true)).called(1);
  });

  test('logout propagates a clear() failure and does not re-derive app state', () async {
    when(session.clear()).thenAnswer((_) async => RepositoryResult<bool>.error(exception: RepositoryException.unknown));
    final result = await repository.logout();
    expect(result.hasData, isFalse);
    verifyNever(appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')));
  });

  test('completeOnboarding marks the flag and re-derives app state', () async {
    await repository.completeOnboarding(label: 'Alice');
    verify(session.setOnboardingComplete(label: 'Alice')).called(1);
    verify(appState.fetchAppState()).called(1);
  });

  test('ordinary logout clears the session without sessionExpired', () async {
    await repository.logout();
    verify(session.clear()).called(1);
    verify(appState.fetchAppState(sessionExpired: false)).called(1);
  });

  test('forced logout re-derives with sessionExpired=true', () async {
    await repository.logout(forced: true);
    verify(session.clear()).called(1);
    verify(appState.fetchAppState(sessionExpired: true)).called(1);
  });
}

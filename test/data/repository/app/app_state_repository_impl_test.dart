import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/repository/app/app_state_repository_impl.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';

import 'app_state_repository_impl_test.mocks.dart';

@GenerateMocks([SessionRepository])
void main() {
  provideDummy<RepositoryResult<SessionModel?>>(const RepositoryResult<SessionModel?>.success(data: null));

  late MockSessionRepository session;
  late AppStateRepositoryImpl repository;

  setUp(() {
    session = MockSessionRepository();
    repository = AppStateRepositoryImpl(session);
  });

  void stubSession(SessionModel? model) {
    when(session.readSession()).thenAnswer((_) async => RepositoryResult<SessionModel?>.success(data: model));
  }

  test('currentState is null before the first resolution', () {
    expect(repository.currentState, isNull);
  });

  test('resolves unauthorized when there is no session', () async {
    stubSession(null);
    final result = await repository.fetchAppState();
    expect(result.data!.state, AppStateType.unauthorized);
    expect(repository.currentState, AppStateType.unauthorized);
  });

  test('resolves registrationPending when onboarding is incomplete', () async {
    stubSession(const SessionModel(identifier: 'abc'));
    final result = await repository.fetchAppState();
    expect(result.data!.state, AppStateType.registrationPending);
  });

  test('resolves authorized when onboarding is complete', () async {
    stubSession(const SessionModel(identifier: 'abc', onboardingComplete: true));
    final result = await repository.fetchAppState();
    expect(result.data!.state, AppStateType.authorized);
  });

  test('carries sessionExpired only on the unauthorized branch', () async {
    stubSession(null);
    final result = await repository.fetchAppState(sessionExpired: true);
    expect(result.data!.state, AppStateType.unauthorized);
    expect(result.data!.sessionExpired, isTrue);
  });

  test('falls back to unauthorized when the session read errors', () async {
    when(session.readSession()).thenAnswer((_) async => RepositoryResult<SessionModel?>.error(exception: RepositoryException.unknown));
    final result = await repository.fetchAppState();
    expect(result.data!.state, AppStateType.unauthorized);
  });

  test('watchAppState replays the latest resolved value to a new subscriber', () async {
    stubSession(const SessionModel(identifier: 'abc', onboardingComplete: true));
    await repository.fetchAppState();
    final first = await repository.watchAppState().first;
    expect(first.data!.state, AppStateType.authorized);
  });
}

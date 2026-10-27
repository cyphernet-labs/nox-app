import 'dart:async';

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

  test('preserves the last resolved state when a warm session read errors', () async {
    // Cold start seeds authorized from a valid session.
    stubSession(const SessionModel(identifier: 'abc', onboardingComplete: true));
    final seeded = await repository.fetchAppState();
    expect(seeded.data!.state, AppStateType.authorized);
    expect(repository.currentState, AppStateType.authorized);

    // A transient storage READ error must NOT log the user out — the warm
    // onError branch keeps the previously resolved authorized state.
    when(session.readSession()).thenAnswer((_) async => RepositoryResult<SessionModel?>.error(exception: RepositoryException.unknown));
    final result = await repository.fetchAppState();
    expect(result.data!.state, AppStateType.authorized);
    expect(repository.currentState, AppStateType.authorized);
  });

  test('watchAppState replays the latest resolved value to a new subscriber', () async {
    stubSession(const SessionModel(identifier: 'abc', onboardingComplete: true));
    await repository.fetchAppState();
    final first = await repository.watchAppState().first;
    expect(first.data!.state, AppStateType.authorized);
  });

  group('the start-up hold (phase 048)', () {
    test('no state is resolved for the screens until the start-up is over', () async {
      stubSession(const SessionModel(identifier: 'abc', onboardingComplete: true));
      final startUp = Completer<void>();
      repository.holdUntil(startUp.future);
      final heard = <AppStateType>[];
      final subscription = repository.watchAppState().listen((result) => heard.add(result.data!.state));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(heard, isEmpty, reason: 'the splash stays while the local data opens');
      verifyNever(session.readSession());

      startUp.complete();
      await pumpEventQueue();
      expect(heard, [AppStateType.authorized]);
    });

    test('the start-up resolves through it meanwhile - its own logout is not held', () async {
      stubSession(null);
      final startUp = Completer<void>();
      repository.holdUntil(startUp.future);

      final result = await repository.fetchAppState(sessionExpired: true);

      expect(result.data!.state, AppStateType.unauthorized);
      final heard = <AppStateType>[];
      final subscription = repository.watchAppState().listen((r) => heard.add(r.data!.state));
      addTearDown(subscription.cancel);
      startUp.complete();
      await pumpEventQueue();
      expect(heard, [AppStateType.unauthorized], reason: 'what the start-up resolved, replayed - not resolved again');
      verify(session.readSession()).called(1);
    });

    test('a start-up that failed still lets the app open', () async {
      stubSession(null);
      final startUp = Completer<void>();
      repository.holdUntil(startUp.future);
      final first = repository.watchAppState().first;

      startUp.completeError(StateError('the start-up broke'));

      expect((await first).data!.state, AppStateType.unauthorized);
    });
  });
}

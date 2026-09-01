import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/repository/app/auth_repository_impl.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_repository_impl_test.mocks.dart';

@GenerateMocks([SessionRepository, AppStateRepository, ChatRepository, MessageRepository, SyncRepository, OutboxRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));
  provideDummy<RepositoryResult<AppStateModel>>(RepositoryResult<AppStateModel>.success(data: AppStateModel.init()));

  late MockSessionRepository session;
  late MockAppStateRepository appState;
  late MockChatRepository chats;
  late MockMessageRepository messages;
  late MockSyncRepository sync;
  late MockOutboxRepository outbox;
  late AuthRepositoryImpl repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    session = MockSessionRepository();
    appState = MockAppStateRepository();
    chats = MockChatRepository();
    messages = MockMessageRepository();
    sync = MockSyncRepository();
    outbox = MockOutboxRepository();
    repository = AuthRepositoryImpl(session, appState, chats, messages, sync, outbox);

    when(chats.clean()).thenAnswer((_) async {});
    when(messages.clean()).thenAnswer((_) async {});
    when(sync.clear()).thenAnswer((_) async {});
    when(outbox.clean()).thenAnswer((_) async {});

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

  tearDown(() async => getIt.reset());

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

  test('logout propagates a clear() failure and does not re-derive app state or wipe caches', () async {
    when(session.clear()).thenAnswer((_) async => RepositoryResult<bool>.error(exception: RepositoryException.unknown));
    final result = await repository.logout();
    expect(result.hasData, isFalse);
    verifyNever(appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')));
    // A failed wipe must not drop the caches (the user is still authorized).
    verifyNever(chats.clean());
    verifyNever(messages.clean());
    verifyNever(sync.clear());
    // The queue holds message texts; a failed wipe must not drop them either.
    verifyNever(outbox.clean());
  });

  test('logout wipes the chat + message caches after a successful clear (full local wipe)', () async {
    await repository.logout();
    // The cursor goes FIRST: a crash mid-wipe must leave it behind the stores
    // (safe), never ahead of an emptied store (a stale high `since` would skip
    // replayed history forever under the monotonic guard).
    // The queue goes FIRST of the stores: it holds unsent message TEXTS, and a
    // crash later in the wipe would leave them for the next identity to send
    // under their own name.
    verifyInOrder([session.clear(), outbox.clean(), sync.clear(), chats.clean(), messages.clean()]);
  });

  test('signing in re-arms the outgoing drain that logout cancelled', () async {
    // The drain's phase subscription dies with logout, and stop() disarms it
    // until start() is called again. Asserting through OBSERVABLE behaviour —
    // does a queued message actually go out after a re-login — because the
    // earlier version of this test passed with the re-arm deleted.
    final outboxRepository = getIt<OutboxRepository>();
    final drain = getIt<OutboxService>();
    await outboxRepository.clean();

    await repository.logout(); // stops and disarms the drain
    await outboxRepository.enqueue(chatId: 'chat_0', text: 'written after the logout');
    await drain.flush();
    expect(await outboxRepository.pending(), hasLength(1), reason: 'a disarmed drain must not send');

    await repository.signIn(identifier: 'registered');
    await drain.flush();

    expect(await outboxRepository.pending(), isEmpty, reason: 'sign-in has to put the drain back to work');
    await outboxRepository.clean();
  });

  test('completeOnboarding marks the flag and re-derives app state', () async {
    await repository.completeOnboarding(label: 'Alice');
    verify(session.setOnboardingComplete(label: 'Alice')).called(1);
    verify(appState.fetchAppState()).called(1);
  });

  test('a failed completeOnboarding does not re-derive app state', () async {
    // The reconnect that carries the new label rides in the same afterMutate,
    // so a failure here must leave both alone rather than announcing a name the
    // session never stored.
    when(
      session.setOnboardingComplete(label: anyNamed('label')),
    ).thenAnswer((_) async => RepositoryResult<bool>.error(exception: RepositoryException.unknown));

    final result = await repository.completeOnboarding(label: 'Alice');

    expect(result.hasData, isFalse);
    verifyNever(appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')));
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

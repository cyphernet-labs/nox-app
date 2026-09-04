import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/repository/app/auth_repository_impl.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_repository_impl_test.mocks.dart';

@GenerateMocks([
  SessionRepository,
  AppStateRepository,
  ChatRepository,
  MessageRepository,
  SyncRepository,
  OutboxRepository,
  FileRepository,
  LiveIdentityHandshake,
])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));
  provideDummy<RepositoryResult<AppStateModel>>(RepositoryResult<AppStateModel>.success(data: AppStateModel.init()));

  late MockSessionRepository session;
  late MockAppStateRepository appState;
  late MockChatRepository chats;
  late MockMessageRepository messages;
  late MockSyncRepository sync;
  late MockOutboxRepository outbox;
  late MockFileRepository files;
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
    files = MockFileRepository();
    repository = AuthRepositoryImpl(session, appState, chats, messages, sync, outbox, files);

    when(chats.clean()).thenAnswer((_) async {});
    when(messages.clean()).thenAnswer((_) async {});
    when(sync.clear()).thenAnswer((_) async {});
    when(outbox.clean()).thenAnswer((_) async {});
    when(files.clean()).thenAnswer((_) async {});

    when(
      session.saveIdentifier(
        identifier: anyNamed('identifier'),
        onboardingComplete: anyNamed('onboardingComplete'),
        label: anyNamed('label'),
      ),
    ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(session.setOnboardingComplete(label: anyNamed('label'))).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(session.clear()).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(session.discardSignIn()).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(
      appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')),
    ).thenAnswer((_) async => RepositoryResult<AppStateModel>.success(data: AppStateModel.init()));
  });

  tearDown(() async => getIt.reset());

  test('signIn no longer consults any built-in list of identifiers', () async {
    // 'registered' used to be one of two strings that made someone a returning
    // person. Nothing in the app knows that word any more: the server decides,
    // and with no live channel in this environment there is nobody to ask, so
    // onboarding is due - for that identifier exactly as for any other.
    await repository.signIn(identifier: 'registered');
    verify(session.saveIdentifier(identifier: 'registered', onboardingComplete: false)).called(1);
    verify(appState.fetchAppState()).called(1);
  });

  test('signIn under a new identifier persists onboardingComplete=false', () async {
    await repository.signIn(identifier: 'someoneNew');
    verify(session.saveIdentifier(identifier: 'someoneNew', onboardingComplete: false)).called(1);
  });

  test('FR-004: signing in never states a label, so a known name cannot be overwritten', () async {
    // The defect this feature removes, asserted at its narrowest point. The
    // old path decided onboarding locally, sent the person to the naming
    // screen, and the name they typed there travelled to the server as a
    // RENAME - overwriting the name they were known by. Sign-in must
    // therefore never raise the rename flag and never state a label itself:
    // the only thing it writes is the identifier.
    await repository.signIn(identifier: 'someoneNew');

    verifyNever(session.updateLabel(label: anyNamed('label')));
    verifyNever(session.markLabelDirty());
    // setOnboardingComplete is what carries a label, and sign-in may only
    // reach it when the SERVER said the person is already known - in which
    // case there is nothing to name.
    verifyNever(session.setOnboardingComplete(label: anyNamed('label')));
  });

  test('a sign-in that cannot ask the server leaves no half-made session behind', () async {
    // Storing the identifier comes first, because that is what makes the
    // greeting state a person instead of going out anonymously. If the
    // handshake then fails, the stored identifier must not survive: a session
    // with no settled outcome would strand the next launch in onboarding -
    // the exact state this method exists to stop handing out.
    when(
      session.saveIdentifier(identifier: anyNamed('identifier'), onboardingComplete: anyNamed('onboardingComplete')),
    ).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.unknown));

    final result = await repository.signIn(identifier: 'someoneNew');

    expect(result.hasData, isFalse);
    verifyNever(appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')));
  });

  test('signIn trims the identifier before persisting', () async {
    // Normalisation still matters, and now for a sharper reason: the login_ref
    // derivation is computed over the stored value, so a trailing newline
    // would make the same person unrecognisable on the next install.
    await repository.signIn(identifier: '  registered\n');
    verify(session.saveIdentifier(identifier: 'registered', onboardingComplete: false)).called(1);
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
    verifyNever(files.clean());
  });

  test('logout wipes the chat + message caches after a successful clear (full local wipe)', () async {
    await repository.logout();
    // The cursor goes FIRST: a crash mid-wipe must leave it behind the stores
    // (safe), never ahead of an emptied store (a stale high `since` would skip
    // replayed history forever under the monotonic guard).
    // The queue goes FIRST of the stores: it holds unsent message TEXTS, and a
    // crash later in the wipe would leave them for the next identity to send
    // under their own name.
    verifyInOrder([session.clear(), outbox.clean(), files.clean(), sync.clear(), chats.clean(), messages.clean()]);
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

  /// Sign-in with a live channel present: the branch the app actually takes on
  /// the stage flavor, and the one no test used to reach — every case above
  /// runs the no-handshake fallback, so the server-decided outcome and its
  /// rollback were both unexercised.
  group('signIn with a live channel', () {
    late MockLiveIdentityHandshake handshake;

    setUp(() {
      handshake = MockLiveIdentityHandshake();
      getIt.allowReassignment = true;
      getIt.registerSingleton<LiveIdentityHandshake>(handshake);
      when(appState.currentState).thenReturn(AppStateType.authorized);
    });

    test('a person the server already knows skips onboarding entirely', () async {
      when(handshake.greet()).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));

      final result = await repository.signIn(identifier: 'anna-id');

      expect(result.data, isTrue);
      verify(session.setOnboardingComplete()).called(1);
      verifyNever(session.noteOnboardingStartedHere());
      // Still no label from here: the name the server holds is the authority.
      verifyNever(session.setOnboardingComplete(label: anyNamed('label')));
    });

    test('a person the server just created goes to naming, and the process remembers it', () async {
      when(handshake.greet()).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_2', label: 'User1234', created: true));

      final result = await repository.signIn(identifier: 'brand-new');

      expect(result.data, isTrue);
      verifyNever(session.setOnboardingComplete());
      // Without this mark a reconnect during naming reports the person's own
      // brand-new row back as "already known" and ends onboarding mid-typing.
      verify(session.noteOnboardingStartedHere()).called(1);
    });

    test('a handshake that never answers rolls the sign-in back, keeping the device id', () async {
      when(handshake.greet()).thenThrow(const IdentityHandshakeTimeout());

      final result = await repository.signIn(identifier: 'anna-id');

      expect(result.hasData, isFalse);
      verify(session.discardSignIn()).called(1);
      // NOT clear(): that wipes secure storage wholesale and takes the device
      // id with it, so one install would register as two devices.
      verifyNever(session.clear());
      verifyNever(session.setOnboardingComplete());
    });

    test('an outcome the server did not state is not treated as an outcome', () async {
      // An older server, or a frame without the field. Guessing false steals a
      // newcomer's naming step; guessing true overwrites a returning person's
      // name. Neither is acceptable, so the sign-in fails and offers a retry.
      when(handshake.greet()).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_3', label: 'Anna', created: null));

      final result = await repository.signIn(identifier: 'anna-id');

      expect(result.hasData, isFalse);
      verify(session.discardSignIn()).called(1);
      verifyNever(session.setOnboardingComplete());
    });
  });
}

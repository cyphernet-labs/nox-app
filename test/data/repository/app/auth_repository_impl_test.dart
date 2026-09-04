import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/repository/app/auth_repository_impl.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
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
  provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.success(data: ''));
  provideDummy<RepositoryResult<String?>>(const RepositoryResult<String?>.success(data: null));
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

  // A link the Go server actually produced, captured from a live noxd.
  const link = 'https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo';

  test('signing in remembers which server the link named', () async {
    // Without this the app pairs with the server a person presented and then
    // sends their messages to the address baked into the build.
    await repository.signIn(identifier: link);
    verify(session.saveServer(address: '127.0.0.1:8080', serverKey: anyNamed('serverKey'))).called(1);
  });

  test('a link that will not parse is refused before anything is stored', () async {
    final result = await repository.signIn(identifier: 'not a pairing link');

    expect(result.hasData, isFalse);
    expect(result.exception, RepositoryException.invalidRequest);
    verifyNever(session.saveServer(address: anyNamed('address'), serverKey: anyNamed('serverKey')));
    verifyNever(session.saveIdentifier(identifier: anyNamed('identifier'), onboardingComplete: anyNamed('onboardingComplete')));
  });

  test('FR-004: signing in never states a label, so a known name cannot be overwritten', () async {
    // The defect feature 031 removed, asserted at its narrowest point: sign-in
    // may write the identity but never a name.
    await repository.signIn(identifier: link);

    verifyNever(session.updateLabel(label: anyNamed('label')));
    verifyNever(session.markLabelDirty());
    verifyNever(session.setOnboardingComplete(label: anyNamed('label')));
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
  /// Sign-in with a live channel: the branch the app takes on the stage flavor.
  group('signIn with a live channel', () {
    late MockLiveIdentityHandshake handshake;

    setUp(() {
      handshake = MockLiveIdentityHandshake();
      getIt.allowReassignment = true;
      getIt.registerSingleton<LiveIdentityHandshake>(handshake);
      when(appState.currentState).thenReturn(AppStateType.authorized);
      when(
        session.deviceSecret(),
      ).thenAnswer((_) async => const RepositoryResult<String>.success(data: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='));
      when(
        session.saveServer(address: anyNamed('address'), serverKey: anyNamed('serverKey')),
      ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    });

    test('claiming a server brings the person into being, so naming is ahead', () async {
      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_2', label: 'User1234', created: true));

      final result = await repository.signIn(identifier: link);

      expect(result.data, isTrue);
      verifyNever(session.setOnboardingComplete());
      // Without this mark a reconnect during naming reports the person's own
      // brand-new row back as "already known" and ends onboarding mid-typing.
      verify(session.noteOnboardingStartedHere()).called(1);
    });

    test('a device added to an existing person skips onboarding entirely', () async {
      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));

      final result = await repository.signIn(identifier: link);

      expect(result.data, isTrue);
      verify(session.setOnboardingComplete()).called(1);
      verifyNever(session.noteOnboardingStartedHere());
    });

    test('only the PUBLIC key is presented - the seed never leaves', () async {
      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));

      await repository.signIn(identifier: link);

      final presented = verify(
        handshake.pair(link: anyNamed('link'), deviceKey: captureAnyNamed('deviceKey'), platform: anyNamed('platform')),
      ).captured.single;
      expect(presented, 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=', reason: 'the public half of the pinned vector');
      expect(presented, isNot(contains('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=')));
    });

    test('an expired invite is told apart from a rejected one', () async {
      // The person acts differently: issue a new invite versus this one is not
      // usable at all.
      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenThrow(const PairingRefused(expired: true));

      final expired = await repository.signIn(identifier: link);
      expect(expired.exception, RepositoryException.notFound);

      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenThrow(const PairingRefused(expired: false));

      final rejected = await repository.signIn(identifier: link);
      expect(rejected.exception, RepositoryException.authentication);
    });

    test('a pairing that never answers rolls back, keeping the device key', () async {
      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenThrow(const IdentityHandshakeTimeout());

      final result = await repository.signIn(identifier: link);

      expect(result.hasData, isFalse);
      verify(session.discardSignIn()).called(1);
      // NOT clear(): that wipes secure storage wholesale and takes the device
      // key with it, so one install would register as two devices.
      verifyNever(session.clear());
      verifyNever(session.setOnboardingComplete());
    });

    test('an outcome the server did not state is not treated as an outcome', () async {
      // An older server, or a frame without the field. Guessing false steals a
      // newcomer's naming step; guessing true overwrites a returning person's
      // name.
      when(
        handshake.pair(link: anyNamed('link'), deviceKey: anyNamed('deviceKey'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_3', label: 'Anna', created: null));

      final result = await repository.signIn(identifier: link);

      expect(result.hasData, isFalse);
      verify(session.discardSignIn()).called(1);
      verifyNever(session.setOnboardingComplete());
    });
  });
}

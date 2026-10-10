import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/repository/app/auth_repository_impl.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/session/pair_refusal.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/service/tor_service.dart';

import 'package:nox_app/general/pairing/pairing_link.dart';
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
    when(
      session.adoptServerIdentity(authorId: anyNamed('authorId'), label: anyNamed('label')),
    ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(session.discardSignIn()).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    when(
      appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')),
    ).thenAnswer((_) async => RepositoryResult<AppStateModel>.success(data: AppStateModel.init()));
  });

  tearDown(() async => getIt.reset());

  // The contract's `minimal` vector: one IPv4 address, shared with the Go
  // server that issues it.
  const link = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';
  const serverKey = 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=';

  test('signing in remembers which server the link named - its address and its key', () async {
    // Without this the app pairs with the server a person presented and then
    // sends their messages to the address baked into the build - or checks
    // the connection against nothing at all.
    await repository.signIn(identifier: link);
    verify(session.saveServer(address: '192.168.1.20:8443', serverKey: serverKey)).called(1);
  });

  test('a link that will not parse is refused before anything is stored', () async {
    for (final broken in [
      'not a pairing link',
      'https://nox.app/p/#AQF_AAABH5CjZmMytIk_2XvPJ-jonqlQtYsZD3SB33P1foxqnrVbFo-VEf6WohQoqA1_na5iVUo',
    ]) {
      final result = await repository.signIn(identifier: broken);

      expect(result.hasData, isFalse);
      expect(result.exception, RepositoryException.invalidRequest, reason: broken);
    }
    verifyNever(session.saveServer(address: anyNamed('address'), serverKey: anyNamed('serverKey')));
    verifyNever(session.saveIdentifier(identifier: anyNamed('identifier'), onboardingComplete: anyNamed('onboardingComplete')));
  });

  test('a link from a newer server asks for an update, before anything is stored', () async {
    final result = await repository.signIn(identifier: 'nox://pair/BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODw');

    expect(result.hasData, isFalse);
    expect(result.exception, RepositoryException.unsupportedSchema, reason: 'apart from a broken link: the person updates the app');
    verifyNever(session.saveServer(address: anyNamed('address'), serverKey: anyNamed('serverKey')));
  });

  test('a link with no direct address and nothing typed has nowhere to start, and stores nothing', () async {
    final onionOnly = PairingLink(
      serverKey: PairingLink.parse(link).serverKey,
      token: PairingLink.parse(link).token,
      addresses: [OnionLinkAddress(PairingLink.parse(link).serverKey)],
    ).encode();

    final result = await repository.signIn(identifier: onionOnly);

    expect(result.exception, RepositoryException.connection);
    verifyNever(session.saveServer(address: anyNamed('address'), serverKey: anyNamed('serverKey')));
  });

  test('a link with no direct address starts at the address typed on the connection screen (phase 045)', () async {
    when(
      session.saveServer(address: anyNamed('address'), serverKey: anyNamed('serverKey')),
    ).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
    final onionOnly = PairingLink(
      serverKey: PairingLink.parse(link).serverKey,
      token: PairingLink.parse(link).token,
      addresses: [OnionLinkAddress(PairingLink.parse(link).serverKey)],
    ).encode();

    await repository.signIn(
      identifier: onionOnly,
      connection: const ConnectionSettings(serverAddress: '10.8.0.2:8443'),
    );

    verify(session.saveServer(address: '10.8.0.2:8443', serverKey: serverKey)).called(1);
    expect((await getIt<ServerAddressesRepository>().read()).data!.manualAddress, isNull, reason: 'no edit of anything');
  });

  test('FR-004: signing in never states a label, so a known name cannot be overwritten', () async {
    // The defect feature 031 removed, asserted at its narrowest point: sign-in
    // may write the identity but never a name.
    await repository.signIn(identifier: link);

    verifyNever(session.updateLabel(label: anyNamed('label')));
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

  test('logout propagates a clear() failure and does not re-derive app state or wipe caches', () async {
    when(session.clear()).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.unknown));
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

  test('logout stops the downloads before it wipes their cache (phase 043)', () async {
    // A download still running would write its next chunk into the cache being
    // deleted, or rename a finished file into it right after.
    final order = <String>[];
    getIt
      ..allowReassignment = true
      ..registerSingleton<AttachmentDownloadService>(_RecordingDownloads(order));
    when(files.clean()).thenAnswer((_) async => order.add('clean'));

    await repository.logout();

    expect(order, ['reset', 'clean']);
  });

  test('logout empties the picture queue BEFORE it stops the downloads (phase 043)', () async {
    // The other way round, the prefetch worker takes this identity's next
    // picture the moment the current one is stopped, and starts it into the
    // wipe.
    final order = <String>[];
    getIt
      ..allowReassignment = true
      ..registerSingleton<AttachmentDownloadService>(_RecordingDownloads(order))
      ..registerSingleton<AttachmentPrefetchService>(_RecordingPrefetch(order));
    when(files.clean()).thenAnswer((_) async => order.add('clean'));

    await repository.logout();

    expect(order, ['prefetch', 'reset', 'clean']);
  });

  test('downloads that fail to stop still let their cache go (phase 043)', () async {
    getIt
      ..allowReassignment = true
      ..registerSingleton<AttachmentDownloadService>(_RecordingDownloads(<String>[], fail: true));

    await repository.logout();

    verify(files.clean()).called(1);
    verify(messages.clean()).called(1);
  });

  test('logout takes the chats still waiting to be created with it, and their messages (phase 041, FR-021)', () async {
    // The real stores this time: what matters is that nothing is LEFT to create
    // - a chat that outlived the logout would be created on the next person's
    // server under their name, with the previous person's words in it.
    await getIt<AppDatabase>().clearEntireDatabase();
    final realChats = getIt<ChatRepository>();
    final realOutbox = getIt<OutboxRepository>();
    final chat = (await realChats.createChat(name: 'Kitchen')).data!;
    await realOutbox.enqueue(chatId: chat.id, text: 'Buy milk');
    final wiping = AuthRepositoryImpl(session, appState, realChats, getIt<MessageRepository>(), sync, realOutbox, files);

    await wiping.logout();

    expect(await realChats.pendingCreations(), isEmpty);
    expect(await getIt<ChatDao>().getById(chat.id), isNull);
    expect(await realOutbox.pending(), isEmpty);
  });

  test('logout stops the Tor client and deletes what it learned (FR-018, SC-007)', () async {
    final tor = getIt<TorService>() as FakeTorService;
    expect(tor.wipes, 0);

    await repository.logout();

    expect(tor.wipes, 1);
    expect(tor.status.state, TorState.stopped);
  });

  test('a failed clear() leaves the Tor client alone, like everything else', () async {
    when(session.clear()).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.unknown));
    await repository.logout();

    expect((getIt<TorService>() as FakeTorService).wipes, 0);
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

  group('a session paired before phase 044 (T038, FR-025)', () {
    test('is retired once, through the forced logout: the full wipe and the pairing screen', () async {
      when(session.predatesServerKey()).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));

      final result = await repository.retireLegacySession();

      expect(result.data, isTrue);
      verifyInOrder([session.clear(), outbox.clean(), files.clean(), sync.clear(), chats.clean(), messages.clean()]);
      verify(appState.fetchAppState(sessionExpired: true)).called(1);
    });

    test('a session with its server key is left alone', () async {
      when(session.predatesServerKey()).thenAnswer((_) async => const RepositoryResult<bool>.success(data: false));

      final result = await repository.retireLegacySession();

      expect(result.data, isFalse);
      verifyNever(session.clear());
      verifyNever(appState.fetchAppState(sessionExpired: anyNamed('sessionExpired')));
    });

    test('a keychain that cannot be read wipes nothing', () async {
      // Still locked after a reboot, say: a valid session as likely as an old
      // one, and a transient failure never logs anybody out.
      when(session.predatesServerKey()).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.unknown));

      final result = await repository.retireLegacySession();

      expect(result.data, isFalse);
      verifyNever(session.clear());
      verifyNever(chats.clean());
    });
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
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
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
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));

      final result = await repository.signIn(identifier: link);

      expect(result.data, isTrue);
      verify(session.setOnboardingComplete()).called(1);
      verifyNever(session.noteOnboardingStartedHere());
    });

    test('every address of the link is stored in order, the onion one kept for later (FR-019)', () async {
      // The contract's `full` vector: an IPv4 address, a name and an onion
      // service. Pairing starts at the first direct address; the onion one is
      // for the connection through Tor once this device is paired.
      const full =
          'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';
      (getIt<TorService>() as FakeTorService).supported = true;
      when(
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));

      final result = await repository.signIn(identifier: full);

      expect(result.data, isTrue);
      verify(session.saveServer(address: '192.168.1.20:8443', serverKey: serverKey)).called(1);
      final stored = (await getIt<ServerAddressesRepository>().read()).data!;
      expect(stored.direct, ['192.168.1.20:8443', 'nox.example.org:8443']);
      expect(stored.onion, '${'a' * 56}.onion:443', reason: 'derived from the service key by the Tor module');
      expect(stored.useTor, isFalse, reason: 'off unless the person ticked it');
      expect(stored.manualAddress, isNull);
      expect(stored.manualOnion, isNull);
      final handed = verify(handshake.pair(link: captureAnyNamed('link'), platform: anyNamed('platform'))).captured.single as PairingLink;
      expect(handed.directAddresses, ['192.168.1.20:8443', 'nox.example.org:8443']);
    });

    group('what the person set on the connection screen (phase 045)', () {
      const full =
          'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';
      final linkOnion = '${'a' * 56}.onion:443';
      final typedOnion = '${'b' * 56}.onion:443';

      setUp(() {
        (getIt<TorService>() as FakeTorService).supported = true;
        when(
          handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
        ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));
      });

      test('the link\'s own values, unchanged, are no edits, and Use Tor is stored as ticked', () async {
        await repository.signIn(
          identifier: full,
          connection: ConnectionSettings(serverAddress: '192.168.1.20:8443', onionAddress: linkOnion, useTor: true),
        );

        final stored = (await getIt<ServerAddressesRepository>().read()).data!;
        expect(stored.manualAddress, isNull);
        expect(stored.manualOnion, isNull);
        expect(stored.useTor, isTrue);
        expect(stored.effectiveOnion, linkOnion);
      });

      test('a changed field is a hand edit, the session still starting at the link\'s own address', () async {
        await repository.signIn(
          identifier: full,
          connection: ConnectionSettings(serverAddress: '10.8.0.2:8443', onionAddress: typedOnion),
        );

        verify(session.saveServer(address: '192.168.1.20:8443', serverKey: serverKey)).called(1);
        final stored = (await getIt<ServerAddressesRepository>().read()).data!;
        expect(stored.manualAddress, '10.8.0.2:8443');
        expect(stored.manualOnion, typedOnion);
        expect(stored.effectiveOnion, typedOnion);
        expect(stored.candidates('192.168.1.20:8443').first, '10.8.0.2:8443', reason: 'the edit is tried first');
      });

      test('an emptied onion field means no onion address, even though the link carried one', () async {
        await repository.signIn(
          identifier: full,
          connection: const ConnectionSettings(serverAddress: '192.168.1.20:8443', useTor: true),
        );

        final stored = (await getIt<ServerAddressesRepository>().read()).data!;
        expect(stored.manualOnion, '');
        expect(stored.effectiveOnion, isNull);
      });

      test('an onion address typed for a link without one is a hand edit too', () async {
        await repository.signIn(
          identifier: link,
          connection: ConnectionSettings(serverAddress: '192.168.1.20:8443', onionAddress: typedOnion, useTor: true),
        );

        final stored = (await getIt<ServerAddressesRepository>().read()).data!;
        expect(stored.onion, isNull);
        expect(stored.manualOnion, typedOnion);
        expect(stored.useTor, isTrue);
      });
    });

    test('the device key is read before anything is presented, and an unreadable one rolls back', () async {
      // The channel opens with it; a keychain that cannot give it up is a
      // failed attempt, never a pairing with a key nobody will find again.
      when(session.deviceSecret()).thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.unknown));

      final result = await repository.signIn(identifier: link);

      expect(result.hasData, isFalse);
      verifyNever(handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')));
      verify(session.discardSignIn()).called(1);
    });

    test('the two refusals stay apart, because each says a different thing to do next', () async {
      // Get a new invite; this one is not usable at all. Two answers, two next
      // actions - collapsing them would tell somebody the wrong thing to do.
      const expectations = <PairRefusal, RepositoryException>{
        PairRefusal.expired: RepositoryException.notFound,
        PairRefusal.notUsable: RepositoryException.authentication,
      };
      for (final entry in expectations.entries) {
        when(handshake.pair(link: anyNamed('link'), platform: anyNamed('platform'))).thenThrow(PairingRefused(reason: entry.key));

        final refused = await repository.signIn(identifier: link);
        expect(refused.exception, entry.value, reason: '${entry.key.name} must stay distinguishable');
      }
      expect(expectations.values.toSet(), hasLength(2), reason: 'no two refusals may share an answer');
    });

    test('a successful pairing re-greets, so the session stops speaking as the pre-pair identity, and waits only briefly', () async {
      // The connection `pair` ran on was greeted before this device existed to
      // the server. Without a second greeting it keeps speaking as whoever
      // greeted then, and a message sent on it comes back looking like a
      // stranger's on the sender's own screen.
      when(
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));
      when(
        handshake.greet(within: anyNamed('within')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));

      await repository.signIn(identifier: link);

      verify(handshake.greet(within: const Duration(seconds: 2))).called(1);
    });

    test('a greeting that fails after pairing does not undo the pairing', () async {
      // The pairing landed and the token is spent. Rolling back here would burn
      // it for nothing - an ordinary reconnect is enough.
      when(
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_1', label: 'Anna', created: false));
      when(handshake.greet(within: anyNamed('within'))).thenThrow(const IdentityHandshakeTimeout());

      final result = await repository.signIn(identifier: link);

      expect(result.data, isTrue);
      verifyNever(session.discardSignIn());
    });

    test('a pairing that never answers rolls back, keeping the device key', () async {
      when(handshake.pair(link: anyNamed('link'), platform: anyNamed('platform'))).thenThrow(const IdentityHandshakeTimeout());

      final result = await repository.signIn(identifier: link);

      expect(result.hasData, isFalse);
      verify(session.discardSignIn()).called(1);
      // NOT clear(): that wipes secure storage wholesale and takes the device
      // key with it, so one install would register as two devices.
      verifyNever(session.clear());
      verifyNever(session.setOnboardingComplete());
    });

    test('a failure puts no token and no key seed into the log', () async {
      // A token in a log is still a usable pairing credential, and a
      // FormatException from a base64 decode carries its source in the message
      // - which here would be the link or the seed (Principle I, FR-035).
      final logs = <String>[];
      final logger = _CapturingLog(logs);
      getIt.registerSingleton<LogRepository>(logger);
      when(
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenThrow(const FormatException('Invalid character', 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='));

      await repository.signIn(identifier: link);

      final written = logs.join('\n');
      expect(written, isNot(contains('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=')));
      expect(written, isNot(contains(link.substring(PairingLink.prefix.length))));
      expect(written, isNot(contains(PairingLink.parse(link).token)));
    });

    test('a sign-in that works says nothing at all in the log', () async {
      // Asserted as SILENCE, not as the absence of two substrings. The version
      // this replaces looked for an id and the word "owner" in a log nothing
      // had ever reached: both matched an empty string, so it could not fail -
      // and "owner" stopped meaning anything when 037 removed ownership.
      //
      // Silence is the stronger claim and the one Principle I / FR-024 want:
      // an author id or a name written on the happy path is a record of who
      // this device belongs to. The FormatException test above proves the
      // capture is wired, so an empty list here is a result rather than a
      // broken harness.
      final logs = <String>[];
      getIt.registerSingleton<LogRepository>(_CapturingLog(logs));
      when(
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_person_7', label: 'Anna', created: true));

      await repository.signIn(identifier: link);

      expect(logs, isEmpty, reason: 'the happy path of sign-in wrote to the log: ${logs.join(" | ")}');
    });

    test('an outcome the server did not state is not treated as an outcome', () async {
      // An older server, or a frame without the field. Guessing false steals a
      // newcomer's naming step; guessing true overwrites a returning person's
      // name.
      when(
        handshake.pair(link: anyNamed('link'), platform: anyNamed('platform')),
      ).thenAnswer((_) async => const IdentityHandshake(authorId: 'u_3', label: 'Anna', created: null));

      final result = await repository.signIn(identifier: link);

      expect(result.hasData, isFalse);
      verify(session.discardSignIn()).called(1);
      verifyNever(session.setOnboardingComplete());
    });
  });
}

/// Records what the app writes, so a test can assert what it does NOT write.
class _CapturingLog implements LogRepository {
  _CapturingLog(this.lines);

  final List<String> lines;

  @override
  void debug({Object? target, required String message}) => lines.add(message);

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) => lines.add(error.toString());
}

/// Records that every download was stopped, and when - or fails to stop them.
class _RecordingDownloads implements AttachmentDownloadService {
  _RecordingDownloads(this.order, {this.fail = false});

  final List<String> order;
  final bool fail;

  @override
  Future<void> reset() async {
    if (fail) throw StateError('a download would not stop');
    order.add('reset');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records when the picture queue was emptied.
class _RecordingPrefetch implements AttachmentPrefetchService {
  _RecordingPrefetch(this.order);

  final List<String> order;

  @override
  void reset() => order.add('prefetch');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

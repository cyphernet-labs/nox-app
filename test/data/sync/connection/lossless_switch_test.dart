import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/real/real_message_remote_data_source.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/repository/chat/message_repository_impl.dart';
import 'package:nox_app/data/service/session_phase_service_impl.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_direct_prober.dart';

/// Twenty switches between the direct path and Tor, each with a message going
/// out and one coming in while the connection is being replaced (phase 040,
/// FR-004, SC-005). Nothing may be lost and nothing may arrive twice.
///
/// Everything on the client side is the real thing - socket, path selector,
/// journal applier, outgoing queue, message repository - over a server that
/// behaves like noxd where it matters here: replay from `since` (boundary
/// event included, as §3 permits), live events, and `message.send` that is
/// idempotent under its `client_message_id`.
const String _link = '10.0.0.5:9000';
final String _onion = '${'a' * 56}.onion:443';
const String _chat = 'c_1';

class _Network implements NetworkChangeService {
  final StreamController<void> changes = StreamController<void>.broadcast();

  @override
  Stream<void> watchChanges() => changes.stream;
}

class _Lifecycle implements AppLifecycleService {
  @override
  AppVisibility get visibility => AppVisibility.foreground;

  @override
  Stream<AppVisibility> watchVisibility() => const Stream<AppVisibility>.empty();
}

/// One connection, served by [_Server].
class _ServedSocket implements SocketConnection {
  _ServedSocket(this._server);

  final _Server _server;
  final StreamController<dynamic> _incoming = StreamController<dynamic>.broadcast();
  bool closed = false;

  @override
  Stream<dynamic> get frames => _incoming.stream;

  @override
  void add(String frame) {
    if (closed) return;
    _server.handle(this, jsonDecode(frame) as Map<String, dynamic>);
  }

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }

  void push(Map<String, dynamic> frame) {
    if (!closed) _incoming.add(jsonEncode(frame));
  }
}

class _Server implements SocketChannelFactory {
  final List<Map<String, dynamic>> journal = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> byKey = <String, Map<String, dynamic>>{};
  final Map<String, int> sends = <String, int>{};
  final List<Uri> dialled = <Uri>[];
  _ServedSocket? current;
  var _next = 0;

  int get head => journal.length;

  @override
  SocketConnection connect(Uri url) {
    dialled.add(url);
    final socket = _ServedSocket(this);
    current = socket;
    // The server speaks first (contract §2).
    scheduleMicrotask(
      () => socket.push({
        'srv': {'schema_max': 1, 'challenge': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='},
      }),
    );
    return socket;
  }

  void handle(_ServedSocket socket, Map<String, dynamic> frame) {
    final id = frame['id'];
    final data = frame['data'] as Map<String, dynamic>;
    switch (frame['cmd']) {
      case 'session.hello':
        final since = data['since'] as int?;
        socket.push({
          'id': id,
          'ok': true,
          'data': {
            'schema': 1,
            'cursor': head,
            'journal_id': 'j_test',
            'identity': {'id': 'u_me', 'label': 'Me'},
            'addresses': {
              'direct': [_link],
              'onion': _onion,
            },
          },
        });
        // From the cursor itself: the boundary event arrives twice, which the
        // contract allows and the client must absorb.
        if (since != null) {
          for (final event in journal.where((e) => (e['seq'] as int) >= max(1, since))) {
            socket.push(event);
          }
        }
      case 'message.send':
        final key = data['client_message_id'] as String;
        sends[key] = (sends[key] ?? 0) + 1;
        var message = byKey[key];
        if (message == null) {
          message = _message(text: (data['body'] as Map<String, dynamic>)['text'] as String, own: true, key: key);
          byKey[key] = message;
          _append(message);
        }
        final reply = message;
        // The answer takes a moment - long enough for a switch to land while it
        // is on the way, which is the case this test is about.
        Timer(
          const Duration(milliseconds: 15),
          () => socket.push({
            'id': id,
            'ok': true,
            'data': {'message': reply},
          }),
        );
      default:
        socket.push({'id': id, 'ok': true, 'data': const <String, dynamic>{}});
    }
  }

  /// A message from another device of the person, arriving now.
  void incoming(String text) => _append(_message(text: text, own: false));

  void _append(Map<String, dynamic> message) {
    final event = {'seq': head + 1, 'event': 'message.new', 'data': message..['seq'] = head + 1};
    journal.add(event);
    current?.push(event);
  }

  Map<String, dynamic> _message({required String text, required bool own, String? key}) => {
    'message_id': 'm_${++_next}',
    'seq': 0,
    'chat_id': _chat,
    'author_id': own ? 'u_me' : 'u_other',
    'author_label': own ? 'Me' : 'Other',
    'client_message_id': ?key,
    'sent_at': 1788000000 + _next,
    'body': {'type': 'text', 'text': text},
  };
}

void main() {
  late _Server server;
  late NoxSocketClient socket;
  late FakeDirectProber prober;
  late FakeTorService tor;
  late _Network network;
  late ConnectionPathSelector selector;
  late SyncService sync;
  late OutboxService outbox;

  Future<void> waitUntil(FutureOr<bool> Function() done, {required String reason}) async {
    for (var i = 0; i < 1000; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition never became true: $reason');
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    await getIt<ChatDao>().upsert(
      const ChatEntity(
        id: _chat,
        name: 'Notes',
        lastMessagePreview: '',
        lastMessageAt: '2026-01-01T00:00:00.000Z',
        unreadCount: 0,
        lastOpenedSeq: null,
      ),
    );

    server = _Server();
    socket = NoxSocketClient(server, getIt<SyncRepository>());
    prober = FakeDirectProber();
    tor = FakeTorService()..supported = true;
    network = _Network();
    await getIt<ServerAddressesRepository>().saveFromServer(direct: const [_link], onion: _onion);
    await getIt<AccessKeyRepository>().deviceKey();
    await getIt<AccessKeyRepository>().markRegistered(true);
    selector = ConnectionPathSelector.forTest(
      prober,
      tor,
      getIt<ServerAddressesRepository>(),
      getIt<AccessKeyRepository>(),
      network,
      _Lifecycle(),
      socket,
      recheckEvery: const Duration(hours: 1),
    )..begin(linkAddress: _link, serverKey: Uint8List(32), deviceSeed: Uint8List(32));
    sync = SyncService(
      socket,
      getIt<SyncRepository>(),
      getIt<ChatDao>(),
      getIt<MessageDao>(),
      getIt<ChatMapper>(),
      getIt<ChatWireMapper>(),
      getIt<MessageMapper>(),
      getIt<MessageWireMapper>(),
      getIt<OutboxRepository>(),
      getIt<ServerAddressesRepository>(),
    )..start();
    final messages = MessageRepositoryImpl(
      getIt<MessageDao>(),
      RealMessageRemoteDataSource(socket),
      getIt<MessageMapper>(),
      getIt<MessageWireMapper>(),
      getIt<ChatDao>(),
      getIt<SessionRepository>(),
    );
    outbox = OutboxService(
      getIt<OutboxRepository>(),
      messages,
      SocketSessionPhaseService(socket),
      getIt<FileRepository>(),
      getIt<AttachmentTransferService>(),
      getIt<ChatRepository>(),
    )..start();
  });

  tearDown(() async {
    await outbox.stop();
    await sync.stop();
    await socket.stop();
    await selector.end();
    await getIt.reset();
  });

  test('twenty switches lose nothing and deliver nothing twice (SC-005)', () async {
    await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
    await waitUntil(() => socket.currentPhase == SessionPhase.live, reason: 'first connection');
    expect(selector.currentPath, ConnectionPath.direct);

    const switches = 20;
    for (var i = 0; i < switches; i++) {
      final toTor = selector.currentPath == ConnectionPath.direct;
      final dialled = server.dialled.length;

      // A message goes out and its answer is still on the way...
      await getIt<OutboxRepository>().enqueue(chatId: _chat, text: 'out $i');
      unawaited(outbox.flush());
      await waitUntil(() => server.sends.length == i + 1, reason: 'send $i reached the server');
      // ...one comes in from another device...
      server.incoming('in $i');
      // ...and the network changes under both.
      prober.home = toTor ? <String>{} : null;
      network.changes.add(null);

      await waitUntil(() => server.dialled.length > dialled, reason: 'switch $i dialled');
      await waitUntil(
        () => socket.currentPhase == SessionPhase.live && selector.currentPath == (toTor ? ConnectionPath.tor : ConnectionPath.direct),
        reason: 'switch $i is live on the other path',
      );
    }

    // Everything settles.
    await waitUntil(() async => (await getIt<OutboxRepository>().pending()).isEmpty, reason: 'the queue drains');
    await waitUntil(() async => await getIt<SyncRepository>().getCursor() == server.head, reason: 'the journal is applied');

    // Each message went into the server's journal exactly once, whatever the
    // number of times its send was presented.
    final ownEvents = server.journal.where((e) => (e['data'] as Map<String, dynamic>)['author_id'] == 'u_me');
    expect(ownEvents, hasLength(switches));
    expect(server.byKey, hasLength(switches));

    // And locally: one row per message, no more.
    final stored = await getIt<MessageDao>().getByChatSorted(_chat);
    final texts = stored.map((m) => m.text).whereType<String>().toList()..sort();
    final expected = [
      for (var i = 0; i < switches; i++) ...['out $i', 'in $i'],
    ]..sort();
    expect(texts, expected, reason: 'every message once - none lost, none twice');

    // The switches really alternated between the two paths.
    final paths = server.dialled.map((u) => u.host.endsWith('.onion') ? 'tor' : 'direct').toList();
    expect(paths.first, 'direct');
    expect(paths.where((p) => p == 'tor').length, greaterThanOrEqualTo(switches ~/ 2));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

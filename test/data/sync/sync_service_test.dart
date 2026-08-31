import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/socket/fake_socket.dart';

/// Applying an event has to leave device-local state alone and move the cursor
/// only once the write succeeded — both are contract rules (§6, §9.4), and both
/// are invisible until something goes wrong in production.
void main() {
  late FakeSocketFactory factory;
  late NoxSocketClient socketClient;
  late SyncService service;
  late SyncRepository sync;
  late ChatDao chatDao;
  late MessageDao messageDao;

  /// Waits for a condition instead of a fixed pause: applies run through an
  /// async queue and several store writes, and a hard-coded delay is exactly
  /// the kind of test that passes on a quiet machine and flakes under load.
  Future<void> waitUntil(Future<bool> Function() done, {String reason = ''}) async {
    for (var i = 0; i < 200; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  Map<String, dynamic> chatFrame(String id, {String name = 'Live chat', int at = 1788000000}) => {
    'chat_id': id,
    'name': name,
    'created_at': at,
    'created_by_label': 'Anna',
    'last_message_preview': '',
    'last_activity_at': at,
  };

  Map<String, dynamic> messageFrame(String id, String chatId, {required int seq, String text = 'hi', int at = 1788000100}) => {
    'message_id': id,
    'seq': seq,
    'chat_id': chatId,
    'author_id': 'u_other',
    'author_label': 'Boris',
    'sent_at': at,
    'body': {'type': 'text', 'text': text},
  };

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    sync = getIt<SyncRepository>();
    chatDao = getIt<ChatDao>();
    messageDao = getIt<MessageDao>();
    factory = FakeSocketFactory();
    socketClient = NoxSocketClient(factory, sync);
    service = SyncService(
      socketClient,
      sync,
      chatDao,
      messageDao,
      getIt<ChatMapper>(),
      getIt<ChatWireMapper>(),
      getIt<MessageMapper>(),
      getIt<MessageWireMapper>(),
      getIt<OutboxRepository>(),
    );
    service.start();
  });

  tearDown(() async {
    await service.stop();
    await socketClient.stop();
    await getIt.reset();
  });

  Future<FakeSocket> connected({int cursor = 0}) async {
    await socketClient.start(url: Uri.parse('ws://127.0.0.1:8080/ws'));
    final socket = factory.latest;
    socket.pushGreeting();
    await settle();
    socket.replyToHello(cursor: cursor);
    await settle();
    return socket;
  }

  test('a new chat event lands in the store and the cursor follows it', () async {
    final socket = await connected();
    socket.pushEvent(seq: 5, event: 'chat.created', data: chatFrame('c_1'));
    await waitUntil(() async => await sync.getCursor() == 5, reason: 'the chat event is applied');

    expect((await chatDao.getById('c_1'))?.name, 'Live chat');
  });

  test('applying a chat event keeps the unread badge, which the wire does not carry', () async {
    await chatDao.upsert(
      const ChatEntity(id: 'c_1', name: 'Old name', lastMessagePreview: 'p', lastMessageAt: '2026-01-01T00:00:00.000Z', unreadCount: 7),
    );
    final socket = await connected();
    socket.pushEvent(
      seq: 6,
      event: 'chat.updated',
      data: chatFrame('c_1', name: 'Renamed'),
    );
    await settle();

    final stored = await chatDao.getById('c_1');
    expect(stored?.name, 'Renamed'); // the wire owns the name
    expect(stored?.unreadCount, 7); // the device owns the badge
  });

  test('an incoming message raises the chat row itself, because the server sends no chat.updated for it', () async {
    await chatDao.upsert(
      const ChatEntity(id: 'c_1', name: 'Chat', lastMessagePreview: '', lastMessageAt: '2026-01-01T00:00:00.000Z', unreadCount: 0),
    );
    final socket = await connected();
    socket.pushEvent(seq: 7, data: messageFrame('m_1', 'c_1', seq: 7, text: 'ping'));
    await waitUntil(() async => await messageDao.getById('m_1') != null);

    expect((await messageDao.getById('m_1'))?.text, 'ping');
    final chat = await chatDao.getById('c_1');
    expect(chat?.lastMessagePreview, contains('ping'));
    expect(chat?.unreadCount, 1);
  });

  test('a duplicate at the replay boundary is dropped instead of applied twice', () async {
    await chatDao.upsert(
      const ChatEntity(id: 'c_1', name: 'Chat', lastMessagePreview: '', lastMessageAt: '2026-01-01T00:00:00.000Z', unreadCount: 0),
    );
    final socket = await connected();
    socket.pushEvent(seq: 9, data: messageFrame('m_9', 'c_1', seq: 9));
    await settle();
    socket.pushEvent(seq: 9, data: messageFrame('m_9', 'c_1', seq: 9));
    await settle();

    // The unread bump is the observable: a second application would double it.
    expect((await chatDao.getById('c_1'))?.unreadCount, 1);
  });

  test('an echo does not erase the local file path of a message already stored', () async {
    await chatDao.upsert(
      const ChatEntity(id: 'c_1', name: 'Chat', lastMessagePreview: '', lastMessageAt: '2026-01-01T00:00:00.000Z', unreadCount: 0),
    );
    await messageDao.upsert(
      const MessageEntity(
        id: 'm_att',
        chatId: 'c_1',
        seq: 20,
        authorId: 'me',
        authorLabel: 'Me',
        text: null,
        sentAt: '2026-01-01T00:00:00.000Z',
        status: 'sent',
        isSystem: false,
        attachmentId: 'f_1',
        attachmentType: 'image',
        attachmentName: 'shot.png',
        attachmentSizeBytes: 10,
        attachmentLocalPath: '/tmp/shot.png',
      ),
    );
    final socket = await connected();
    socket.pushEvent(
      seq: 21,
      data: {
        ...messageFrame('m_att', 'c_1', seq: 21),
        'body': null,
        'attachment': {'file_id': 'f_1', 'name': 'shot.png', 'size': 10, 'mime': 'image/png', 'expires_at': 1900000000},
      },
    );
    await settle();

    // The wire has no localPath; losing it would break preview and save.
    expect((await messageDao.getById('m_att'))?.attachmentLocalPath, '/tmp/shot.png');
  });

  test('a failed apply halts the tail, and a fresh catch-up resumes it', () async {
    final socket = await connected(cursor: 0);
    // Close the database under the applier so the write fails for real.
    await getIt<AppDatabase>().clearEntireDatabase();
    await chatDao.upsert(
      const ChatEntity(id: 'c_1', name: 'Chat', lastMessagePreview: '', lastMessageAt: '2026-01-01T00:00:00.000Z', unreadCount: 0),
    );

    // A malformed payload fails to parse inside the apply.
    socket.pushEvent(seq: 30, data: const {'message_id': 'bad'});
    await settle();
    final afterFailure = await sync.getCursor();

    // The tail is held: a later event must NOT move the cursor past the gap,
    // or the failed one would never be redelivered.
    socket.pushEvent(seq: 31, data: messageFrame('m_31', 'c_1', seq: 31));
    await settle();
    expect(await sync.getCursor(), afterFailure);

    // A reconnect starts a new catch-up, which redelivers the gap — applying
    // has to resume, or one transient failure would silence the device forever.
    await socketClient.stop();
    final second = await connected(cursor: 0);
    second.pushEvent(seq: 31, data: messageFrame('m_31', 'c_1', seq: 31));
    await settle();
    expect(await sync.getCursor(), 31);
  });
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/outbox_dao.dart';
import 'package:nox_app/data/mapper/chat/outbox_mapper.dart';
import 'package:nox_app/data/remote/datasource/real/real_chat_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_message_remote_data_source.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/repository/chat/outbox_repository_impl.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the REAL outgoing queue against a running `noxd` — the live half of
/// feature 027's Definition of Done, which unit tests cannot answer because the
/// property under test belongs to the server: does a retry under the same key
/// produce ONE message.
///
/// Deliberately named without the `_test` suffix so the suite never collects
/// it. Run by hand, with the server up:
///
///   client_backend$ go build -o /tmp/noxd . && /tmp/noxd -addr 127.0.0.1:8080 -db /tmp/nox-live.db
///   fvm flutter test test/live/live_outbox_probe.dart
class _MemoryCursor implements SyncRepository {
  int _cursor = 0;
  String? _epoch;
  @override
  Future<int> getCursor() async => _cursor;
  @override
  Future<void> advanceCursor(int seq) async => _cursor = seq > _cursor ? seq : _cursor;
  @override
  Future<void> clear() async => _cursor = 0;
  @override
  Future<String?> getEpoch() async => _epoch;
  @override
  Future<void> setEpoch(String epoch) async => _epoch = epoch;
}

/// A phase the probe drives by hand, standing in for "the channel is up".
class _Phase implements SessionPhaseService {
  SessionPhase phaseValue = SessionPhase.disconnected;
  @override
  SessionPhase get phase => phaseValue;
  @override
  Stream<SessionPhase> watchPhase() => const Stream<SessionPhase>.empty();
}

/// The thin slice of MessageRepository the drain uses: send through the REAL
/// data source, and remember what came back so the probe can inspect it.
class _LiveSend implements MessageRepository {
  _LiveSend(this._remote);

  final RealMessageRemoteDataSource _remote;
  final List<MessageModel> accepted = <MessageModel>[];

  @override
  Future<RepositoryResult<MessageModel>> sendMessage({
    required String chatId,
    required String clientMessageId,
    String? text,
    dynamic attachment,
  }) async {
    final reply = await _remote.sendMessage(chatId: chatId, clientMessageId: clientMessageId, text: text);
    final data = reply.data;
    if (data == null) {
      return RepositoryResult<MessageModel>.error(exception: RepositoryException.fromWireCode(reply.error?.code ?? 'internal'));
    }
    final model = MessageModel(
      id: data.messageId,
      seq: data.seq,
      chatId: data.chatId,
      authorId: data.authorId,
      authorLabel: data.authorLabel,
      text: data.body?.text,
      sentAt: DateTime.fromMillisecondsSinceEpoch(data.sentAt * 1000),
    );
    accepted.add(model);
    return RepositoryResult<MessageModel>.success(data: model);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async => getIt.reset());

  test('a queued message survives a restart and arrives exactly once', () async {
    final socket = NoxSocketClient(WebSocketChannelFactory(), _MemoryCursor());
    addTearDown(socket.stop);
    await socket.start(url: Uri.parse('ws://127.0.0.1:8080/ws'), labelProvider: () async => 'OutboxProbe');
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(socket.identity, isNotNull, reason: 'the greeting must have been answered');

    final chats = RealChatRemoteDataSource(socket);
    final created = await chats.createChat(name: 'Outbox ${DateTime.now().microsecondsSinceEpoch}');
    expect(created.success, isTrue, reason: 'chat.create: ${created.error?.code}');
    final chatId = created.data!.chatId;

    // The store the queue lives in. One database, two "app runs" over it.
    final db = AppDatabaseTest();
    await db.clearEntireDatabase();
    final dao = OutboxDao(db);
    final mapper = OutboxMapper();

    // RUN 1 — the channel is down, so the message is only written, never sent.
    final firstRun = OutboxRepositoryImpl(dao, mapper) as OutboxRepository;
    final offlinePhase = _Phase();
    final sender = _LiveSend(RealMessageRemoteDataSource(socket));
    final firstDrain = OutboxService(firstRun, sender, offlinePhase);
    final queued = (await firstRun.enqueue(chatId: chatId, text: 'written before the restart')).data!;
    await firstDrain.flush();
    expect(sender.accepted, isEmpty, reason: 'nothing may go out while the channel is down');
    await firstDrain.stop();

    // RUN 2 — a fresh repository and drain over the SAME store: the closest a
    // probe gets to relaunching the app. The channel is up this time.
    final secondRun = OutboxRepositoryImpl(OutboxDao(db), OutboxMapper()) as OutboxRepository;
    final restored = await secondRun.pending();
    expect(restored, hasLength(1), reason: 'the queue survived the restart');
    expect(restored.single.clientMessageId, queued.clientMessageId, reason: 'and kept its idempotency key');

    final livePhase = _Phase()..phaseValue = SessionPhase.live;
    final secondSender = _LiveSend(RealMessageRemoteDataSource(socket));
    final secondDrain = OutboxService(secondRun, secondSender, livePhase);
    await secondDrain.flush();
    addTearDown(secondDrain.stop);

    expect(secondSender.accepted, hasLength(1), reason: 'the restart sent it');
    expect(await secondRun.pending(), isEmpty, reason: 'and the queue released it');

    // The server's half of the promise: the SAME key a third time returns the
    // same message rather than storing a second one.
    final again = await secondSender.sendMessage(
      chatId: chatId,
      clientMessageId: queued.clientMessageId,
      text: 'written before the restart',
    );
    expect(again.data!.id, secondSender.accepted.first.id, reason: 'idempotent: the original echo comes back');

    final history = await RealMessageRemoteDataSource(socket).getMessages(config: GetMessagesConfig.tail(chatId: chatId));
    final mine = history.data!.messages.where((m) => m.body?.text == 'written before the restart');
    expect(mine, hasLength(1), reason: 'exactly one copy on the server, after two sends of the same key');
  }, timeout: const Timeout(Duration(seconds: 40)));
}

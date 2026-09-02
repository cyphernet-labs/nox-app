import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nox_app/data/remote/datasource/real/real_chat_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_message_remote_data_source.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';

/// Drives the app's REAL transport and data sources against a running `noxd`.
///
/// Deliberately named without the `_test` suffix so the suite never collects it:
/// it needs a server, and the gate must stay runnable without one. Run it by
/// hand after starting the server:
///
///   client_backend$ go build -o /tmp/noxd . && /tmp/noxd -addr 127.0.0.1:8080 -db /tmp/nox-live.db
///   fvm flutter test test/live/live_exchange_probe.dart
///
/// It is the cheapest honest answer to "does the vertical actually work" —
/// the same classes the dev flavor resolves, no mocks anywhere.
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

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    // Only for the log channel the transport writes through; the data sources
    // under test are constructed by hand against the REAL socket.
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async => getIt.reset());

  test('the app stack exchanges messages with a live noxd', () async {
    final socket = NoxSocketClient(WebSocketChannelFactory(), _MemoryCursor());
    addTearDown(socket.stop);

    await socket.start(
      url: Uri.parse('ws://127.0.0.1:8080/ws'), // A probe names itself and nothing else: no login derivation, no device
      // id. That is deliberate - the contract forbids refusing such a greeting,
      // and it is exactly the shape this probe must keep working in.
      credentialsProvider: () async => const GreetingCredentials(label: 'AppProbe'),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(socket.identity, isNotNull, reason: 'the greeting must have been answered');
    expect(socket.limits, isNotNull);

    final chats = RealChatRemoteDataSource(socket);
    final created = await chats.createChat(name: 'Probe ${DateTime.now().microsecondsSinceEpoch}');
    expect(created.success, isTrue, reason: 'chat.create: ${created.error?.code}');
    final chatId = created.data!.chatId;

    final listed = await chats.getChats(config: GetChatsConfig.firstPage());
    expect(listed.data!.chats.any((c) => c.chatId == chatId), isTrue, reason: 'the created chat comes back in the list');

    final messages = RealMessageRemoteDataSource(socket);
    // Unique per run: the key is an IDEMPOTENCY key, so reusing a fixed one
    // across runs makes the server correctly return the first run's echo — with
    // the first run's chat, which then looks like a client bug and is not one.
    final key = 'probe-${DateTime.now().microsecondsSinceEpoch}';
    final sent = await messages.sendMessage(chatId: chatId, clientMessageId: key, text: 'sent from the app stack');
    expect(sent.success, isTrue, reason: 'message.send: ${sent.error?.code}');
    expect(sent.data!.body?.text, 'sent from the app stack');

    // The same key must not create a second copy — this is what makes a retry
    // after a lost reply safe.
    final resent = await messages.sendMessage(chatId: chatId, clientMessageId: key, text: 'sent from the app stack');
    expect(resent.data!.seq, sent.data!.seq, reason: 'idempotent resend returns the original echo');
    expect(resent.data!.messageId, sent.data!.messageId);

    final history = await messages.getMessages(config: GetMessagesConfig.tail(chatId: chatId));

    expect(history.data!.messages.map((m) => m.messageId), contains(sent.data!.messageId));

    // The server owns uniqueness: the name just created must read as taken.
    final availability = await chats.isNameAvailable(name: created.data!.name);
    expect(availability.data!.available, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

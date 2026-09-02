import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/datasource/real/real_chat_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_file_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_message_remote_data_source.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/repository/file/file_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the REAL file chain against a running `noxd` — the live half of
/// feature 028's Definition of Done.
///
/// The property that matters here belongs to the server and cannot be answered
/// by any mock: are the bytes that come back the bytes that went up. So this
/// compares them byte for byte.
///
/// Named without the `_test` suffix so the suite never collects it. Run by hand:
///
///   client_backend$ go build -o /tmp/noxd . && /tmp/noxd -addr 127.0.0.1:8080 -db /tmp/nox-live.db
///   fvm flutter test test/live/live_files_probe.dart
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
  @override
  Future<String?> getJournal() async => _journal;
  @override
  Future<void> setJournal(String journalId) async => _journal = journalId;

  String? _journal;
}

void main() {
  setUpAll(() async {
    // `flutter test` installs an HttpOverrides that answers 400 to every
    // request, so a test cannot reach the network by accident. This probe wants
    // to, on purpose — it is the only way to ask the server whether the bytes
    // that came back are the bytes that went up.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async => getIt.reset());

  test('a file goes up, a message names it, and the same bytes come back', () async {
    final socket = NoxSocketClient(WebSocketChannelFactory(), _MemoryCursor());
    addTearDown(socket.stop);
    await socket.start(
      url: Uri.parse('ws://127.0.0.1:8080/ws'), // A probe names itself and nothing else: no login derivation, no device
      // id. That is deliberate - the contract forbids refusing such a greeting,
      // and it is exactly the shape this probe must keep working in.
      credentialsProvider: () async => const GreetingCredentials(label: 'FilesProbe'),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(socket.identity, isNotNull, reason: 'the greeting must have been answered');

    // The one place both transports meet, wired the way the app wires it.
    final config = getIt<AppConfigRepository>();
    await config.initialize(flavorType: AppFlavorType.stage);
    // Wired exactly as the app wires it — through initBase(), not by setting
    // the base URL here. Doing it by hand is what let a build with no base URL
    // at all pass this probe: every transfer would have failed in the real app
    // and the probe would have been green.
    final api = ApiClient(config)..initBase();
    final files = FileRepositoryImpl(RealFileRemoteDataSource(socket, api), config);

    // Bytes that could not be mistaken for anything else.
    final random = Random(20280902);
    final payload = List<int>.generate(64 * 1024, (_) => random.nextInt(256));
    final source = File('${Directory.systemTemp.path}/nox_probe_${DateTime.now().microsecondsSinceEpoch}.bin')..writeAsBytesSync(payload);
    addTearDown(() => source.existsSync() ? source.deleteSync() : null);

    var lastFraction = 0.0;
    final uploaded = await files.upload(
      path: source.path,
      mime: 'application/octet-stream',
      onProgress: (fraction) => lastFraction = fraction,
    );
    expect(uploaded.hasData, isTrue, reason: 'upload: ${uploaded.exception}');
    expect(lastFraction, greaterThan(0), reason: 'the progress channel has to carry something real');
    final fileId = uploaded.data!;

    // A message may now name it — the step the whole chain exists to enable.
    final chats = RealChatRemoteDataSource(socket);
    final chat = await chats.createChat(name: 'Files ${DateTime.now().microsecondsSinceEpoch}');
    expect(chat.success, isTrue, reason: 'chat.create: ${chat.error?.code}');
    final chatId = chat.data!.chatId;

    final messages = RealMessageRemoteDataSource(socket);
    final sent = await messages.sendMessage(
      chatId: chatId,
      clientMessageId: 'files-probe-${DateTime.now().microsecondsSinceEpoch}',
      attachment: MessageAttachment(id: fileId, type: FileType.other, name: 'payload.bin', sizeBytes: payload.length),
    );
    expect(sent.success, isTrue, reason: 'message.send: ${sent.error?.code}');
    expect(sent.data!.attachment?.fileId, fileId, reason: 'the echo names the file we uploaded');
    expect(sent.data!.attachment?.size, payload.length);

    // And the recipient's half: the bytes come back.
    final fetched = await files.download(fileId: fileId, suggestedName: 'payload.bin');
    expect(fetched.hasData, isTrue, reason: 'download: ${fetched.exception}');
    final roundTripped = File(fetched.data!).readAsBytesSync();
    expect(roundTripped.length, payload.length);
    expect(roundTripped, payload, reason: 'the same bytes, or the chain is decorative');

    // The history carries the attachment, so a second device sees it too.
    final history = await messages.getMessages(config: GetMessagesConfig.tail(chatId: chatId));
    expect(history.data!.messages.any((m) => m.attachment?.fileId == fileId), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

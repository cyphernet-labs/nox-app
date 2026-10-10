@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/datasource/real/real_chat_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_file_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_message_remote_data_source.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/repository/file/file_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_target.dart';

/// The secure channel end to end (phase 044): the app's Dart code over the
/// native module built from this tree, against a `noxd` built from this tree,
/// with a fresh database - the link it prints, a pairing by it, the greeting,
/// a message, and a file up and down. Every connection is a channel: TCP,
/// TLS 1.3, then the Eidolon check of both keys.
///
/// It also measures what SC-006 asks of a channel at home - open in under a
/// second - and checks the refusal that matters most: a channel that expects
/// another server key never opens (SC-003, US2).
///
/// Manual, outside the gates - it needs the server and the new module:
///   (cd client_backend && go build -o /tmp/nox044/noxd . && \
///     /tmp/nox044/noxd -db /tmp/nox044/nox.db -addr 127.0.0.1:8443 -status-addr 127.0.0.1:8081)
///   fvm flutter test test/live/channel_probe.dart --dart-define=link=LINK   # the machine link on http://127.0.0.1:8081, or from `noxd link`
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    // Only for the log channel the transport writes through; everything under
    // test is constructed by hand over the real module.
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async => getIt.reset());

  test('a v3 link pairs over the channel, and messages and file bytes travel it', () async {
    LiveTarget.letTheNetworkThrough();
    final target = LiveTarget.orSkip();
    if (target == null) return;
    final home = Uri.parse('https://${target.address}');
    const api = NativeNoxChannelApi();

    // --- SC-006: a channel at home opens in under a second. ---
    // Measured on the second open: the first one in a process also builds the
    // module's runtime and TLS configuration, and the first load of a freshly
    // built library waits for the OS to scan it - neither is the channel.
    Future<int> openOnce() async {
      final watch = Stopwatch()..start();
      final channel = await api.open(
        DirectTarget(home.host, home.port),
        deviceSeed: target.deviceSeed,
        serverKey: target.link.serverKey,
        timeout: const Duration(seconds: 5),
      );
      final opened = watch.elapsedMilliseconds;
      channel.close();
      expect(await channel.closed, isNull, reason: 'closed by us, normally');
      return opened;
    }

    final first = await openOnce();
    final opened = await openOnce();
    stdout.writeln('MEASURE: a channel at home opened in $opened ms (the first in this process: $first ms)');
    expect(opened, lessThan(1000), reason: 'SC-006');

    // --- SC-003: a channel expecting another server key never opens. ---
    final stranger = Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    await expectLater(
      api.open(DirectTarget(home.host, home.port), deviceSeed: target.deviceSeed, serverKey: stranger, timeout: const Duration(seconds: 5)),
      throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.wrongServer)),
    );

    // --- Pairing by the link, then the greeting of a device the server has. ---
    final channels = target.client();
    final socket = NoxSocketClient(WebSocketChannelFactory(channels), _MemoryCursor());
    addTearDown(socket.stop);
    await target.pair(socket);
    await socket.start(url: target.socketUrl, credentialsProvider: () async => const GreetingCredentials());
    for (var i = 0; i < 50 && socket.identity == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(socket.identity, isNotNull, reason: 'session.hello answered for the key this channel proved');

    // --- A message. ---
    final chats = RealChatRemoteDataSource(socket);
    final chat = await chats.createChat(name: 'Channel ${DateTime.now().microsecondsSinceEpoch}');
    expect(chat.success, isTrue, reason: 'chat.create: ${chat.error?.code}');
    final messages = RealMessageRemoteDataSource(socket);
    final sent = await messages.sendMessage(
      chatId: chat.data!.chatId,
      clientMessageId: 'channel-probe-${DateTime.now().microsecondsSinceEpoch}',
      text: 'over the secure channel',
    );
    expect(sent.success, isTrue, reason: 'message.send: ${sent.error?.code}');

    // --- A file up and down, each on a channel of its own. ---
    final config = getIt<AppConfigRepository>();
    await config.initialize(flavorType: AppFlavorType.stage);
    final apiClient = ApiClient(config, channels)..initBase(address: target.restUrl);
    final files = FileRepositoryImpl(RealFileRemoteDataSource(socket, apiClient), config, getIt<DeviceVault>());
    final random = Random(20441009);
    final payload = List<int>.generate(3 * channelWindowBytes + 17, (_) => random.nextInt(256));
    final source = File('${Directory.systemTemp.path}/nox_channel_probe_${DateTime.now().microsecondsSinceEpoch}.bin')
      ..writeAsBytesSync(payload);
    addTearDown(() => source.existsSync() ? source.deleteSync() : null);
    final uploaded = await files.upload(path: source.path, mime: 'application/octet-stream');
    expect(uploaded.hasData, isTrue, reason: 'upload: ${uploaded.exception}');
    final withFile = await messages.sendMessage(
      chatId: chat.data!.chatId,
      clientMessageId: 'channel-probe-file-${DateTime.now().microsecondsSinceEpoch}',
      attachment: MessageAttachment(id: uploaded.data!, type: FileType.other, name: 'payload.bin', sizeBytes: payload.length),
    );
    expect(withFile.success, isTrue, reason: 'message.send with the file: ${withFile.error?.code}');
    final fetched = await files.download(fileId: uploaded.data!, suggestedName: 'payload.bin');
    expect(fetched.hasData, isTrue, reason: 'download: ${fetched.exception}');
    expect(File(fetched.data!).readAsBytesSync(), payload, reason: 'the same bytes back');
    channels.unbind();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _MemoryCursor implements SyncRepository {
  int _cursor = 0;
  bool _stored = false;
  String? _epoch;
  String? _journal;

  @override
  Future<int> getCursor() async => _cursor;

  @override
  Future<bool> hasCursor() async => _stored;

  @override
  Future<void> advanceCursor(int seq) async {
    _stored = true;
    _cursor = seq > _cursor ? seq : _cursor;
  }

  @override
  Future<void> clear() async {
    _stored = false;
    _cursor = 0;
  }

  @override
  Future<String?> getEpoch() async => _epoch;

  @override
  Future<void> setEpoch(String epoch) async => _epoch = epoch;

  @override
  Future<String?> getJournal() async => _journal;

  @override
  Future<void> setJournal(String journalId) async => _journal = journalId;
}

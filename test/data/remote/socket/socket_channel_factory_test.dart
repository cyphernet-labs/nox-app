import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/channel/channel_failure.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

import '../channel/fake_channel.dart';

class _SilentLog implements LogRepository {
  @override
  void debug({Object? target, required String message}) {}

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) {}
}

/// The real WebSocket over the channel client: what is handed to a connection
/// before its channel is verified, and what becomes of it.
void main() {
  final serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
  final deviceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));
  HttpOverrides? saved;

  setUp(() {
    getIt.allowReassignment = true;
    getIt.registerSingleton<LogRepository>(_SilentLog());
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });

  tearDown(() async {
    HttpOverrides.global = saved;
    await getIt.reset();
  });

  test('a token handed to a connection whose server proves another key never leaves the device (SC-003)', () async {
    final api = ScriptedChannelApi()..answer = (_) => throw const ChannelOpenException(ChannelFailure.wrongServer);
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    final connection = WebSocketChannelFactory(channels).connect(Uri.parse('wss://192.168.1.20:8443/ws'));
    // Handed over the moment the connection exists, as `pair` is.
    connection.add('{"id":1,"cmd":"pair","data":{"token":"AAECAwQFBgcICQoLDA0ODw"}}');

    final errors = <Object>[];
    await connection.frames.handleError(errors.add).drain<void>();

    expect(channelFailureOf(errors.single), ChannelFailure.wrongServer);
    // The only channel ever asked for was refused before it existed: there
    // was nothing the frame could have been written to.
    expect(api.calls, hasLength(1));
    await connection.close();
    channels.unbind();
  });

  test('a frame handed over before the channel opens goes out once it has, and not before', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      ws.listen(ws.add, onDone: ws.close);
    });
    final api = LoopbackChannelApi(server.port);
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    final connection = WebSocketChannelFactory(channels).connect(Uri.parse('wss://192.168.1.20:8443/ws'));
    final echoed = connection.frames.first;
    connection.add('{"id":1,"cmd":"session.hello"}');

    expect(await echoed, '{"id":1,"cmd":"session.hello"}');
    await connection.close();
    channels.unbind();
  });

  test('closing a dial still under way returns at once, and the dial failing later raises nothing', () async {
    // The channel's own close follows the dial, and one that then fails never
    // completes it: awaited, that wedged a reconnect, a logout half-way
    // through its wipe and a failed sign-in's rollback.
    final api = ScriptedChannelApi();
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    final errors = <Object>[];
    final finished = Completer<void>();
    // Not awaited itself: an error inside the zone never completes the
    // zone's own future, so the end is signalled from within.
    runZonedGuarded(() async {
      try {
        final connection = WebSocketChannelFactory(channels).connect(Uri.parse('wss://192.168.1.20:8443/ws'));
        connection.frames.listen((_) {}, onError: (Object _) {});
        while (api.calls.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        connection.add('{"cmd":"pair"}');

        await connection.close().timeout(const Duration(seconds: 1));

        // The module gives up on the open after the app did.
        api.calls.single.result.completeError(const ChannelOpenException(ChannelFailure.network));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } finally {
        finished.complete();
      }
    }, (error, _) => errors.add(error));
    await finished.future;

    expect(errors, isEmpty);
    channels.unbind();
  });

  test('a dial abandoned before it opened sends nothing once it does', () async {
    // The WebSocket flushes what it was handed as soon as the upgrade
    // completes, close or no close: a pairing token given to a dial the app
    // had already given up on reached the server behind its back.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final asked = Completer<void>();
    final upgrade = Completer<void>();
    final received = <Object?>[];
    var upgraded = false;
    server.listen((request) async {
      if (!asked.isCompleted) asked.complete();
      await upgrade.future;
      final socket = await WebSocketTransformer.upgrade(request);
      upgraded = true;
      socket.listen(received.add, onError: (Object _) {});
    });
    final channels = ChannelHttpClient(LoopbackChannelApi(server.port))..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    final connection = WebSocketChannelFactory(channels).connect(Uri.parse('wss://192.168.1.20:8443/ws'));
    connection.frames.listen((_) {}, onError: (Object _) {});
    connection.add('{"cmd":"pair"}');
    // The channel is open and the upgrade asked for: the WebSocket is not.
    await asked.future.timeout(const Duration(seconds: 5));

    await connection.close().timeout(const Duration(seconds: 1));
    upgrade.complete();
    for (var i = 0; i < 100 && !upgraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(upgraded, isTrue, reason: 'the dial did complete');
    expect(received, isEmpty, reason: 'nothing it was handed went out');
    channels.unbind();
  });

  test('a dial bounds the connect of the socket client itself, so a give-up reaches the module', () {
    final channels = ChannelHttpClient(ScriptedChannelApi())..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    final factory = WebSocketChannelFactory(channels);

    unawaited(factory.connect(Uri.parse('wss://192.168.1.20:8443/ws')).close());
    expect(channels.client.connectionTimeout, WebSocketChannelFactory.directConnectTimeout);

    unawaited(factory.connect(Uri.parse('wss://${'a' * 56}.onion/ws')).close());
    expect(channels.client.connectionTimeout, WebSocketChannelFactory.onionConnectTimeout);
    channels.unbind();
  });
}

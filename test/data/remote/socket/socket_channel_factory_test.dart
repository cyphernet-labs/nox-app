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

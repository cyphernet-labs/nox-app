import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/channel/channel_failure.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_tor/channel.dart';
import 'package:web_socket_channel/io.dart';

import 'fake_channel.dart';

class _RecordingLog implements LogRepository {
  final List<String> lines = <String>[];

  @override
  void debug({Object? target, required String message}) => lines.add(message);

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) => lines.add('$error');
}

const String _onionHost = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd.onion';

/// The one place a connection to the server is opened: both transports go
/// through it, every open names the bound keys, and what it hands `HttpClient`
/// carries real HTTP and WebSocket traffic.
void main() {
  final serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
  final deviceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));
  late _RecordingLog log;
  HttpOverrides? saved;

  setUp(() {
    log = _RecordingLog();
    getIt.allowReassignment = true;
    getIt.registerSingleton<LogRepository>(log);
    // `flutter test` installs HttpOverrides that answer 400 to every request
    // without a connection ever being made; this client must make its own.
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });

  tearDown(() async {
    HttpOverrides.global = saved;
    await getIt.reset();
  });

  test('without a binding an open fails at once, and the module is never asked', () async {
    final api = ScriptedChannelApi();
    final channels = ChannelHttpClient(api);
    await expectLater(channels.transferClient.getUrl(Uri.parse('https://10.0.0.5:8443/files/x')), throwsA(isA<SocketException>()));
    expect(api.calls, isEmpty);
  });

  test('an onion host is opened through Tor, anything else at its address', () {
    expect(ChannelHttpClient.targetFor(Uri.parse('wss://10.0.0.5:8443/ws')), const DirectTarget('10.0.0.5', 8443));
    expect(ChannelHttpClient.targetFor(Uri.parse('wss://[fe80::1]:8443/ws')), const DirectTarget('fe80::1', 8443));
    expect(ChannelHttpClient.targetFor(Uri.parse('https://nox.example.org/files/x')), const DirectTarget('nox.example.org', 443));
    expect(ChannelHttpClient.targetFor(Uri.parse('wss://$_onionHost/ws')), const OnionTarget(_onionHost));
  });

  test('every open carries the bound keys and the path budget', () async {
    final api = ScriptedChannelApi();
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    unawaited(channels.client.getUrl(Uri.parse('https://10.0.0.5:8443/ws')).then((_) {}, onError: (Object _) {}));
    unawaited(channels.client.getUrl(Uri.parse('https://$_onionHost/ws')).then((_) {}, onError: (Object _) {}));
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, hasLength(2));
    expect(api.calls[0].serverKey, serverKey);
    expect(api.calls[0].deviceSeed, deviceSeed);
    expect(api.calls[0].timeout, ChannelHttpClient.directOpenTimeout);
    expect(api.calls[1].target, const OnionTarget(_onionHost));
    expect(api.calls[1].timeout, ChannelHttpClient.onionOpenTimeout);
    channels.unbind();
  });

  test('a refusal reaches the caller as the channel failure, through every envelope', () async {
    final api = ScriptedChannelApi()..answer = (_) => throw const ChannelOpenException(ChannelFailure.wrongServer);
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);

    Object? plain;
    try {
      await channels.client.getUrl(Uri.parse('https://10.0.0.5:8443/'));
    } on Object catch (e) {
      plain = e;
    }
    expect(channelFailureOf(plain), ChannelFailure.wrongServer);

    final socket = IOWebSocketChannel.connect(Uri.parse('wss://10.0.0.5:8443/ws'), customClient: channels.client);
    Object? ws;
    try {
      await socket.ready;
    } on Object catch (e) {
      ws = e;
    }
    expect(channelFailureOf(ws), ChannelFailure.wrongServer, reason: 'unwrapped from WebSocketChannelException.inner');

    final dio = Dio()..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => channels.transferClient);
    Object? viaDio;
    try {
      await dio.get<void>('https://10.0.0.5:8443/files/x');
    } on Object catch (e) {
      viaDio = e;
    }
    expect(viaDio, isA<DioException>());
    expect(channelFailureOf(viaDio), ChannelFailure.wrongServer, reason: 'unwrapped from DioException.error');
    expect(channelFailureOf(const SocketException('down')), isNull);
  });

  test('a connect the pool gives up on is cancelled in the module, and a late channel is closed on arrival', () async {
    final api = ScriptedChannelApi();
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    channels.client.connectionTimeout = const Duration(milliseconds: 50);
    await expectLater(channels.client.getUrl(Uri.parse('https://10.0.0.5:8443/ws')), throwsA(isA<SocketException>()));
    final call = api.calls.single;
    expect(call.cancelled, isTrue, reason: 'the cancel reaches the open');
    final late = FakeNoxChannel();
    call.result.complete(late);
    await Future<void>.delayed(Duration.zero);
    expect(late.closeCalls, 1);
    channels.unbind();
  });

  test('a new binding drops the pooled clients, the same one keeps them, and after unbinding nothing opens', () async {
    final api = ScriptedChannelApi();
    final channels = ChannelHttpClient(api);
    var discarded = 0;
    channels.onDiscarded = () => discarded++;
    channels.bind(serverKey: serverKey, deviceSeed: deviceSeed);
    final first = channels.client;
    channels.bind(serverKey: Uint8List.fromList(serverKey), deviceSeed: Uint8List.fromList(deviceSeed));
    expect(identical(channels.client, first), isTrue);
    expect(discarded, 1);
    channels.bind(serverKey: Uint8List(32), deviceSeed: deviceSeed);
    expect(identical(channels.client, first), isFalse, reason: 'another server');
    expect(discarded, 2);
    channels.unbind();
    expect(channels.boundServerKey, isNull);
    await expectLater(channels.client.getUrl(Uri.parse('https://10.0.0.5:8443/')), throwsA(isA<SocketException>()));
  });

  test('unbinding ends the opens under way on both clients, and a channel that opens anyway is closed on arrival', () async {
    // A logout: the person's server is nobody this install may reach now, an
    // open still running included.
    final api = ScriptedChannelApi();
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    // Each outcome taken as it comes, so a request failing early is no
    // unhandled error.
    final requests = [
      channels.client.getUrl(Uri.parse('https://10.0.0.5:8443/ws')),
      channels.transferClient.getUrl(Uri.parse('https://10.0.0.5:8443/files/x')),
    ].map((request) => request.then<Object?>((_) => null, onError: (Object error) => error)).toList();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, hasLength(2), reason: 'both opens are under way in the module');

    channels.unbind();
    await Future<void>.delayed(Duration.zero);

    for (final call in api.calls) {
      expect(call.cancelled, isTrue, reason: 'the cancel reaches every open');
    }
    final late = [FakeNoxChannel(), FakeNoxChannel()];
    for (var i = 0; i < late.length; i++) {
      api.calls[i].result.complete(late[i]);
    }
    expect(await Future.wait(requests), everyElement(isA<SocketException>()));
    expect([for (final channel in late) channel.closeCalls], [1, 1], reason: 'a channel opened after the cancel is closed on arrival');
  });

  test('the log names the path and the outcome - never an onion host or a key', () async {
    final api = ScriptedChannelApi()..answer = (_) => throw const ChannelOpenException(ChannelFailure.torOnionNotFound);
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    await expectLater(channels.client.getUrl(Uri.parse('https://$_onionHost/ws')), throwsA(isA<ChannelOpenException>()));
    final line = log.lines.singleWhere((l) => l.startsWith('channel:'));
    expect(line, contains('onion'));
    expect(line, contains('torOnionNotFound'));
    expect(line, isNot(contains('abcdefgh')));
    expect(line, isNot(contains(base64.encode(serverKey))));
    channels.unbind();
  });

  group('over a real HTTP server', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final ws = await WebSocketTransformer.upgrade(request);
          ws.listen(ws.add, onDone: ws.close);
          return;
        }
        final body = await request.fold<int>(0, (n, chunk) => n + chunk.length);
        request.response.write('${request.method} ${request.uri.path} $body');
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('a request and its answer travel the channel', () async {
      final api = LoopbackChannelApi(server.port);
      final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
      final request = await channels.transferClient.getUrl(Uri.parse('https://192.168.1.20:8443/health'));
      final response = await request.close();
      expect(await utf8.decodeStream(response), 'GET /health 0');
      expect(api.targets.single, const DirectTarget('192.168.1.20', 8443));
      channels.unbind();
    });

    test('a body larger than the window is written through addStream, held to the window, and arrives whole', () async {
      // Paced, so the queue outgrows the window and the writer is held back.
      final api = LoopbackChannelApi(server.port, 16 * 1024 * 1024);
      final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
      final dio = Dio()..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => channels.transferClient);
      final size = 3 * channelWindowBytes + 17;
      final response = await dio.put<String>(
        'https://192.168.1.20:8443/files/token',
        data: Stream<List<int>>.fromIterable([for (var i = 0; i < 4; i++) Uint8List(i < 3 ? channelWindowBytes : 17)]),
        options: Options(headers: {Headers.contentLengthHeader: size}, responseType: ResponseType.plain),
      );
      expect(response.data, 'PUT /files/token $size');
      final peak = api.opened.single.peakQueued;
      expect(peak, greaterThan(channelWindowBytes), reason: 'the queue did outgrow the window');
      expect(peak, lessThanOrEqualTo(2 * channelWindowBytes), reason: 'by one write at most: the source was paused');
      channels.unbind();
    });

    test('a WebSocket runs over the channel both ways', () async {
      final api = LoopbackChannelApi(server.port);
      final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
      final socket = IOWebSocketChannel.connect(Uri.parse('wss://192.168.1.20:8443/ws'), customClient: channels.client);
      await socket.ready;
      final echoed = socket.stream.first;
      socket.sink.add('{"cmd":"session.hello"}');
      expect(await echoed, '{"cmd":"session.hello"}');
      await socket.sink.close();
      channels.unbind();
    });
  });
}

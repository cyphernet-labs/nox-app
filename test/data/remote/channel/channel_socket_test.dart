import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/channel/channel_socket.dart';
import 'package:nox_tor/channel.dart';

import 'fake_channel.dart';

/// `ChannelSocket` over a scripted channel: the socket contract `HttpClient`
/// and `WebSocket` rely on - writes, the window, flush, the two ways to end,
/// and what a failing channel looks like from above.
void main() {
  late FakeNoxChannel channel;
  late ChannelSocket socket;

  setUp(() {
    channel = FakeNoxChannel();
    socket = ChannelSocket(channel, remoteAddress: InternetAddress('10.0.0.5'), remotePort: 8443);
  });

  Future<void> turn() => Future<void>.delayed(Duration.zero);

  group('writing', () {
    test('add and the write helpers reach the channel, encoded', () {
      socket.add(utf8.encode('GET '));
      socket.write('/ws');
      socket.writeln(' HTTP/1.1');
      socket.writeAll(['a', 'b'], ',');
      socket.writeCharCode(0x21);
      expect(utf8.decode(channel.writtenBytes), 'GET /ws HTTP/1.1\na,b!');
    });

    test('addStream writes every chunk and completes when its source does', () async {
      final source = StreamController<List<int>>();
      final adding = socket.addStream(source.stream);
      source
        ..add([1, 2, 3])
        ..add([4]);
      await source.close();
      await adding;
      expect(channel.writtenBytes, [1, 2, 3, 4]);
      // The sink is free again.
      socket.add([5]);
      expect(channel.writtenBytes.last, 5);
    });

    test('a queue past the window pauses the source until the channel has room again', () async {
      var paused = 0;
      var resumed = 0;
      final source = StreamController<List<int>>(onPause: () => paused++, onResume: () => resumed++);
      final adding = socket.addStream(source.stream);
      source.add(Uint8List(channelWindowBytes + 1));
      await turn();
      expect(paused, 1, reason: 'more than a window is queued');
      expect(resumed, 0);
      channel.drain();
      await turn();
      expect(resumed, 1, reason: 'the channel said it can take more');
      await source.close();
      await adding;
    });

    test('a queue within the window never pauses the source', () async {
      var paused = 0;
      final source = StreamController<List<int>>(onPause: () => paused++);
      final adding = socket.addStream(source.stream);
      source.add(Uint8List(channelWindowBytes));
      await turn();
      expect(paused, 0);
      await source.close();
      await adding;
    });

    test('add and flush are refused while a stream is bound, as any IOSink refuses them', () async {
      final source = StreamController<List<int>>();
      final adding = socket.addStream(source.stream);
      expect(() => socket.add([1]), throwsStateError);
      expect(() => socket.flush(), throwsStateError);
      await source.close();
      await adding;
    });

    test('flush waits for the channel to drain', () async {
      socket.add([1]);
      var flushed = false;
      final flushing = socket.flush().then((_) => flushed = true);
      await turn();
      expect(flushed, isFalse);
      channel.drain();
      await flushing;
      expect(flushed, isTrue);
    });

    test('a flush the channel cannot finish fails as a socket error', () async {
      socket.add([1]);
      final flushing = socket.flush();
      channel.fail(ChannelFailure.network);
      await expectLater(flushing, throwsA(isA<SocketException>()));
    });
  });

  group('reading', () {
    test('what the server sends is delivered, and its end of sending ends the stream', () async {
      final got = <int>[];
      final ended = Completer<void>();
      socket.listen(got.addAll, onDone: ended.complete);
      channel
        ..receive([1, 2])
        ..receive([3]);
      channel.eof();
      await ended.future;
      expect(got, [1, 2, 3]);
    });

    test('pausing the socket pauses the channel, and the module with it', () async {
      final sub = socket.listen((_) {});
      await turn();
      expect(channel.readerPaused, isFalse);
      sub.pause();
      await turn();
      expect(channel.readerPaused, isTrue, reason: 'a paused reader is what stops the acknowledgements');
      sub.resume();
      await turn();
      expect(channel.readerPaused, isFalse);
      await sub.cancel();
    });

    test('a channel that fails reads as a SocketException - the type the HTTP stack expects', () async {
      final errors = <Object>[];
      final ended = Completer<void>();
      socket.listen((_) {}, onError: errors.add, onDone: ended.complete);
      channel.fail(ChannelFailure.network);
      await ended.future;
      expect(errors.single, isA<SocketException>());
    });
  });

  group('ending', () {
    test('close shuts the sending side, and later writes are refused', () async {
      await socket.close();
      expect(channel.shutDown, isTrue);
      expect(() => socket.add([1]), throwsStateError);
      expect(await socket.done, same(socket));
    });

    test('once both sides are done the channel is let go', () async {
      final ended = Completer<void>();
      socket.listen((_) {}, onDone: ended.complete);
      await socket.close();
      expect(channel.closeCalls, 0, reason: 'the server has not finished sending');
      channel.eof();
      await ended.future;
      channel.drain();
      await turn();
      expect(channel.closeCalls, 1);
    });

    test('after the server ended its side, what close() queued goes out before the channel is let go', () async {
      // A channel's close drops its queue: let go at once, the request written
      // after the server's end of sending never left.
      final ended = Completer<void>();
      socket.listen((_) {}, onDone: ended.complete);
      channel.eof();
      await ended.future;
      socket.add([1, 2, 3]);

      await socket.close();
      await turn();

      expect(channel.writtenBytes, [1, 2, 3]);
      expect(channel.shutDown, isTrue);
      expect(channel.pendingFlushes, 1, reason: 'the queue is waited for');
      expect(channel.closeCalls, 0, reason: 'cut before the queue went out');
      channel.drain();
      await turn();
      expect(channel.closeCalls, 1, reason: 'let go once the queue is out');
    });

    // A widget test for its fake clock alone: the bound is seconds long.
    testWidgets('a queue that never drains holds the channel no longer than its bound', (tester) async {
      final stuck = FakeNoxChannel();
      final closing = ChannelSocket(stuck);
      closing.listen((_) {});
      stuck.eof();
      await tester.pump();
      closing.add([1]);
      await closing.close();

      await tester.pump(const Duration(seconds: 4));
      expect(stuck.closeCalls, 0, reason: 'still waiting for the queue');
      await tester.pump(const Duration(seconds: 2));
      expect(stuck.closeCalls, 1, reason: 'a server that stopped reading held the channel for good');
    });

    test('destroy closes the channel and ends a stream still being written', () async {
      var cancelled = false;
      final source = StreamController<List<int>>(onCancel: () => cancelled = true);
      final adding = socket.addStream(source.stream);
      source.add([1]);
      await turn();
      socket.destroy();
      await adding;
      expect(channel.closeCalls, 1);
      expect(cancelled, isTrue, reason: 'the body stops being read');
      // Writes after a destroy go nowhere, as on a reset socket.
      socket.add([2]);
      expect(channel.writtenBytes, [1]);
    });

    test('a channel that fails under a body stops the body and fails its write', () async {
      var cancelled = false;
      final source = StreamController<List<int>>(onCancel: () => cancelled = true);
      final adding = socket.addStream(source.stream);
      source.add([1]);
      await turn();
      channel.fail(ChannelFailure.network);
      await expectLater(adding, throwsA(isA<SocketException>()));
      expect(cancelled, isTrue, reason: 'a large file is not read to the end into a channel that is gone');
      await expectLater(socket.done, throwsA(isA<SocketException>()));
    });

    test('a channel that closes normally completes done without an error', () async {
      channel.close();
      expect(await socket.done, same(socket));
    });
  });

  test('the transport is the module own: options are accepted and the addresses are placeholders', () {
    expect(socket.setOption(SocketOption.tcpNoDelay, true), isTrue);
    expect(socket.address.type, isNot(InternetAddressType.unix), reason: 'HttpClient sets TCP_NODELAY on anything else');
    expect(socket.port, 0);
    expect(socket.remoteAddress, InternetAddress('10.0.0.5'));
    expect(socket.remotePort, 8443);
    expect(ChannelSocket(FakeNoxChannel()).remoteAddress, InternetAddress.anyIPv4, reason: 'a name or an onion address is never exposed');
  });
}

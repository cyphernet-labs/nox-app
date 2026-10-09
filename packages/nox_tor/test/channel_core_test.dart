import 'dart:async';
import 'dart:typed_data';

import 'package:nox_tor/channel.dart';
import 'package:nox_tor/src/channel_core.dart';
import 'package:test/test.dart';

/// The module as the test scripts it: every call recorded, every answer chosen.
class _FakeAbi implements ChannelAbi {
  int nextHandle = 1;
  int? refuseOpenWith;
  final List<({int kind, String host, int port, Uint8List seed, Uint8List key, int timeoutMs})> opens = [];
  final List<({int handle, int length})> acks = [];
  final List<({int handle, int ticket})> flushes = [];
  final List<int> shutdowns = <int>[];
  final List<int> closes = <int>[];
  final List<Uint8List> written = <Uint8List>[];

  /// What every write answers: the queue's size after it.
  int queueAfterWrite = 0;

  @override
  int open(int targetKind, String host, int port, Uint8List deviceSeed, Uint8List serverKey, int timeoutMs) {
    opens.add((
      kind: targetKind,
      host: host,
      port: port,
      seed: Uint8List.fromList(deviceSeed),
      key: Uint8List.fromList(serverKey),
      timeoutMs: timeoutMs,
    ));
    return refuseOpenWith ?? nextHandle++;
  }

  @override
  int write(int handle, Uint8List bytes) {
    written.add(Uint8List.fromList(bytes));
    return queueAfterWrite;
  }

  @override
  int ack(int handle, int length) {
    acks.add((handle: handle, length: length));
    return 0;
  }

  @override
  int flush(int handle, int ticket) {
    flushes.add((handle: handle, ticket: ticket));
    return 0;
  }

  @override
  int shutdownWrite(int handle) {
    shutdowns.add(handle);
    return 0;
  }

  @override
  int close(int handle) {
    closes.add(handle);
    return 0;
  }

  int ackedBytes(int handle) => acks.where((a) => a.handle == handle).fold(0, (sum, a) => sum + a.length);
}

/// The channel's event machine over a scripted module (phase 044,
/// contracts/ffi-channel.md): what Dart does with each event, what it
/// acknowledges and when, and how an open ends - none of it needs the
/// library, so all of it is pinned here.
void main() {
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final key = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
  const home = DirectTarget('192.168.1.20', 8443);
  late _FakeAbi abi;
  late ChannelCore core;

  setUp(() {
    abi = _FakeAbi();
    core = ChannelCore(abi, openGrace: const Duration(milliseconds: 100));
  });

  Future<void> turn() => Future<void>.delayed(Duration.zero);

  Uint8List bytes(int length, [int fill = 1]) => Uint8List(length)..fillRange(0, length, fill);

  /// Opens a channel and verifies it, as the module would.
  Future<NoxChannel> opened({ChannelTarget target = home}) async {
    final opening = core.open(target, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30));
    core.deliver(abi.nextHandle - 1, ChannelEvent.open, Uint8List.fromList(key), 0);
    return opening;
  }

  group('opening', () {
    test('the module is asked with the target, both keys and the timeout, and OPEN with the right key hands the channel over', () async {
      final channel = await opened();

      expect(channel, isA<NoxChannel>());
      final call = abi.opens.single;
      expect(call.kind, 0);
      expect(call.host, '192.168.1.20');
      expect(call.port, 8443);
      expect(call.seed, seed);
      expect(call.key, key);
      expect(call.timeoutMs, 30000);
    });

    test('an onion target is kind 1, port 443', () async {
      await opened(target: OnionTarget('${'a' * 56}.onion'));

      expect(abi.opens.single.kind, 1);
      expect(abi.opens.single.port, 443);
    });

    test('an OPEN naming another key is the wrong server, and the channel is dropped (checked again in Dart)', () async {
      final opening = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30));
      core.deliver(1, ChannelEvent.open, Uint8List(32), 0);

      await expectLater(opening, throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.wrongServer)));
      expect(abi.closes, [1]);
    });

    test('an OPEN without the key is the module failing, not a verified channel', () async {
      final opening = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30));
      core.deliver(1, ChannelEvent.open, null, 0);

      await expectLater(opening, throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.internal)));
    });

    test('CLOSED before OPEN fails the open with its kind; a normal close there reads as the network', () async {
      final refused = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30));
      core.deliver(1, ChannelEvent.closed, null, 5);
      await expectLater(refused, throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.wrongServer)));

      final dropped = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30));
      core.deliver(2, ChannelEvent.closed, null, 0);
      await expectLater(dropped, throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.network)));
      expect(core.liveChannels, 0);
    });

    test('every failure kind of the contract maps to its name, and an unknown one is internal', () async {
      for (var code = 1; code <= 12; code++) {
        final opening = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30));
        core.deliver(abi.nextHandle - 1, ChannelEvent.closed, null, code);
        await expectLater(
          opening,
          throwsA(
            isA<ChannelOpenException>().having(
              (e) => e.failure,
              'failure',
              code <= 11 ? ChannelFailure.values[code - 1] : ChannelFailure.internal,
            ),
          ),
        );
      }
    });

    test('a refused call is an argument error for -7, and the module failing otherwise', () async {
      abi.refuseOpenWith = -7;
      await expectLater(core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 1)), throwsArgumentError);
      abi.refuseOpenWith = -1;
      await expectLater(
        core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 1)),
        throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.internal)),
      );
    });

    test('a cancel before OPEN abandons the open in the module, and a late OPEN changes nothing', () async {
      final cancel = Completer<void>();
      final opening = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30), cancel: cancel.future);
      cancel.complete();
      await expectLater(opening, throwsA(isA<ChannelOpenException>()));
      expect(abi.closes, [1], reason: 'nox_chan_close, not a wait for the module timeout');

      core.deliver(1, ChannelEvent.open, Uint8List.fromList(key), 0);
      core.deliver(1, ChannelEvent.closed, null, 0);
      expect(core.liveChannels, 0, reason: 'the handle is let go at its CLOSED');
    });

    test('a cancel after OPEN leaves the channel to whoever holds it', () async {
      final cancel = Completer<void>();
      final opening = core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(seconds: 30), cancel: cancel.future);
      core.deliver(1, ChannelEvent.open, Uint8List.fromList(key), 0);
      await opening;

      cancel.complete();
      await turn();

      expect(abi.closes, isEmpty);
    });

    test('a module that never answers is given up on past its own deadline', () async {
      final watch = Stopwatch()..start();
      await expectLater(
        core.open(home, deviceSeed: seed, serverKey: key, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.timeout)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(abi.closes, [1]);
    });

    test('an event for a handle nobody holds is dropped', () {
      expect(() => core.deliver(42, ChannelEvent.data, bytes(3), 0), returnsNormally);
    });
  });

  group('incoming bytes and the window', () {
    test('bytes that arrive before anybody listens are held, unacknowledged, and handed over with the listener', () async {
      final channel = await opened();
      core.deliver(1, ChannelEvent.data, bytes(10), 0);
      core.deliver(1, ChannelEvent.data, bytes(5, 2), 0);
      expect(abi.ackedBytes(1), 0, reason: 'nobody took them yet: the module must stop after one window');

      final got = <int>[];
      channel.incoming.listen(got.addAll);
      await turn();

      expect(got, [...bytes(10), ...bytes(5, 2)]);
      expect(abi.ackedBytes(1), 15);
    });

    test('a paused reader holds the acknowledgements back, and its resume releases them in order', () async {
      final channel = await opened();
      final got = <int>[];
      final sub = channel.incoming.listen(got.addAll);
      core.deliver(1, ChannelEvent.data, bytes(4), 0);
      await turn();
      expect(abi.ackedBytes(1), 4);

      sub.pause();
      await turn();
      core.deliver(1, ChannelEvent.data, bytes(6, 2), 0);
      core.deliver(1, ChannelEvent.data, bytes(7, 3), 0);
      expect(abi.ackedBytes(1), 4, reason: 'paused: not one byte more is acknowledged');

      sub.resume();
      await turn();
      expect(abi.ackedBytes(1), 17);
      expect(got, [...bytes(4), ...bytes(6, 2), ...bytes(7, 3)]);
    });

    test('a reader that left: what comes is acknowledged at once, so the other half of the channel is not stalled', () async {
      final channel = await opened();
      final sub = channel.incoming.listen((_) {});
      core.deliver(1, ChannelEvent.data, bytes(3), 0);
      await turn();
      await sub.cancel();

      core.deliver(1, ChannelEvent.data, bytes(8), 0);

      expect(abi.ackedBytes(1), 11);
    });

    test("the server's end of sending ends the stream - after everything held", () async {
      final channel = await opened();
      core.deliver(1, ChannelEvent.data, bytes(3), 0);
      core.deliver(1, ChannelEvent.eof, null, 0);

      expect(await channel.incoming.expand((chunk) => chunk).toList(), bytes(3));
    });

    test('a channel that fails after opening: the held bytes, then the failure, then done - and closed names it', () async {
      final channel = await opened();
      final events = <Object>[];
      final done = Completer<void>();
      core.deliver(1, ChannelEvent.data, bytes(2), 0);
      core.deliver(1, ChannelEvent.closed, null, 1);
      channel.incoming.listen((chunk) => events.add(chunk.length), onError: events.add, onDone: done.complete);
      await done.future;

      expect(events.first, 2);
      expect(events.last, isA<ChannelLostException>().having((e) => e.failure, 'failure', ChannelFailure.network));
      expect(await channel.closed, ChannelFailure.network);
      expect(core.liveChannels, 0);
    });

    test('nothing is acknowledged after CLOSED: the handle is gone', () async {
      final channel = await opened();
      channel.incoming.listen((_) {});
      core.deliver(1, ChannelEvent.closed, null, 0);
      final before = abi.acks.length;

      core.deliver(1, ChannelEvent.data, bytes(5), 0);
      await turn();

      expect(abi.acks.length, before);
      expect(await channel.closed, isNull, reason: 'closed normally');
    });
  });

  group('outgoing bytes', () {
    test('a write reports the queue, and room to write waits for WRITABLE only past the window', () async {
      final channel = await opened();
      abi.queueAfterWrite = channelWindowBytes;
      expect(channel.write(bytes(10)), channelWindowBytes);
      await channel.writable;

      abi.queueAfterWrite = channelWindowBytes + 1;
      channel.write(bytes(10));
      var room = false;
      unawaited(channel.writable.then((_) => room = true));
      await turn();
      expect(room, isFalse, reason: 'over the window');

      core.deliver(1, ChannelEvent.writable, null, 0);
      await turn();
      expect(room, isTrue);
      await channel.writable;
    });

    test('a flush completes on the DRAINED of its own ticket, not another', () async {
      final channel = await opened();
      var first = false;
      var second = false;
      unawaited(channel.flush().then((_) => first = true));
      unawaited(channel.flush().then((_) => second = true));
      expect(abi.flushes.map((f) => f.ticket), [1, 2]);

      core.deliver(1, ChannelEvent.drained, null, 2);
      await turn();
      expect((first, second), (false, true));

      core.deliver(1, ChannelEvent.drained, null, 1);
      await turn();
      expect(first, isTrue);
    });

    test('CLOSED fails what still waits: a flush, and room to write', () async {
      final channel = await opened();
      abi.queueAfterWrite = channelWindowBytes + 1;
      channel.write(bytes(1));
      final waiting = channel.writable;
      final flushing = channel.flush();

      core.deliver(1, ChannelEvent.closed, null, 1);

      await expectLater(flushing, throwsStateError);
      await expectLater(waiting, throwsStateError);
      expect(() => channel.write(bytes(1)), throwsStateError);
    });

    test('shutting the sending side is asked of the module once, and later writes are refused', () async {
      final channel = await opened();
      channel.shutdownWrite();
      channel.shutdownWrite();

      expect(abi.shutdowns, [1]);
      expect(() => channel.write(bytes(1)), throwsStateError);
    });

    test('close is asked of the module once', () async {
      final channel = await opened();
      channel.close();
      channel.close();

      expect(abi.closes, [1]);
    });

    test('an empty write asks the module nothing', () async {
      final channel = await opened();
      channel.write(Uint8List(0));

      expect(abi.written, isEmpty);
    });
  });
}

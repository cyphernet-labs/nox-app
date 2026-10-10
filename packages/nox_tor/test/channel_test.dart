import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nox_tor/channel.dart';
import 'package:test/test.dart';

final Uint8List _seed = Uint8List.fromList(List<int>.generate(32, (i) => i));
final Uint8List _serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));

/// An isolate of its own opens a channel to [args] `[port, timeoutMs, ready]`
/// and says so once the module has it; it then lives until it is killed, or
/// until the open ends and it reports how.
Future<void> _openFromAnotherIsolate(List<Object> args) async {
  final [port as int, timeoutMs as int, ready as SendPort] = args;
  final opening = const NativeNoxChannelApi().open(
    DirectTarget('127.0.0.1', port),
    deviceSeed: _seed,
    serverKey: _serverKey,
    timeout: Duration(milliseconds: timeoutMs),
  );
  ready.send('opening');
  try {
    await opening;
    ready.send('opened');
  } on ChannelOpenException catch (e) {
    ready.send(e.failure.name);
  }
}

/// A peer that takes every connection and never says a word; [ended] fires
/// for each when the other side lets go of it.
class _SilentPeer {
  _SilentPeer._(this._server) {
    _server.listen((socket) {
      _held.add(socket);
      final ended = Completer<void>();
      _accepted.add(ended.future);
      socket.listen(null, onDone: ended.complete, onError: (Object _) => ended.complete(), cancelOnError: true);
    });
  }

  static Future<_SilentPeer> start() async => _SilentPeer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final List<Socket> _held = <Socket>[];
  final StreamController<Future<void>> _accepted = StreamController<Future<void>>();
  late final StreamIterator<Future<void>> _next = StreamIterator<Future<void>>(_accepted.stream);

  int get port => _server.port;

  /// The next connection the peer took: [ended] completes when it ends.
  Future<({Future<void> ended})> accepted() async {
    if (!await _next.moveNext()) throw StateError('the peer stopped');
    return (ended: _next.current);
  }

  Future<void> close() async {
    for (final socket in _held) {
      socket.destroy();
    }
    await _server.close();
    // The iterator holds its subscription paused between reads: closed from
    // this side, its done could never be delivered.
    await _next.cancel();
  }
}

/// Spawns [_openFromAnotherIsolate]; the isolate and what it reports.
Future<(Isolate, StreamIterator<Object?>)> _spawnOpener(int port, Duration timeout) async {
  final reports = ReceivePort();
  final isolate = await Isolate.spawn(_openFromAnotherIsolate, <Object>[port, timeout.inMilliseconds, reports.sendPort]);
  final said = StreamIterator<Object?>(reports);
  addTearDown(said.cancel);
  expect(await said.moveNext(), isTrue);
  expect(said.current, 'opening');
  return (isolate, said);
}

/// Kills [isolate] the way a hot restart kills the root one, and waits for it
/// to be gone.
Future<void> _kill(Isolate isolate) async {
  final exited = ReceivePort();
  isolate.addOnExitListener(exited.sendPort);
  isolate.kill(priority: Isolate.immediate);
  await exited.first;
  exited.close();
}

// The secure channel against the library the hook built for the host. Only
// the refusals live here - every one of them is decided before any server
// would speak; the exchange with a real Eidolon peer is the crate's own
// integration test (rust/tests/channel.rs).
void main() {
  const api = NativeNoxChannelApi();
  final seed = _seed;
  final serverKey = _serverKey;

  group('refused before the module is asked', () {
    test('a seed or a server key of the wrong length', () {
      expect(
        api.open(const DirectTarget('127.0.0.1', 1), deviceSeed: Uint8List(31), serverKey: serverKey, timeout: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(
        api.open(const DirectTarget('127.0.0.1', 1), deviceSeed: seed, serverKey: Uint8List(33), timeout: const Duration(seconds: 1)),
        throwsArgumentError,
      );
    });

    test('no host, a port out of range, no time at all', () {
      expect(
        api.open(const DirectTarget('', 443), deviceSeed: seed, serverKey: serverKey, timeout: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(
        api.open(const DirectTarget('127.0.0.1', 0), deviceSeed: seed, serverKey: serverKey, timeout: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(
        api.open(const DirectTarget('127.0.0.1', 70000), deviceSeed: seed, serverKey: serverKey, timeout: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(
        api.open(const DirectTarget('127.0.0.1', 1), deviceSeed: seed, serverKey: serverKey, timeout: Duration.zero),
        throwsArgumentError,
      );
    });

    test('a CLOSED code names its kind, and an unknown one is internal', () {
      expect(ChannelFailure.fromCode(0), isNull);
      expect(ChannelFailure.fromCode(1), ChannelFailure.network);
      expect(ChannelFailure.fromCode(5), ChannelFailure.wrongServer);
      expect(ChannelFailure.fromCode(11), ChannelFailure.internal);
      expect(ChannelFailure.fromCode(12), ChannelFailure.internal);
      expect(ChannelFailure.fromCode(-3), ChannelFailure.internal);
    });

    test('an onion target never prints its address, and is always port 443', () {
      const host = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcd.onion';
      expect('${const OnionTarget(host)}', isNot(contains('abcdefgh')));
      expect(const OnionTarget(host).port, 443);
    });
  });

  group('against the network', () {
    test('a closed port is a network failure', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      await expectLater(
        api.open(DirectTarget('127.0.0.1', port), deviceSeed: seed, serverKey: serverKey, timeout: const Duration(seconds: 5)),
        throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.network)),
      );
    });

    test('a peer that takes the connection and never answers runs out the time', () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await silent.close();
      });
      final watch = Stopwatch()..start();
      await expectLater(
        api.open(
          DirectTarget('127.0.0.1', silent.port),
          deviceSeed: seed,
          serverKey: serverKey,
          timeout: const Duration(milliseconds: 800),
        ),
        throwsA(isA<ChannelOpenException>().having((e) => e.failure, 'failure', ChannelFailure.timeout)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a cancelled open ends at once, long before its time', () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      silent.listen(held.add);
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await silent.close();
      });
      final cancel = Completer<void>();
      final opening = api.open(
        DirectTarget('127.0.0.1', silent.port),
        deviceSeed: seed,
        serverKey: serverKey,
        timeout: const Duration(seconds: 30),
        cancel: cancel.future,
      );
      final watch = Stopwatch()..start();
      Timer(const Duration(milliseconds: 200), cancel.complete);
      await expectLater(opening, throwsA(isA<ChannelOpenException>()));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('an isolate that goes away', () {
    test('a channel it left behind ends on its next event, and the process lives on', () async {
      // Before the events went to a port, the CLOSED of this open - a timeout,
      // a second after the isolate is gone - called a function deleted with
      // the isolate, and the VM aborted the process.
      final peer = await _SilentPeer.start();
      addTearDown(peer.close);
      final (isolate, _) = await _spawnOpener(peer.port, const Duration(seconds: 1));
      final connection = await peer.accepted();
      await _kill(isolate);

      await connection.ended.timeout(const Duration(seconds: 10));
      // The CLOSED went nowhere, and nothing else did either: this isolate,
      // and the process, are still here to open the next channel.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final (another, said) = await _spawnOpener(peer.port, const Duration(milliseconds: 500));
      expect(await said.moveNext(), isTrue);
      expect(said.current, ChannelFailure.timeout.name);
      another.kill();
    });

    test('a new isolate ends the channels an earlier one left behind before it opens its own', () async {
      final peer = await _SilentPeer.start();
      addTearDown(peer.close);
      // An open with a minute to go: nothing of its own would end it soon.
      final (left, _) = await _spawnOpener(peer.port, const Duration(minutes: 1));
      final leftBehind = await peer.accepted();
      await _kill(left);
      await expectLater(
        leftBehind.ended.timeout(const Duration(milliseconds: 300)),
        throwsA(isA<TimeoutException>()),
        reason: 'nothing has asked about it yet',
      );

      final (next, said) = await _spawnOpener(peer.port, const Duration(milliseconds: 500));
      await leftBehind.ended.timeout(const Duration(seconds: 5));
      expect(await said.moveNext(), isTrue);
      expect(said.current, ChannelFailure.timeout.name, reason: 'the new isolate opens its own as usual');
      next.kill();
    });
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nox_tor/channel.dart';
import 'package:test/test.dart';

// The secure channel against the library the hook built for the host. Only
// the refusals live here - every one of them is decided before any server
// would speak; the exchange with a real Eidolon peer is the crate's own
// integration test (rust/tests/channel.rs).
void main() {
  const api = NativeNoxChannelApi();
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));

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
      // The abandoned handle's CLOSED is still to come from the module; the
      // test isolate waits for it rather than exit under a pending callback.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });
}

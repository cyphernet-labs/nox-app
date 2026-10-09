import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_tor/channel.dart';

import '../../remote/channel/fake_channel.dart';

enum _Answer { home, otherKey, closed, silent }

/// Addresses on a scripted network: which one is this person's server, which
/// proves another key, which refuses the connection, which never answers.
class _Network implements NoxChannelApi {
  _Network(this.answers);

  final Map<String, _Answer> answers;
  final List<ChannelTarget> opened = <ChannelTarget>[];
  final List<Duration> timeouts = <Duration>[];
  final List<Uint8List> serverKeys = <Uint8List>[];
  final List<FakeNoxChannel> channels = <FakeNoxChannel>[];
  int cancelled = 0;

  @override
  Future<NoxChannel> open(
    ChannelTarget target, {
    required Uint8List deviceSeed,
    required Uint8List serverKey,
    required Duration timeout,
    Future<void>? cancel,
  }) {
    opened.add(target);
    timeouts.add(timeout);
    serverKeys.add(Uint8List.fromList(serverKey));
    switch (answers['${target.host}:${target.port}'] ?? _Answer.closed) {
      case _Answer.home:
        final channel = FakeNoxChannel();
        channels.add(channel);
        return Future<NoxChannel>.value(channel);
      case _Answer.otherKey:
        return Future<NoxChannel>.error(const ChannelOpenException(ChannelFailure.wrongServer));
      case _Answer.closed:
        return Future<NoxChannel>.error(const ChannelOpenException(ChannelFailure.network));
      case _Answer.silent:
        final pending = Completer<NoxChannel>();
        final deadline = Timer(timeout, () {
          if (!pending.isCompleted) pending.completeError(const ChannelOpenException(ChannelFailure.timeout));
        });
        cancel?.then((_) {
          cancelled++;
          deadline.cancel();
          if (!pending.isCompleted) pending.completeError(const ChannelOpenException(ChannelFailure.timeout));
        });
        return pending.future;
    }
  }
}

/// The direct probe opens a channel and closes it: whether this person's
/// server proved its key at an address is the whole question (phase 044,
/// FR-001, FR-002, FR-011).
void main() {
  final serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
  final deviceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));

  Future<DirectProbeResult> probe(_Network network, List<String> candidates) =>
      ChannelDirectProber(network).probe(candidates, serverKey: serverKey, deviceSeed: deviceSeed);

  test('the server proving its key wins, and the probe channel is closed at once with nothing sent', () async {
    final network = _Network({'192.168.1.20:8443': _Answer.home});

    final result = await probe(network, ['192.168.1.20:8443']);

    expect(result.address, '192.168.1.20:8443');
    expect(result.notHome, isEmpty);
    expect(network.opened.single, const DirectTarget('192.168.1.20', 8443));
    expect(network.serverKeys.single, serverKey);
    expect(network.timeouts.single, ChannelDirectProber.attemptTimeout);
    expect(network.channels.single.closeCalls, 1);
    expect(network.channels.single.written, isEmpty);
  });

  test('another key is "not home", never a win - and never anything more (FR-011)', () async {
    final network = _Network({'192.168.1.20:8443': _Answer.otherKey});

    final result = await probe(network, ['192.168.1.20:8443']);

    expect(result.address, isNull);
    expect(result.notHome, ['192.168.1.20:8443']);
  });

  test('a dead first candidate hands over to the rest without waiting out its head start', () async {
    final network = _Network({'10.0.0.2:8443': _Answer.otherKey, '10.0.0.3:8443': _Answer.home});

    final watch = Stopwatch()..start();
    final result = await probe(network, ['10.0.0.1:8443', '10.0.0.2:8443', '10.0.0.3:8443']);

    expect(result.address, '10.0.0.3:8443');
    expect(result.notHome, ['10.0.0.2:8443']);
    expect(watch.elapsed, lessThan(ChannelDirectProber.stagger));
  });

  test('a listener that never answers costs one attempt, not the round - and is dropped once it is won', () async {
    final network = _Network({'10.0.0.1:8443': _Answer.silent, '10.0.0.2:8443': _Answer.home});

    final result = await probe(network, ['10.0.0.1:8443', '10.0.0.2:8443']);

    expect(result.address, '10.0.0.2:8443');
    await pumpEventQueue();
    expect(network.cancelled, 1, reason: 'the open still running is cancelled in the module, not left to its timeout');
  });

  test('nothing answering ends within the budget, so Tor is not kept waiting (FR-002)', () async {
    final network = _Network({'10.0.0.1:8443': _Answer.silent});

    final watch = Stopwatch()..start();
    final result = await probe(network, ['10.0.0.1:8443']);

    expect(result.address, isNull);
    expect(watch.elapsed, lessThan(ChannelDirectProber.budget + const Duration(milliseconds: 500)));
  });

  test('no candidates is no address, and an onion address is never tried as a direct one', () async {
    final network = _Network(const {});
    expect((await probe(network, const [])).address, isNull);
    expect((await probe(network, ['${'a' * 56}.onion:443'])).address, isNull);
    expect(network.opened, isEmpty);
  });
}

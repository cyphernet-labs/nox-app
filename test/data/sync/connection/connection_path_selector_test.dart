import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../remote/socket/fake_socket.dart';
import 'fake_direct_prober.dart';

/// How the app chooses its way to the server (phase 040, US1-US3): direct
/// first, Tor only when no direct address answers and only where it can work,
/// and back to direct as soon as it answers again.
const String _pin = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';
const String _link = '10.0.0.5:9000';
final String _onionHost = '${'a' * 56}.onion';
final String _onion = '$_onionHost:443';

class _Network implements NetworkChangeService {
  final StreamController<void> changes = StreamController<void>.broadcast();

  @override
  Stream<void> watchChanges() => changes.stream;
}

/// A network source whose first answer never comes, like connectivity_plus on
/// some simulators: its stream is stuck in an `async*` body at an await.
class _StuckNetwork implements NetworkChangeService {
  @override
  Stream<void> watchChanges() async* {
    await Completer<void>().future;
    yield null;
  }
}

class _Lifecycle implements AppLifecycleService {
  final StreamController<AppVisibility> changes = StreamController<AppVisibility>.broadcast();

  @override
  AppVisibility visibility = AppVisibility.foreground;

  @override
  Stream<AppVisibility> watchVisibility() => changes.stream;

  void go(AppVisibility next) {
    visibility = next;
    changes.add(next);
  }
}

void main() {
  late FakeSocketFactory factory;
  late NoxSocketClient socket;
  late FakeDirectProber prober;
  late FakeTorService tor;
  late ServerAddressesRepository addresses;
  late AccessKeyRepository keys;
  late _Network network;
  late _Lifecycle lifecycle;
  late ConnectionPathSelector selector;

  ConnectionPathSelector build({
    bool forceTor = false,
    bool mobile = true,
    Duration recheckEvery = const Duration(hours: 1),
    Duration torReadyBudget = const Duration(milliseconds: 400),
  }) => ConnectionPathSelector.forTest(
    prober,
    tor,
    addresses,
    keys,
    network,
    lifecycle,
    socket,
    forceTor: forceTor,
    mobile: mobile,
    recheckEvery: recheckEvery,
    torReadyBudget: torReadyBudget,
    resumeReadyBudget: const Duration(milliseconds: 150),
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    factory = FakeSocketFactory();
    socket = NoxSocketClient(factory, getIt<SyncRepository>());
    prober = FakeDirectProber();
    tor = FakeTorService();
    addresses = getIt<ServerAddressesRepository>();
    keys = getIt<AccessKeyRepository>();
    network = _Network();
    lifecycle = _Lifecycle();
    selector = build()..begin(linkAddress: _link, fingerprint: _pin);
  });

  tearDown(() async {
    await socket.stop();
    await selector.end();
    await getIt.reset();
  });

  Future<void> waitUntil(FutureOr<bool> Function() done, {String reason = ''}) async {
    for (var i = 0; i < 400; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition never became true${reason.isEmpty ? '' : ': $reason'}');
  }

  /// The server is reachable through its onion address with this device's key.
  Future<void> torWorks() async {
    tor.supported = true;
    await addresses.saveFromServer(direct: const <String>[], onion: _onion);
    await keys.deviceKey();
    await keys.markRegistered(true);
  }

  Future<FakeSocket> greetLatest() async {
    final connection = factory.latest;
    connection.pushGreeting();
    await waitUntil(() => connection.commandNamed('session.hello') != null, reason: 'the client greets back');
    connection.replyToHello(cursor: 0);
    await waitUntil(() => socket.currentPhase == SessionPhase.live, reason: 'the greeting is applied');
    return connection;
  }

  /// Starts the socket on the selector and greets the connection it dials.
  Future<FakeSocket> connectAndGreet() async {
    if (!socket.currentPhase.isCurrent) {
      await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
    }
    await waitUntil(() => factory.created.isNotEmpty, reason: 'a connection is dialled');
    return greetLatest();
  }

  group('choosing a path (US1)', () {
    test('a direct address that answers wins, and Tor is never touched', () async {
      await torWorks();

      final target = await selector.nextTarget();

      expect(target, Uri.parse('wss://$_link/ws'));
      expect(tor.starts, 0, reason: 'Tor runs only when the direct path does not (FR-006)');
      expect(selector.selection.path, ConnectionPath.direct);
    });

    test('direct candidates go in order: last good, the server list, the link (FR-001)', () async {
      await addresses.saveFromServer(direct: const ['192.168.1.20:8080', '192.168.1.21:8080'], onion: null);
      await addresses.recordLastGood('192.168.1.21:8080');
      prober.home = <String>{};

      await selector.nextTarget();

      expect(prober.rounds.single, ['192.168.1.21:8080', '192.168.1.20:8080', _link]);
    });

    test('no direct answer, and Tor brings up the onion address with the device key', () async {
      await torWorks();
      prober.home = <String>{};

      final target = await selector.nextTarget();

      expect(target, Uri.parse('wss://$_onionHost/ws'));
      expect(tor.starts, 1);
      expect(tor.target?.host, _onionHost);
      expect(tor.target?.port, 443);
      expect(tor.target?.key, (await keys.deviceKey()).data!.privateKey);
      expect(selector.selection.path, ConnectionPath.tor);
    });

    test('no onion address means no Tor, and no path', () async {
      tor.supported = true;
      await keys.markRegistered(true);
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.starts, 0);
      expect(selector.selection.roundFailed, isTrue);
    });

    test('a key the server does not have yet means no Tor (FR-007)', () async {
      tor.supported = true;
      await addresses.saveFromServer(direct: const <String>[], onion: _onion);
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.starts, 0);
    });

    test('where Tor cannot run - Linux - the app goes direct only (FR-031)', () async {
      await torWorks();
      tor.supported = false;
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.starts, 0);
    });

    test('a build the Tor network refused does not start it again (FR-026)', () async {
      await torWorks();
      tor.emit(const TorStatus(state: TorState.obsolete, error: TorError.softwareDeprecated));
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.starts, 0);
    });

    test('a Tor that is not ready within its budget is no path this round', () async {
      await torWorks();
      tor.afterStart = const TorStatus(state: TorState.bootstrapping, bootstrapPercent: 40);
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.starts, 1);
    });

    test('an invite lends its one-time key for the pairing it carries (FR-020)', () async {
      tor.supported = true;
      final lent = Uint8List.fromList(List<int>.generate(32, (i) => i));
      selector.lendInvite(onion: _onion, oneTimeKey: lent);
      prober.home = <String>{};

      final target = await selector.nextTarget();

      expect(target, Uri.parse('wss://$_onionHost/ws'));
      expect(tor.target?.key, lent);
    });

    test('the lent key leaves with its pairing: out of Tor and wiped, the link untouched (FR-021)', () async {
      tor.supported = true;
      final lent = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      selector.lendInvite(onion: _onion, oneTimeKey: lent);
      prober.home = <String>{};
      await selector.nextTarget();
      final inTor = tor.target!.key;

      selector.forgetLentKey();

      expect(tor.target, isNull);
      expect(inTor, everyElement(0), reason: 'the copy the selector held is wiped');
      expect(lent, isNot(everyElement(0)), reason: 'the link the caller holds is left as it was');
      expect(await selector.nextTarget(), isNull, reason: 'no key, no Tor');
    });

    test('a lent key dropped while Tor starts is not set again (FR-021)', () async {
      tor.supported = true;
      final gate = Completer<void>();
      tor.startGate = gate;
      selector.lendInvite(onion: _onion, oneTimeKey: Uint8List.fromList(List<int>.filled(32, 3)));
      prober.home = <String>{};
      final round = selector.nextTarget();
      await waitUntil(() => tor.starts == 1, reason: 'Tor is starting');

      selector.forgetLentKey();
      gate.complete();

      expect(await round, isNull);
      expect(tor.target, isNull, reason: 'the pairing is over; its key stays out');
    });

    test('a registered key that is gone is not minted anew on the way to Tor (FR-018)', () async {
      // A round racing a logout reads "registered" and then finds the key
      // wiped; a key minted there would survive the logout.
      tor.supported = true;
      await addresses.saveFromServer(direct: const <String>[], onion: _onion);
      await keys.markRegistered(true);
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect((await keys.storedDeviceKey()).data, isNull, reason: 'nothing was minted');
    });

    test('a Tor client that failed is started afresh, not waited on', () async {
      await torWorks();
      tor.afterStart = const TorStatus(state: TorState.failed, error: TorError.network);
      prober.home = <String>{};
      final watch = Stopwatch()..start();

      expect(await selector.nextTarget(), isNull);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 350)), reason: 'a failed client ends the 400 ms wait at once');

      tor.afterStart = const TorStatus(state: TorState.ready, bootstrapPercent: 100);
      expect(await selector.nextTarget(), Uri.parse('wss://$_onionHost/ws'));
      expect(tor.stops, 1, reason: 'stopped before it was started again');
      expect(tor.starts, 2);
    });

    test('the debug switch skips the direct addresses', () async {
      await selector.end();
      selector = build(forceTor: true)..begin(linkAddress: _link, fingerprint: _pin);
      await torWorks();

      expect(await selector.nextTarget(), Uri.parse('wss://$_onionHost/ws'));
      expect(prober.rounds, isEmpty);
    });

    test('a release build ignores the debug switch', () {
      expect(ConnectionPathSelector.resolveForceTor(debug: false, requested: true), isFalse);
      expect(ConnectionPathSelector.resolveForceTor(debug: true, requested: false), isFalse);
      expect(ConnectionPathSelector.resolveForceTor(debug: true, requested: true), isTrue);
    });
  });

  group('the round that failed (research decision 12)', () {
    test('it is held through the retries and cleared by a greeting', () async {
      prober.home = <String>{};
      expect(await selector.nextTarget(), isNull);
      expect(selector.selection.roundFailed, isTrue);

      prober.home = null;
      final target = await selector.nextTarget();
      expect(selector.selection.roundFailed, isTrue, reason: 'nothing has answered yet');

      selector.reportGreeted(target!);
      expect(selector.selection.roundFailed, isFalse);
    });

    test('a target handed out and never greeted is a failed round', () async {
      await selector.nextTarget();
      expect(selector.selection.roundFailed, isFalse);

      await selector.nextTarget();

      expect(selector.selection.roundFailed, isTrue);
    });
  });

  group('back to the direct path (US2)', () {
    Future<void> onTor() async {
      await torWorks();
      prober.home = <String>{};
      await connectAndGreet();
      expect(selector.currentPath, ConnectionPath.tor);
    }

    test('every so often the direct path is checked, taken when it answers, and Tor stops (FR-003)', () async {
      await selector.end();
      selector = build(recheckEvery: const Duration(milliseconds: 150))..begin(linkAddress: _link, fingerprint: _pin);
      await onTor();

      prober.home = null;
      await waitUntil(() => factory.urls.last == Uri.parse('wss://$_link/ws'), reason: 'the socket moves to the direct address');
      await greetLatest();

      expect(selector.currentPath, ConnectionPath.direct);
      await waitUntil(() => tor.stops > 0, reason: 'Tor stops once the direct connection is greeted');
      expect(tor.target, isNull);
    });

    test('a network change checks the direct path at once', () async {
      await onTor();
      final dialled = factory.created.length;

      prober.home = null;
      network.changes.add(null);
      await waitUntil(() => factory.created.length > dialled, reason: 'the switch happens on the change');

      expect(factory.urls.last, Uri.parse('wss://$_link/ws'));
    });

    test('another key at the direct address is no reason to switch (FR-005)', () async {
      await onTor();
      final dialled = factory.created.length;

      prober.otherKey = {_link};
      prober.home = null;
      network.changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(factory.created.length, dialled, reason: 'still on Tor');
      expect(selector.currentPath, ConnectionPath.tor);
    });

    test('on the direct path a network change checks the address in use; a dead one is left (T029)', () async {
      await connectAndGreet();
      expect(selector.currentPath, ConnectionPath.direct);
      final rounds = prober.rounds.length;

      prober.home = <String>{};
      network.changes.add(null);
      // The check of the address in use, then a whole round of choosing.
      await waitUntil(() => prober.rounds.length >= rounds + 2, reason: 'the socket chooses again');

      expect(socket.currentPhase, isNot(SessionPhase.live), reason: 'the dead connection was left');
    });

    test('on the direct path a network change that leaves the address working changes nothing', () async {
      await connectAndGreet();
      final dialled = factory.created.length;

      network.changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(factory.created.length, dialled);
      expect(prober.rounds.last, [_link], reason: 'only the address in use was checked');
    });
  });

  group('in the background (FR-025)', () {
    Future<void> onTor() async {
      await torWorks();
      prober.home = <String>{};
      await connectAndGreet();
    }

    test('Tor sleeps in the background and wakes in front', () async {
      await onTor();

      lifecycle.go(AppVisibility.background);
      lifecycle.go(AppVisibility.foreground);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(tor.dormancy, [true, false]);
    });

    test('a Tor that does not wake up in time is started again from its directories', () async {
      await onTor();
      final starts = tor.starts;

      lifecycle.go(AppVisibility.background);
      tor.emit(const TorStatus(state: TorState.bootstrapping, bootstrapPercent: 20));
      tor.afterStart = const TorStatus(state: TorState.ready, bootstrapPercent: 100);
      lifecycle.go(AppVisibility.foreground);
      await waitUntil(() => tor.starts > starts, reason: 'restarted after the wake-up budget');

      expect(tor.target?.host, _onionHost, reason: 'the target is set again');
    });

    test('back in front with the socket on the ladder, the path is chosen at once', () async {
      prober.home = <String>{};
      await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
      await waitUntil(() => socket.currentPhase == SessionPhase.disconnected, reason: 'on the ladder');
      final asked = prober.rounds.length;

      lifecycle.go(AppVisibility.background);
      lifecycle.go(AppVisibility.foreground);
      await waitUntil(() => prober.rounds.length > asked, reason: 'a new round, not the next rung');
    });

    test('a foreground that was never left changes nothing', () async {
      // The lifecycle service replays its current value to a new listener.
      // Taken as a return from the background, it restarted the attempt a
      // sign-in was waiting on - and the pairing failed at once.
      prober.home = <String>{};
      unawaited(socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials()));
      await waitUntil(() => prober.rounds.isNotEmpty, reason: 'the first round ran');
      final asked = prober.rounds.length;

      lifecycle.go(AppVisibility.foreground);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(prober.rounds.length, asked, reason: 'no new round for a replay');
    });

    test('a desktop does not sleep', () async {
      await selector.end();
      selector = build(mobile: false)..begin(linkAddress: _link, fingerprint: _pin);
      await onTor();

      lifecycle.go(AppVisibility.background);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(tor.dormancy, isEmpty);
    });
  });

  group('a new address changes nothing but the way (US3)', () {
    test('a greeted direct address becomes the last good one (T032)', () async {
      await addresses.saveFromServer(direct: const ['192.168.1.20:8080'], onion: null);
      await connectAndGreet();

      await waitUntil(() async => (await addresses.read()).data?.lastGood == '192.168.1.20:8080', reason: 'recorded');
    });

    test('the old address is dead, Tor carries the news, and the next check moves to the new one (T033)', () async {
      // The server's machine got a new address at home. The old one is gone,
      // so the device comes in through Tor and learns the new one from the
      // server itself.
      await torWorks();
      await addresses.saveFromServer(direct: const ['192.168.1.20:8080'], onion: _onion);
      await addresses.recordLastGood('192.168.1.20:8080');
      prober.home = {'192.168.1.30:8080'};
      final connection = await connectAndGreet();
      expect(selector.currentPath, ConnectionPath.tor);

      // The server says where it is now - in this test, straight into the
      // repository, the way SyncService stores a server.addresses event.
      connection.pushEvent(seq: 0, event: 'server.addresses');
      await addresses.saveFromServer(direct: const ['192.168.1.30:8080'], onion: _onion);

      await waitUntil(() => factory.urls.last == Uri.parse('wss://192.168.1.30:8080/ws'), reason: 'a new address is checked at once');
      await greetLatest();
      expect(selector.currentPath, ConnectionPath.direct);
    });
  });

  group('a key the onion service does not know (T039)', () {
    const refused = TorStatus(state: TorState.ready, bootstrapPercent: 100, error: TorError.wrongClientAuth, port: 9150);

    test('turned away for longer than the grace, this device key counts as unknown, and Tor waits', () async {
      await selector.end();
      selector = ConnectionPathSelector.forTest(
        prober,
        tor,
        addresses,
        keys,
        network,
        lifecycle,
        socket,
        keyRefusalGrace: const Duration(milliseconds: 100),
        torReadyBudget: const Duration(milliseconds: 400),
      )..begin(linkAddress: _link, fingerprint: _pin);
      await torWorks();
      prober.home = <String>{};
      expect(await selector.nextTarget(), isNotNull);

      tor.emit(refused);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(await selector.nextTarget(), isNull, reason: 'no Tor until the key is registered again');
      expect((await keys.isRegistered()).data, isFalse, reason: 'the next greeting registers it again');
    });

    test('a refusal right after the key went in is the description still spreading, not an unknown key', () async {
      // A pairing a moment ago, or a registration: the service's published
      // description lags behind. Switching Tor off here would strand a device
      // that is away from home and has no other way in.
      await torWorks();
      prober.home = <String>{};
      expect(await selector.nextTarget(), isNotNull);

      tor.emit(refused);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await selector.nextTarget(), Uri.parse('wss://$_onionHost/ws'), reason: 'Tor is tried again');
      expect((await keys.isRegistered()).data, isTrue);
    });

    test('a lent key turned away is kept: its pairing ends on its own deadline', () async {
      tor.supported = true;
      final lent = Uint8List.fromList(List<int>.filled(32, 5));
      selector.lendInvite(onion: _onion, oneTimeKey: lent);
      prober.home = <String>{};
      await selector.nextTarget();

      tor.emit(refused);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await selector.nextTarget(), Uri.parse('wss://$_onionHost/ws'), reason: 'still lent');
      expect(tor.target?.key, lent);
    });

    test('a greeting at home ends the run of refusals: an old one is no evidence later', () async {
      await selector.end();
      selector = ConnectionPathSelector.forTest(
        prober,
        tor,
        addresses,
        keys,
        network,
        lifecycle,
        socket,
        keyRefusalGrace: const Duration(milliseconds: 100),
        torReadyBudget: const Duration(milliseconds: 400),
      )..begin(linkAddress: _link, fingerprint: _pin);
      await torWorks();
      prober.home = <String>{};
      expect(await selector.nextTarget(), isNotNull);
      tor.emit(refused);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      prober.home = <String>{_link};
      final direct = await selector.nextTarget();
      selector.reportGreeted(direct!);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      prober.home = <String>{};
      expect(await selector.nextTarget(), Uri.parse('wss://$_onionHost/ws'), reason: 'the key is not called unknown');
      expect((await keys.isRegistered()).data, isTrue);
    });
  });

  test('a stale bring-up finishing does not clear the mark of the round that replaced it', () async {
    // The mark is what lets a command wait out a Tor bring-up instead of
    // failing on the short timeout; a newer round must keep it.
    await torWorks();
    tor.afterStart = const TorStatus(state: TorState.bootstrapping, bootstrapPercent: 30);
    prober.home = <String>{};

    final first = selector.nextTarget();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final second = selector.nextTarget();
    await first; // times out at 400 ms, a stale round by then
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(selector.bringingUpSlowPath, isTrue, reason: 'the second round is still bringing Tor up');
    await second;
    expect(selector.bringingUpSlowPath, isFalse);
  });

  test('a newer round that went direct leaves no slow-path mark behind', () async {
    // The mark stretches the greeting and command waits to the slow budget;
    // a stale round still waiting on Tor must not hold it over a direct link.
    await torWorks();
    tor.afterStart = const TorStatus(state: TorState.bootstrapping, bootstrapPercent: 30);
    prober.home = <String>{};
    final first = selector.nextTarget();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    prober.home = <String>{_link};
    expect(await selector.nextTarget(), Uri.parse('wss://$_link/ws'));

    expect(selector.bringingUpSlowPath, isFalse);
    expect(await first.timeout(const Duration(milliseconds: 200)), isNull, reason: 'the stale round stops waiting at once');
  });

  test('an attempt a network change cut short is not a failed round', () async {
    prober.home = <String>{_link};
    await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
    await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
    expect(socket.currentPhase, SessionPhase.connecting);

    network.changes.add(null);
    await waitUntil(() => factory.created.length == 2, reason: 'dialled again at once');

    expect(selector.selection.roundFailed, isFalse, reason: 'no round finished, so none failed');
  });

  test('a restart keeps the session shown as coming up', () async {
    // Shown as idle, the gap before begin() would read as "no connection" and
    // flash the banner on every rename.
    await selector.end(keepTor: true);
    expect(selector.selection.active, isTrue);

    selector.begin(linkAddress: _link, fingerprint: _pin);
    expect(selector.selection.active, isTrue);
  });

  test('ending does not wait on a source whose cancel never finishes', () async {
    // On an iOS simulator the network source's first answer never came, and an
    // `async*` stream suspended on it cannot finish cancelling. Awaiting that
    // cancel wedged the channel restart a sign-in waits on.
    await selector.end();
    selector = ConnectionPathSelector.forTest(prober, tor, addresses, keys, _StuckNetwork(), lifecycle, socket)
      ..begin(linkAddress: _link, fingerprint: _pin);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await selector.end().timeout(const Duration(seconds: 2), onTimeout: () => fail('end() waited on the stuck source'));
  });

  test('ending the session stops Tor and asks nothing more', () async {
    await torWorks();
    prober.home = <String>{};
    await selector.nextTarget();
    expect(tor.target, isNotNull);

    await selector.end();

    expect(tor.stops, greaterThan(0));
    expect(await selector.nextTarget(), isNull);
    expect(selector.selection.active, isFalse);
  });
}

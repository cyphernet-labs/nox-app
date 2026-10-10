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
import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
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
final Uint8List _serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
final Uint8List _deviceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));
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

/// The real store, with reads that can be held - how a test lands a begin() or
/// an end() while the selector waits on the addresses.
class _HeldAddresses implements ServerAddressesRepository {
  _HeldAddresses(this._store);

  final ServerAddressesRepository _store;

  /// While set, every read waits for it.
  Future<void>? hold;
  int reads = 0;

  @override
  Future<RepositoryResult<ServerAddresses>> read() async {
    reads++;
    await hold;
    return _store.read();
  }

  @override
  Future<RepositoryResult<bool>> saveFromServer({required List<String> direct, required String? onion}) =>
      _store.saveFromServer(direct: direct, onion: onion);

  @override
  Future<RepositoryResult<bool>> recordLastGood(String address) => _store.recordLastGood(address);

  @override
  Future<RepositoryResult<bool>> recordGreetedViaTor() => _store.recordGreetedViaTor();

  @override
  Stream<ServerAddresses> watch() => _store.watch();

  @override
  Future<RepositoryResult<bool>> clear() => _store.clear();
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
    ServerAddressesRepository? store,
  }) => ConnectionPathSelector.forTest(
    prober,
    tor,
    store ?? addresses,
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
    selector = build()..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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

    test('every probe opens its channels with the keys the session was begun with (phase 044)', () async {
      prober.home = <String>{};

      await selector.nextTarget();

      expect(prober.keys.single.serverKey, _serverKey);
      expect(prober.keys.single.deviceSeed, _deviceSeed);
    });

    test('a session not begun with keys has no path at all', () async {
      await selector.end();
      selector = build();

      expect(await selector.nextTarget(), isNull);
      expect(prober.rounds, isEmpty, reason: 'nothing to open a channel with');
    });

    test('ending the session wipes its copy of the device key, and leaves the caller its own', () async {
      final seed = Uint8List.fromList(_deviceSeed);
      await selector.end();
      selector = build()..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: seed);
      prober.home = <String>{};
      await selector.nextTarget();
      // The array the probe was handed is the selector's own copy: the one
      // that has to go with the session.
      final own = prober.seedsHanded.single;
      expect(own, _deviceSeed);
      expect(identical(own, seed), isFalse, reason: 'the selector keeps a copy of its own');

      await selector.end();

      expect(own, everyElement(0), reason: 'the device key outlived its session');
      expect(seed, _deviceSeed, reason: 'the caller keeps what it handed over');
      expect(await selector.nextTarget(), isNull);
    });

    test('a round whose read of the addresses outlives a new begin() probes with the new key, never the wiped one', () async {
      final store = _HeldAddresses(addresses);
      await selector.end();
      selector = build(store: store)..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
      final held = Completer<void>();
      store.hold = held.future;
      prober.home = <String>{};

      final round = selector.nextTarget();
      await waitUntil(() => store.reads == 1, reason: 'the round reads the addresses');
      // A start over a running session: the seed it replaces is wiped in place.
      final next = Uint8List.fromList(List<int>.generate(32, (i) => 0x40 + i));
      selector.begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: next);
      held.complete();
      await round;

      expect(prober.keys.single.deviceSeed, next, reason: 'the probe opened its channels with a key wiped under it');
    });

    test('a check of the direct path whose read of the addresses outlives end() opens nothing with the wiped key', () async {
      final store = _HeldAddresses(addresses);
      await selector.end();
      selector = build(store: store)..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
      await torWorks();
      prober.home = <String>{};
      await connectAndGreet();
      expect(selector.currentPath, ConnectionPath.tor);
      final held = Completer<void>();
      store.hold = held.future;
      final reads = store.reads;
      final probes = prober.rounds.length;

      // A network change on Tor checks the direct path, which answers again.
      prober.home = null;
      network.changes.add(null);
      await waitUntil(() => store.reads > reads, reason: 'the check reads the addresses');
      await selector.end();
      held.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(prober.rounds, hasLength(probes), reason: 'a probe for a session that had ended');
      expect(prober.keys.where((k) => k.deviceSeed.every((b) => b == 0)), isEmpty, reason: 'a probe opened with the wiped key');
    });

    test('a link lends no key any more: an unregistered device has no way through Tor (FR-019)', () async {
      // Version-3 links carry no one-time access key, so a device pairs at
      // home until phase 045, and only its own registered key opens the
      // onion service.
      tor.supported = true;
      await addresses.saveFromServer(direct: const <String>[], onion: _onion);
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.target, isNull);
    });

    test('a client that will not take the key is no path this round', () async {
      await torWorks();
      tor.takesTargets = false;
      prober.home = <String>{};

      expect(await selector.nextTarget(), isNull);
      expect(tor.starts, 1);
    });

    test('the key is given to the client on every bring-up, not only when it changed', () async {
      // Nothing says whether a client rebuilt after a failure still holds it.
      await torWorks();
      prober.home = <String>{};
      await selector.nextTarget();
      final sets = tor.targetSets;

      await selector.nextTarget();

      expect(tor.targetSets, sets + 1);
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

    test('a start that did not take is no path this round, at once', () async {
      // Refused by the library, or overtaken by a stop: waiting on a client
      // that is not running spent the whole budget of the round.
      await torWorks();
      tor.afterStart = TorStatus.stopped;
      prober.home = <String>{};
      final watch = Stopwatch()..start();

      expect(await selector.nextTarget(), isNull);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 350)), reason: 'the budget is 400 ms');
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
      selector = build(forceTor: true)..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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

  group('away from home the last time (T053)', () {
    test('a greeting through Tor is remembered for the next attempt', () async {
      await torWorks();
      prober.home = <String>{};
      await connectAndGreet();

      await waitUntil(() async => (await addresses.read()).data!.viaTorLast, reason: 'remembered');
    });

    test('Tor comes up while the direct addresses are tried, not after them', () async {
      await torWorks();
      await addresses.recordGreetedViaTor();
      final probing = Completer<void>();
      prober.gate = probing.future;
      prober.home = <String>{};

      final round = selector.nextTarget();
      await waitUntil(() => prober.rounds.isNotEmpty, reason: 'the probe is under way');
      await waitUntil(() => tor.starts == 1, reason: 'Tor started during the probe');
      probing.complete();

      expect(await round, Uri.parse('wss://$_onionHost/ws'));
    });

    test('a direct answer still wins, and Tor started alongside it stops', () async {
      await torWorks();
      await addresses.recordGreetedViaTor();
      prober.home = <String>{_link};

      await connectAndGreet();

      expect(selector.currentPath, ConnectionPath.direct);
      await waitUntil(() => tor.status.state == TorState.stopped, reason: 'Tor stopped on the direct greeting (FR-006)');
      expect((await addresses.read()).data!.viaTorLast, isFalse, reason: 'home again');
    });

    test('without the mark, Tor waits for the direct addresses as before', () async {
      await torWorks();
      final probing = Completer<void>();
      prober.gate = probing.future;
      prober.home = <String>{};

      final round = selector.nextTarget();
      await waitUntil(() => prober.rounds.isNotEmpty, reason: 'the probe is under way');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tor.starts, 0);
      probing.complete();
      await round;
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
      selector = build(recheckEvery: const Duration(milliseconds: 150))
        ..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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

    test('back in front on Tor, the key stays with the client: there is no listener to renew (phase 044)', () async {
      await onTor();
      final clears = tor.targetClears;

      lifecycle.go(AppVisibility.background);
      lifecycle.go(AppVisibility.foreground);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(tor.targetClears, clears, reason: 'the bridge and its listening socket are gone');
      expect(tor.target?.host, _onionHost);
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
      selector = build(mobile: false)..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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
    // What the channel's onion connect reports in the status, as the bridge
    // did before it.
    const refused = TorStatus(state: TorState.ready, bootstrapPercent: 100, error: TorError.wrongClientAuth);

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
      )..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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

    test('a restart in the middle of a run of refusals starts a new run', () async {
      // The status stream reports changes only, and a client that keeps being
      // refused keeps one error: without forgetting the last one seen, the
      // next session never noticed a refusal at all, and Tor went on dialling
      // with a key the service does not know.
      await selector.end();
      ConnectionPathSelector build100() => ConnectionPathSelector.forTest(
        prober,
        tor,
        addresses,
        keys,
        network,
        lifecycle,
        socket,
        keyRefusalGrace: const Duration(milliseconds: 100),
        torReadyBudget: const Duration(milliseconds: 400),
      );
      selector = build100()..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
      await torWorks();
      prober.home = <String>{};
      expect(await selector.nextTarget(), isNotNull);
      tor.emit(refused);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await selector.end(keepTor: true);
      selector.begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
      tor.afterStart = refused;
      for (var i = 0; i < 3; i++) {
        await selector.nextTarget();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }

      expect(await selector.nextTarget(), isNull, reason: 'the key counts as unknown after the grace');
      expect((await keys.isRegistered()).data, isFalse);
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
      )..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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

    selector.begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
    expect(selector.selection.active, isTrue);
  });

  test('ending does not wait on a source whose cancel never finishes', () async {
    // On an iOS simulator the network source's first answer never came, and an
    // `async*` stream suspended on it cannot finish cancelling. Awaiting that
    // cancel wedged the channel restart a sign-in waits on.
    await selector.end();
    selector = ConnectionPathSelector.forTest(prober, tor, addresses, keys, _StuckNetwork(), lifecycle, socket)
      ..begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
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

  group('a restart of the channel (phase 042)', () {
    Future<void> onTorHere() async {
      await torWorks();
      prober.home = <String>{};
      await connectAndGreet();
      expect(selector.currentPath, ConnectionPath.tor);
    }

    test('keeps a Tor client that is ready', () async {
      await onTorHere();
      final stops = tor.stops;

      await selector.end(keepTor: true);

      expect(tor.stops, stops, reason: 'a healthy client is worth keeping');
    });

    test('keeps a Tor client still coming up within its budget, so a second press loses nothing', () async {
      await torWorks();
      prober.home = <String>{};
      tor.afterStart = const TorStatus(state: TorState.bootstrapping, bootstrapPercent: 30);
      unawaited(selector.nextTarget());
      await waitUntil(() => tor.starts == 1, reason: 'Tor is coming up');
      final stops = tor.stops;

      await selector.end(keepTor: true);

      expect(tor.stops, stops);
    });

    test('stops a Tor client coming up for longer than its budget, and the next round starts it afresh', () async {
      await torWorks();
      prober.home = <String>{};
      tor.afterStart = const TorStatus(state: TorState.bootstrapping, bootstrapPercent: 15);
      // Waits out the readiness budget (400 ms here) and finds no path.
      expect(await selector.nextTarget(), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tor.status.state, TorState.bootstrapping, reason: 'stuck, the way Arti can stay at 15 %');
      final stops = tor.stops;

      await selector.end(keepTor: true);

      expect(tor.stops, stops + 1, reason: 'coming up for longer than the budget is not coming up');
      selector.begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
      tor.afterStart = const TorStatus(state: TorState.ready, bootstrapPercent: 100);
      final starts = tor.starts;
      expect(await selector.nextTarget(), isNotNull);
      expect(tor.starts, starts + 1, reason: 'started afresh');
    });

    test('stops a Tor client that failed', () async {
      await onTorHere();
      tor.emit(const TorStatus(state: TorState.failed));
      final stops = tor.stops;

      await selector.end(keepTor: true);

      expect(tor.stops, stops + 1);
    });

    test('the strip gives way after a restart, and comes back when the new round fails too', () async {
      prober.home = <String>{};
      expect(await selector.nextTarget(), isNull);
      expect(selector.selection.roundFailed, isTrue, reason: 'No connection');

      await selector.end(keepTor: true);
      selector.begin(linkAddress: _link, serverKey: _serverKey, deviceSeed: _deviceSeed);
      expect(selector.selection.roundFailed, isFalse, reason: 'connecting again');

      expect(await selector.nextTarget(), isNull);
      expect(selector.selection.roundFailed, isTrue, reason: 'No connection again');
    });

    test('back in front during an attempt under way, the attempt is left to finish', () async {
      prober.home = <String>{};
      final gate = Completer<void>();
      prober.gate = gate.future;
      unawaited(socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials()));
      await waitUntil(() => prober.rounds.isNotEmpty, reason: 'an attempt is under way');
      expect(socket.currentPhase, SessionPhase.connecting);

      lifecycle.go(AppVisibility.background);
      lifecycle.go(AppVisibility.foreground);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(prober.rounds, hasLength(1), reason: 'not restarted - the path-choice bound ends a hung one');
      gate.complete();
    });

    test('a network change with the socket on the ladder tries again at once', () async {
      prober.home = <String>{};
      await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
      await waitUntil(() => socket.currentPhase == SessionPhase.disconnected, reason: 'on the ladder');
      final asked = prober.rounds.length;

      network.changes.add(null);

      await waitUntil(() => prober.rounds.length > asked, reason: 'a new round, not the next rung');
    });

    test('with a live connection, a return to the front leaves it alone', () async {
      prober.home = <String>{_link};
      await connectAndGreet();
      final dialled = factory.created.length;

      lifecycle.go(AppVisibility.background);
      lifecycle.go(AppVisibility.foreground);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(factory.created, hasLength(dialled));
      expect(socket.currentPhase, SessionPhase.live);
    });
  });
}

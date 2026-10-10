import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/connection_status_service_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../remote/socket/fake_socket.dart';
import 'fake_direct_prober.dart';

class _Network implements NetworkChangeService {
  @override
  Stream<void> watchChanges() => const Stream<void>.empty();
}

class _Lifecycle implements AppLifecycleService {
  @override
  AppVisibility get visibility => AppVisibility.foreground;

  @override
  Stream<AppVisibility> watchVisibility() => const Stream<AppVisibility>.empty();
}

/// The wrong-server banner, from the channel's refusal up to the screen
/// (phase 044, T030, FR-011): another key at a DIRECT address is "not home"
/// and shows nothing, while behind the ONION address it is the banner. The
/// socket, the path selector and the status are the real ones; only the
/// connections and the probe are fakes.
void main() {
  late FakeSocketFactory factory;
  late NoxSocketClient socket;
  late FakeDirectProber prober;
  late FakeTorService tor;
  late ConnectionPathSelector selector;
  late LiveConnectionStatusService status;
  const link = '10.0.0.5:9000';
  final onionHost = '${'a' * 56}.onion';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    factory = FakeSocketFactory();
    socket = NoxSocketClient.forTest(
      factory,
      getIt<SyncRepository>(),
      minBackoff: const Duration(milliseconds: 20),
      maxBackoff: const Duration(milliseconds: 40),
    );
    prober = FakeDirectProber(home: {link});
    tor = FakeTorService();
    selector = ConnectionPathSelector.forTest(
      prober,
      tor,
      getIt<ServerAddressesRepository>(),
      getIt<AccessKeyRepository>(),
      _Network(),
      _Lifecycle(),
      socket,
      torReadyBudget: const Duration(milliseconds: 400),
    )..begin(linkAddress: link, serverKey: Uint8List(32), deviceSeed: Uint8List(32));
    status = LiveConnectionStatusService(socket, selector, tor);
    getIt.allowReassignment = true;
    getIt.registerSingleton<ConnectionStatusService>(status);
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

  Future<ChatsListBloc> chatsList() async {
    final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
    addTearDown(bloc.close);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return bloc;
  }

  test('another key at a direct address never raises the banner: the next attempt is made, and nothing shows', () async {
    final seen = <LinkState>[];
    final sub = status.watchStatus().listen((s) => seen.add(s.state));
    addTearDown(sub.cancel);
    await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
    await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');

    factory.latest.refuseServerKey();
    await waitUntil(() => factory.created.length >= 2, reason: 'the ladder goes on to the next attempt');
    final bloc = await chatsList();

    expect(seen, isNot(contains(LinkState.serverMismatch)));
    expect((bloc.state as Initialized).isServerMismatch, isFalse);
  });

  test('another key behind the onion address is the banner', () async {
    tor.supported = true;
    await getIt<ServerAddressesRepository>().saveFromServer(direct: const <String>[], onion: '$onionHost:443');
    await getIt<AccessKeyRepository>().deviceKey();
    await getIt<AccessKeyRepository>().markRegistered(true);
    prober.home = <String>{};
    await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
    await waitUntil(() => factory.created.isNotEmpty, reason: 'dialled');
    expect(factory.latest, isNotNull);
    expect(factory.urls.single.host, onionHost);

    factory.latest.refuseServerKey();
    await waitUntil(() => status.status.isServerMismatch, reason: 'the banner');
    final bloc = await chatsList();

    expect((bloc.state as Initialized).isServerMismatch, isTrue);
    expect((bloc.state as Initialized).isOffline, isFalse, reason: '"no connection" would be false here');
  });
}

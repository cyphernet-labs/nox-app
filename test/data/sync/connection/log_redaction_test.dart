import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logger/logger.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/repository/log_repository_impl.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/connection/tor_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/app_lifecycle_service.dart';
import 'package:nox_app/domain/service/network_change_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../remote/channel/fake_channel.dart';
import '../../remote/socket/fake_socket.dart';
import '../live_identity_handshake_test.mocks.dart';
import 'fake_direct_prober.dart';

/// Nothing that names the server's onion service, opens it, or pairs with the
/// server reaches a log line (phase 040, FR-013, SC-008; phase 044, FR-022;
/// Constitution I): not from the path selector, not from a pairing, not from
/// a channel that would not open - and not from an exception somebody else
/// wrote.
final String _onionHost = '${'a' * 56}.onion';

/// The contract's `full` vector: a direct address, a name and an onion
/// service.
const String _link =
    'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';

class _Capture extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

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

class _Repository with BaseRepositoryHelper {
  Future<RepositoryResult<bool>> run(Future<RepositoryResult<bool>> Function() body) => execute<bool>(body);
}

void main() {
  late _Capture capture;
  late FakeSocketFactory factory;
  late NoxSocketClient socket;
  late FakeTorService tor;
  late ConnectionPathSelector selector;
  final serverKey = Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
  final deviceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));

  /// Every secret the run handles, as the wire, the store and the link spell
  /// them.
  late List<String> secrets;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    capture = _Capture();
    getIt.allowReassignment = true;
    getIt.registerSingleton<LogRepository>(LoggerLogRepository.withOutput(capture));

    factory = FakeSocketFactory();
    socket = NoxSocketClient(factory, getIt<SyncRepository>());
    tor = getIt<TorService>() as FakeTorService..supported = true;
    selector = ConnectionPathSelector.forTest(
      FakeDirectProber(home: <String>{}),
      tor,
      getIt<ServerAddressesRepository>(),
      getIt<AccessKeyRepository>(),
      _Network(),
      _Lifecycle(),
      socket,
    );
    final own = (await getIt<AccessKeyRepository>().deviceKey()).data!;
    final link = PairingLink.parse(_link);
    secrets = [
      own.publicBase64,
      base64Encode(own.privateKey),
      base64Encode(deviceSeed),
      base64Encode(serverKey),
      link.token,
      _link.substring(PairingLink.prefix.length),
    ];
  });

  tearDown(() async {
    await socket.stop();
    await selector.end();
    await getIt.reset();
  });

  void expectNothingLeaked() {
    final all = capture.lines.join('\n');
    expect(all, isNot(contains('.onion')), reason: 'an onion address reached the log');
    expect(all, isNot(contains('nox://pair/A')), reason: 'a pairing link reached the log');
    for (final secret in secrets) {
      expect(all, isNot(contains(secret)), reason: 'key material reached the log');
    }
  }

  test('a run through Tor names no onion address', () async {
    await getIt<ServerAddressesRepository>().saveFromServer(direct: const ['10.0.0.5:9000'], onion: '$_onionHost:443');
    await getIt<AccessKeyRepository>().deviceKey();
    await getIt<AccessKeyRepository>().markRegistered(true);
    selector.begin(linkAddress: '10.0.0.5:9000', serverKey: serverKey, deviceSeed: deviceSeed);

    await socket.start(targets: selector, credentialsProvider: () async => const GreetingCredentials());
    // The path is chosen after start() returns.
    for (var i = 0; i < 200 && factory.created.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final peer = factory.latest;
    peer.pushGreeting();
    for (var i = 0; i < 200 && peer.commandNamed('session.hello') == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    peer.replyToHello(cursor: 0);
    for (var i = 0; i < 200 && socket.currentPhase != SessionPhase.live; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // The service turns the key away, and the selector says so.
    tor.emit(const TorStatus(state: TorState.ready, bootstrapPercent: 100, error: TorError.wrongClientAuth));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(factory.urls.single.host, _onionHost, reason: 'the run did go through Tor');
    expect(capture.lines, isNotEmpty);
    expectNothingLeaked();
  });

  test('a pairing names neither the link, its token nor an address', () async {
    final starter = MockLiveSessionStarter();
    when(starter.restart()).thenAnswer((_) async {
      await socket.stop();
      await socket.start(url: Uri.parse('wss://10.0.0.5:9000/ws'), credentialsProvider: () async => const GreetingCredentials.unpaired());
      factory.latest.pushGreeting();
    });
    final handshake = LiveIdentityHandshake(socket, starter, getIt<AccessKeyRepository>());

    Object? outcome;
    unawaited(handshake.pair(link: PairingLink.parse(_link), platform: 'ios').then((v) => outcome = v, onError: (Object e) => outcome = e));
    for (var i = 0; i < 200 && (factory.created.isEmpty || factory.latest.commandNamed('pair') == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    factory.latest.reply(factory.latest.sent.indexWhere((f) => f['cmd'] == 'pair'), ok: false, code: 'internal');
    for (var i = 0; i < 200 && outcome == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(outcome, isA<PairingFailed>());
    expectNothingLeaked();
  });

  test('a channel that would not open through Tor fails without naming where it was going, or with what', () async {
    // The real HttpClient, not the test binding's stand-in that answers 400.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final api = ScriptedChannelApi()..answer = (_) => throw const ChannelOpenException(ChannelFailure.torOnionNotFound);
    final channels = ChannelHttpClient(api)..bind(serverKey: serverKey, deviceSeed: deviceSeed);
    addTearDown(channels.unbind);
    final repository = _Repository();

    final result = await repository.run(() async {
      final request = await channels.client.getUrl(Uri.parse('https://$_onionHost/files/abc'));
      await request.close();
      return const RepositoryResult<bool>.success(data: true);
    });

    expect(result.hasData, isFalse);
    expect(capture.lines.join('\n'), contains('channel: onion failed (torOnionNotFound)'));
    expectNothingLeaked();
  });

  test('an exception that carries the onion URI is scrubbed on the way out', () async {
    // dart:io writes the request URI into HttpException, and repositories log
    // what they catch. Nobody wrote this text, so the log has to catch it.
    final repository = _Repository();

    await repository.run(
      () async => throw HttpException('Connection closed while receiving data', uri: Uri.parse('https://$_onionHost/files/abc')),
    );

    expect(capture.lines.join('\n'), contains('[onion]'));
    expectNothingLeaked();
  });
}

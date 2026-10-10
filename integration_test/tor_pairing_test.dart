import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:integration_test/integration_test.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/connection/direct_prober.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_tor/channel.dart';
import 'package:uuid/uuid.dart';

/// "Away from home" on demand: while [away] is set, no direct address answers.
class _AwayProber implements DirectProber {
  _AwayProber(this._real);

  final DirectProber _real;
  bool away = false;

  @override
  Future<DirectProbeResult> probe(List<String> candidates, {required Uint8List serverKey, required Uint8List deviceSeed}) => away
      ? Future<DirectProbeResult>.value(const DirectProbeResult())
      : _real.probe(candidates, serverKey: serverKey, deviceSeed: deviceSeed);
}

/// Device B on a simulator or an emulator, as phases 045 and 046 have it: away
/// from home - no direct address answers - an invite carrying the onion
/// address pairs THROUGH TOR, with `Use Tor` ticked on the connection screen,
/// once the device that issued it says Allow, and the device talks to its
/// server through Tor. No access key anywhere. The Tor client and the channel
/// are the real ones, in the app's process on that platform.
///
/// An invite pairs nothing until the device that issued it allows it (phase
/// 046), so the run brings that device itself ([_Issuer]): paired at home by a
/// machine link - it dials the link's direct address, which the simulator or
/// the emulator has to reach - it issues the invite and answers the request.
///
/// Manual, like the live probes: it needs a running `noxd` whose onion
/// service a separate tor publishes, and a fresh machine link for every run -
/// `test/live/tor_live_probe.dart` leaves the server and its tor behind, with
/// the service page's address in `<work>/page.txt`:
///   fvm flutter test integration_test/tor_pairing_test.dart -d DEVICE \
///     --dart-define=link="$(/tmp/noxd link -status-addr "$(cat /tmp/nox_e2e/page.txt)" | head -1)"
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');

  testWidgets(
    'away from home, an invite pairs through Tor with Use Tor on once its device allows it, and the device talks through Tor',
    (tester) async {
      if (link.isEmpty) {
        debugPrint('SKIP: pass --dart-define=link=<a machine link: noxd\'s service page, or `noxd link`>');
        return;
      }
      await configureDependencies(Environment.dev);
      await getIt.allReady();
      await getIt<AppConfigRepository>().initialize(flavorType: AppFlavorType.stage);
      // Registered before anything resolves the path selector.
      getIt.allowReassignment = true;
      final away = _AwayProber(ChannelDirectProber(const NativeNoxChannelApi()))..away = true;
      getIt.registerSingleton<DirectProber>(away);
      final tor = getIt<TorService>();

      // The issuing device, at home: paired by the machine link, it issues the
      // invite this device then pairs by.
      final issuer = await _Issuer.pair(link);
      addTearDown(issuer.close);
      final inviteLink = await issuer.invite();
      final invite = PairingLink.parse(inviteLink);
      final serviceKey = invite.onionServiceKey;
      final derived = serviceKey == null ? null : tor.onionFromPublicKey(serviceKey);
      debugPrint('TOR: supported=${tor.isSupported} status=${tor.status} onion in the invite=${derived != null}');
      final socket = getIt<NoxSocketClient>();
      final selector = getIt<ConnectionPathSelector>();
      final rssBefore = ProcessInfo.currentRss;

      expect(derived, isNotNull, reason: 'the invite names the onion service, and the module derives its address');

      // As the connection screen hands it over: the link's addresses, and Use
      // Tor ticked (phase 045). The request reaches the issuing device once this
      // one got through Tor, and the sign-in waits for the answer (phase 046).
      final asked = issuer.nextRequest(within: const Duration(minutes: 8));
      final watch = Stopwatch()..start();
      final signingIn = getIt<AuthRepository>().signIn(
        identifier: inviteLink,
        connection: ConnectionSettings(serverAddress: invite.directAddresses.first, onionAddress: '$derived:443', useTor: true),
      );
      final first = await Future.any<Object>([asked, signingIn]);
      if (first is! String) {
        asked.ignore();
        fail('the sign-in ended before the issuing device was asked: ${(first as RepositoryResult<bool>).exception}');
      }
      debugPrint('MEASURE: asked on the issuing device in ${watch.elapsedMilliseconds} ms');
      await issuer.allow(first);
      final signedIn = await signingIn;
      debugPrint('MEASURE: paired through Tor in ${watch.elapsedMilliseconds} ms (${signedIn.hasData ? 'ok' : signedIn.exception})');
      expect(signedIn.hasData, isTrue, reason: 'the pairing, through Tor');
      await _until('live through Tor', const Duration(minutes: 4), () {
        return socket.currentPhase == SessionPhase.live && selector.currentPath == ConnectionPath.tor;
      });
      debugPrint('MEASURE: live through Tor ${watch.elapsedMilliseconds} ms after the start');

      final chat = await getIt<ChatRepository>().createChat(
        name: 'From ${Platform.operatingSystem} ${DateTime.now().millisecondsSinceEpoch}',
      );
      expect(chat.hasData, isTrue);
      // A chat is made on the device first (phase 041): the outbox takes it to
      // the server, and only then can a message name it.
      getIt<OutboxService>().start();
      unawaited(getIt<OutboxService>().flush());
      await _until('the chat on the server', const Duration(minutes: 2), () => getIt<ChatRepository>().isOnServer(chatId: chat.data!.id));
      final sendWatch = Stopwatch()..start();
      final sent = await getIt<MessageRepository>().sendMessage(
        chatId: chat.data!.id,
        clientMessageId: const Uuid().v4(),
        text: 'hello through Tor from ${Platform.operatingSystem}',
      );
      debugPrint('MEASURE: a message through Tor in ${sendWatch.elapsedMilliseconds} ms');
      expect(sent.hasData, isTrue);
      debugPrint(
        'MEASURE: RSS ${(rssBefore / 1048576).toStringAsFixed(1)} MB before, '
        '${(ProcessInfo.currentRss / 1048576).toStringAsFixed(1)} MB on Tor',
      );

      // An invite issued by THIS device, through Tor, carries the onion address
      // too, so a device it allows pairs through Tor as well (phase 045).
      final next = await getIt<DeviceRepository>().inviteDevice();
      expect(next.data?.onion, isTrue, reason: 'issued through Tor, and carrying the onion address');
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

/// The device that issued the invite, spoken for over the wire: a key of its
/// own, its own channel and socket - the classes the app uses, without the
/// app around them.
class _Issuer {
  _Issuer._(this._link) {
    final seed = Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    _channel = ChannelHttpClient(const NativeNoxChannelApi())..bind(serverKey: _link.serverKey, deviceSeed: seed);
    _socket = NoxSocketClient(WebSocketChannelFactory(_channel), _NoCursor());
  }

  final PairingLink _link;
  late final ChannelHttpClient _channel;
  late final NoxSocketClient _socket;

  Uri get _url => Uri.parse('wss://${_link.directAddresses.first}/ws');

  /// Pairs a new device by [machineLink], and greets as it.
  static Future<_Issuer> pair(String machineLink) async {
    final issuer = _Issuer._(PairingLink.parse(machineLink));
    final socket = issuer._socket;
    await socket.start(url: issuer._url, credentialsProvider: () async => const GreetingCredentials.unpaired());
    final reply = await socket.pair(token: issuer._link.token, platform: 'linux');
    expect(reply.ok && reply.data?['identity'] != null, isTrue, reason: 'pair: ${reply.errorCode}');
    await socket.stop();
    await socket.start(url: issuer._url, credentialsProvider: () async => const GreetingCredentials());
    await _until('the issuing device greeted', const Duration(seconds: 15), () => socket.identity != null);
    return issuer;
  }

  /// Issues an invite and returns its link.
  Future<String> invite() async {
    final reply = await _socket.send('device.invite', <String, dynamic>{});
    expect(reply.ok, isTrue, reason: 'device.invite: ${reply.errorCode}');
    return reply.data!['link'] as String;
  }

  /// The id of the next request this device is asked about.
  Future<String> nextRequest({required Duration within}) => _socket.events
      .firstWhere((e) => e.event == ServerEvent.devicePairRequested)
      .timeout(within)
      .then((e) => e.data['request_id'] as String);

  /// Allow.
  Future<void> allow(String requestId) async {
    final reply = await _socket.send('device.approve', <String, dynamic>{'request_id': requestId, 'allow': true});
    expect(reply.ok, isTrue, reason: 'device.approve: ${reply.errorCode}');
  }

  Future<void> close() async {
    await _socket.stop();
    _channel.unbind();
  }
}

/// The issuing device keeps no cursor: it reads nothing from the journal.
class _NoCursor implements SyncRepository {
  @override
  Future<int> getCursor() async => 0;
  @override
  Future<bool> hasCursor() async => false;
  @override
  Future<void> advanceCursor(int seq) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<String?> getEpoch() async => null;
  @override
  Future<void> setEpoch(String epoch) async {}
  @override
  Future<String?> getJournal() async => null;
  @override
  Future<void> setJournal(String journalId) async {}
}

Future<void> _until(String what, Duration budget, FutureOr<bool> Function() done) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < budget) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('not reached within ${budget.inSeconds} s: $what');
}

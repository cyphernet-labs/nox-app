@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/pairing_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/pair_request_service.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_tor/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_target.dart';

/// Drives the REAL client code against a running `noxd`, which is the gap the
/// first live run left: it spoke the wire directly and so never exercised the
/// client's own greeting, which turned out to be the defect that mattered.
///
/// Since phase 046 it drives pairing with approval from both sides: the app as
/// the NEW device waiting for Allow on the device that issued the invite, and
/// the app as the ISSUING device asked about a new one. The other side is a
/// device of its own key spoken for over the wire ([_Wire]), with the same
/// socket and channel classes the app uses.
///
/// Run manually, not in the gate: it needs a server, and the native module
/// built from this tree (every connection is a channel of it, phase 044).
///   1. cd client_backend && go build -o /tmp/noxd . && /tmp/noxd -db /tmp/t.db -addr 0.0.0.0:8443 -status-addr 127.0.0.1:8081
///   2. flutter test test/live/pairing_live_probe.dart --dart-define=status=127.0.0.1:8081
///
/// With `status` every test asks the running server for a machine link of its
/// own, the way `noxd link` does (`POST /control/link`), so the three run in
/// one go - each new link voids the one before it. Without it, the first test
/// alone runs on `--dart-define=link=<machine link>` from the service page.
/// `--dart-define=expiry=true` adds a fourth that waits out an invite's ten
/// minutes, so it is off unless asked for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const link = String.fromEnvironment('link');
  const status = String.fromEnvironment('status');
  const expiry = bool.fromEnvironment('expiry');

  setUpAll(() async {
    LiveTarget.letTheNetworkThrough();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.dev);
    await getIt.allReady();
  });

  test('a machine link pairs, names the person, lists the device and revokes it', () async {
    final machine = link.isNotEmpty ? link : (status.isEmpty ? null : await _machineLink(status));
    if (machine == null) {
      stdout.writeln('SKIP: pass --dart-define=status=<service page address>, or --dart-define=link=<machine link>');
      return;
    }

    final auth = getIt<AuthRepository>();
    final session = getIt<SessionRepository>();
    final devices = getIt<DeviceRepository>();

    // An install upgraded from a build that still wrote the ownership key. The
    // sweep has nothing to prove on a fresh one, and this probe is the only
    // place the whole path runs against a real server. Seeded and then swept in
    // the same order main() does it - the key is written by the OLD build, and
    // the new one drops it at bootstrap rather than on the first read.
    await (await SharedPreferences.getInstance()).setBool('session.is_owner', true);
    await session.sweepLegacyKeys();

    final signedIn = await auth.signIn(identifier: machine);
    stdout.writeln('SIGN IN: ${signedIn.hasData ? 'ok' : signedIn.exception}');
    expect(signedIn.hasData, isTrue, reason: 'the whole flow starts here');
    // On a server with nobody yet the machine link creates the person, and the
    // name is chosen next (2.3); on one with a person it joins them.
    final state = (await getIt<AppStateRepository>().fetchAppState()).data?.state;
    stdout.writeln('STATE: $state');
    expect(state, anyOf(AppStateType.registrationPending, AppStateType.authorized));

    // The wipe-on-refusal bug showed up exactly here: the key and the address
    // were deleted while pairing succeeded, spending the one-shot token.
    stdout.writeln('SERVER: ${(await session.serverAddress()).data}');
    expect((await session.serverAddress()).data, isNotNull, reason: 'the paired server must survive the sign-in');
    expect((await session.deviceSecret()).hasData, isTrue, reason: 'the device key must survive the sign-in');

    final named = await auth.completeOnboarding(label: 'LiveAnna');
    stdout.writeln('NAME: ${named.hasData ? 'ok' : named.exception}');
    expect(named.hasData, isTrue);

    await Future<void>.delayed(const Duration(seconds: 2));
    final list = await devices.getDevices();
    stdout.writeln('DEVICES: ${list.data?.map((d) => '${d.platform}/current=${d.isCurrent}').toList()}');
    expect(list.hasData, isTrue);
    expect(list.data!.where((d) => d.isCurrent).length, 1, reason: 'this device has to recognise itself');

    final invite = await devices.inviteDevice();
    stdout.writeln('INVITE: ${invite.hasData ? 'ok' : invite.exception}');
    expect(invite.hasData, isTrue);

    // The link a person carries to their other device has to be dialable from
    // there. A server bound to a wildcard used to put loopback in it, which is
    // reachable from this machine and nowhere else. And it names the same
    // server key the first link did: there is one server.
    final parsed = PairingLink.parse(invite.data!.link);
    stdout.writeln('INVITE LINK: ${parsed.directAddresses.first}');
    expect(parsed.directAddresses.first, (await session.serverAddress()).data);
    expect(parsed.serverKeyBase64, (await session.serverKey()).data);
    // The reply's flag says what the link carries (phase 045): an invite names
    // the onion service exactly when the server has one, and the card calls a
    // link with neither it nor a public address home-only.
    expect(invite.data!.onion, parsed.onionServiceKey != null);

    // A rename travels as its own command now. The reply carries the name back,
    // which is what proves it landed rather than being accepted locally.
    final renamed = await devices.setLabel(label: 'LiveBobbi');
    stdout.writeln('RENAME: ${renamed.hasData ? 'ok' : renamed.exception}');
    expect(renamed.hasData, isTrue);

    // Signing out revokes this device's own key, so the key stops being a way
    // in rather than merely being forgotten here.
    final out = await auth.logout();
    stdout.writeln('LOGOUT: ${out.hasData ? 'ok' : out.exception}');
    expect(out.hasData, isTrue);
    expect((await session.readSession()).data, isNull);
    expect((await session.serverAddress()).data, isNull);
    // The key an older build wrote is gone. Seeded above BEFORE the sign-in,
    // because a fresh install never has it - and an assertion on a key nothing
    // ever wrote passes whether the sweep exists or not.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('session.is_owner'), isNull, reason: 'the legacy key survived a full session');
    expect(prefs.getString('session.author_id'), isNull);

    // And the token really is spent on the server: the same link cannot be
    // reused by the next install's key - a fresh pairing needs a fresh link.
    final again = await auth.signIn(identifier: machine);
    stdout.writeln('REUSE: ${again.hasData ? 'accepted' : again.exception}');
    expect(again.hasData, isFalse, reason: 'a machine link pairs once');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
    'an invite pairs this device only after Allow on the device that issued it; Deny and Cancel end the wait',
    () async {
      if (status.isEmpty) {
        stdout.writeln('SKIP: pass --dart-define=status=<service page address>');
        return;
      }
      final auth = getIt<AuthRepository>();
      final session = getIt<SessionRepository>();

      // The issuing device: paired by a machine link of its own, greeted. The
      // person may hold devices from earlier runs: counts are taken from here.
      final issuer = await _Wire.paired(await _machineLink(status), platform: 'linux');
      addTearDown(issuer.close);
      final before = (await issuer.devices()).length;

      // --- Allow. ---
      final first = await _presentAndWait(auth, issuer);
      expect(first.asked.data['platform'], PlatformUtils.family, reason: 'the question names the family this device gave');
      expect(await issuer.approve(first.requestId, allow: true), isTrue);
      final allowed = await first.signIn;
      stdout.writeln('ALLOW: ${allowed.hasData ? 'paired' : allowed.exception}');
      expect(allowed.hasData, isTrue);
      expect(
        (await getIt<AppStateRepository>().fetchAppState()).data?.state,
        AppStateType.authorized,
        reason: 'an invite joins the person who issued it: there is no name to choose',
      );
      expect((await session.readPendingPairing()).data, isNull, reason: 'the wait is forgotten once it ends - the link is a credential');
      final listed = await issuer.devices();
      stdout.writeln('ISSUER SEES: ${listed.length} devices');
      expect(listed.length, before + 1);

      // Signing out revokes this device's own key over its greeted connection.
      expect((await auth.logout()).hasData, isTrue);
      expect((await issuer.devices()).length, before, reason: 'the logout revoked this device on the server');

      // --- Deny. ---
      final second = await _presentAndWait(auth, issuer);
      expect(await issuer.approve(second.requestId, allow: false), isTrue);
      final denied = await second.signIn;
      stdout.writeln('DENY: ${denied.hasData ? 'paired' : denied.exception}');
      expect(denied.exception, PairingException.declined);
      expect((await session.readSession()).data, isNull, reason: 'a declined sign-in leaves nothing behind');

      // --- Cancel. ---
      final third = await _presentAndWait(auth, issuer);
      final over = issuer.next(ServerEvent.devicePairResolved, requestId: third.requestId);
      await auth.cancelPairing();
      final cancelled = await third.signIn;
      stdout.writeln('CANCEL: ${cancelled.hasData ? 'paired' : cancelled.exception}');
      expect(cancelled.exception, PairingException.cancelled);
      await over; // the issuing device stops being asked
      expect(await issuer.approve(third.requestId, allow: true), isFalse, reason: 'an Allow after Cancel finds nothing to allow');
      expect((await session.readSession()).data, isNull);
      expect((await issuer.devices()).length, before, reason: 'neither Deny nor Cancel paired anything');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'this device is asked about a new device, answers Allow and Deny, and the last device leaving brings the link back',
    () async {
      if (status.isEmpty) {
        stdout.writeln('SKIP: pass --dart-define=status=<service page address>');
        return;
      }
      final auth = getIt<AuthRepository>();
      final devices = getIt<DeviceRepository>();
      final requests = getIt<PairRequestService>();

      // The person exists already: a machine link joins them, with no name to
      // choose.
      final signedIn = await auth.signIn(identifier: await _machineLink(status));
      expect(signedIn.hasData, isTrue);
      expect((await getIt<AppStateRepository>().fetchAppState()).data?.state, AppStateType.authorized);

      // --- Allow, from this device. ---
      final invite = await devices.inviteDevice();
      expect(invite.hasData, isTrue, reason: 'device.invite: ${invite.exception}');
      final newcomer = _Wire(PairingLink.parse(invite.data!.link));
      addTearDown(newcomer.close);
      final closed = requests.watchClosed().first;
      expect((await newcomer.present(platform: 'windows')).data?['status'], 'pending');
      final asked = await requests.watchRequests().firstWhere((r) => r.isNotEmpty).timeout(const Duration(seconds: 15));
      stdout.writeln('ASKED: ${asked.single.platform}');
      expect(asked.single.platform, DevicePlatform.windows);
      expect((await requests.answer(requestId: asked.single.requestId, allow: true)).data, isTrue);
      final resolved = await newcomer.next(ServerEvent.pairResolved);
      expect(resolved.data['outcome'], 'allowed');
      expect(await closed.timeout(const Duration(seconds: 15)), asked.single.requestId);
      expect(await requests.watchRequests().first, isEmpty, reason: 'nothing left to ask about');

      // --- Deny, from this device. ---
      final invite2 = await devices.inviteDevice();
      expect(invite2.hasData, isTrue);
      final refused = _Wire(PairingLink.parse(invite2.data!.link));
      addTearDown(refused.close);
      expect((await refused.present(platform: 'ios')).data?['status'], 'pending');
      final asked2 = await requests.watchRequests().firstWhere((r) => r.isNotEmpty).timeout(const Duration(seconds: 15));
      expect(asked2.single.platform, DevicePlatform.ios);
      expect((await requests.answer(requestId: asked2.single.requestId, allow: false)).data, isTrue);
      expect((await refused.next(ServerEvent.pairResolved)).data['outcome'], 'denied');

      // --- The last device leaving. Every other device of the person is
      // revoked from here - the ones earlier runs left too - and then this one
      // logs out: the machine is back to "no devices", and its page shows a link
      // at once (FR-015).
      final all = await devices.getDevices();
      expect(all.hasData, isTrue);
      for (final device in all.data!.where((d) => !d.isCurrent)) {
        expect((await devices.revoke(deviceKey: device.deviceKey)).hasData, isTrue);
      }
      expect((await auth.logout()).hasData, isTrue);
      final page = await _get('http://$status/');
      stdout.writeln('PAGE AFTER THE LAST DEVICE: ${page.contains('nox://pair/') ? 'a link' : 'no link'}');
      expect(page, contains('nox://pair/'), reason: 'with no devices left the page leads with a machine link');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('a request nobody answers ends as an expired link once the invite\'s ten minutes are up', () async {
    if (status.isEmpty || !expiry) {
      stdout.writeln('SKIP: pass --dart-define=status=<service page address> and --dart-define=expiry=true (it waits ten minutes)');
      return;
    }
    final auth = getIt<AuthRepository>();
    final issuer = await _Wire.paired(await _machineLink(status), platform: 'linux');
    addTearDown(issuer.close);

    // The issuing device is asked and never answers - an app closed, or off
    // the network. The server closes the request at the invite's deadline by
    // itself; the new device reads the outcome as an expired link.
    final waiting = await _presentAndWait(auth, issuer);
    final over = issuer.next(ServerEvent.devicePairResolved, requestId: waiting.requestId, within: const Duration(minutes: 12));
    final watch = Stopwatch()..start();
    final expired = await waiting.signIn;
    stdout.writeln('NO ANSWER: ${expired.exception} after ${watch.elapsed.inSeconds} s');
    expect(expired.exception, RepositoryException.notFound, reason: 'an unanswered request reads as an expired link');
    await over;
    expect(await issuer.approve(waiting.requestId, allow: true), isFalse, reason: 'an Allow after the deadline finds nothing to allow');
  }, timeout: const Timeout(Duration(minutes: 13)));
}

/// A sign-in through an invite, under way and waiting: the request the issuing
/// device was asked about, and the sign-in itself, which ends with the answer.
class _Waiting {
  _Waiting(this.signIn, this.asked);

  final Future<RepositoryResult<bool>> signIn;
  final ServerEvent asked;

  String get requestId => asked.data['request_id'] as String;
}

/// Has [issuer] invite, starts this app's sign-in with the invite, and returns
/// once the app says it waits and the issuer has been asked.
Future<_Waiting> _presentAndWait(AuthRepository auth, _Wire issuer) async {
  final invite = await issuer.invite();
  final asked = issuer.next(ServerEvent.devicePairRequested);
  final waiting = auth.watchAwaitingApproval().firstWhere((w) => w);
  final signIn = auth.signIn(identifier: invite);
  await waiting.timeout(const Duration(seconds: 30));
  stdout.writeln('WAITING: Waiting for approval on your other device');
  return _Waiting(signIn, await asked);
}

/// A machine link from the running server, asked for the way `noxd link`
/// asks: `POST /control/link` on the service page's listener, with the
/// control header and no Origin.
Future<String> _machineLink(String status) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(Uri.parse('http://$status/control/link'));
    request.headers.set('X-Nox-Control', '1');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, 200, reason: 'POST /control/link: $body');
    return (jsonDecode(body) as Map<String, dynamic>)['link'] as String;
  } finally {
    client.close(force: true);
  }
}

/// The service page, as the browser on that machine reads it.
Future<String> _get(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// Another device of the same person, spoken for over the wire: a key of its
/// own, its own channel and socket - the classes the app uses, without the
/// app around them.
class _Wire {
  _Wire(this.link) : _seed = Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256))) {
    _channel = ChannelHttpClient(const NativeNoxChannelApi())..bind(serverKey: link.serverKey, deviceSeed: _seed);
    socket = NoxSocketClient(WebSocketChannelFactory(_channel), _NoCursor());
    _events = socket.events.listen(_seen.add);
  }

  /// Pairs a new device by a machine link and greets as it.
  static Future<_Wire> paired(String machineLink, {required String platform}) async {
    final wire = _Wire(PairingLink.parse(machineLink));
    final reply = await wire.present(platform: platform);
    expect(reply.ok && reply.data?['identity'] != null, isTrue, reason: 'pair: ${reply.errorCode}');
    await wire.greet();
    return wire;
  }

  final PairingLink link;
  final Uint8List _seed;
  late final ChannelHttpClient _channel;
  late final NoxSocketClient socket;
  late final StreamSubscription<ServerEvent> _events;
  final StreamController<ServerEvent> _seen = StreamController<ServerEvent>.broadcast();

  Uri get _url => Uri.parse('wss://${link.directAddresses.first}/ws');

  /// Presents this link's token as a device that is not paired yet.
  Future<CommandReply> present({required String platform}) async {
    await socket.start(url: _url, credentialsProvider: () async => const GreetingCredentials.unpaired());
    return socket.pair(token: link.token, platform: platform);
  }

  /// Opens the socket again as the paired device it now is, and greets.
  Future<void> greet() async {
    await socket.stop();
    await socket.start(url: _url, credentialsProvider: () async => const GreetingCredentials());
    final watch = Stopwatch()..start();
    while (socket.identity == null) {
      if (watch.elapsed > const Duration(seconds: 15)) fail('the wire device never greeted');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// The next [name] event - about [requestId], when given.
  Future<ServerEvent> next(String name, {String? requestId, Duration within = const Duration(seconds: 15)}) =>
      _seen.stream.firstWhere((e) => e.event == name && (requestId == null || e.data['request_id'] == requestId)).timeout(within);

  /// Issues an invite and returns its link.
  Future<String> invite() async {
    final reply = await socket.send('device.invite', <String, dynamic>{});
    expect(reply.ok, isTrue, reason: 'device.invite: ${reply.errorCode}');
    return reply.data!['link'] as String;
  }

  /// Answers a request; false when the server had nothing left to answer.
  Future<bool> approve(String requestId, {required bool allow}) async {
    final reply = await socket.send('device.approve', <String, dynamic>{'request_id': requestId, 'allow': allow});
    if (!reply.ok && reply.errorCode == 'not_found') return false;
    expect(reply.ok, isTrue, reason: 'device.approve: ${reply.errorCode}');
    return true;
  }

  /// The person's devices, as the server lists them.
  Future<List<dynamic>> devices() async {
    final reply = await socket.send('device.list', <String, dynamic>{});
    expect(reply.ok, isTrue, reason: 'device.list: ${reply.errorCode}');
    return reply.data!['devices'] as List<dynamic>;
  }

  Future<void> close() async {
    await _events.cancel();
    await socket.stop();
    _channel.unbind();
    await _seen.close();
  }
}

/// The wire devices keep no cursor: they read nothing from the journal.
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

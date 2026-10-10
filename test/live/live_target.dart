import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_tor/channel.dart';

/// Where a live probe dials, the key it insists on finding there, and the
/// device key it proves itself with (phase 044).
///
/// The first two come out of ONE `--dart-define=link=<pairing link>` - the
/// version-3 link a fresh `noxd` prints - because the address and the server
/// key are two halves of one fact and passing them separately is how they
/// come to disagree. The device key is new for every run, as a fresh install
/// has; [pair] makes it known to the server with the link's token.
///
/// Every connection is a channel of the native module, so these probes need
/// the library built from this tree's Rust crate. Without a link there is
/// nothing to check the server against, so a probe skips rather than dialling
/// blind.
class LiveTarget {
  LiveTarget._(this.link) : deviceSeed = Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256)));

  static const String _define = String.fromEnvironment('link');

  final PairingLink link;

  /// This run's device key seed.
  final Uint8List deviceSeed;

  /// The target, or null when nothing was passed or it will not parse.
  static LiveTarget? fromDefine() {
    final parsed = PairingLink.tryParse(_define);
    return parsed == null ? null : LiveTarget._(parsed);
  }

  /// Says why it is skipping, and returns null, so a probe body reads as one
  /// early return.
  static LiveTarget? orSkip() {
    final target = fromDefine();
    if (target == null) {
      stdout.writeln('SKIP: pass --dart-define=link=<pairing link printed by noxd>');
    }
    return target;
  }

  /// A channel client bound to this server and this run's device key, shared
  /// by both transports of the probe exactly as the app shares one.
  ChannelHttpClient client() => ChannelHttpClient(const NativeNoxChannelApi())..bind(serverKey: link.serverKey, deviceSeed: deviceSeed);

  /// The link's first direct address - what the connection screen shows in
  /// its address field (phase 045). These probes dial it directly.
  String get address => link.directAddresses.first;

  /// The command channel.
  Uri get socketUrl => Uri.parse('wss://$address/ws');

  /// The base for attachment bytes.
  String get restUrl => 'https://$address';

  /// Pairs this run's device key by the link's token, over [socket], and
  /// stops it again. The server knows a device only by the key its channel
  /// proves, and a key it does not know may do nothing but pair - so a probe
  /// pairs first and then starts its socket again, greeting as a device the
  /// server has. Spends the link: a claim link pairs once.
  Future<void> pair(NoxSocketClient socket) async {
    await socket.start(url: socketUrl, credentialsProvider: () async => const GreetingCredentials.unpaired());
    final reply = await socket.pair(token: link.token, platform: 'macos');
    expect(reply.ok, isTrue, reason: 'pair: ${reply.errorCode}');
    await socket.stop();
  }

  /// Lets a probe reach a real server.
  ///
  /// `TestWidgetsFlutterBinding` installs HttpOverrides that answer every
  /// request with a mock, so the suite cannot touch the network by accident -
  /// and a probe that dials a live `noxd` fails with `Unsupported operation:
  /// Mocked response` before a single byte leaves the process. Reaching the
  /// network is the whole point of these files, so they lift it.
  static void letTheNetworkThrough() => HttpOverrides.global = null;
}

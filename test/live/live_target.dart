import 'dart:io';

import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';

/// Where a live probe dials, and the key it insists on finding there.
///
/// Both come out of ONE `--dart-define=link=<pairing link>` - the line a fresh
/// `noxd` prints - because the address and the fingerprint are two halves of
/// one fact and passing them separately is how they come to disagree.
///
/// Since the transport is TLS there is no such thing as a probe that "just
/// connects": without a fingerprint there is nothing to check the server
/// against, so a probe with no link skips rather than dialling blind.
class LiveTarget {
  const LiveTarget._(this.link);

  static const String _define = String.fromEnvironment('link');

  final PairingLink link;

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

  /// A client pinned to this server, shared by both transports of the probe
  /// exactly as the app shares one.
  PinnedHttpClient client() => PinnedHttpClient()..pinTo(link.serverFingerprint);

  /// The command channel.
  Uri get socketUrl => Uri.parse('wss://${link.authority}/ws');

  /// The base for attachment bytes.
  String get restUrl => 'https://${link.authority}';
}

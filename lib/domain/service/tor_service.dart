import 'dart:typed_data';

import 'package:nox_app/domain/model/connection/tor_status.dart';

/// The Tor client built into the app (phase 040), as the rest of the app sees
/// it. The real one is a Rust module behind `package:nox_tor`; the test
/// environment gets a fake, so no widget or BLoC test loads the library.
abstract class TorService {
  /// False on Linux, and wherever the native library is absent.
  bool get isSupported;

  /// Starts the client from its directories. Returns at once: progress shows
  /// in [watchStatus].
  Future<void> start();

  /// Stops it. Its directories stay, for a fast warm start next time.
  Future<void> stop();

  /// Stops it and deletes its directories - logout.
  Future<void> wipe();

  /// Points the loopback bridge at one onion service with the client key that
  /// opens it; replaces any previous target.
  void setTarget({required String onionHost, required int port, required Uint8List clientKey});

  void clearTarget();

  void setDormant(bool dormant);

  TorStatus get status;

  /// The current status on listen, then every change.
  Stream<TorStatus> watchStatus();

  /// Port and secret of the bridge while a target is set.
  TorBridgeEndpoint? get bridge;

  /// The `<56>.onion` address of a v3 public key; null where Tor is unsupported.
  String? onionFromPublicKey(Uint8List publicKey);
}

/// What a connection to the bridge needs: where it listens, and the 32 bytes
/// every connection must open with.
class TorBridgeEndpoint {
  const TorBridgeEndpoint({required this.port, required this.secret});

  final int port;
  final Uint8List secret;
}

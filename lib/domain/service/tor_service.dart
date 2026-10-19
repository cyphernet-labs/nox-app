import 'dart:typed_data';

import 'package:nox_app/domain/model/connection/tor_status.dart';

/// The Tor client built into the app (phase 040), as the rest of the app sees
/// it. The real one is a Rust module behind `package:nox_tor`; the test
/// environment gets a fake, so no widget or BLoC test loads the library.
///
/// It carries no connections itself (phase 044): a connection through Tor is
/// a channel of the same module, opened by the transport like any other, to
/// the onion address alone - no target is set in advance and no access key is
/// held (phase 045). What stays here is the client's lifecycle.
abstract class TorService {
  /// Whether the native library is there - on all five platforms since phase
  /// 045; false only where it failed to load.
  bool get isSupported;

  /// Starts the client from its directories. Returns at once: progress shows
  /// in [watchStatus].
  Future<void> start();

  /// Stops it. Its directories stay, for a fast warm start next time.
  Future<void> stop();

  /// Stops it and deletes its directories - logout.
  Future<void> wipe();

  void setDormant(bool dormant);

  TorStatus get status;

  /// The current status on listen, then every change.
  Stream<TorStatus> watchStatus();

  /// The `<56>.onion` address of a v3 public key; null where the native
  /// module is absent.
  String? onionFromPublicKey(Uint8List publicKey);
}

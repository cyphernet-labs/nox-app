import 'dart:typed_data';

import 'package:nox_tor/nox_tor.dart';

/// The calls `NativeTorService` makes into `package:nox_tor`, as an object, so
/// a test can stand in for the native library and for the network behind it.
class NoxTorApi {
  const NoxTorApi();

  void start({required String stateDir, required String cacheDir}) => NoxTor.start(stateDir: stateDir, cacheDir: cacheDir);

  void stop() => NoxTor.stop();

  void setTarget({required String onionHost, required int port, required Uint8List clientKey}) =>
      NoxTor.setTarget(onionHost: onionHost, port: port, clientKey: clientKey);

  void clearTarget() => NoxTor.clearTarget();

  void setDormant(bool dormant) => NoxTor.setDormant(dormant);

  NoxTorSnapshot status() => NoxTor.status();

  Uint8List bridgeSecret() => NoxTor.bridgeSecret();

  String onionFromPublicKey(Uint8List publicKey) => NoxTor.onionFromPublicKey(publicKey);

  /// Which Tor client the library carries, e.g. `arti-client 0.47.0`.
  String version() => NoxTor.version;
}

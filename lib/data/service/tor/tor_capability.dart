import 'package:flutter/foundation.dart';
import 'package:nox_tor/nox_tor.dart';

/// Whether this platform has the Tor client built in (phases 040, 045).
///
/// All five do since phase 045 - Linux among them: the module is built for it
/// since phase 044, and the channel needs it there anyway. A library that
/// failed to load counts as absent, and the app then reaches its server only
/// directly.
///
/// Like `VideoPlaybackCapability`, [debugOverride] is the only way to run the
/// other branch in a test, because `dart:io Platform` cannot be overridden.
/// Tests MUST reset it in tearDown.
abstract final class TorCapability {
  const TorCapability._();

  @visibleForTesting
  static bool? debugOverride;

  static bool get isAvailable => debugOverride ?? NoxTor.isSupported;
}

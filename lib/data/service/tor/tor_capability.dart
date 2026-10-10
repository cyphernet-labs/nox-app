import 'package:flutter/foundation.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_tor/nox_tor.dart';

/// Whether this platform has the Tor client built in (phase 040).
///
/// iOS, Android, macOS and Windows do; Linux does not yet (`tor-linux-app`):
/// the build hook makes the library there too, because every channel goes
/// through it (phase 044), but the app does not start its Tor client and
/// reaches its server only directly. A library that failed to load counts as
/// absent.
///
/// Like `VideoPlaybackCapability`, [debugOverride] is the only way to run the
/// other branch in a test, because `dart:io Platform` cannot be overridden.
/// Tests MUST reset it in tearDown.
abstract final class TorCapability {
  const TorCapability._();

  @visibleForTesting
  static bool? debugOverride;

  static bool get isAvailable => debugOverride ?? (!PlatformUtils.isLinux && NoxTor.isSupported);
}

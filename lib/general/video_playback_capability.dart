import 'package:flutter/foundation.dart';
import 'package:nox_app/general/platform_utils.dart';

/// Single source of truth for whether this platform can play a video attachment
/// in the app (5.3). Playback is backed by `video_player`, whose federated
/// implementations cover iOS, Android and macOS only — there is no Windows and
/// no Linux implementation, so a controller there fails at `initialize()` rather
/// than degrading. One predicate governs the whole surface: where it is false
/// the file screen is exactly what it was before playback existed — the type
/// glyph, the name, the size and `Save`.
///
/// The gap is deliberate and owner-approved (2026-09-20). The alternative,
/// `media_kit`, does cover all five, but ships libmpv as native binaries in
/// every bundle, and the two platforms it would add are the two this project
/// cannot verify — the same reason P15 and P17 are deferred. A player nobody
/// can run is a claim, not a feature.
///
/// The predicate is the same as `QrScannerCapability`'s, and for the same kind
/// of reason rather than by coincidence: both are plugins whose authors
/// implemented the three platforms with a first-party video/camera stack.
///
/// `PlatformUtils` is built on `dart:io Platform`, which is NOT overridable via
/// `debugDefaultTargetPlatformOverride`; on the golden/test host (macOS) it
/// always reports macOS. [debugOverride] is the only way to exercise the
/// Windows/Linux branch in a test. Tests MUST reset it in tearDown.
abstract final class VideoPlaybackCapability {
  const VideoPlaybackCapability._();

  @visibleForTesting
  static bool? debugOverride;

  static bool get isAvailable => debugOverride ?? (PlatformUtils.isMobile || PlatformUtils.isMacOS);
}

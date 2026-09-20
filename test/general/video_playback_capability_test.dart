import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_app/general/video_playback_capability.dart';

/// The gap is deliberate: `video_player` implements iOS, Android and macOS and
/// nothing else, so Windows and Linux keep the file screen they always had.
/// These pin the predicate, because the cost of it drifting is a controller
/// that throws on a platform where nobody here can see it throw.
void main() {
  tearDown(() => VideoPlaybackCapability.debugOverride = null);

  test('the override decides, so the Windows/Linux branch is reachable from a macOS host', () {
    VideoPlaybackCapability.debugOverride = false;
    expect(VideoPlaybackCapability.isAvailable, isFalse);

    VideoPlaybackCapability.debugOverride = true;
    expect(VideoPlaybackCapability.isAvailable, isTrue);
  });

  test('with no override it answers for the real platform', () {
    // The suite runs on macOS, which is one of the three that has a player.
    expect(VideoPlaybackCapability.isAvailable, PlatformUtils.isMobile || PlatformUtils.isMacOS);
  });
}

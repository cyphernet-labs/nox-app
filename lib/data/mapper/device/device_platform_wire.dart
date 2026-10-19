import 'package:nox_app/domain/model/device/pair_request.dart';

/// The OS family a device names itself by on the wire (contract §8A), as one of
/// the app's own words. Anything else - a missing value, a name this build does
/// not know - is [DevicePlatform.unknown], never text to show.
abstract final class DevicePlatformWire {
  static DevicePlatform parse(Object? value) => switch (value) {
    'ios' => DevicePlatform.ios,
    'android' => DevicePlatform.android,
    'macos' => DevicePlatform.macos,
    'windows' => DevicePlatform.windows,
    'linux' => DevicePlatform.linux,
    _ => DevicePlatform.unknown,
  };
}

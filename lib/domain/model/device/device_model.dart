import 'package:nox_app/domain/model/device/pair_request.dart';

/// One authorised device of this person, as the revoke list shows it.
class DeviceModel {
  const DeviceModel({
    required this.deviceKey,
    required this.platform,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  /// The public key. Never shown as-is: 32 bytes of base64 look identical
  /// across five rows, which is why [platform] and the two moments exist.
  final String deviceKey;

  /// The OS family, and nothing finer. Enough to recognise one's own tablet
  /// among three; the exact model would be a fingerprint the server has no
  /// reason to hold. One of the app's own words, never wire text.
  final DevicePlatform platform;

  final DateTime pairedAt;
  final DateTime lastSeenAt;

  /// True for the device the person is holding. Revoking it is a logout, which
  /// is a different sentence to read before tapping.
  final bool isCurrent;
}

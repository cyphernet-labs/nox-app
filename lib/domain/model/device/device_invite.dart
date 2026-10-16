/// An invite for another device of this person (contract §8A, `device.invite`).
class DeviceInvite {
  const DeviceInvite({required this.link, required this.onion, this.public = false});

  final String link;

  /// The link carries the server's onion address: a device can pair with it
  /// through Tor, from any network (phase 045).
  final bool onion;

  /// The link carries the server's public address: a device can pair with it
  /// from outside the home network too (phase 045).
  final bool public;

  /// Neither: the link works only on the home network, and the card says so.
  bool get homeOnly => !onion && !public;
}

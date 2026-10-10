/// An invite for another device of this person (contract §8A, `device.invite`).
class DeviceInvite {
  const DeviceInvite({required this.link, required this.onion});

  final String link;

  /// The server vouches that the link works from any network, and the link
  /// carries the onion address to back it. Until phase 045 the server always
  /// answers false - a new device pairs at home, because the onion service
  /// opens only for a paired device's key - so the card says so.
  final bool onion;
}

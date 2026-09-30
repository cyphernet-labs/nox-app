/// An invite for another device of this person (contract §8A, `device.invite`).
class DeviceInvite {
  const DeviceInvite({required this.link, required this.onion});

  final String link;

  /// The link is version 2: it carries the onion address and a one-time access
  /// key, so it works from any network. False - the server could not offer
  /// that right now, or predates phase 039 - means it works at home only.
  final bool onion;
}

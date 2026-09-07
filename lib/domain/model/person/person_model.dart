/// One member of the circle, as the People screen shows them.
///
/// A name and whether they own this machine. No devices, no device count and no
/// keys: "who lives here" is not "who owns how much hardware", and a count on
/// its own says more about a person than a list of names has any business
/// saying (contract §8B).
class PersonModel {
  const PersonModel({required this.id, required this.label, required this.isOwner, required this.isSelf});

  /// The server-minted public id. Never shown: it is how messages are attributed,
  /// not how a person is recognised.
  final String id;

  final String label;

  /// True for the one person who owns the server. Stated by the server, never
  /// inferred here — the same rule the badge in Settings follows.
  final bool isOwner;

  /// True for the person holding this device. Resolved locally, because the
  /// server answers about the circle rather than about who is asking.
  final bool isSelf;
}

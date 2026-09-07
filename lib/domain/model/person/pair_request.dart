/// Somebody is at the door: an invite has been presented and is waiting for the
/// owner to say yes or no (contract §8B).
///
/// It carries nothing about who is knocking, and that is not an omission. Until
/// they are let in, the server knows nothing about them: no name, no picture —
/// they choose a name afterwards. The platform their unauthenticated device
/// claimed is an assertion, not a fact, and showing it as one would be telling
/// the owner something nobody verified.
class PairRequest {
  const PairRequest({required this.requestId, required this.invitedAt, required this.expiresAt});

  /// Names this request on the wire. Not the invite token: that is a credential
  /// and it stays where it was issued.
  final String requestId;

  /// When the owner issued this invite. The one thing the server does know, and
  /// what lets the owner recognise their own invite among several.
  ///
  /// Nullable because a frame that did not state it must not be turned into a
  /// moment in 1970 — the screen simply says less, rather than something false.
  final DateTime? invitedAt;

  /// When the question stops being answerable. Null means the server did not
  /// state it, which is not the same as "already expired": the server remains
  /// the authority on when a question dies.
  final DateTime? expiresAt;
}

/// Fixed mock identity for the signed-in device during the UI phase. The chat
/// thread (5.2) decides "own vs other" by comparing a message's `authorId` to
/// [currentUserId]; these values mirror what the settings identity card (7.1)
/// shows. It exists only so the thread renders own/other bubbles deterministically;
/// a real local identity source replaces it in the backend phase.
//
// TODO(backend): replace with the real local identity (currentUserId + label).
abstract final class IdentityMockData {
  const IdentityMockData._();

  /// Stable identifier of the signed-in device (own messages).
  static const String currentUserId = 'me';

  /// Display label of the signed-in user.
  static const String currentLabel = 'You';
}

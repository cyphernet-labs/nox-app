/// Device-local state of the deterministic mock world. The wire (contract v0)
/// carries no unread counters (§8.3) and no system messages (§4), so the
/// local halves of the seed live here, applied by the repositories at
/// seed-time — the remote seam stays contract-shaped.
abstract final class ChatSeedMockData {
  /// Unread badges of the seeded chats (device-local overlay); ids absent
  /// here seed with 0.
  static const Map<String, int> unreadByChatId = {
    'chat_0': 3,
    'chat_2': 12,
    'chat_4': 142,
    'chat_6': 1,
    'chat_8': 4,
    'chat_11': 2,
    'chat_14': 7,
    'chat_17': 1,
  };

  static int unreadFor(String chatId) => unreadByChatId[chatId] ?? 0;

  /// The synthesized genesis line of every seeded chat ("Chat created by …"),
  /// client-rendered per contract §4: label + age below match the pre-025
  /// seed so the golden baselines stay frozen.
  static const String genesisAuthorLabel = 'Aria';
  static const Duration genesisAge = Duration(days: 2, hours: 6);
}

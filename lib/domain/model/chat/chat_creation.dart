/// Where a chat stands while the server does not have it yet (phase 041).
/// No value at all means the server has it: an ordinary chat.
enum ChatCreation {
  /// On this device only. The queue creates it on the server as soon as there
  /// is a channel, by any path.
  pending,

  /// The server answered that another chat has this name. Nothing is sent
  /// until the person renames it; then it is pending again.
  nameTaken,

  /// The server refused for another reason, and the same request would be
  /// refused again. Nothing is sent until the person asks to try again.
  failed,
}

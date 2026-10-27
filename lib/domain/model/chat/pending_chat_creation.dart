import 'package:nox_app/domain/model/chat/chat_model.dart';

/// A chat waiting to be created on the server (phase 041), with how many
/// times that failed in a way worth retrying: the pause before the next try
/// grows with it, as it does for a message.
class PendingChatCreation {
  const PendingChatCreation({required this.chat, required this.attempts});

  final ChatModel chat;
  final int attempts;
}

import 'package:flutter/widgets.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';

/// Subscribes to a single chat row ([chatId]) and rebuilds [builder] with the
/// current [ChatModel] on every change — so a rename (from the card header pencil)
/// propagates live to every surface that shows the name/avatar (thread title, card
/// header, desktop thread header). [builder] receives the resolved chat
/// (`snapshot.data ?? initial`), so callers never handle the raw snapshot or the
/// `?? initial` fallback themselves. [initial] seeds the first frame before the
/// stream emits.
class WatchChat extends StatelessWidget {
  const WatchChat({super.key, required this.chatId, required this.initial, required this.builder});

  final String chatId;
  final ChatModel initial;
  final Widget Function(BuildContext context, ChatModel chat) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatModel?>(
      stream: chatRepository.watchChat(chatId: chatId),
      initialData: initial,
      builder: (context, snapshot) => builder(context, snapshot.data ?? initial),
    );
  }
}

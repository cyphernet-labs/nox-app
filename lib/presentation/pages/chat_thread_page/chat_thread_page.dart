import 'package:flutter/material.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// 5.2 Chat thread — read history + send text/files within one chat. Mobile: a
/// full-screen pushed screen (AppBar back + chat name → chat card). Desktop: the
/// thread normally lives in the 5.1 list-detail pane; opened standalone from the
/// gallery it renders the thread pane (with the persistent header) full-window.
/// The body ([AppThreadViewWidget]) owns the [ChatThreadBloc].
class ChatThreadPage extends StatelessWidget {
  const ChatThreadPage({super.key, required this.chat, this.demo = false});

  final ChatModel chat;
  final bool demo;

  static Route<void> route(ChatModel chat) => MaterialPageRoute<void>(
    builder: (_) => ChatThreadPage(chat: chat),
    settings: const RouteSettings(name: '/chat-thread'),
  );

  /// Gallery entry: a sample chat with the dev scenario control.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => ChatThreadPage(chat: _sampleChat, demo: true),
    settings: const RouteSettings(name: '/chat-thread'),
  );

  static final ChatModel _sampleChat = ChatModel(
    id: 'chat_0',
    name: 'Design crit',
    lastMessagePreview: '',
    lastMessageAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Constants.railBreakpoint;
        if (wide) {
          // Standalone desktop preview: the thread pane (persistent header) full-window.
          return Scaffold(
            body: AppThreadViewWidget(
              chat: chat,
              demo: demo,
              showHeader: true,
              onInfo: () => showChatCard(context, chat),
              onOpenFile: (file) => showFileView(context, file),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: context.l10n.tooltipBack,
              icon: AppIconWidget(NoxIcons.arrowBack),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            // Tapping the chat name opens the chat card (5.4).
            title: InkWell(onTap: () => showChatCard(context, chat), child: Text(chat.name)),
          ),
          body: AppThreadViewWidget(chat: chat, demo: demo, onOpenFile: (file) => showFileView(context, file)),
        );
      },
    );
  }
}

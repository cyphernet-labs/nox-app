import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:nox_app/presentation/widgets/chat/app_author_header_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_date_separator_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_system_line_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_header_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

/// Shared chat-thread body (5.2) — used by the mobile [ChatThreadPage] and the
/// desktop thread pane inside the 5.1 list-detail. Owns the [ChatThreadBloc] (single
/// owner; hosts only pass [chat]). Renders a reverse message stream with date
/// separators, author headers (grouped by stable author id) and a leading system
/// line, plus an editable composer with optimistic send. [showHeader] adds the
/// desktop [AppThreadHeaderWidget].
class AppThreadViewWidget extends StatefulWidget {
  const AppThreadViewWidget({super.key, required this.chat, this.demo = false, this.showHeader = false, this.onInfo, this.onOpenFile});

  final ChatModel chat;
  final bool demo;
  final bool showHeader;

  /// Open the chat card (5.4). Wired by callers; null → no-op (the chat-card screen
  /// lands in US3).
  final VoidCallback? onInfo;

  /// Open the file view (5.3) for an attachment. Wired by callers; null → no-op
  /// (the file-view screen lands in US2).
  final void Function(MessageAttachment attachment)? onOpenFile;

  @override
  State<AppThreadViewWidget> createState() => _AppThreadViewWidgetState();
}

class _AppThreadViewWidgetState extends State<AppThreadViewWidget> {
  late final ChatThreadBloc _bloc;
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ChatThreadScenario _scenario = ChatThreadScenario.normal;

  @override
  void initState() {
    super.initState();
    _bloc = ChatThreadBloc()..add(ChatThreadEvent.initialize(widget.chat.id));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _composer.dispose();
    _bloc.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // Reverse list: scrolling up (toward older history) approaches maxScrollExtent.
    if (position.pixels >= position.maxScrollExtent - 200) {
      _bloc.add(const ChatThreadEvent.loadMessages());
    }
  }

  void _onSend() {
    final state = _bloc.state;
    final attachment = state is Initialized ? state.draftAttachment : null;
    _bloc.add(ChatThreadEvent.messageSent(text: _composer.text, attachment: attachment));
    _composer.clear();
    setState(() {}); // recompute the send affordance
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatThreadBloc>.value(
      value: _bloc,
      child: BlocBuilder<ChatThreadBloc, ChatThreadState>(
        builder: (context, state) {
          return Column(
            children: [
              if (widget.showHeader) AppThreadHeaderWidget(chat: widget.chat, onInfo: widget.onInfo ?? () {}),
              if (state is Initialized && state.isOffline) const _OfflineBanner(),
              Expanded(child: _body(context, state)),
              if (state is Initialized) _composerBar(state),
              if (kDebugMode && widget.demo) _scenarioControl(),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, ChatThreadState state) {
    if (state is Initializing) return const AppProgressWidget();
    if (state is Error) {
      return AppErrorWidget(onTryAgain: () => _bloc.add(ChatThreadEvent.initialize(widget.chat.id)));
    }
    final initialized = state as Initialized;
    final all = initialized.allMessages;

    // Initial load (no data yet) → spinner, not the empty state.
    if (all.isEmpty && initialized.loadingInProgress) return const AppProgressWidget();

    if (!initialized.hasMessages) {
      final systemLines = all.where((m) => m.isSystem).toList();
      return Column(
        children: [
          for (final m in systemLines) AppSystemLineWidget(text: TextConstants.systemChatCreated(m.authorLabel)),
          Expanded(
            child: AppEmptyContentWidget(
              illustration: Assets.svg.illustrations.emptyMessages,
              title: TextConstants.threadEmptyTitle,
              message: TextConstants.threadEmptyMessage,
            ),
          ),
        ],
      );
    }

    final rows = _buildRows(context, initialized);
    final display = rows.reversed.toList();
    final showLoadingOlder = initialized.loadingInProgress && rows.isNotEmpty;

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s12, vertical: AppSpacingTokens.s8),
      itemCount: display.length + (showLoadingOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (showLoadingOlder && index == display.length) {
          return Padding(padding: EdgeInsets.all(AppSpacingTokens.s8), child: const AppProgressWidget(size: 20));
        }
        return display[index];
      },
    );
  }

  /// Chronological rows (oldest → newest): system line, date separators, author
  /// headers, message bubbles. The caller reverses for the `reverse: true` list.
  List<Widget> _buildRows(BuildContext context, Initialized state) {
    final rows = <Widget>[];
    String? lastDay;
    String? lastOtherAuthorId;
    for (final m in state.allMessages) {
      if (m.isSystem) {
        rows.add(AppSystemLineWidget(text: TextConstants.systemChatCreated(m.authorLabel)));
        continue;
      }
      final day = '${m.sentAt.year}-${m.sentAt.month}-${m.sentAt.day}';
      if (day != lastDay) {
        rows.add(AppDateSeparatorWidget(label: DateFormatter.daySeparator(m.sentAt)));
        lastDay = day;
        lastOtherAuthorId = null;
      }
      final isOwn = m.authorId == state.currentId;
      if (!isOwn && m.authorId != lastOtherAuthorId) {
        rows.add(AppAuthorHeaderWidget(label: m.authorLabel));
      }
      rows.add(_bubble(context, m, isOwn));
      lastOtherAuthorId = isOwn ? null : m.authorId;
    }
    return rows;
  }

  Widget _bubble(BuildContext context, MessageModel m, bool isOwn) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget? file;
    final attachment = m.attachment;
    if (attachment != null) {
      final onColor = isOwn ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
      file = InkWell(
        onTap: () => widget.onOpenFile?.call(attachment),
        child: AppFileChipWidget(
          type: attachment.type,
          name: attachment.name,
          size: FileSizeFormatter.format(attachment.sizeBytes),
          inBubble: true,
          onColor: onColor,
        ),
      );
    }
    Widget bubble = AppMessageBubbleWidget(isOwn: isOwn, text: m.text, time: DateFormatter.time(m.sentAt), status: m.status, file: file);
    if (isOwn && m.status == MessageStatus.error) {
      bubble = Tooltip(
        message: TextConstants.tooltipRetry,
        child: GestureDetector(onTap: () => _bloc.add(ChatThreadEvent.sendRetried(m.id)), child: bubble),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacingTokens.s2),
      child: bubble,
    );
  }

  Widget _composerBar(Initialized state) {
    final draft = state.draftAttachment;
    final canSend = _composer.text.trim().isNotEmpty || draft != null;
    return AppComposerWidget(
      controller: _composer,
      sendActive: canSend,
      onChanged: (_) => setState(() {}),
      onAttach: () => _bloc.add(const ChatThreadEvent.attachmentPicked()),
      onSend: _onSend,
      onSubmitted: canSend ? _onSend : null,
      attachment: draft == null
          ? null
          : AppFileChipWidget(
              type: draft.type,
              name: draft.name,
              size: FileSizeFormatter.format(draft.sizeBytes),
              removable: true,
              onRemove: () => _bloc.add(const ChatThreadEvent.attachmentRemoved()),
            ),
    );
  }

  Widget _scenarioControl() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: DropdownButton<ChatThreadScenario>(
        value: _scenario,
        isExpanded: true,
        onChanged: (selected) {
          if (selected != null) {
            setState(() => _scenario = selected);
            _bloc.add(ChatThreadEvent.setScenario(selected));
          }
        },
        items: [for (final s in ChatThreadScenario.values) DropdownMenuItem(value: s, child: Text('scenario: ${s.name}'))],
      ),
    );
  }
}

/// Persistent "No connection" strip at the top of the thread (5.2 offline).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s8),
        child: Row(
          children: [
            AppIconWidget(NoxIcons.error, size: 20, color: colorScheme.onSurfaceVariant),
            SizedBox(width: AppSpacingTokens.s12),
            Expanded(
              child: Text(TextConstants.noConnection, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
            ),
          ],
        ),
      ),
    );
  }
}

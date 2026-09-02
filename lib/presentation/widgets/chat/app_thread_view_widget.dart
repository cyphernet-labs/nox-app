import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/app_dev_scenario_dropdown.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/widgets/chat/watch_chat.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';
import 'package:nox_app/presentation/widgets/chat/app_author_header_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_composer_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_date_separator_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_image_attachment_widget.dart';
import 'package:nox_app/presentation/pages/image_viewer_page/image_viewer_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_message_bubble_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_system_line_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_header_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

/// Shared chat-thread body (5.2) — used by the mobile [ChatThreadPage] and the
/// desktop thread pane inside the 5.1 list-detail. Owns the [ChatThreadBloc] (single
/// owner; hosts only pass [chat]). Renders a reverse message stream with date
/// separators, author headers (grouped by stable author id) and a leading system
/// line, plus an editable composer with optimistic send. [showHeader] adds the
/// desktop [AppThreadHeaderWidget].
class AppThreadViewWidget extends StatefulWidget {
  const AppThreadViewWidget({
    super.key,
    required this.chat,
    this.demo = false,
    this.showHeader = false,
    this.onInfo,
    this.onOpenFile,
    this.initialScenario,
    this.initialSendText,
  });

  final ChatModel chat;
  final bool demo;
  final bool showHeader;

  /// Open the chat card (5.4). Wired by callers; null → no-op.
  final VoidCallback? onInfo;

  /// Open the file view (5.3) for an attachment. Wired by callers; null → no-op.
  /// Opens the file screen. The message id travels with the attachment so a
  /// download started there can be recorded against it — without it, the bytes
  /// land in the cache and the thread still shows a chip.
  final void Function(MessageAttachment attachment, String? messageId)? onOpenFile;

  /// Test-only seam: seed the debug [ChatThreadScenario] on init so golden tests can
  /// render the offline / send-error states deterministically (mirrors ChatsListPage).
  @visibleForTesting
  final ChatThreadScenario? initialScenario;

  /// Test-only seam: auto-send this text on init — paired with [initialScenario] =
  /// sendError it renders the inline send-error bubble for the golden (no UI interaction).
  @visibleForTesting
  final String? initialSendText;

  @override
  State<AppThreadViewWidget> createState() => _AppThreadViewWidgetState();
}

class _AppThreadViewWidgetState extends State<AppThreadViewWidget> {
  /// Distance (px) from the top of the reverse history at which the next page
  /// prefetches — a screenful of runway before the user reaches the oldest message.
  static const double _loadMoreThreshold = 200;

  late final ChatThreadBloc _bloc;
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ChatThreadScenario _scenario = ChatThreadScenario.normal;

  @override
  void initState() {
    super.initState();
    _bloc = ChatThreadBloc()..add(ChatThreadEvent.initialize(widget.chat.id));
    // Test-only: seed a debug scenario (+ optionally auto-send) so golden tests can lock
    // the offline / send-error states. The events queue after initialize.
    if (widget.initialScenario != null) {
      _scenario = widget.initialScenario!;
      _bloc.add(ChatThreadEvent.setScenario(widget.initialScenario!));
      if (widget.initialSendText != null) _bloc.add(ChatThreadEvent.messageSent(text: widget.initialSendText));
    }
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
    // Guard on a real scrollable extent so a short (non-filling) list doesn't fire.
    if (position.maxScrollExtent > 0 && position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _bloc.add(const ChatThreadEvent.loadMessages());
    }
  }

  void _onSend() {
    final state = _bloc.state;
    final attachment = state is Initialized ? state.draftAttachment : null;
    _bloc.add(ChatThreadEvent.messageSent(text: _composer.text, attachment: attachment));
    _composer.clear(); // the reactive send button + draft chip update on their own
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatThreadBloc>.value(
      value: _bloc,
      child: BlocConsumer<ChatThreadBloc, ChatThreadState>(
        // A file refused for its size is a transient notice, not a screen
        // state: the composer is unchanged and the person just picks another.
        listenWhen: (previous, current) =>
            previous is Initialized && current is Initialized && previous.oversizedAttachmentTick != current.oversizedAttachmentTick,
        listener: (context, state) {
          final limit = FileSizeFormatter.format(getIt<AppConfigRepository>().limits.maxAttachmentBytes);
          showAppSnackBar(context, text: context.l10n.attachmentTooLarge(limit));
        },
        builder: (context, state) {
          return Column(
            children: [
              // Reactive to the chat row so a rename (from the side-sheet card) updates the
              // desktop header's name + avatar live.
              if (widget.showHeader)
                WatchChat(
                  chatId: widget.chat.id,
                  initial: widget.chat,
                  builder: (context, chat) => AppThreadHeaderWidget(chat: chat, onInfo: widget.onInfo ?? () {}),
                ),
              if (state is Initialized && state.isOffline) AppNoticeStripWidget(message: context.l10n.noConnection, icon: NoxIcons.wifiOff),
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
    final all = initialized.allMessages; // single merge+sort per build

    // Initial load (no data yet) → spinner, not the empty state.
    if (all.isEmpty && initialized.loadingInProgress) return const AppProgressWidget();

    if (!initialized.hasMessages) {
      return Column(
        children: [
          for (final m in all.where((m) => m.isSystem)) AppSystemLineWidget(text: context.l10n.systemChatCreated(m.authorLabel)),
          Expanded(
            child: AppEmptyContentWidget(
              illustration: Assets.svg.illustrations.emptyMessages,
              title: context.l10n.threadEmptyTitle,
              message: context.l10n.threadEmptyMessage,
            ),
          ),
        ],
      );
    }

    // Build lightweight row descriptors once (oldest → newest), then reverse for the
    // reverse: true list and materialize each widget lazily in itemBuilder.
    final rows = _rows(context, all, initialized.currentId).reversed.toList();
    final showLoadingOlder = initialized.loadingInProgress && rows.isNotEmpty;

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s12, vertical: AppSpacingTokens.s8),
      itemCount: rows.length + (showLoadingOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (showLoadingOlder && index == rows.length) {
          return Padding(padding: EdgeInsets.all(AppSpacingTokens.s8), child: const AppProgressWidget(size: 20));
        }
        return _buildRow(context, rows[index]);
      },
    );
  }

  /// Chronological row descriptors: system line, date separators, author headers,
  /// message rows. Pure data — widgets are built lazily by [_buildRow].
  List<_ThreadRow> _rows(BuildContext context, List<MessageModel> all, String currentId) {
    final rows = <_ThreadRow>[];
    String? lastDay;
    String? lastOtherAuthorId;
    for (final m in all) {
      if (m.isSystem) {
        rows.add(_SystemRow(m.authorLabel));
        continue;
      }
      final day = '${m.sentAt.year}-${m.sentAt.month}-${m.sentAt.day}';
      if (day != lastDay) {
        rows.add(_DateRow(DateFormatter.daySeparator(m.sentAt, l10n: context.l10n)));
        lastDay = day;
        lastOtherAuthorId = null;
      }
      final isOwn = m.authorId == currentId;
      if (!isOwn && m.authorId != lastOtherAuthorId) rows.add(_AuthorRow(m.authorLabel));
      rows.add(_MessageRow(m, isOwn));
      lastOtherAuthorId = isOwn ? null : m.authorId;
    }
    return rows;
  }

  Widget _buildRow(BuildContext context, _ThreadRow row) {
    return switch (row) {
      _SystemRow(:final label) => AppSystemLineWidget(text: context.l10n.systemChatCreated(label)),
      _DateRow(:final label) => AppDateSeparatorWidget(label: label),
      _AuthorRow(:final label) => AppAuthorHeaderWidget(label: label),
      _MessageRow(:final message, :final isOwn) => _bubble(context, message, isOwn),
    };
  }

  // Image-thumbnail-or-type-chip preview for [attachment], shared by the read-only
  // message bubble (tap → viewer / File view) and the composer draft (removable). A
  // decodable image with a real local file renders inline; everything else (non-image
  // / no path / missing file / non-decodable format like svg, heic off Apple) falls
  // back to the type-icon chip. The distinct affordances are threaded in: [onImageTap]/
  // [onChipTap] make it tappable (bubble), [onRemove] makes it removable (composer);
  // a bubble chip (has [onChipTap]) also gets the in-bubble tint via [onColor].
  Widget _attachmentPreview(
    MessageAttachment attachment, {
    Color? onColor,
    double? imageSize,
    VoidCallback? onImageTap,
    VoidCallback? onChipTap,
    VoidCallback? onRemove,
  }) {
    final size = FileSizeFormatter.format(attachment.sizeBytes);
    if (AppImageAttachmentWidget.canRender(attachment)) {
      return AppImageAttachmentWidget(
        localPath: attachment.localPath!,
        type: attachment.type,
        name: attachment.name,
        size: size,
        onColor: onColor,
        width: imageSize,
        height: imageSize,
        onTap: onImageTap,
        onRemove: onRemove,
      );
    }
    final chip = AppFileChipWidget(
      type: attachment.type,
      name: attachment.name,
      size: size,
      inBubble: onChipTap != null,
      onColor: onColor,
      removable: onRemove != null,
      onRemove: onRemove,
    );
    return onChipTap != null ? InkWell(onTap: onChipTap, child: chip) : chip;
  }

  Widget _bubble(BuildContext context, MessageModel m, bool isOwn) {
    final colorScheme = Theme.of(context).colorScheme;
    final attachment = m.attachment;
    final Widget? file = attachment == null
        ? null
        : _attachmentPreview(
            attachment,
            onColor: isOwn ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
            onImageTap: () => openImageViewer(context, attachment.localPath!),
            onChipTap: () => widget.onOpenFile?.call(attachment, m.id),
          );
    Widget bubble = AppMessageBubbleWidget(isOwn: isOwn, text: m.text, time: DateFormatter.time(m.sentAt), status: m.status, file: file);
    final isFailed = isOwn && m.status == MessageStatus.error;
    final isQueued = isOwn && m.status == MessageStatus.pending;
    if (isFailed || isQueued) {
      // Long-press (secondary click on desktop — Principle VI puts the same
      // affordance at both widths) discards. The escape hatch covers BOTH
      // queued states, not just the failed one: since feature 027 an unsent
      // message outlives the screen AND the process, and a send that keeps
      // failing retryably stays `pending` forever, so an error-only gesture
      // would leave exactly the stuck case with no way out.
      bubble = GestureDetector(
        // Tap still means retry, and only a failed bubble has anything to
        // retry — a queued one is already on its way.
        onTap: isFailed ? () => _bloc.add(ChatThreadEvent.sendRetried(m.id)) : null,
        onLongPress: () => _bloc.add(ChatThreadEvent.sendDiscarded(m.id)),
        onSecondaryTap: () => _bloc.add(ChatThreadEvent.sendDiscarded(m.id)),
        child: bubble,
      );
      // The hint stays on the failed bubble alone, as before: naming a retry on
      // a message that is still going would be a lie.
      if (isFailed) bubble = Tooltip(message: context.l10n.tooltipRetry, child: bubble);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacingTokens.s2),
      child: bubble,
    );
  }

  Widget _composerBar(Initialized state) {
    final draft = state.draftAttachment;
    return AppComposerWidget(
      controller: _composer,
      onAttach: () => _bloc.add(const ChatThreadEvent.attachmentPicked()),
      onSend: _onSend,
      // A decodable image draft shows a compact removable thumbnail (P2); every other
      // type stays the removable type-icon chip.
      attachment: draft == null
          ? null
          : _attachmentPreview(
              draft,
              imageSize: AppDimensionTokens.layout.imageThumbCompact,
              onRemove: () => _bloc.add(const ChatThreadEvent.attachmentRemoved()),
            ),
    );
  }

  Widget _scenarioControl() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: AppDevScenarioDropdown<ChatThreadScenario>(
        value: _scenario,
        isExpanded: true,
        items: {for (final s in ChatThreadScenario.values) s: 'scenario: ${s.name}'},
        onChanged: (selected) {
          setState(() => _scenario = selected);
          _bloc.add(ChatThreadEvent.setScenario(selected));
        },
      ),
    );
  }
}

/// Lightweight thread row descriptors (built once per render, materialized lazily).
sealed class _ThreadRow {
  const _ThreadRow();
}

class _SystemRow extends _ThreadRow {
  const _SystemRow(this.label);
  final String label;
}

class _DateRow extends _ThreadRow {
  const _DateRow(this.label);
  final String label;
}

class _AuthorRow extends _ThreadRow {
  const _AuthorRow(this.label);
  final String label;
}

class _MessageRow extends _ThreadRow {
  const _MessageRow(this.message, this.isOwn);
  final MessageModel message;
  final bool isOwn;
}

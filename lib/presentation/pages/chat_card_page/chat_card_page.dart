import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_panel_header_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_side_sheet_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

/// Open the chat card (5.4) adaptively: mobile pushes the full screen; desktop
/// shows a right side-sheet over the thread (corpus `09-drawer`). Reached from the
/// thread (5.2): the AppBar chat name (mobile) or the header info action (desktop).
Future<void> showChatCard(BuildContext context, ChatModel chat) {
  final wide = MediaQuery.sizeOf(context).width >= Constants.railBreakpoint;
  if (wide) {
    return showRightSideSheet<void>(context, child: ChatCardBody(chat: chat, isDrawer: true));
  }
  return Navigator.of(context).push(ChatCardPage.route(chat));
}

/// 5.4 Chat card — read-only chat header + shared files (List / Grid). Mobile: a
/// full-screen pushed screen (AppBar back + chat name). Desktop: a right side-sheet
/// (Details header). No edit / mute / pin / report and no metadata. The body
/// ([ChatCardBody]) owns the [ChatCardBloc].
class ChatCardPage extends StatelessWidget {
  const ChatCardPage({super.key, required this.chat, this.demo = false});

  final ChatModel chat;
  final bool demo;

  static Route<void> route(ChatModel chat) => MaterialPageRoute<void>(
    builder: (_) => ChatCardPage(chat: chat),
    settings: const RouteSettings(name: '/chat-card'),
  );

  /// Gallery entry: a sample chat with the dev scenario control.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => ChatCardPage(chat: _sampleChat, demo: true),
    settings: const RouteSettings(name: '/chat-card'),
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
          // Standalone desktop preview: the side-sheet panel over a scrim.
          final colorScheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: colorScheme.scrim.withValues(alpha: 0.5),
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.of(context).maybePop()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppSideSheetPanel(
                    child: ChatCardBody(chat: chat, demo: demo, isDrawer: true),
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: TextConstants.tooltipBack,
              icon: AppIconWidget(NoxIcons.arrowBack),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          body: ChatCardBody(chat: chat, demo: demo),
        );
      },
    );
  }
}

/// The chat-card content (header + files). Owns the [ChatCardBloc]; hosted by the
/// mobile [ChatCardPage] (Scaffold) and the desktop side-sheet.
class ChatCardBody extends StatefulWidget {
  const ChatCardBody({super.key, required this.chat, this.demo = false, this.isDrawer = false});

  final ChatModel chat;
  final bool demo;
  final bool isDrawer;

  @override
  State<ChatCardBody> createState() => _ChatCardBodyState();
}

class _ChatCardBodyState extends State<ChatCardBody> {
  late final ChatCardBloc _bloc;
  ChatCardScenario _scenario = ChatCardScenario.normal;

  @override
  void initState() {
    super.initState();
    _bloc = ChatCardBloc()..add(ChatCardEvent.initialize(widget.chat.id));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatCardBloc>.value(
      value: _bloc,
      child: BlocBuilder<ChatCardBloc, ChatCardState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isDrawer) _drawerHeader(context),
              _header(context),
              Expanded(child: _section(context, state)),
              if (kDebugMode && widget.demo) _scenarioControl(),
            ],
          );
        },
      ),
    );
  }

  Widget _drawerHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPanelHeaderWidget(title: TextConstants.chatInfoTitle, onClose: () => Navigator.of(context).maybePop()),
        const Divider(height: 1),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      child: Row(
        children: [
          AppAvatarWidget(name: widget.chat.name, size: 56),
          SizedBox(width: AppSpacingTokens.s16),
          Expanded(
            child: Text(
              widget.chat.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, ChatCardState state) {
    if (state is Initializing) return const AppProgressWidget();
    if (state is Error) return AppErrorWidget(onTryAgain: () => _bloc.add(ChatCardEvent.initialize(widget.chat.id)));
    final initialized = state as Initialized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (initialized.isOffline) const AppNoticeStripWidget(message: TextConstants.noConnection),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s8, AppSpacingTokens.s16, AppSpacingTokens.s8),
          child: Row(
            children: [
              Expanded(child: Text(TextConstants.filesSectionTitle, style: Theme.of(context).textTheme.titleMedium)),
              AppSegmentedWidget<FilesViewMode>(
                options: const {FilesViewMode.list: TextConstants.filesViewList, FilesViewMode.grid: TextConstants.filesViewGrid},
                selected: initialized.viewMode,
                onChanged: (mode) => _bloc.add(ChatCardEvent.viewModeChanged(mode)),
              ),
            ],
          ),
        ),
        Expanded(child: _files(context, initialized)),
      ],
    );
  }

  Widget _files(BuildContext context, Initialized state) {
    if (state.files.isEmpty) {
      return AppEmptyContentWidget(
        illustration: Assets.svg.illustrations.emptyFiles,
        title: TextConstants.filesEmptyTitle,
        message: TextConstants.filesEmptyMessage,
      );
    }
    return state.viewMode == FilesViewMode.list ? _list(context, state.files) : _grid(context, state.files);
  }

  Widget _list(BuildContext context, List<MessageAttachment> files) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return ListTile(
          leading: AppFileGlyphWidget(type: file.type, iconSize: 22, box: 40),
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(FileSizeFormatter.format(file.sizeBytes)),
          onTap: () => showFileView(context, file),
        );
      },
    );
  }

  Widget _grid(BuildContext context, List<MessageAttachment> files) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final columns = widget.isDrawer ? 2 : 3;
    return GridView.builder(
      padding: EdgeInsets.all(AppSpacingTokens.s12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: AppSpacingTokens.s8,
        mainAxisSpacing: AppSpacingTokens.s8,
        childAspectRatio: 0.82,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return InkWell(
          onTap: () => showFileView(context, file),
          borderRadius: BorderRadius.circular(NoxRadius.m),
          child: Container(
            padding: EdgeInsets.all(AppSpacingTokens.s8),
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(NoxRadius.m)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppFileGlyphWidget(type: file.type, iconSize: 28, box: 56),
                SizedBox(height: AppSpacingTokens.s8),
                Text(
                  file.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
                ),
                SizedBox(height: AppSpacingTokens.s4),
                Text(FileSizeFormatter.format(file.sizeBytes), style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _scenarioControl() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: DropdownButton<ChatCardScenario>(
        value: _scenario,
        isExpanded: true,
        onChanged: (selected) {
          if (selected != null) {
            setState(() => _scenario = selected);
            _bloc.add(ChatCardEvent.setScenario(selected));
          }
        },
        items: [for (final s in ChatCardScenario.values) DropdownMenuItem(value: s, child: Text('scenario: ${s.name}'))],
      ),
    );
  }
}

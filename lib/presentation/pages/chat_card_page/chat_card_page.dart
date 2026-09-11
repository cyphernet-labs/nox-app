import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/presentation/widgets/app_dev_scenario_dropdown.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_hairline_divider_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/widgets/chat/app_card_section_header_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_people_section_widget.dart';
import 'package:nox_app/presentation/widgets/chat/watch_chat.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_segmented_widget.dart';
import 'package:nox_app/presentation/widgets/chat/rename_chat_dialog/app_rename_chat_dialog_widget.dart';
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
  const ChatCardPage({super.key, required this.chat, this.demo = false, this.initialScenario, this.initialViewMode});

  final ChatModel chat;
  final bool demo;

  /// Test-only seam: render a debug [ChatCardScenario] (offline / empty / fatal)
  /// deterministically for goldens, without driving the demo dropdown.
  @visibleForTesting
  final ChatCardScenario? initialScenario;

  /// Test-only seam: open in a specific [FilesViewMode] (e.g. grid) for goldens. Pair with
  /// the normal scenario — the List/Grid toggle only shows when there are files to view.
  @visibleForTesting
  final FilesViewMode? initialViewMode;

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
            backgroundColor: colorScheme.scrim.withValues(alpha: NoxOpacity.scrim),
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.of(context).maybePop()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppSideSheetPanel(
                    child: ChatCardBody(
                      chat: chat,
                      demo: demo,
                      isDrawer: true,
                      initialScenario: initialScenario,
                      initialViewMode: initialViewMode,
                    ),
                  ),
                ),
              ],
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
            // Reactive like the body header: a rename from the header pencil updates the
            // AppBar title live too (the two co-visible name surfaces must not disagree).
            title: WatchChat(
              chatId: chat.id,
              initial: chat,
              builder: (context, current) => Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          body: ChatCardBody(chat: chat, demo: demo, initialScenario: initialScenario, initialViewMode: initialViewMode),
        );
      },
    );
  }
}

/// The chat-card content (header + files). Owns the [ChatCardBloc]; hosted by the
/// mobile [ChatCardPage] (Scaffold) and the desktop side-sheet.
class ChatCardBody extends StatefulWidget {
  const ChatCardBody({super.key, required this.chat, this.demo = false, this.isDrawer = false, this.initialScenario, this.initialViewMode});

  final ChatModel chat;
  final bool demo;
  final bool isDrawer;

  /// Test-only seams (see [ChatCardPage]): force a debug scenario / view mode on init.
  @visibleForTesting
  final ChatCardScenario? initialScenario;
  @visibleForTesting
  final FilesViewMode? initialViewMode;

  @override
  State<ChatCardBody> createState() => _ChatCardBodyState();
}

class _ChatCardBodyState extends State<ChatCardBody> {
  late final ChatCardBloc _bloc;
  ChatCardScenario _scenario = ChatCardScenario.normal;

  @override
  void initState() {
    super.initState();
    // Test-only seams (goldens): pin the debug scenario at construction (deterministic —
    // no setScenario re-init race) and keep the demo dropdown in sync.
    _bloc = ChatCardBloc(initialScenario: widget.initialScenario)..add(ChatCardEvent.initialize(widget.chat.id));
    if (widget.initialScenario != null) _scenario = widget.initialScenario!;
    if (widget.initialViewMode != null) {
      // ViewModeChanged is a no-op until the bloc reaches Initialized (it can't copyWith an
      // Initializing state); wait for the first loaded state, then flip the mode. catchError
      // swallows the StateError if the bloc closes first (early dispose → no Initialized).
      _bloc.stream
          .firstWhere((state) => state is Initialized)
          .then((_) {
            if (mounted) _bloc.add(ChatCardEvent.viewModeChanged(widget.initialViewMode!));
          })
          .catchError((Object _) {});
    }
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
              // Panel chrome stays OUTSIDE the scroll: the close button has to be
              // reachable however far the body has been scrolled.
              if (widget.isDrawer) _drawerHeader(context),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _header(context)),
                    // Design (ChatInfoDrawer): a divider separates the identity block
                    // from what follows — desktop drawer only (the mobile card is
                    // full-screen).
                    if (widget.isDrawer) const SliverToBoxAdapter(child: AppHairlineDividerWidget()),
                    // The banner stays at the top of the card, where the spec pins
                    // it: pushed below the People block it lands ~150dp down, and on a
                    // phone at a large text scale it can fall off the first fold.
                    if (state is Initialized && state.isOffline)
                      SliverToBoxAdapter(
                        child: AppNoticeStripWidget(message: context.l10n.noConnection, icon: NoxIcons.wifiOff),
                      ),
                    // Only once there is something to show. Rendered unconditionally
                    // it stacked a person and a disabled button over the embedded
                    // error screen and over the loading spinner - two states the
                    // spec's table does not put it in.
                    if (state is Initialized) ...[
                      SliverToBoxAdapter(child: AppChatPeopleSectionWidget(personLabel: state.personLabel)),
                      const SliverToBoxAdapter(child: AppHairlineDividerWidget()),
                      SliverToBoxAdapter(child: SizedBox(height: AppSpacingTokens.s12)),
                    ],
                    ..._sectionSlivers(context, state),
                  ],
                ),
              ),
              if (kDebugMode && widget.demo) _scenarioControl(),
            ],
          );
        },
      ),
    );
  }

  // Desktop drawer 'Details' header (design: titleLarge). The bottom hairline is drawn
  // by AppPanelHeaderWidget itself, so no extra divider is added here.
  Widget _drawerHeader(BuildContext context) =>
      AppPanelHeaderWidget(title: context.l10n.chatInfoTitle, largeTitle: true, onClose: () => Navigator.of(context).maybePop());

  Widget _header(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Reactive to the chat row: a rename updates the name AND the generated avatar here
    // live (and, on desktop, in the thread behind the side-sheet). Falls back to the
    // passed chat until the first snapshot.
    return WatchChat(
      chatId: widget.chat.id,
      initial: widget.chat,
      builder: (context, chat) {
        return Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s8, AppSpacingTokens.s16, AppSpacingTokens.s16),
          child: Row(
            children: [
              AppRingedAvatarWidget(name: chat.name, size: AppDimensionTokens.size.avatarLg),
              SizedBox(width: AppSpacingTokens.s16),
              Expanded(
                child: Text(
                  chat.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
                ),
              ),
              // Rename — every device here belongs to the same person, so any of
              // them may rename (5.4).
              IconButton(
                tooltip: context.l10n.renameChatTitle,
                icon: AppIconWidget(NoxIcons.edit, color: colorScheme.onSurfaceVariant),
                onPressed: () => AppRenameChatDialogWidget.show(context, chatId: chat.id, currentName: chat.name),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Everything below the panel chrome, as slivers of the card's ONE scroll.
  ///
  /// One scroll, because the shape this replaced fails without warning. The body
  /// used to be a fixed Column whose single flexible child was this section, and
  /// when the chrome above it outgrew the surface - which the People block made
  /// possible at a large text scale, and the offline banner made likely -
  /// `Expanded` clamps to ZERO. The files list then renders at no height at all:
  /// not clipped and not scrolled past, absent, with every attachment in the
  /// chat unreachable and only a striped overflow bar to say so. Scrolling only
  /// the empty state, which is what the previous round did, fixed the one case
  /// that showed a stripe and left the case that silently ate the content.
  ///
  /// Design spec 5.4 calls this body a scrolling column. It never was one.
  List<Widget> _sectionSlivers(BuildContext context, ChatCardState state) {
    if (state is Initializing) return [_fillRest(context, const AppProgressWidget())];
    if (state is Error) {
      return [_fillRest(context, AppErrorWidget(onTryAgain: () => _bloc.add(ChatCardEvent.initialize(widget.chat.id))))];
    }
    final initialized = state as Initialized;

    return [
      SliverToBoxAdapter(
        child: AppCardSectionHeaderWidget(
          title: context.l10n.filesSectionTitle,
          trailing: initialized.files.isNotEmpty
              ? AppSegmentedWidget<FilesViewMode>(
                  options: {FilesViewMode.list: context.l10n.filesViewList, FilesViewMode.grid: context.l10n.filesViewGrid},
                  selected: initialized.viewMode,
                  onChanged: (mode) => _bloc.add(ChatCardEvent.viewModeChanged(mode)),
                )
              : null,
        ),
      ),
      if (initialized.files.isEmpty)
        _fillRest(
          context,
          AppEmptyContentWidget(
            illustration: Assets.svg.illustrations.emptyFiles,
            title: context.l10n.filesEmptyTitle,
            message: context.l10n.filesEmptyMessage,
          ),
        )
      else if (initialized.viewMode == FilesViewMode.list)
        _list(context, initialized.files)
      else
        _grid(context, initialized.files),
    ];
  }

  /// A one-off state (spinner, error, empty) centred in whatever the slivers
  /// above it left, growing the scroll instead of overflowing when that is not
  /// enough.
  ///
  /// Deliberately NOT `SliverFillRemaining(hasScrollBody: false)`, which asks
  /// its child for an intrinsic height — and `RenderConstrainedBox` answers that
  /// question by passing the FULL width down, ignoring the `maxWidth` it will
  /// actually impose at layout time. `AppEmptyContentWidget` caps its message
  /// that way, so the text was measured at one width, laid out at a narrower
  /// one, wrapped onto an extra line and overflowed by exactly that line.
  /// Measured here from the sliver's own constraints instead, so no intrinsic is
  /// consulted at all.
  ///
  /// `viewportMainAxisExtent - precedingScrollExtent` rather than
  /// `remainingPaintExtent`: the latter changes as the card is scrolled, and the
  /// height of a centred block must not depend on where the reader is.
  Widget _fillRest(BuildContext context, Widget child) {
    final inset = _bottomInset(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final rest = math.max(0.0, constraints.viewportMainAxisExtent - constraints.precedingScrollExtent - inset);
        return SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: rest),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// The system inset this scroll has to keep its last row clear of.
  ///
  /// A `ListView` reads `MediaQuery.padding` for itself - `BoxScrollView` wraps
  /// its sliver in a `SliverPadding` built from it - and a `CustomScrollView`
  /// does not. Moving the card onto slivers therefore dropped an inset nobody
  /// had to think about before, and the last file row ended up under a phone's
  /// gesture bar. Goldens cannot see it: the test view has no padding.
  ///
  /// Zero in the desktop side sheet, which sits inside a SafeArea that has
  /// already consumed it - so reading it here cannot inset the same space twice.
  static double _bottomInset(BuildContext context) => MediaQuery.paddingOf(context).bottom;

  Widget _list(BuildContext context, List<MessageAttachment> files) {
    final colorScheme = Theme.of(context).colorScheme;
    // A sliver, so the rows stay lazily built inside the card's single scroll -
    // a shrink-wrapped list would lay out every attachment of the chat at once.
    // Padded by the system inset, which the ListView this replaced added itself.
    return SliverPadding(
      padding: EdgeInsets.only(bottom: _bottomInset(context)),
      sliver: SliverList.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return ListTile(
            leading: AppFileGlyphWidget(type: file.type, iconSize: AppDimensionTokens.icon.xl, box: AppDimensionTokens.size.fileGlyphSm),
            title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(FileSizeFormatter.format(file.sizeBytes)),
            trailing: AppIconWidget(NoxIcons.chevronRight, size: AppDimensionTokens.icon.base, color: colorScheme.onSurfaceVariant),
            onTap: () => showFileView(context, file),
          );
        },
      ),
    );
  }

  Widget _grid(BuildContext context, List<MessageAttachment> files) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final columns = widget.isDrawer ? 2 : 3;
    return SliverPadding(
      padding: EdgeInsets.all(AppSpacingTokens.s12).copyWith(bottom: AppSpacingTokens.s12 + _bottomInset(context)),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacingTokens.s8,
          mainAxisSpacing: AppSpacingTokens.s8,
          // Near-square cells (design = square; a true 1.0 clips the 48dp glyph +
          // single-line name + size at 3 columns with Flutter's taller text metrics).
          childAspectRatio: 0.8,
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
                  AppFileGlyphWidget(type: file.type, iconSize: AppDimensionTokens.icon.fab, box: AppDimensionTokens.size.fileGlyphMd),
                  SizedBox(height: AppSpacingTokens.s8),
                  Text(
                    file.name,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyleTokens.labelMedium(color: colorScheme.onSurface),
                  ),
                  SizedBox(height: AppSpacingTokens.s4),
                  Text(
                    FileSizeFormatter.format(file.sizeBytes),
                    style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _scenarioControl() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: AppDevScenarioDropdown<ChatCardScenario>(
        value: _scenario,
        isExpanded: true,
        items: {for (final s in ChatCardScenario.values) s: 'scenario: ${s.name}'},
        onChanged: (selected) {
          setState(() => _scenario = selected);
          _bloc.add(ChatCardEvent.setScenario(selected));
        },
      ),
    );
  }
}

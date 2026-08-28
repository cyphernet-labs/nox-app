import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/app_dev_scenario_dropdown.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/feature_flags.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/chat_card_page/chat_card_page.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/chat_thread_page.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:nox_app/presentation/pages/file_view_page/file_view_page.dart';
import 'package:nox_app/presentation/widgets/chat/app_chat_item_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_thread_view_widget.dart';
import 'package:nox_app/presentation/widgets/chat/app_search_field_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_list_detail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_empty_content_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_error_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_notice_strip_widget.dart';
import 'package:nox_app/presentation/widgets/state/app_progress_widget.dart';

/// 5.1 Chats list — the Chats tab body and the global open chats list. Mobile: an
/// AppBar wordmark + persistent search + a pull-to-refresh paginated list; tapping a
/// chat opens the (M4) thread placeholder. Desktop: a list-detail (rail provided by
/// the shell) — a 360 list pane + a thread pane that highlights the selected row
/// without a push (thread content = M4 placeholder). Owns [ChatsListBloc] over the
/// cache-first chats repository (mock-backed until the 016 flip). `[inShell]`
/// suppresses the back affordance
/// when hosted as a shell tab; [scrollToTop] is bumped by the shell on Chats re-tap.
class ChatsListPage extends StatefulWidget {
  const ChatsListPage({
    super.key,
    this.demo = false,
    this.inShell = false,
    this.scrollToTop,
    this.openCreated,
    this.forceWide,
    this.initialScenario,
    this.accountLabel,
    this.onAccount,
  });

  final bool demo;
  final bool inShell;
  final ValueListenable<int>? scrollToTop;

  /// Account identity + jump callback for the MOBILE account affordance (N4): the
  /// shell feeds the live session label and a tap handler that switches to the
  /// Settings tab + lands on Account (the mobile counterpart to the desktop rail
  /// avatar). Rendered only on the narrow branch, and only when both are supplied
  /// (i.e. hosted in the shell) — desktop reaches Account through the rail.
  final String? accountLabel;
  final VoidCallback? onAccount;

  /// Bumped by the shell with the chat just created via the `+` FAB → the list reloads
  /// (so the new chat appears) and opens it (mobile push / desktop select).
  final ValueListenable<ChatModel?>? openCreated;

  /// Test-only seam: seeds the debug [ChatsListScenario] on init so golden tests can
  /// render the empty / offline / inline-error / fatal states deterministically
  /// without driving the dev dropdown. Null → the normal (filled) scenario.
  @visibleForTesting
  final ChatsListScenario? initialScenario;

  /// When hosted in the shell, the shell's layout decision (rail vs bottom bar) is
  /// passed down so the body doesn't re-measure its (rail-narrowed) width and land
  /// on the wrong branch. Null (standalone) → self-measure against the breakpoint.
  final bool? forceWide;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const ChatsListPage(),
    settings: const RouteSettings(name: '/chats'),
  );

  /// Gallery entry: opens standalone with the dev scenario control.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const ChatsListPage(demo: true),
    settings: const RouteSettings(name: '/chats'),
  );

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends BaseStatePage<ChatsListPage> {
  late final ChatsListBloc _bloc;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
    if (widget.initialScenario != null) {
      _devScenario = widget.initialScenario!;
      _bloc.add(ChatsListEvent.setScenario(widget.initialScenario!));
    }
    widget.scrollToTop?.addListener(_onScrollToTop);
    widget.openCreated?.addListener(_onOpenCreated);
  }

  @override
  void dispose() {
    widget.scrollToTop?.removeListener(_onScrollToTop);
    widget.openCreated?.removeListener(_onOpenCreated);
    _searchController.dispose();
    _scrollController.dispose();
    _bloc.close();
    super.dispose();
  }

  void _onScrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _refresh() async {
    // Keep the RefreshIndicator spinner up until the reset load actually finishes
    // (the handler emits loadingInProgress:true then false), not a fixed delay.
    final done = _bloc.stream.firstWhere((s) => s is Error || (s is Initialized && !s.loadingInProgress));
    _bloc.add(const ChatsListEvent.loadChats(reset: true));
    await done.timeout(const Duration(seconds: 5), onTimeout: () => _bloc.state);
  }

  void _onTapChat(ChatModel chat, {required bool wide}) {
    if (wide) {
      _bloc.add(ChatsListEvent.chatSelected(chat.id)); // desktop: select, no push
    } else {
      Navigator.of(context).push(ChatThreadPage.route(chat)); // mobile: push the real thread (5.2)
    }
  }

  // A chat was just created via the shell `+`: reload so it appears in the list, then
  // open it (mobile pushes the thread, desktop selects it in the detail pane).
  void _onOpenCreated() {
    final chat = widget.openCreated?.value;
    if (chat == null || !mounted) return;
    _bloc.add(const ChatsListEvent.loadChats(reset: true));
    final wide = widget.forceWide ?? (MediaQuery.of(context).size.width >= Constants.railBreakpoint);
    _onTapChat(chat, wide: wide);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatsListBloc>.value(
      value: _bloc,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = widget.forceWide ?? (constraints.maxWidth >= Constants.railBreakpoint);
          return BlocBuilder<ChatsListBloc, ChatsListState>(
            builder: (context, state) => wide ? _desktop(context, state) : _mobile(context, state),
          );
        },
      ),
    );
  }

  // ---- Mobile ----------------------------------------------------------------

  Widget _mobile(BuildContext context, ChatsListState state) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.inShell
            ? null
            : IconButton(
                tooltip: context.l10n.tooltipBack,
                icon: AppIconWidget(NoxIcons.arrowBack),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        title: const AppWordmarkWidget(),
        actions: [if (widget.accountLabel != null && widget.onAccount != null) _accountAvatar(context)],
        bottom: const AppSplashHairlineWidget(),
      ),
      body: Column(
        children: [
          if (FeatureFlags.enableSearch) _searchField(),
          _banners(context, state),
          Expanded(child: _list(context, state, wide: false)),
          if (kDebugMode && widget.demo) _scenarioControl(),
        ],
      ),
    );
  }

  // Mobile account affordance (N4): the app-bar counterpart to the desktop rail
  // avatar — same generated avatar (hashed bg + account initials), tapping it hands
  // off to the shell (switch to Settings + jump to Account). Wrapped in a ≥48 tap
  // target (a11y). Guarded by the null-check at the call site (shell-only, mobile-only).
  Widget _accountAvatar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8),
      child: Tooltip(
        message: context.l10n.settingsAccountTitle,
        child: InkResponse(
          onTap: widget.onAccount,
          customBorder: const CircleBorder(),
          // A 48x48 hit target around the 36 avatar (a11y FR-016 — the raw avatar is < 48).
          child: SizedBox(
            width: AppSpacingTokens.s48,
            height: AppSpacingTokens.s48,
            child: Center(
              child: AppRingedAvatarWidget(
                name: widget.accountLabel!,
                initials: noxAccountInitials(widget.accountLabel!),
                size: AppDimensionTokens.size.avatarXs,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Desktop (list-detail) -------------------------------------------------

  Widget _desktop(BuildContext context, ChatsListState state) {
    final selectedId = state is Initialized ? state.selectedChatId : null;
    return Scaffold(
      body: AppListDetailWidget(
        listPaneWidth: AppDimensionTokens.layout.chatsListPaneW,
        listPane: Column(
          children: [
            _paneHeader(context),
            if (FeatureFlags.enableSearch) _searchField(),
            _banners(context, state),
            Expanded(child: _list(context, state, wide: true)),
            if (kDebugMode && widget.demo) _scenarioControl(),
          ],
        ),
        detailPane: _threadPane(state, selectedId),
      ),
    );
  }

  Widget _paneHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s12, AppSpacingTokens.s8, AppSpacingTokens.s12),
      child: Row(
        children: [
          if (!widget.inShell)
            IconButton(
              tooltip: context.l10n.tooltipBack,
              icon: AppIconWidget(NoxIcons.arrowBack),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          // Pane title (the wordmark belongs only to the desktop window strip).
          Expanded(
            child: Text(context.l10n.chats, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _threadPane(ChatsListState state, String? selectedId) {
    final colorScheme = Theme.of(context).colorScheme;
    final ChatModel? selected = (selectedId == null || state is! Initialized)
        ? null
        : state.items.where((c) => c.id == selectedId).firstOrNull;
    final Widget content;
    if (selected == null) {
      // No selection (or the selected chat dropped out of the list, e.g. filtered
      // by search) → the illustrated empty state, not a stale thread placeholder.
      content = AppEmptyContentWidget(
        illustration: Assets.svg.illustrations.emptyChats,
        title: context.l10n.chatsNoSelectionTitle,
        message: context.l10n.chatsNoSelectionMessage,
      );
    } else {
      // Desktop list-detail: the real thread (5.2) loads in the pane (no push),
      // capped to a ≤980 reading column. The cap lives at this desktop call site
      // (not inside the shared AppThreadViewWidget) so mobile stays full-bleed.
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.threadReadingColumnW),
          child: AppThreadViewWidget(
            key: ValueKey(selected.id),
            chat: selected,
            showHeader: true,
            onInfo: () => showChatCard(context, selected),
            onOpenFile: (file) => showFileView(context, file),
          ),
        ),
      );
    }
    // A distinct pane background separates the thread from the list pane.
    return ColoredBox(color: colorScheme.surfaceContainerLowest, child: content);
  }

  // ---- Shared ----------------------------------------------------------------

  Widget _searchField() {
    return AppSearchFieldWidget(controller: _searchController, onChanged: (value) => _bloc.add(ChatsListEvent.searchChanged(value)));
  }

  Widget _banners(BuildContext context, ChatsListState state) {
    if (state is! Initialized) return const SizedBox.shrink();
    if (state.isOffline) return AppNoticeStripWidget(message: context.l10n.noConnection, icon: NoxIcons.wifiOff);
    if (state.hasLoadError) {
      return AppNoticeStripWidget(message: context.l10n.chatsLoadError);
    }
    return const SizedBox.shrink();
  }

  Widget _list(BuildContext context, ChatsListState state, {required bool wide}) {
    if (state is Initializing) return const AppProgressWidget();
    if (state is Error) return AppErrorWidget(onTryAgain: () => _bloc.add(const ChatsListEvent.initialize()));
    final initialized = state as Initialized;
    final selectedId = initialized.selectedChatId;

    final pagedList = PagedListView<String, ChatModel>.separated(
      state: initialized.pagingState,
      scrollController: _scrollController,
      fetchNextPage: () => _bloc.add(const ChatsListEvent.loadChats()),
      builderDelegate: PagedChildBuilderDelegate<ChatModel>(
        itemBuilder: (context, chat, index) {
          final row = AppChatItemWidget(
            key: ValueKey(chat.id),
            name: chat.name,
            preview: chat.lastMessagePreview,
            time: DateFormatter.relative(chat.lastMessageAt, l10n: context.l10n),
            unread: chat.unreadCount,
            onTap: () => _onTapChat(chat, wide: wide),
          );
          if (wide) {
            // Desktop rows are uniformly inset (design: every ChatRow carries an 8px
            // horizontal margin + lg radius). A Material with the matching borderRadius +
            // antiAlias clip hosts the row's InkWell, so hover/press feedback follows the
            // pill corners instead of overflowing as a rectangle; selection only swaps the
            // fill, so the row content never shifts horizontally when it becomes selected.
            final selectedFill = Theme.of(context).colorScheme.secondaryContainer;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8),
              child: Material(
                color: chat.id == selectedId ? selectedFill : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimensionTokens.radius.lg),
                clipBehavior: Clip.antiAlias,
                child: row,
              ),
            );
          }
          return ColoredBox(color: Colors.transparent, child: row);
        },
        firstPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
        newPageProgressIndicatorBuilder: (_) => const AppProgressWidget(),
        firstPageErrorIndicatorBuilder: (_) => AppErrorWidget(onTryAgain: () => _bloc.add(const ChatsListEvent.loadChats(reset: true))),
        noItemsFoundIndicatorBuilder: (_) => initialized.isSearching
            ? Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: AppSpacingTokens.s48),
                  child: Text(
                    context.l10n.chatsSearchEmpty,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            : AppEmptyContentWidget(
                illustration: Assets.svg.illustrations.emptyChats,
                title: context.l10n.chatsEmptyTitle,
                message: context.l10n.chatsEmptyMessage,
              ),
      ),
      separatorBuilder: (context, index) => const SizedBox.shrink(),
    );
    if (!FeatureFlags.enablePullToRefresh) return pagedList;
    return RefreshIndicator(onRefresh: _refresh, child: pagedList);
  }

  Widget _scenarioControl() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: Row(
        children: [
          Expanded(
            child: AppDevScenarioDropdown<ChatsListScenario>(
              value: _devScenario,
              isExpanded: true,
              items: {for (final s in ChatsListScenario.values) s: 'scenario: ${s.name}'},
              onChanged: (selected) {
                setState(() => _devScenario = selected);
                _bloc.add(ChatsListEvent.setScenario(selected));
              },
            ),
          ),
          // Debug-only (Feature 014, FR-010): push a mock inbound into a NON-selected chat
          // so its unread badge increments live — a viewed chat would just reset to 0.
          TextButton(onPressed: _simulateIncoming, child: const Text('Sim in')),
        ],
      ),
    );
  }

  void _simulateIncoming() {
    final state = _bloc.state;
    if (state is! Initialized || state.items.isEmpty) return;
    final selected = state.selectedChatId;
    final target = state.items.firstWhere((c) => c.id != selected, orElse: () => state.items.first);
    getIt<MessageRepository>().simulateIncoming(chatId: target.id);
  }

  ChatsListScenario _devScenario = ChatsListScenario.normal;
}

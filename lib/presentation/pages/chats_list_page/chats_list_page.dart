import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/feature_flags.dart';
import 'package:nox_app/general/formatters/date_formatter.dart';
import 'package:nox_app/general/text_constants.dart';
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
/// network-only mock chats repository. `[inShell]` suppresses the back affordance
/// when hosted as a shell tab; [scrollToTop] is bumped by the shell on Chats re-tap.
class ChatsListPage extends StatefulWidget {
  const ChatsListPage({super.key, this.demo = false, this.inShell = false, this.scrollToTop, this.forceWide});

  final bool demo;
  final bool inShell;
  final ValueListenable<int>? scrollToTop;

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
    widget.scrollToTop?.addListener(_onScrollToTop);
  }

  @override
  void dispose() {
    widget.scrollToTop?.removeListener(_onScrollToTop);
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
                tooltip: TextConstants.tooltipBack,
                icon: AppIconWidget(NoxIcons.arrowBack),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        title: const AppWordmarkWidget(),
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
              tooltip: TextConstants.tooltipBack,
              icon: AppIconWidget(NoxIcons.arrowBack),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          // Pane title (the wordmark belongs only to the desktop window strip).
          Expanded(
            child: Text(TextConstants.chats, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
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
        title: TextConstants.chatsNoSelectionTitle,
        message: TextConstants.chatsNoSelectionMessage,
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
    if (state.isOffline) return AppNoticeStripWidget(message: TextConstants.noConnection, icon: NoxIcons.wifiOff);
    if (state.hasLoadError) {
      return const AppNoticeStripWidget(message: TextConstants.chatsLoadError);
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
            time: DateFormatter.relative(chat.lastMessageAt),
            unread: chat.unreadCount,
            onTap: () => _onTapChat(chat, wide: wide),
          );
          if (wide && chat.id == selectedId) {
            // Desktop selected row: an inset rounded pill (not a full-bleed band).
            return Container(
              margin: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppDimensionTokens.radius.lg),
              ),
              child: row,
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
                    TextConstants.chatsSearchEmpty,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            : AppEmptyContentWidget(
                illustration: Assets.svg.illustrations.emptyChats,
                title: TextConstants.chatsEmptyTitle,
                message: TextConstants.chatsEmptyMessage,
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
      child: DropdownButton<ChatsListScenario>(
        value: _devScenario,
        isExpanded: true,
        onChanged: (selected) {
          if (selected != null) {
            setState(() => _devScenario = selected);
            _bloc.add(ChatsListEvent.setScenario(selected));
          }
        },
        items: [for (final s in ChatsListScenario.values) DropdownMenuItem(value: s, child: Text('scenario: ${s.name}'))],
      ),
    );
  }

  ChatsListScenario _devScenario = ChatsListScenario.normal;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

/// 4.1 Tab-bar shell — the app skeleton. Width-driven (`LayoutBuilder` on
/// `Constants.railBreakpoint` = 840dp): a narrow window gets the [AppBottomBarWidget]
/// (circular notch) + a center-docked [AppCreateFabWidget]; a wide window gets the
/// [AppNavigationRailWidget] with the `+` as its leading FAB. Two destinations
/// (Chats / Settings) hosted in a state-preserving cross-fade (`tabFade`). This is
/// a presentational shell with NO BLoC (blueprint 05 §5/§6 carve-out — tab index is
/// trivial local state), the live replacement for the unmounted Feature-001 AppShell.
///
/// The `+` opens the real Create chat (6.1), which self-adapts to a full-screen push
/// (mobile) or a modal dialog (desktop) via its own LayoutBuilder. Tab bodies start
/// as placeholders; US2 swaps in the real Settings root (7.1) and US3 the real Chats
/// list (5.1).
class TabBarShell extends StatefulWidget {
  const TabBarShell({super.key, this.demo = false});

  /// Gallery-preview mode: propagated to the tab bodies so the Settings tab's
  /// Log out / Force logout (dev) do NOT wipe real storage or drive the real spine.
  final bool demo;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const TabBarShell(),
    settings: const RouteSettings(name: '/shell'),
  );

  /// Gallery entry: previews the shell with its tabs in demo mode (no real side effects).
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const TabBarShell(demo: true),
    settings: const RouteSettings(name: '/shell'),
  );

  @override
  State<TabBarShell> createState() => _TabBarShellState();
}

class _TabBarShellState extends State<TabBarShell> {
  // Default display label shown by the account avatar (and Settings) until/unless
  // the session spine yields a cached label. Mirrors SettingsRootState's default.
  static const String _kDefaultAccountLabel = 'User7421';

  AppTab _active = AppTab.chats;

  // Bumped when the Chats tab is re-tapped while already active → the Chats list
  // listens and scrolls to top.
  final ValueNotifier<int> _chatsScrollToTop = ValueNotifier<int>(0);

  // Bumped when the desktop rail account avatar is tapped → the Settings tab
  // listens and lands on the Account section (even if a different section was
  // previously selected and the tab's state was preserved).
  final ValueNotifier<int> _settingsJumpToAccount = ValueNotifier<int>(0);

  // Account avatar label — read once from the session spine (display-only; the
  // shell stays BLoC-less per blueprint 05 §5.1). Falls back to the default while
  // loading / when no session label is cached.
  String _accountLabel = _kDefaultAccountLabel;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccountLabel());
  }

  Future<void> _loadAccountLabel() async {
    final result = await sessionRepository.readSession();
    if (!mounted) return;
    result.match(
      onData: (session) {
        final label = session?.label;
        if (label != null && label.isNotEmpty) setState(() => _accountLabel = label);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _chatsScrollToTop.dispose();
    _settingsJumpToAccount.dispose();
    super.dispose();
  }

  void _onSelect(AppTab tab) {
    if (tab == _active) {
      // Re-tap active tab: Chats → scroll list to top; Settings → no-op (4.1 Q-table).
      if (tab == AppTab.chats) _chatsScrollToTop.value++;
      return;
    }
    setState(() => _active = tab);
  }

  void _onCreate() => Navigator.of(context).push(CreateChatPage.route());

  // Desktop rail account avatar → switch to Settings and land on the Account section.
  void _onAccount() {
    if (_active != AppTab.settings) setState(() => _active = AppTab.settings);
    _settingsJumpToAccount.value++;
  }

  Widget _body(bool useRail) {
    // Tab bodies own their AppBar (nested under this shell's Scaffold). The shell's
    // layout decision is passed via forceWide so a body doesn't re-measure its
    // rail-narrowed width and land on the wrong (mobile) branch in the 840–rail band.
    // Rebuilt each frame, but State (blocs / scroll) is preserved by widget type +
    // position; the scrollToTop notifier is a stable shell-owned field.
    final bodies = <Widget>[
      ChatsListPage(inShell: true, demo: widget.demo, scrollToTop: _chatsScrollToTop, forceWide: useRail),
      SettingsRootPage(inShell: true, demo: widget.demo, forceWide: useRail, jumpToAccount: _settingsJumpToAccount),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < bodies.length; i++)
          // IgnorePointer + AnimatedOpacity (not Offstage) keeps every tab in the
          // tree so its state (scroll position, input) survives switches (FR-021),
          // while cross-fading over `tabFade`.
          IgnorePointer(
            ignoring: _active.index != i,
            child: AnimatedOpacity(
              opacity: _active.index == i ? 1 : 0,
              duration: NoxDuration.tabFade,
              curve: NoxEasing.standard,
              child: bodies[i],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // On Chats the back gesture pops the shell (returns to the gallery in the
      // standalone preview; in the real flow this would be SystemNavigator.pop to
      // minimize the app — // TODO(backend): wire the real minimize). On any other
      // tab, back first returns to Chats instead of leaving the shell.
      canPop: _active == AppTab.chats,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _active != AppTab.chats) setState(() => _active = AppTab.chats);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= Constants.railBreakpoint;
          return useRail ? _desktop() : _mobile();
        },
      ),
    );
  }

  Widget _mobile() {
    return Scaffold(
      body: _body(false),
      floatingActionButton: AppCreateFabWidget(onPressed: _onCreate),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: AppBottomBarWidget(active: _active, onSelect: _onSelect),
    );
  }

  Widget _desktop() {
    return Scaffold(
      body: Column(
        children: [
          // Branded window strip + brand-splash hairline at the top of the desktop
          // shell. Native min/max/close controls stay deferred (desktop-infra phase).
          const AppWindowTitlebarWidget(subtitle: 'Chats'),
          Expanded(
            child: Row(
              children: [
                AppNavigationRailWidget(
                  active: _active,
                  onSelect: _onSelect,
                  onCreate: _onCreate,
                  accountLabel: _accountLabel,
                  onAccount: _onAccount,
                ),
                VerticalDivider(width: AppDimensionTokens.border.hairline),
                Expanded(child: _body(true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

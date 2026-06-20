import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/chats_list_page/chats_list_page.dart';
import 'package:nox_app/presentation/pages/create_chat_page/create_chat_page.dart';
import 'package:nox_app/presentation/pages/settings_root_page/settings_root_page.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_navigation_rail_widget.dart';

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
  const TabBarShell({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const TabBarShell(),
    settings: const RouteSettings(name: '/shell'),
  );

  @override
  State<TabBarShell> createState() => _TabBarShellState();
}

class _TabBarShellState extends State<TabBarShell> {
  AppTab _active = AppTab.chats;

  // Bumped when the Chats tab is re-tapped while already active → the Chats list
  // (US3) listens and scrolls to top. Unused by the placeholder body until then.
  final ValueNotifier<int> _chatsScrollToTop = ValueNotifier<int>(0);

  // Tab bodies. Each owns its own Scaffold + AppBar (nested under this shell's
  // Scaffold, which provides the bottom bar / rail + docked FAB).
  late final List<Widget> _bodies = <Widget>[
    ChatsListPage(inShell: true, scrollToTop: _chatsScrollToTop),
    const SettingsRootPage(inShell: true),
  ];

  @override
  void dispose() {
    _chatsScrollToTop.dispose();
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

  Widget _body() {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _bodies.length; i++)
          // IgnorePointer + AnimatedOpacity (not Offstage) keeps every tab in the
          // tree so its state (scroll position, input) survives switches (FR-021),
          // while cross-fading over `tabFade`.
          IgnorePointer(
            ignoring: _active.index != i,
            child: AnimatedOpacity(
              opacity: _active.index == i ? 1 : 0,
              duration: NoxDuration.tabFade,
              curve: NoxEasing.standard,
              child: _bodies[i],
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
      body: _body(),
      floatingActionButton: AppCreateFabWidget(onPressed: _onCreate),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: AppBottomBarWidget(active: _active, onSelect: _onSelect),
    );
  }

  Widget _desktop() {
    return Scaffold(
      body: Row(
        children: [
          AppNavigationRailWidget(active: _active, onSelect: _onSelect, onCreate: _onCreate),
          const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/l10n_extension.dart';
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
/// a (currently) BLoC-less shell holding trivial local state — tab index plus a
/// one-shot, display-only avatar-label read (see the `_accountLabel` note on the
/// blueprint 05 §5.1 stretch). It is the live replacement for the unmounted
/// Feature-001 AppShell and migrates to a shell value-BLoC (§6.1) in the backend phase.
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
  AppTab _active = AppTab.chats;

  // Bumped when the Chats tab is re-tapped while already active → the Chats list
  // listens and scrolls to top.
  final ValueNotifier<int> _chatsScrollToTop = ValueNotifier<int>(0);

  // Bumped when the desktop rail account avatar is tapped → the Settings tab
  // listens and lands on the Account section (even if a different section was
  // previously selected and the tab's state was preserved).
  final ValueNotifier<int> _settingsJumpToAccount = ValueNotifier<int>(0);

  // Carries the chat just created via the `+` FAB → the Chats list listens, reloads
  // (so the new chat appears) and opens it (mobile pushes the thread, desktop selects
  // it in the detail pane).
  final ValueNotifier<ChatModel?> _chatsOpenCreated = ValueNotifier<ChatModel?>(null);

  // Account avatar label for the desktop rail avatar. Fed LIVE by the session's
  // reactive label channel (feature 015): watchLabel emits the current cached label
  // on listen, then every rename — so editing the label in the Settings tab updates
  // the rail avatar within the same session, no restart. Falls back to the placeholder
  // when no label is cached (or after logout, which emits null).
  //
  // This subscription + setState stretches the blueprint 05 §5.1 UI-first carve-out
  // (which assumes NO repository/async) — a deliberate, display-only convenience; the
  // shell's tab/label/jump state migrates into a shell value-BLoC (AppRootBloc, §6.1)
  // once real tabs/data exist. // TODO(blueprint-shell-bloc): move shell state into a value-BLoC.
  String _accountLabel = Constants.defaultUserLabel;
  StreamSubscription<String?>? _labelSub;

  @override
  void initState() {
    super.initState();
    _labelSub = sessionRepository.watchLabel().listen((label) {
      if (!mounted) return;
      setState(() => _accountLabel = (label != null && label.isNotEmpty) ? label : Constants.defaultUserLabel);
    });
  }

  @override
  void dispose() {
    _labelSub?.cancel();
    _chatsScrollToTop.dispose();
    _settingsJumpToAccount.dispose();
    _chatsOpenCreated.dispose();
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

  Future<void> _onCreate({required bool desktop}) async {
    // Create chat (6.1) resolves with the created chat on success. Desktop shows a real
    // modal dialog over the live list (N5); mobile pushes the full-screen form. Hand the
    // result to the Chats tab to reload + open (mobile push / desktop select); null = cancelled.
    final created = desktop ? await CreateChatPage.showAsDialog(context) : await Navigator.of(context).push(CreateChatPage.route());
    if (created == null || !mounted) return;
    if (_active != AppTab.chats) setState(() => _active = AppTab.chats);
    _chatsOpenCreated.value = created;
  }

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
      ChatsListPage(
        inShell: true,
        demo: widget.demo,
        scrollToTop: _chatsScrollToTop,
        openCreated: _chatsOpenCreated,
        forceWide: useRail,
        // Mobile-only account affordance (N4) — the app-bar avatar hands off to the
        // same Settings/Account jump as the desktop rail avatar. The page renders it
        // only on the narrow branch, so the desktop rail stays the wide entry point.
        accountLabel: _accountLabel,
        onAccount: _onAccount,
      ),
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
          return useRail ? _desktop(context) : _mobile();
        },
      ),
    );
  }

  Widget _mobile() {
    return Scaffold(
      body: _body(false),
      floatingActionButton: AppCreateFabWidget(onPressed: () => _onCreate(desktop: false)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: AppBottomBarWidget(active: _active, onSelect: _onSelect),
    );
  }

  Widget _desktop(BuildContext context) {
    // The titlebar screen-label tracks the active tab (R3 parity): on mobile the
    // AppBar title already changes per tab, so the desktop strip must too — and via
    // l10n, not a hardcoded English literal, so it localizes (EN/UK) like the rail.
    final subtitle = switch (_active) {
      AppTab.chats => context.l10n.chats,
      AppTab.settings => context.l10n.settings,
    };
    return Scaffold(
      body: Column(
        children: [
          // Branded window strip + brand-splash hairline at the top of the desktop
          // shell. Native min/max/close controls stay deferred (desktop-infra phase).
          AppWindowTitlebarWidget(subtitle: subtitle),
          Expanded(
            child: Row(
              children: [
                // No VerticalDivider here: the rail draws its OWN right hairline
                // (AppNavigationRailWidget's border), so a divider would double the seam.
                AppNavigationRailWidget(
                  active: _active,
                  onSelect: _onSelect,
                  onCreate: () => _onCreate(desktop: true),
                  accountLabel: _accountLabel,
                  onAccount: _onAccount,
                ),
                Expanded(child: _body(true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

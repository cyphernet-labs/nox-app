import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/item_list_page/item_list_page.dart';
import 'package:nox_app/presentation/pages/placeholder/settings_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// NOT currently mounted — `AppRoot` starts at `HomePage` (the UI-kit launcher)
/// until real chat features land; the live shell widgets now live in
/// `lib/presentation/widgets/shell/`. Kept as the Feature-001 skeleton.
///
/// Adaptive app shell. The layout is **width-driven** (`LayoutBuilder` on
/// `constraints.maxWidth >= Constants.railBreakpoint`, 840dp, M3 medium->expanded)
/// — NOT Platform-driven, so a narrow desktop window gets the bottom bar and a
/// wide one gets the rail. Mobile branch: bottom bar (BottomAppBar with a notch
/// + center-docked `+` FAB). Desktop branch: NavigationRail with the `+` as its
/// leading FAB. Two destinations (Chats / Settings); body = IndexedStack (keeps
/// tab state). No list-detail / no account avatar (no profile screen). Single-window.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static final List<_Destination> _destinations = <_Destination>[
    _Destination(label: TextConstants.chats, icon: NoxIcons.forum, selectedIcon: NoxIcons.forumFill),
    _Destination(label: TextConstants.settings, icon: NoxIcons.settings, selectedIcon: NoxIcons.settingsFill),
  ];

  // Chats tab body is the Item verification-harness (mock data, scaffold-demo);
  // Settings is a placeholder. No real product features yet (FR-013).
  static const List<Widget> _pages = <Widget>[ItemListPage(), SettingsPlaceholderPage()];

  void _onSelect(int i) => setState(() => _index = i);

  // Create-chat is a no-op in the skeleton (no real feature, FR-013).
  void _onCreate() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(TextConstants.comingSoon)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= Constants.railBreakpoint;
        final Widget body = IndexedStack(index: _index, children: _pages);
        return useRail ? _buildRail(body) : _buildBottomBar(body);
      },
    );
  }

  Widget _buildRail(Widget body) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _onSelect,
            labelType: NavigationRailLabelType.all,
            leading: FloatingActionButton(onPressed: _onCreate, tooltip: TextConstants.comingSoon, child: AppIconWidget(NoxIcons.add)),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: AppIconWidget(d.icon), selectedIcon: AppIconWidget(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          VerticalDivider(width: AppDimensionTokens.border.hairline),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Widget body) {
    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _onCreate,
        tooltip: TextConstants.comingSoon,
        child: AppIconWidget(NoxIcons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarItem(destination: _destinations[0], selected: _index == 0, onTap: () => _onSelect(0)),
            const SizedBox(width: NoxSpacing.minTapTarget), // notch gap for the docked FAB
            _BarItem(destination: _destinations[1], selected: _index == 1, onTap: () => _onSelect(1)),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final SvgGenImage icon;
  final SvgGenImage selectedIcon;
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.destination, required this.selected, required this.onTap});

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIconWidget(selected ? destination.selectedIcon : destination.icon, color: color),
            Text(destination.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

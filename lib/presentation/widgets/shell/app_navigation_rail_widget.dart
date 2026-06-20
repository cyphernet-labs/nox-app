import 'package:flutter/material.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

/// Desktop/wide navigation rail for the [TabBarShell] (4.1 desktop branch): two
/// destinations (Chats / Settings) with the docked `+` create-chat action as the
/// leading FAB. The kit analogue of [AppBottomBarWidget] for `>= railBreakpoint`
/// windows. Selected destination uses `primary` (per `navigationRailTheme`).
class AppNavigationRailWidget extends StatelessWidget {
  const AppNavigationRailWidget({super.key, required this.active, required this.onSelect, required this.onCreate});

  final AppTab active;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: active.index,
      onDestinationSelected: (index) => onSelect(AppTab.values[index]),
      labelType: NavigationRailLabelType.all,
      leading: AppCreateFabWidget(onPressed: onCreate),
      destinations: [
        NavigationRailDestination(
          icon: AppIconWidget(NoxIcons.forum),
          selectedIcon: AppIconWidget(NoxIcons.forumFill),
          label: const Text(TextConstants.chats),
        ),
        NavigationRailDestination(
          icon: AppIconWidget(NoxIcons.settings),
          selectedIcon: AppIconWidget(NoxIcons.settingsFill),
          label: const Text(TextConstants.settings),
        ),
      ],
    );
  }
}

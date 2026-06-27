import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_create_fab_widget.dart';

/// Desktop/wide navigation rail for the [TabBarShell] (4.1 desktop branch): two
/// destinations (Chats / Settings) with the docked `+` create-chat action as the
/// leading FAB, and the account avatar pinned to the bottom of the rail. The kit
/// analogue of [AppBottomBarWidget] for `>= railBreakpoint` windows. Selected
/// destination uses `primary` (per `navigationRailTheme`).
///
/// The account avatar (design: `NavRail` bottom avatar, size 36 + subtle ring)
/// renders the user's [accountLabel] initials via [noxAccountInitials] over the
/// hashed avatar color; tapping it routes to Settings / Account ([onAccount]).
/// `trailingAtBottom: true` pins the avatar to the bottom of the rail — without it
/// the `trailing` slot renders inside the top-aligned destinations group (right
/// under `Settings`), not at the bottom.
class AppNavigationRailWidget extends StatelessWidget {
  const AppNavigationRailWidget({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onCreate,
    required this.accountLabel,
    required this.onAccount,
  });

  final AppTab active;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback onCreate;

  /// Display label whose initials + hashed color render the bottom account avatar.
  final String accountLabel;

  /// Tap on the account avatar → switch to Settings and land on the Account section.
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: active.index,
      onDestinationSelected: (index) => onSelect(AppTab.values[index]),
      labelType: NavigationRailLabelType.all,
      leading: AppCreateFabWidget(onPressed: onCreate),
      trailing: _accountAvatar(context),
      trailingAtBottom: true,
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

  Widget _accountAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s12),
      child: Tooltip(
        message: TextConstants.settingsAccountTitle,
        child: InkResponse(
          onTap: onAccount,
          customBorder: const CircleBorder(),
          child: Container(
            // Subtle ring, matching the chat-row avatars (design: `0 0 0 2px onSurface@0.06`).
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: colorScheme.onSurface.withValues(alpha: 0.06), spreadRadius: AppDimensionTokens.border.thick)],
            ),
            child: AppAvatarWidget(name: accountLabel, initials: noxAccountInitials(accountLabel), size: AppDimensionTokens.size.avatarXs),
          ),
        ),
      ),
    );
  }
}

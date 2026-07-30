import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_bottom_bar_widget.dart';

/// Desktop/wide navigation rail for the [TabBarShell] (4.1 desktop branch). A
/// custom rail built to the design `NavRail` (NOT Material's `NavigationRail`,
/// whose stock metrics/indicator do not match): an 80-wide `surface` strip with a
/// right hairline and, top-to-bottom — a **rounded-square** create FAB (radius lg,
/// elevation 2), the two destinations (Chats / Settings) evenly spaced (gap 12),
/// each a rounded-square (radius md) ink target with a pill indicator behind the
/// icon, then a `Spacer`, and the account avatar pinned to the bottom.
///
/// The account avatar (design: size 36 + subtle ring) renders the user's
/// [accountLabel] initials via [noxAccountInitials] over the hashed avatar color;
/// tapping it routes to Settings / Account ([onAccount]). All press/hover feedback
/// is clipped to the rounded shapes (FAB / destination cells / avatar circle).
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
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: AppDimensionTokens.border.hairline),
        ),
      ),
      child: Material(
        color: colorScheme.surface,
        child: SizedBox(
          width: AppSpacingTokens.s80,
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppSpacingTokens.s8, AppSpacingTokens.s16, AppSpacingTokens.s8, AppSpacingTokens.s20),
            child: Column(
              children: [
                _createFab(context),
                // Breathing room between the FAB and the destinations group (design: 22).
                SizedBox(height: AppSpacingTokens.s24),
                _destination(context, AppTab.chats, NoxIcons.forum, NoxIcons.forumFill, context.l10n.chats),
                SizedBox(height: AppSpacingTokens.s12),
                _destination(context, AppTab.settings, NoxIcons.settings, NoxIcons.settingsFill, context.l10n.settings),
                const Spacer(),
                _accountAvatar(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Rounded-square create FAB (design: 56, radius lg, primaryContainer, elevation 2).
  // The Material's borderRadius + antiAlias clip keeps the tap splash square-cornered.
  Widget _createFab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.tooltipCreateChat,
      child: Material(
        color: colorScheme.primaryContainer,
        elevation: NoxElevation.level2,
        borderRadius: BorderRadius.circular(AppDimensionTokens.radius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onCreate,
          child: SizedBox(
            width: AppSpacingTokens.s56,
            height: AppSpacingTokens.s56,
            child: Center(
              child: AppIconWidget(NoxIcons.add, size: AppDimensionTokens.icon.fab, color: colorScheme.onPrimaryContainer),
            ),
          ),
        ),
      ),
    );
  }

  // Destination cell (icon-pill + label) — a rounded-square (radius md) ink target,
  // so hover/press feedback is square-cornered; the selected icon sits in a pill
  // indicator (radius full, secondaryContainer).
  Widget _destination(BuildContext context, AppTab tab, SvgGenImage icon, SvgGenImage selectedIcon, String label) {
    final selected = active == tab;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // This is a custom rail (not Material's NavigationRail), so it must supply the
    // destination semantics itself — mirror the mobile bottom bar's _Tab so a screen
    // reader announces each destination as a selectable button with its selected
    // state on desktop too (R4 parity; otherwise the rail reads as a plain tappable).
    // NB: no explicit `label` here — the child Text(label) already contributes the
    // accessible name to this node; re-setting it would concatenate into a duplicated
    // "Chats\nChats" announcement.
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () => onSelect(tab),
        borderRadius: BorderRadius.circular(AppDimensionTokens.radius.md),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSpacingTokens.s56,
                height: AppSpacingTokens.s32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? colorScheme.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppDimensionTokens.radius.pill),
                ),
                child: AppIconWidget(
                  selected ? selectedIcon : icon,
                  size: AppDimensionTokens.icon.xl,
                  color: selected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: AppSpacingTokens.s4),
              Text(label, style: textTheme.labelMedium?.copyWith(color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.settingsAccountTitle,
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
    );
  }
}

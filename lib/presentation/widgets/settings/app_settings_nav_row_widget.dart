import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// A navigable settings row (7.1), in one of two shapes — never merged into a
/// shared card. Icon-less per the locked spec. [color] tints the title (the
/// destructive `Log out` row → `ColorScheme.error`).
///
/// [menuPane] (desktop list-detail): an M3 NavigationDrawer destination — a
/// stadium item that is TRANSPARENT until [selected], when it fills with
/// `secondaryContainer`. No container of its own, because the pane is the
/// container.
///
/// Otherwise (the phone list): a standalone rounded tile on
/// `surfaceContainerLow`, one per destination, separated by a gap.
///
/// They were briefly all inside ONE card with hairlines between them. Three
/// devices doing one job - a card edge, a hairline, and a selection pill - and on
/// desktop the pill broke out through the card's rounded corner, because a
/// stadium inset by 8 is wider at its ends than the corner it sits in.
class AppSettingsNavRowWidget extends StatelessWidget {
  const AppSettingsNavRowWidget({
    super.key,
    required this.title,
    required this.onTap,
    this.color,
    this.selected = false,
    this.menuPane = false,
  });

  final String title;
  final VoidCallback onTap;
  final Color? color;
  final bool selected;
  final bool menuPane;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (menuPane) {
      return Padding(
        padding: EdgeInsets.fromLTRB(AppSpacingTokens.s8, 0, AppSpacingTokens.s8, AppSpacingTokens.s4),
        child: ListTile(
          title: Text(title, style: color == null ? null : TextStyle(color: color)),
          textColor: color,
          selected: selected,
          selectedTileColor: colorScheme.secondaryContainer,
          shape: const StadiumBorder(),
          onTap: onTap,
        ),
      );
    }
    final radius = BorderRadius.circular(AppDimensionTokens.radius.lg);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, 0, AppSpacingTokens.s16, AppSpacingTokens.s8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(title, style: color == null ? null : TextStyle(color: color)),
          textColor: color,
          shape: RoundedRectangleBorder(borderRadius: radius),
          onTap: onTap,
        ),
      ),
    );
  }
}

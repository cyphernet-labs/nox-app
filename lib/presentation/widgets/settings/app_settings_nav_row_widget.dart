import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// A navigable settings row (7.1): a `ListTile` with a title and tap handler. Icon-
/// less per the locked spec (the flat list has no leading/trailing glyphs). [color]
/// tints the title (used for the destructive `Log out` row → `ColorScheme.error`).
/// [selected] highlights the row in the desktop list-detail menu pane. In [menuPane]
/// mode (desktop list-detail) the rows are inset 8px and the selected highlight is a
/// full stadium pill (design: SettingsNavItem `margin 0 8px` + `radius 999`), instead
/// of the mobile flat list's full-bleed square highlight.
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
    final tile = ListTile(
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      textColor: color,
      selected: selected,
      selectedTileColor: colorScheme.secondaryContainer,
      shape: menuPane ? const StadiumBorder() : null,
      onTap: onTap,
    );
    if (!menuPane) return tile;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8),
      child: tile,
    );
  }
}

import 'package:flutter/material.dart';

/// A navigable settings row (7.1): a `ListTile` with a title and tap handler. Icon-
/// less per the locked spec (the flat list has no leading/trailing glyphs). [color]
/// tints the title (used for the destructive `Log out` row → `ColorScheme.error`).
/// [selected] highlights the row in the desktop list-detail menu pane.
class AppSettingsNavRowWidget extends StatelessWidget {
  const AppSettingsNavRowWidget({super.key, required this.title, required this.onTap, this.color, this.selected = false});

  final String title;
  final VoidCallback onTap;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      textColor: color,
      selected: selected,
      selectedTileColor: colorScheme.secondaryContainer,
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// A navigable settings row (7.1), in one of two shapes, each straight from its
/// own design corpus. Both lead with the 40dp circular chip the corpora draw.
///
/// [menuPane] (desktop list-detail) — `SettingsNavItem`: a stadium item that is
/// transparent until [selected], when it fills with `secondaryContainer`. No
/// container of its own; the pane is the container, and the groups are separated
/// by a line under each, not by a card.
///
/// Otherwise (the phone list) — `SettingsNavRow`: a standalone rounded tile on
/// `surfaceContainerLow`, one per destination, with a trailing chevron. The
/// corpus draws these inside one shared card; they are separate tiles here by an
/// owner decision taken while this screen was being reworked.
///
/// [danger] is the destructive `Log out` row: `error` throughout, the chip filled
/// at 14% of it, the glyph always the FILLED variant, and no chevron — it opens a
/// dialog, it does not navigate.
class AppSettingsNavRowWidget extends StatelessWidget {
  const AppSettingsNavRowWidget({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.selectedIcon,
    this.danger = false,
    this.selected = false,
    this.menuPane = false,
  });

  final String title;

  /// The glyph while unselected — and, when [selectedIcon] is null, always.
  final SvgGenImage icon;

  /// The FILLED variant, drawn while [selected] or [danger]. Same axis the bottom
  /// bar swaps on its tabs.
  final SvgGenImage? selectedIcon;

  final VoidCallback onTap;
  final bool danger;
  final bool selected;
  final bool menuPane;

  /// Chip fill for the selected row: the design tints it with the row's own
  /// foreground rather than reaching for another container colour.
  static const double _selectedChipAlpha = 0.12;

  /// Chip fill for the destructive row.
  static const double _dangerChipAlpha = 0.14;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = danger ? colorScheme.error : (selected ? colorScheme.onSecondaryContainer : colorScheme.onSurface);
    final chipColor = danger
        ? colorScheme.error.withValues(alpha: _dangerChipAlpha)
        : (selected ? colorScheme.onSecondaryContainer.withValues(alpha: _selectedChipAlpha) : colorScheme.secondaryContainer);
    final glyphColor = danger ? colorScheme.error : colorScheme.onSecondaryContainer;
    final glyph = (selected || danger) ? (selectedIcon ?? icon) : icon;
    final chip = Container(
      width: AppDimensionTokens.size.avatarSm,
      height: AppDimensionTokens.size.avatarSm,
      decoration: BoxDecoration(shape: BoxShape.circle, color: chipColor),
      child: Center(
        child: AppIconWidget(glyph, size: AppDimensionTokens.icon.lg, color: glyphColor),
      ),
    );
    final label = Text(title, style: textTheme.bodyLarge?.copyWith(color: foreground));

    if (menuPane) {
      return Padding(
        padding: EdgeInsets.fromLTRB(AppSpacingTokens.s8, 0, AppSpacingTokens.s8, AppSpacingTokens.s4),
        child: ListTile(
          leading: chip,
          title: label,
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
          leading: chip,
          title: label,
          // No chevron on the destructive row: it opens a dialog rather than
          // going anywhere, and a chevron would promise otherwise.
          trailing: danger
              ? null
              : AppIconWidget(NoxIcons.chevronRight, size: AppDimensionTokens.icon.lg, color: colorScheme.onSurfaceVariant),
          shape: RoundedRectangleBorder(borderRadius: radius),
          onTap: onTap,
        ),
      ),
    );
  }
}

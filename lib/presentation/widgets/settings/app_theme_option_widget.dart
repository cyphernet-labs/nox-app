import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Selectable theme option card (Appearance 7.3): a mini preview thumbnail + label,
/// with a primary outline + check glyph when selected. Single-select is owned by
/// the parent. Presentational only.
class AppThemeOptionWidget extends StatelessWidget {
  const AppThemeOptionWidget({
    super.key,
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
    this.caption,
  });

  final String label;
  final Widget preview;
  final bool selected;
  final VoidCallback onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = BorderRadius.circular(NoxRadius.m);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          padding: EdgeInsets.all(AppSpacingTokens.s12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: borderRadius,
            border: Border.all(color: selected ? colorScheme.primary : colorScheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              preview,
              SizedBox(width: AppSpacingTokens.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                    if (caption != null) Text(caption!, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected) AppIconWidget(NoxIcons.check, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

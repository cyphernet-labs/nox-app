import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Selectable theme option card (Appearance 7.3): a mini preview thumbnail + label,
/// with an always-present radio indicator (filled `primary` dot when selected) and a
/// `surfaceContainerHigh` fill + primary outline only when selected. Single-select is
/// owned by the parent. Presentational only.
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
            color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
            borderRadius: borderRadius,
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outlineVariant,
              width: selected ? AppDimensionTokens.border.thick : AppDimensionTokens.border.hairline,
            ),
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
                    if (caption != null) Text(caption!, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              _RadioIndicator(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always-rendered single-select radio dot: a ringed circle (`primary` when
/// selected, `outline` otherwise) with a centered filled `primary` dot only when
/// selected. Sized from `icon.lg` (20).
class _RadioIndicator extends StatelessWidget {
  const _RadioIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final diameter = AppDimensionTokens.icon.lg;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? colorScheme.primary : colorScheme.outline, width: AppDimensionTokens.border.thick),
      ),
      child: selected
          ? Container(
              width: AppSpacingTokens.s10,
              height: AppSpacingTokens.s10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.primary),
            )
          : null,
    );
  }
}

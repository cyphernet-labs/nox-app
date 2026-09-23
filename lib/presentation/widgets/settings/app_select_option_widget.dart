import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Selectable option card - Appearance 7.3 and Language 7.4: an optional preview
/// thumbnail + label, with an always-present radio indicator (filled `primary` dot
/// when selected) and a `surfaceContainerHigh` fill + primary outline only when
/// selected. Single-select is owned by the parent. Presentational only.
///
/// It was `AppThemeOptionWidget` while Appearance was the only caller. Language
/// picked the same shape up because the screen spec asks for it in those words -
/// "pattern as in 7.3" - and the name had to stop naming one of two callers.
class AppSelectOptionWidget extends StatelessWidget {
  const AppSelectOptionWidget({super.key, required this.label, required this.selected, required this.onTap, this.preview, this.caption});

  final String label;

  /// The leading thumbnail, for an option that has something to show. Appearance
  /// draws a miniature of the theme (96×76); Language draws a 64×48 tile — the
  /// country's flag, or the device glyph for `System`, which is what that option
  /// follows. Null leaves the label alone against the card's edge.
  ///
  /// The flags were circle-masked icons until 2026-09-20, which is why they used
  /// to sit in a 40dp circle and clip against the row; the mask is gone and the
  /// artwork under it always covered a full square.
  final Widget? preview;
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
              if (preview != null) ...[preview!, SizedBox(width: AppSpacingTokens.s16)],
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

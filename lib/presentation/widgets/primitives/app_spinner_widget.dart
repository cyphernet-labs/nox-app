import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';

/// Indeterminate circular progress (M3 default). Standalone → `primary`;
/// inside a `FilledButton` pass `color: cs.onPrimary`. Source: primitives.md `NoxSpinner`.
class AppSpinnerWidget extends StatelessWidget {
  const AppSpinnerWidget({super.key, this.size, this.color, this.strokeWidth});

  /// Null falls back to `icon.xl` (24) / `border.heavy` (3) — a token getter
  /// can't be a const default.
  final double? size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? AppDimensionTokens.icon.xl;
    return SizedBox(
      width: dimension,
      height: dimension,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth ?? AppDimensionTokens.border.heavy,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

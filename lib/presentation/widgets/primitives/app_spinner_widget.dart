import 'package:flutter/material.dart';

/// Indeterminate circular progress (M3 default). Standalone → `primary`;
/// inside a `FilledButton` pass `color: cs.onPrimary`. Source: primitives.md `NoxSpinner`.
class AppSpinnerWidget extends StatelessWidget {
  const AppSpinnerWidget({super.key, this.size = 24, this.color, this.strokeWidth = 3});

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color ?? Theme.of(context).colorScheme.primary),
    );
  }
}

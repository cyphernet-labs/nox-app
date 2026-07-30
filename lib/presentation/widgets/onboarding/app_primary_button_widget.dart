import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Full-width primary submit button used by the onboarding forms (Sign in / Done).
/// A `FilledButton` stretched to `double.infinity` that swaps its label for a
/// centered spinner while [loading]. [onPressed] is passed through verbatim (null →
/// disabled); callers keep owning the enable/disable rule (e.g. gating on submit),
/// so [loading] only governs the label↔spinner swap, not the disabled state. The
/// spinner colour (`onPrimary`) is resolved here, removing the ad-hoc `Theme.of`
/// each call site used to carry.
class AppPrimaryButtonWidget extends StatelessWidget {
  const AppPrimaryButtonWidget({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        child: loading ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.onPrimary) : Text(label),
      ),
    );
  }
}

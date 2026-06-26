import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Error state: an error glyph + an optional message + an optional retry CTA.
/// Used by `state.when(error: ...)` and first-page pagination errors.
class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({super.key, this.message, this.onTryAgain});

  final String? message;
  final VoidCallback? onTryAgain;

  static double get _iconSize => AppDimensionTokens.icon.hero;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconWidget(NoxIcons.error, size: _iconSize, color: colorScheme.onSurfaceVariant),
            SizedBox(height: AppSpacingTokens.s16),
            Text(
              message ?? TextConstants.errorGeneralTitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (onTryAgain != null) ...[
              SizedBox(height: AppSpacingTokens.s16),
              FilledButton(onPressed: onTryAgain, child: const Text(TextConstants.actionTryAgain)),
            ],
          ],
        ),
      ),
    );
  }
}

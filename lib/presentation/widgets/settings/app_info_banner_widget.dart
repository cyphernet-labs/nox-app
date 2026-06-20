import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Inline information banner (MaterialBanner style): a NoxIcons glyph, a message and
/// a single text action — e.g. the "notifications are off in system settings"
/// prompt. Presentational; the action is owned by the caller.
class AppInfoBannerWidget extends StatelessWidget {
  const AppInfoBannerWidget({super.key, required this.icon, required this.message, required this.actionLabel, required this.onAction});

  final SvgGenImage icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: colorScheme.secondaryContainer,
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      child: Row(
        children: [
          AppIconWidget(icon, color: colorScheme.onSecondaryContainer),
          SizedBox(width: AppSpacingTokens.s12),
          Expanded(
            child: Text(message, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSecondaryContainer)),
          ),
          SizedBox(width: AppSpacingTokens.s8),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: colorScheme.onSecondaryContainer),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

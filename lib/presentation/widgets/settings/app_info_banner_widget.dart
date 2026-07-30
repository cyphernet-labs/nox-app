import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/state/app_banner_shell_widget.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Inline information banner (MaterialBanner style): a NoxIcons glyph, an optional
/// bold title, a message and a single text action laid out on its own row — e.g.
/// the "Notifications are blocked" prompt. Surface + elevation read it as a layered
/// banner. Presentational; the action is owned by the caller.
class AppInfoBannerWidget extends StatelessWidget {
  const AppInfoBannerWidget({
    super.key,
    required this.icon,
    this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final SvgGenImage icon;
  final String? title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppBannerShellWidget(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconWidget(icon, color: colorScheme.onSurfaceVariant),
        SizedBox(width: AppSpacingTokens.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title!, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                SizedBox(height: AppSpacingTokens.s4),
              ],
              Text(message, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              SizedBox(height: AppSpacingTokens.s8),
              // Action on its own row under the message (M3 banner convention).
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

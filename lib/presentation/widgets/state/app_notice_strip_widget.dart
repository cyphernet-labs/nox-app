import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Persistent inline notice strip (offline / inline-error) shown under the
/// AppBar/search or at the top of a pane: an elevated `surfaceContainer` banner
/// with a contextual glyph ([icon] — e.g. `wifiOff` offline, `error` for a load
/// error), a message, and an optional action. Shared by the chats list (5.1), the
/// chat thread (5.2) and the chat card (5.4) — sits below the chrome and avoids
/// `MaterialBanner`'s non-empty-actions requirement.
class AppNoticeStripWidget extends StatelessWidget {
  const AppNoticeStripWidget({super.key, required this.message, this.icon, this.actionLabel, this.onAction});

  final String message;

  /// Leading glyph; null falls back to `error` (a token getter can't be a const default).
  final SvgGenImage? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colorScheme.surfaceContainer,
      elevation: NoxElevation.level3,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s8),
        child: Row(
          children: [
            AppIconWidget(icon ?? NoxIcons.error, size: AppDimensionTokens.icon.lg, color: colorScheme.onSurfaceVariant),
            SizedBox(width: AppSpacingTokens.s12),
            Expanded(
              child: Text(message, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
            ),
            if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

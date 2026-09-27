import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Inline notice card: a NoxIcons glyph, an optional bold title, a message, and a
/// single text action at the trailing edge - e.g. the "Notifications are blocked"
/// prompt. Presentational; the action is owned by the caller.
///
/// An inset CARD, in the geometry every other card on a settings screen uses
/// (radius `lg`, the same 16 margin the settings group gives itself). It used to
/// be a full-bleed `MaterialBanner`-style slab on [AppBannerShellWidget] -
/// `surfaceContainer` at elevation 3, edge to edge - which was M3-correct for a
/// banner and looked like nothing else on the screen it appeared on: a heavy grey
/// band across the top, over an inset card that started 16 further in.
/// `surfaceContainer` rather than the group's `surfaceContainerLow`, so that it
/// still reads as a note ABOUT the rows below rather than as one of them.
///
/// The full-bleed shell stays where full bleed is right: [AppNoticeStripWidget],
/// the offline strip that sits directly under the chats chrome.
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
    return Card(
      margin: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s4, AppSpacingTokens.s16, AppSpacingTokens.s16),
      elevation: NoxElevation.level1,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensionTokens.radius.lg)),
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        child: Row(
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
                  // Its own row under the message, at the TRAILING edge - where M3
                  // ends a notice's actions.
                  Align(
                    alignment: Alignment.centerRight,
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
        ),
      ),
    );
  }
}

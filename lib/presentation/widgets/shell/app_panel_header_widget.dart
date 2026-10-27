import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_hairline_divider_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Header row for an overlay panel (desktop side-sheet / lightbox): an optional
/// [leading] widget (e.g. the file-type glyph), a title and a trailing close button,
/// with a hairline beneath it (design: both the drawer and lightbox headers carry a
/// bottom border). Shared by the chat card drawer (5.4, [largeTitle] → `titleLarge`)
/// and the file view lightbox (5.3, `titleMedium`).
class AppPanelHeaderWidget extends StatelessWidget {
  const AppPanelHeaderWidget({super.key, required this.title, required this.onClose, this.leading, this.largeTitle = false});

  final String title;
  final VoidCallback onClose;
  final Widget? leading;
  final bool largeTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s8, AppSpacingTokens.s8, AppSpacingTokens.s8),
          child: Row(
            children: [
              if (leading != null) ...[leading!, SizedBox(width: AppSpacingTokens.s12)],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (largeTitle ? textTheme.titleLarge : textTheme.titleMedium)?.copyWith(color: colorScheme.onSurface),
                ),
              ),
              IconButton(tooltip: context.l10n.actionClose, icon: AppIconWidget(NoxIcons.close), onPressed: onClose),
            ],
          ),
        ),
        const AppHairlineDividerWidget(),
      ],
    );
  }
}

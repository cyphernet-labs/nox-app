import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Header row for an overlay panel (desktop side-sheet / lightbox): a title and a
/// trailing close button. Shared by the chat card drawer (5.4) and the file view
/// lightbox (5.3).
class AppPanelHeaderWidget extends StatelessWidget {
  const AppPanelHeaderWidget({super.key, required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s8, AppSpacingTokens.s8, AppSpacingTokens.s8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
            ),
          ),
          IconButton(tooltip: TextConstants.actionClose, icon: AppIconWidget(NoxIcons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

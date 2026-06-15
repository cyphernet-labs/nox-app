import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Message input (5.2 §9.8): `surfaceContainer`, top divider, optional attachment
/// chip above the row. Attach + text + send; send active → `primary` (filled),
/// else `onSurface`@38%. Source: `NoxComposer`.
class AppComposerWidget extends StatelessWidget {
  const AppComposerWidget({super.key, this.value, this.attachment, this.sendActive = false, this.onAttach, this.onSend});

  final String? value;
  final Widget? attachment; // an AppFileChipWidget(removable: true)
  final bool sendActive;
  final VoidCallback? onAttach;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasValue = value != null && value!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachment != null)
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacingTokens.s12, AppSpacingTokens.s8, AppSpacingTokens.s12, 0),
              child: Align(alignment: Alignment.centerLeft, child: attachment),
            ),
          Padding(
            padding: EdgeInsets.all(AppSpacingTokens.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onAttach,
                  tooltip: TextConstants.tooltipAttachFile,
                  icon: AppIconWidget(NoxIcons.attachFile, color: colorScheme.onSurfaceVariant),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s4, vertical: AppSpacingTokens.s12),
                    child: Text(
                      hasValue ? value! : TextConstants.composerHint,
                      style: textTheme.bodyLarge?.copyWith(color: hasValue ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: sendActive ? onSend : null,
                  tooltip: TextConstants.tooltipSend,
                  icon: AppIconWidget(
                    NoxIcons.sendFill,
                    color: sendActive ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

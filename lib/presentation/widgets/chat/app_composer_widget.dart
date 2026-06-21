import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Message input (5.2 §9.8): `surfaceContainer`, top divider, an optional attachment
/// chip above the row. Attach + a growing multiline field (4–6 lines, then scrolls)
/// + send; send active → `primary` (filled), else `onSurface`@38%. Editable
/// (controller-driven); the owner recomputes [sendActive] on [onChanged].
/// Source: `NoxComposer`.
class AppComposerWidget extends StatelessWidget {
  const AppComposerWidget({
    super.key,
    required this.controller,
    this.focusNode,
    this.attachment,
    this.sendActive = false,
    this.onChanged,
    this.onAttach,
    this.onSend,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final Widget? attachment; // an AppFileChipWidget(removable: true)
  final bool sendActive;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onSend;

  static const int _maxLines = 6;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
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
                      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s4, vertical: AppSpacingTokens.s4),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: onChanged,
                        minLines: 1,
                        maxLines: _maxLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: TextConstants.composerHint,
                          hintStyle: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
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
      ),
    );
  }
}

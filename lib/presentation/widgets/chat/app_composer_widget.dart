import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Message input (5.2 §9.8): `surfaceContainer`, top divider, an optional attachment
/// chip above the row. Attach + a growing multiline field (1–6 lines, then scrolls)
/// + send. The send affordance is reactive: it watches [controller] (and the
/// [attachment] presence) via a [ValueListenableBuilder] so typing only rebuilds the
/// send button, not the owner's message list. Send is enabled when the field is
/// non-empty or an attachment is staged. Source: `NoxComposer`.
class AppComposerWidget extends StatelessWidget {
  const AppComposerWidget({super.key, required this.controller, this.focusNode, this.attachment, this.onAttach, this.onSend});

  final TextEditingController controller;
  final FocusNode? focusNode;
  final Widget? attachment; // an AppFileChipWidget(removable: true)
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
                    tooltip: context.l10n.tooltipAttachFile,
                    icon: AppIconWidget(NoxIcons.attachFile, color: colorScheme.onSurfaceVariant),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s4, vertical: AppSpacingTokens.s4),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: _maxLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: context.l10n.composerHint,
                          hintStyle: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final active = value.text.trim().isNotEmpty || attachment != null;
                      return IconButton(
                        onPressed: active ? onSend : null,
                        tooltip: context.l10n.tooltipSend,
                        icon: AppIconWidget(
                          NoxIcons.sendFill,
                          color: active ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: NoxOpacity.disabled),
                        ),
                      );
                    },
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

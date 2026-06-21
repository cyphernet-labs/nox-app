import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

// MessageStatus is the domain single source of truth; re-export so existing callers
// (gallery / bubble tests) keep importing it from this widget.
export 'package:nox_app/domain/model/chat/message_status.dart';

/// Message bubble (5.2): base radius `l`; the own bottom-right / other
/// bottom-left corner clips to `xs` (`NoxRadius.bubble`). Own = `primaryContainer`;
/// other = `surfaceContainerHigh`. Optional file chip inside. Max width 80%.
/// Source: `NoxMessageBubble`.
class AppMessageBubbleWidget extends StatelessWidget {
  const AppMessageBubbleWidget({
    super.key,
    required this.isOwn,
    this.text,
    required this.time,
    this.status = MessageStatus.none,
    this.file,
    this.isLast = false,
  });

  final bool isOwn;
  final String? text;
  final String time;
  final MessageStatus status;
  final Widget? file; // an optional AppFileChipWidget rendered inside
  final bool isLast;

  static const double _maxWidthFactor = 0.8;
  static const double _statusIconSize = 14;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final background = isOwn ? colorScheme.primaryContainer : colorScheme.surfaceContainerHigh;
    final foreground = isOwn ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    final meta = isOwn ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant;
    final statusColor = status == MessageStatus.error ? colorScheme.error : meta;
    final statusIcon = isOwn ? _statusIcon(status) : null; // null for non-own or MessageStatus.none
    final hasText = text != null && text!.isNotEmpty;
    final hasFileOnly = file != null && !hasText;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : AppSpacingTokens.s2),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * _maxWidthFactor),
        padding: hasFileOnly
            ? EdgeInsets.all(AppSpacingTokens.s8)
            : EdgeInsets.symmetric(horizontal: AppSpacingTokens.s12, vertical: AppSpacingTokens.s8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: NoxRadius.bubble(isOwn: isOwn),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (file != null)
              Padding(
                padding: EdgeInsets.only(bottom: hasText ? AppSpacingTokens.s8 : 0),
                child: file,
              ),
            if (hasText) Text(text!, style: textTheme.bodyLarge?.copyWith(color: foreground)),
            SizedBox(height: AppSpacingTokens.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: textTheme.labelSmall?.copyWith(color: meta)),
                if (statusIcon != null) ...[
                  SizedBox(width: AppSpacingTokens.s4),
                  AppIconWidget(statusIcon, size: _statusIconSize, color: statusColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

SvgGenImage? _statusIcon(MessageStatus status) => switch (status) {
  MessageStatus.pending => NoxIcons.schedule,
  MessageStatus.sent => NoxIcons.check,
  MessageStatus.error => NoxIcons.error,
  MessageStatus.none => null,
};

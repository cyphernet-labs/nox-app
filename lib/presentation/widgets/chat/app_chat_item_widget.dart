import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';

/// Chat row (5.1): avatar (subtle ring) + name + preview + time + unread badge.
/// Unread emphasis — name w600, preview `onSurface`, time `primary`, badge shown.
/// Badge hidden at 0, caps `99+`. Min height 72. Source: `NoxChatListItem`.
class AppChatItemWidget extends StatelessWidget {
  const AppChatItemWidget({super.key, required this.name, required this.preview, required this.time, this.unread = 0, this.onTap});

  final String name;
  final String preview;
  final String time;
  final int unread;
  final VoidCallback? onTap;

  static const double _minHeight = 72;
  static const double _avatarSize = 40;
  static const double _badgeSize = 20;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasUnread = unread > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: _minHeight),
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s12),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: colorScheme.onSurface.withValues(alpha: 0.06), spreadRadius: 2)],
              ),
              child: AppAvatarWidget(name: name, size: _avatarSize),
            ),
            SizedBox(width: AppSpacingTokens.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(color: hasUnread ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacingTokens.s8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: textTheme.labelSmall?.copyWith(color: hasUnread ? colorScheme.primary : colorScheme.onSurfaceVariant)),
                SizedBox(height: AppSpacingTokens.s6),
                if (hasUnread)
                  Container(
                    constraints: const BoxConstraints(minWidth: _badgeSize),
                    height: _badgeSize,
                    padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(NoxRadius.full)),
                    child: Text(unread > 99 ? '99+' : '$unread', style: textTheme.labelSmall?.copyWith(color: colorScheme.onPrimary)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

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

  static double get _minHeight => AppDimensionTokens.size.chatRowMinH;
  static double get _avatarSize => AppDimensionTokens.size.avatarSm;
  static double get _badgeSize => AppSpacingTokens.s20;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasUnread = unread > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: _minHeight),
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s12),
        child: Row(
          children: [
            AppRingedAvatarWidget(name: name, size: _avatarSize),
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
                  // Only when there IS one. Rendered unconditionally, an empty
                  // preview still took a line, so a chat with no messages was a
                  // two-line column with nothing on its second line - and the
                  // Row centres the column, which left the title sitting above
                  // the row's centre with blank space under it.
                  if (preview.isNotEmpty)
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
            // Right meta column reserves a min width (design: trailing column minWidth 44)
            // so the time/badge right-edge stays aligned across short and long timestamps.
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: AppSpacingTokens.s44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(time, style: textTheme.labelSmall?.copyWith(color: hasUnread ? colorScheme.primary : colorScheme.onSurfaceVariant)),
                  // The gap belongs to the badge. Without it the timestamp of an
                  // unread-free row was pushed up off the centre line by 6.
                  if (hasUnread) SizedBox(height: AppSpacingTokens.s6),
                  if (hasUnread)
                    Container(
                      constraints: BoxConstraints(minWidth: _badgeSize),
                      height: _badgeSize,
                      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(NoxRadius.full)),
                      child: Text(unread > 99 ? '99+' : '$unread', style: textTheme.labelSmall?.copyWith(color: colorScheme.onPrimary)),
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

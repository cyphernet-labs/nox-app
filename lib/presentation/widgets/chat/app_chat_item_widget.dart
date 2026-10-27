import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/chat_creation.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';

/// Chat row (5.1): avatar (subtle ring) + name + preview + time + unread badge.
/// Unread emphasis — name w600, preview `onSurface`, time `primary`, badge shown.
/// Badge hidden at 0, caps `99+`. Min height 72. Source: `NoxChatListItem`.
///
/// A chat that is not on the person's server yet ([creation], phase 041) says
/// so with the glyphs a message already uses for the same thing: a clock in
/// place of the time while it waits, the error glyph there - and the reason in
/// place of the preview, in the error colour - once the server refused it.
class AppChatItemWidget extends StatelessWidget {
  const AppChatItemWidget({
    super.key,
    required this.name,
    required this.preview,
    required this.time,
    this.unread = 0,
    this.creation,
    this.onTap,
  });

  final String name;
  final String preview;
  final String time;
  final int unread;

  /// Null for a chat the server has.
  final ChatCreation? creation;
  final VoidCallback? onTap;

  static double get _minHeight => AppDimensionTokens.size.chatRowMinH;
  static double get _avatarSize => AppDimensionTokens.size.avatarSm;
  static double get _badgeSize => AppSpacingTokens.s20;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasUnread = unread > 0;
    final refusal = switch (creation) {
      ChatCreation.nameTaken => context.l10n.chatCreationNameTaken,
      ChatCreation.failed => context.l10n.chatCreationFailed,
      ChatCreation.pending || null => null,
    };
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
                  if (refusal != null)
                    Text(
                      refusal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                    )
                  else if (preview.isNotEmpty)
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
                  switch (creation) {
                    null => Text(
                      time,
                      style: textTheme.labelSmall?.copyWith(color: hasUnread ? colorScheme.primary : colorScheme.onSurfaceVariant),
                    ),
                    ChatCreation.pending => Semantics(
                      label: context.l10n.chatCreationPending,
                      child: AppIconWidget(NoxIcons.schedule, size: AppDimensionTokens.icon.sm, color: colorScheme.onSurfaceVariant),
                    ),
                    // Said in words on the line beside it; announcing the glyph
                    // as well would read the same refusal twice.
                    ChatCreation.nameTaken || ChatCreation.failed => ExcludeSemantics(
                      child: AppIconWidget(NoxIcons.error, size: AppDimensionTokens.icon.sm, color: colorScheme.error),
                    ),
                  },
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

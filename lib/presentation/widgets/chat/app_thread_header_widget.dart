import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Persistent thread header for the DESKTOP thread pane (5.2 in the 5.1 list-detail).
/// Reconciled to the NOX model: avatar + chat name (tap → chat card) + an info action
/// (→ chat card drawer). No members / per-chat search / folder (open shared space;
/// those corpus affordances are out of scope this iteration). Mobile uses the AppBar
/// instead, so this widget is desktop-only.
class AppThreadHeaderWidget extends StatelessWidget {
  const AppThreadHeaderWidget({super.key, required this.chat, required this.onInfo});

  final ChatModel chat;
  final VoidCallback onInfo;

  static double get _avatarSize => AppDimensionTokens.size.avatarXs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s12, vertical: AppSpacingTokens.s8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onInfo,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacingTokens.s4),
                      child: Row(
                        children: [
                          AppAvatarWidget(name: chat.name, size: _avatarSize),
                          SizedBox(width: AppSpacingTokens.s12),
                          Expanded(
                            child: Text(
                              chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onInfo,
                  tooltip: TextConstants.tooltipChatInfo,
                  icon: AppIconWidget(NoxIcons.folderOpen, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Divider(height: AppDimensionTokens.border.hairline),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_hairline_divider_widget.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';

/// Persistent thread header for the DESKTOP thread pane (5.2 in the 5.1 list-detail).
/// Reconciled to the NOX model: avatar + chat name (tap → chat card) + an info action
/// (→ chat card drawer) plus a DISABLED invite action - the seam a relay will
/// attach to. No per-chat search or folder (out of scope this iteration). Mobile
/// uses the AppBar instead, so this widget is desktop-only.
class AppThreadHeaderWidget extends StatelessWidget {
  const AppThreadHeaderWidget({super.key, required this.chat, required this.onInfo});

  final ChatModel chat;
  final VoidCallback onInfo;

  // Design (ThreadHeader): a ringed avatar at avatarSm (40), not the plain avatarXs.
  static double get _avatarSize => AppDimensionTokens.size.avatarSm;

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
                          AppRingedAvatarWidget(name: chat.name, size: _avatarSize),
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
                // The seam a relay will attach to. Disabled, with the tooltip
                // saying why: an action that is missing answers "how do I add
                // somebody?" with silence, and one that raises an error answers
                // it with a fault. The glyph is the kit's own `add` rather than
                // a person-add invented here - a dedicated one belongs to the
                // design corpus, and this control is not final enough to earn it.
                IconButton(
                  onPressed: null,
                  tooltip: '${context.l10n.chatInvitePerson} — ${context.l10n.chatInviteLater}',
                  icon: AppIconWidget(NoxIcons.add, color: colorScheme.onSurfaceVariant),
                ),
                IconButton(
                  onPressed: onInfo,
                  tooltip: context.l10n.tooltipChatInfo,
                  icon: AppIconWidget(NoxIcons.folderOpen, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const AppHairlineDividerWidget(),
        ],
      ),
    );
  }
}

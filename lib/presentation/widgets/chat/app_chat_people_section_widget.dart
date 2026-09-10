import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app/session_model.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';

/// The people of a chat, and the seam a relay will attach to (5.4).
///
/// Today it lists exactly one person — whoever this machine belongs to — because
/// there is nobody else it could list: a client backend serves one human being,
/// and talking to anybody else goes through a relay that does not exist yet.
///
/// The invite control is therefore DISABLED rather than absent. A missing
/// control answers "how do I add someone?" with silence; a disabled one with a
/// caption answers it with "later", which is the truth. It raises no error when
/// tapped either — an error would read as a fault rather than as unfinished
/// work.
///
/// Deliberately NOT a roster. Nothing is stored, no participants field appears
/// on the chat, and no membership is implied: the section renders what the
/// session already knows. When the relay lands this is where a real roster
/// goes, and its layout is already settled on both widths.
class AppChatPeopleSectionWidget extends StatefulWidget {
  const AppChatPeopleSectionWidget({super.key});

  @override
  State<AppChatPeopleSectionWidget> createState() => _AppChatPeopleSectionWidgetState();
}

class _AppChatPeopleSectionWidgetState extends State<AppChatPeopleSectionWidget> {
  /// Started once, in initState, rather than in build.
  ///
  /// `readSession` goes through the platform keychain, so it is a real round
  /// trip; a future built in `build` would be restarted by every inherited
  /// change — a theme switch, a locale change — and each restart re-reads the
  /// keychain for a value that cannot have moved.
  late final Future<SessionModel?> _session = sessionRepository.readSession().then((result) => result.data);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s0, AppSpacingTokens.s16, AppSpacingTokens.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.chatPeopleTitle, style: textTheme.titleMedium),
          SizedBox(height: AppSpacingTokens.s8),
          // Read rather than watched. The card is opened fresh each time and
          // closes with the answer still on screen, so a rename landing while
          // it is open has nowhere to be wrong — and a second live label
          // subscription would collide with the shell's, which is single-listen
          // by construction.
          FutureBuilder<SessionModel?>(
            future: _session,
            builder: (context, snapshot) {
              // Nothing until the answer is in. `resolveIdentity(null)` returns
              // the fallback name and its own hash-picked avatar colour, so
              // rendering while the read is pending shows a person who is not
              // there — a stranger's name and colour, for as many frames as the
              // keychain takes.
              if (snapshot.connectionState != ConnectionState.done) {
                return SizedBox(height: AppDimensionTokens.size.avatarXs);
              }
              final identity = resolveIdentity(snapshot.data);
              return Row(
                children: [
                  AppRingedAvatarWidget(name: identity.label, size: AppDimensionTokens.size.avatarXs),
                  SizedBox(width: AppSpacingTokens.s12),
                  Expanded(
                    child: Text(
                      identity.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: AppSpacingTokens.s12),
          // Null onPressed, not an empty callback: a control that looks live and
          // does nothing is worse than one that says it is not ready.
          FilledButton(onPressed: null, child: Text(context.l10n.chatInvitePerson)),
          SizedBox(height: AppSpacingTokens.s4),
          Text(
            context.l10n.chatInviteLater,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

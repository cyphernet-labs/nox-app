import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/chat/app_card_section_header_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';

/// The people of a chat, and the seam a relay will attach to (5.4).
///
/// Lists exactly one person — whoever this machine belongs to — because there is
/// nobody else it could list: a client backend serves one human being, and
/// talking to anybody else goes through a relay that does not exist yet.
///
/// Deliberately NOT a roster. Nothing is stored, no participants field appears
/// on the chat, and no membership is implied. When the relay lands this is where
/// a real roster goes, and its layout is already settled on both widths.
///
/// Purely presentational: [personLabel] arrives resolved from `ChatCardBloc`.
/// The widget used to read the session itself, which paid a keychain round trip
/// on every card open — for a value the page's own BLoC is already positioned to
/// hold — and flashed the fallback name while that read was in flight.
class AppChatPeopleSectionWidget extends StatelessWidget {
  const AppChatPeopleSectionWidget({required this.personLabel, super.key});

  final String personLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The card's other section uses the same widget, so the two headings of
        // one screen cannot drift apart.
        AppCardSectionHeaderWidget(title: context.l10n.chatPeopleTitle),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s0, AppSpacingTokens.s16, AppSpacingTokens.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // A PERSON, so the account initials — not the chat-row ones.
                  // The two rules differ on purpose (nox_brand.dart), and the
                  // wrong one shows the same human as "US" here and "U" in the
                  // shell avatar two taps away.
                  AppRingedAvatarWidget(
                    name: personLabel,
                    initials: noxAccountInitials(personLabel),
                    size: AppDimensionTokens.size.avatarXs,
                  ),
                  SizedBox(width: AppSpacingTokens.s12),
                  Expanded(
                    child: Text(
                      personLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSpacingTokens.s12),
              // Null onPressed, not an empty callback: a control that looks live
              // and does nothing is worse than one that says it is not ready.
              FilledButton(onPressed: null, child: Text(context.l10n.chatInvitePerson)),
              SizedBox(height: AppSpacingTokens.s4),
              // The caption lives HERE and not in the header's tooltip: the spec
              // gives it this one home, because a header has no room for it.
              Text(
                context.l10n.chatInviteLater,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

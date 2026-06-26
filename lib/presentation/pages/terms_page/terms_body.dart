import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/settings/app_version_text_widget.dart';

/// 7.6 Terms content — bundled legal copy (placeholder until legal text lands) as
/// titled scrollable sections + a version footer. No Scaffold/AppBar so it embeds
/// in both the mobile leaf chrome (TermsPage) and the desktop Settings list-detail
/// pane (7.1).
class TermsBody extends StatelessWidget {
  const TermsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s8, AppSpacingTokens.s16, AppSpacingTokens.s16),
      children: [
        _section(context, TextConstants.termsTermsHeading, TextConstants.termsTermsBody),
        SizedBox(height: AppSpacingTokens.s24),
        _section(context, TextConstants.termsPrivacyHeading, TextConstants.termsPrivacyBody),
        SizedBox(height: AppSpacingTokens.s32),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${TextConstants.versionLabel} ', style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              AppVersionTextWidget(showBuild: false, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String heading, String body) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
        SizedBox(height: AppSpacingTokens.s8),
        Text(body, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

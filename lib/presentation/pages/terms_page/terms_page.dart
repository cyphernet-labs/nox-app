import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/widgets/settings/app_version_text_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.6 Terms — read-only bundled legal copy (placeholder until legal text lands) as
/// titled scrollable sections, with an app-version footer. No acceptance flow. No
/// own BLoC (UI-first exception, blueprint 05 §5.1).
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const TermsPage(),
    settings: const RouteSettings(name: '/settings/terms'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(title: TextConstants.settingsTermsTitle, actions: const [AppThemeToggle()], body: const _TermsBody());
  }
}

/// Verbatim Terms content — no Scaffold/AppBar so it embeds in both mobile and
/// desktop chrome.
class _TermsBody extends StatelessWidget {
  const _TermsBody();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
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

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_nav_row_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_version_text_widget.dart';

/// 7.7 About content — one settings row: `Version` with the version and build on
/// the right, informational, going nowhere (the corpus's `SettingsNavRow` with a
/// trailing value). No Scaffold/AppBar so it embeds in both the mobile leaf chrome
/// (AboutPage) and the desktop Settings list-detail pane (7.1).
class AboutBody extends StatelessWidget {
  const AboutBody({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.only(top: AppSpacingTokens.s4),
      children: [
        AppSettingsNavRowWidget(
          title: context.l10n.versionLabel,
          icon: NoxIcons.info,
          onTap: null,
          value: AppVersionTextWidget(style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/settings/app_version_text_widget.dart';

/// 7.7 About content — app version + build number only. No Scaffold/AppBar so it
/// embeds in both the mobile leaf chrome (AboutPage) and the desktop Settings
/// list-detail pane (7.1).
class AboutBody extends StatelessWidget {
  const AboutBody({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        ListTile(
          title: Text(TextConstants.versionLabel),
          subtitle: AppVersionTextWidget(style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

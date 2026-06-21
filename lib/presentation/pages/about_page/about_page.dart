import 'package:flutter/material.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/pages/about_page/about_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.7 About — only the app version + build number. No licenses, copyright, website
/// or credits. No own BLoC (UI-first exception, blueprint 05 §5.1). Content lives
/// in [AboutBody] so it can also fill the desktop Settings list-detail pane (7.1).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const AboutPage(),
    settings: const RouteSettings(name: '/settings/about'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(title: TextConstants.settingsAboutTitle, actions: const [AppThemeToggle()], body: const AboutBody());
  }
}

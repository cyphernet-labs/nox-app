import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/language_page/language_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.4 Language — choose the UI language (System / English / Українська) as plain
/// radio rows. Selecting a language persists it (LocaleController + shared_preferences)
/// and live-re-renders the whole app via `MaterialApp.locale` + AppLocalizations (012).
/// No own BLoC (UI-first exception, blueprint 05 §5.1).
/// Content lives in [LanguageBody] so it can also fill the desktop list-detail pane.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const LanguagePage(),
    settings: const RouteSettings(name: '/settings/language'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(title: context.l10n.settingsLanguageTitle, body: const LanguageBody());
  }
}

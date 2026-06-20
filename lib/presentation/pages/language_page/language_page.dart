import 'package:flutter/material.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.4 Language — choose the UI language (System / English / Українська) as plain
/// radio rows. Selection is session-local; true app-wide live re-render needs the
/// l10n layer (backend phase). No own BLoC (UI-first exception, blueprint 05 §5.1).
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const LanguagePage(),
    settings: const RouteSettings(name: '/settings/language'),
  );

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  // TODO(backend): promote to an app-level LocaleController + l10n live re-render.
  AppLanguage _selected = AppLanguage.system;

  String _label(AppLanguage language) => switch (language) {
    AppLanguage.system => TextConstants.languageSystem,
    AppLanguage.english => TextConstants.languageEnglish,
    AppLanguage.ukrainian => TextConstants.languageUkrainian,
  };

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(
      title: TextConstants.settingsLanguageTitle,
      actions: const [AppThemeToggle()],
      body: RadioGroup<AppLanguage>(
        groupValue: _selected,
        onChanged: (value) => setState(() => _selected = value ?? _selected),
        child: ListView(
          children: [for (final language in AppLanguage.values) RadioListTile<AppLanguage>(value: language, title: Text(_label(language)))],
        ),
      ),
    );
  }
}

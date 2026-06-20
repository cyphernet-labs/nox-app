import 'package:flutter/material.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/text_constants.dart';

/// 7.4 Language content — System / English / Українська radio rows (session-local).
/// No Scaffold/AppBar so it embeds in both the mobile leaf chrome (LanguagePage)
/// and the desktop Settings list-detail pane (7.1). No own BLoC (UI-first exception).
class LanguageBody extends StatefulWidget {
  const LanguageBody({super.key});

  @override
  State<LanguageBody> createState() => _LanguageBodyState();
}

class _LanguageBodyState extends State<LanguageBody> {
  // TODO(backend): promote to an app-level LocaleController + l10n live re-render.
  AppLanguage _selected = AppLanguage.system;

  String _label(AppLanguage language) => switch (language) {
    AppLanguage.system => TextConstants.languageSystem,
    AppLanguage.english => TextConstants.languageEnglish,
    AppLanguage.ukrainian => TextConstants.languageUkrainian,
  };

  @override
  Widget build(BuildContext context) {
    return RadioGroup<AppLanguage>(
      groupValue: _selected,
      onChanged: (value) => setState(() => _selected = value ?? _selected),
      child: ListView(
        children: [for (final language in AppLanguage.values) RadioListTile<AppLanguage>(value: language, title: Text(_label(language)))],
      ),
    );
  }
}

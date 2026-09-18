import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/locale_controller.dart';
import 'package:nox_app/presentation/widgets/settings/app_select_option_widget.dart';

/// 7.4 Language content — System / English / Українська as single-select option
/// cards, the same [AppSelectOptionWidget] Appearance 7.3 uses. The screen spec
/// asks for exactly that ("pattern as in 7.3"); until now this screen was the one
/// place in Settings still on raw `RadioListTile`s, with 40dp national flags that
/// clipped against the rows they sat in and a hand-mixed 10%-alpha selection tint
/// instead of a Material token.
///
/// No Scaffold/AppBar so it embeds in both the mobile leaf chrome (LanguagePage)
/// and the desktop Settings list-detail pane (7.1). No own BLoC (UI-first exception).
class LanguageBody extends StatefulWidget {
  const LanguageBody({super.key});

  @override
  State<LanguageBody> createState() => _LanguageBodyState();
}

class _LanguageBodyState extends State<LanguageBody> {
  AppLanguage _selected = LocaleController.instance.language.value;

  String _label(BuildContext context, AppLanguage language) => switch (language) {
    AppLanguage.system => context.l10n.languageSystem,
    AppLanguage.english => context.l10n.languageEnglish,
    AppLanguage.ukrainian => context.l10n.languageUkrainian,
  };

  void _select(AppLanguage language) {
    setState(() => _selected = language);
    LocaleController.instance.set(language);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      children: [
        for (final language in AppLanguage.values)
          Padding(
            padding: EdgeInsets.only(bottom: AppSpacingTokens.s12),
            child: AppSelectOptionWidget(label: _label(context, language), selected: _selected == language, onTap: () => _select(language)),
          ),
      ],
    );
  }
}

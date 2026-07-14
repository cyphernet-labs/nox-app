import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/locale_controller.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';

/// 7.4 Language content — System / English / Українська radio rows inside a settings
/// group, each with a leading flag/glyph (smartphone chip / UK flag / UA flag) and a
/// `primary`-tinted selected row (session-local). No Scaffold/AppBar so it embeds in
/// both the mobile leaf chrome (LanguagePage) and the desktop Settings list-detail
/// pane (7.1). No own BLoC (UI-first exception).
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

  /// 40dp round leading: a smartphone chip for System, the country flag otherwise.
  Widget _leading(BuildContext context, AppLanguage language) {
    final size = AppDimensionTokens.size.avatarSm;
    switch (language) {
      case AppLanguage.system:
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.secondaryContainer),
          child: AppIconWidget(NoxIcons.smartphone, size: AppDimensionTokens.icon.base, color: colorScheme.onSecondaryContainer),
        );
      case AppLanguage.english:
        return Assets.svg.flags.gb.svg(width: size, height: size);
      case AppLanguage.ukrainian:
        return Assets.svg.flags.ua.svg(width: size, height: size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RadioGroup<AppLanguage>(
      groupValue: _selected,
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selected = value);
        LocaleController.instance.set(value);
      },
      child: ListView(
        children: [
          AppSettingsGroupWidget(
            children: [
              for (final language in AppLanguage.values)
                RadioListTile<AppLanguage>(
                  value: language,
                  title: Text(_label(context, language)),
                  secondary: _leading(context, language),
                  controlAffinity: ListTileControlAffinity.trailing,
                  selected: _selected == language,
                  selectedTileColor: colorScheme.primary.withValues(alpha: 0.1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

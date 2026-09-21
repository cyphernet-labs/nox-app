import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/app_language.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/locale_controller.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_select_option_widget.dart';

/// 7.4 Language content — System / English / Українська as single-select option
/// cards, the same [AppSelectOptionWidget] Appearance 7.3 uses, each with a
/// [_LanguagePreview] thumbnail in the same geometry. The screen spec asks for
/// exactly that ("pattern as in 7.3"); until now this screen was the one place in
/// Settings still on raw `RadioListTile`s, with 40dp circular flags that clipped
/// against the rows they sat in and a hand-mixed 10%-alpha selection tint instead
/// of a Material token.
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
            child: AppSelectOptionWidget(
              label: _label(context, language),
              preview: _LanguagePreview(language: language),
              selected: _selected == language,
              onTap: () => _select(language),
            ),
          ),
      ],
    );
  }
}

/// Leading thumbnail for one language option, in the geometry Appearance 7.3 gives
/// its theme previews - the same tile, hairline border and radius - so the two
/// screens read as one control with different contents inside it.
///
/// A flag for each language, and for `System` the thing it actually follows: the
/// device. There is no flag for "whatever the OS is set to", and a half-of-each
/// one would claim the app knows which half it will get.
///
/// The flag assets were circle-masked icons, which is why they used to sit in a
/// 40dp circle and clip. The mask is gone; the artwork under it was always drawn
/// on a full square.
class _LanguagePreview extends StatelessWidget {
  const _LanguagePreview({required this.language});

  final AppLanguage language;

  // 7.3's tile is 96x76 because its card carries a label AND a caption. This one
  // has a single word beside it, so the same tile there is an oversized one here:
  // the geometry is shared, the proportion answers to the content.
  static double get _width => AppSpacingTokens.s64;
  static double get _height => AppSpacingTokens.s48;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppDimensionTokens.radius.sm);
    final Widget content = switch (language) {
      AppLanguage.system => ColoredBox(
        color: colorScheme.secondaryContainer,
        child: Center(
          child: AppIconWidget(NoxIcons.smartphone, size: AppDimensionTokens.icon.lg, color: colorScheme.onSecondaryContainer),
        ),
      ),
      AppLanguage.english => Assets.svg.flags.gb.svg(fit: BoxFit.cover),
      AppLanguage.ukrainian => Assets.svg.flags.ua.svg(fit: BoxFit.cover),
    };
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: colorScheme.outlineVariant, width: AppDimensionTokens.border.hairline),
      ),
      child: ClipRRect(borderRadius: radius, child: content),
    );
  }
}

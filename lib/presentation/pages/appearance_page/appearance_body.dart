import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';

/// 7.3 Appearance content — System / Light / Dark theme cards applied app-wide via
/// the existing [AppRootBloc]. No Scaffold/AppBar so it embeds in both the mobile
/// leaf chrome (AppearancePage) and the desktop Settings list-detail pane (7.1).
/// Requires an [AppRootBloc] ancestor (provided app-wide by AppRoot).
class AppearanceBody extends StatelessWidget {
  const AppearanceBody({super.key});

  static const List<(ThemeMode, String)> _options = [
    (ThemeMode.system, TextConstants.themeSystem),
    (ThemeMode.light, TextConstants.themeLight),
    (ThemeMode.dark, TextConstants.themeDark),
  ];

  @override
  Widget build(BuildContext context) {
    final current = context.watch<AppRootBloc>().state.themeMode;
    return ListView(
      padding: EdgeInsets.all(AppSpacingTokens.s16),
      children: [
        for (final (mode, label) in _options)
          Padding(
            padding: EdgeInsets.only(bottom: AppSpacingTokens.s12),
            child: AppThemeOptionWidget(
              label: label,
              preview: _ThemePreview(mode: mode),
              selected: current == mode,
              onTap: () => context.read<AppRootBloc>().add(AppRootEvent.setTheme(themeMode: mode)),
            ),
          ),
      ],
    );
  }
}

/// Small theme swatch (brand-token colors, theme-independent so each option reads
/// the same regardless of the current theme).
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final ThemeMode mode;

  static const double _width = 48;
  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(NoxRadius.s);
    final border = Border.all(color: Theme.of(context).colorScheme.outlineVariant);
    final light = ColoredBox(color: noxLightScheme.surface);
    final dark = ColoredBox(color: noxDarkScheme.surface);
    Widget fill;
    switch (mode) {
      case ThemeMode.light:
        fill = light;
      case ThemeMode.dark:
        fill = dark;
      case ThemeMode.system:
        fill = Row(
          children: [
            Expanded(child: light),
            Expanded(child: dark),
          ],
        );
    }
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(borderRadius: radius, border: border),
      child: ClipRRect(borderRadius: radius, child: fill),
    );
  }
}

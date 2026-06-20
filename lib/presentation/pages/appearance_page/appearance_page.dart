import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_color_scheme.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';
import 'package:nox_app/presentation/widgets/settings/app_theme_option_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.3 Appearance — pick the theme (System / Light / Dark). Selection is applied
/// app-wide immediately via the existing [AppRootBloc] (the live feature). No own
/// BLoC (UI-first exception, blueprint 05 §5.1).
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const AppearancePage(),
    settings: const RouteSettings(name: '/settings/appearance'),
  );

  static const List<(ThemeMode, String)> _options = [
    (ThemeMode.system, TextConstants.themeSystem),
    (ThemeMode.light, TextConstants.themeLight),
    (ThemeMode.dark, TextConstants.themeDark),
  ];

  @override
  Widget build(BuildContext context) {
    final current = context.watch<AppRootBloc>().state.themeMode;
    return AppDetailScaffoldWidget(
      title: TextConstants.settingsAppearanceTitle,
      body: ListView(
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
      ),
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
    // Swatches use the actual generated theme surfaces (theme-independent) so each
    // option reads as a true thumbnail of that theme.
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

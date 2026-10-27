import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';

/// App-bar control that flips the app theme via [AppRootBloc]. Text-based (no
/// Material Icons font) so it renders identically in the app and in goldens, and
/// stays consistent with the kit's SVG-only icon discipline. Requires an
/// [AppRootBloc] ancestor (provided app-wide by `AppRoot`).
class AppThemeToggle extends StatelessWidget {
  const AppThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: context.l10n.tooltipToggleTheme,
      child: TextButton(
        onPressed: () => context.read<AppRootBloc>().add(AppRootEvent.setTheme(themeMode: isDark ? ThemeMode.light : ThemeMode.dark)),
        child: Text(isDark ? context.l10n.themeLight : context.l10n.themeDark),
      ),
    );
  }
}

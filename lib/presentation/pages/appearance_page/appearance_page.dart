import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/appearance_page/appearance_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.3 Appearance — pick the theme (System / Light / Dark). Selection is applied
/// app-wide immediately via the existing [AppRootBloc] (the live feature). No own
/// BLoC (UI-first exception, blueprint 05 §5.1). Content lives in [AppearanceBody]
/// so it can also fill the desktop Settings list-detail pane (7.1).
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const AppearancePage(),
    settings: const RouteSettings(name: '/settings/appearance'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(title: context.l10n.settingsAppearanceTitle, body: const AppearanceBody());
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/terms_page/terms_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.6 Terms — read-only bundled legal copy (placeholder until legal text lands) as
/// titled scrollable sections, with an app-version footer. No acceptance flow. No
/// own BLoC (UI-first exception, blueprint 05 §5.1). Content lives in [TermsBody]
/// so it can also fill the desktop Settings list-detail pane (7.1).
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const TermsPage(),
    settings: const RouteSettings(name: '/settings/terms'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(title: TextConstants.settingsTermsTitle, body: const TermsBody());
  }
}

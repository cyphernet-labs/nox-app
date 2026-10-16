import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/connection_page/bloc/connection_settings_bloc.dart';
import 'package:nox_app/presentation/pages/connection_page/connection_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// Settings > Connection (phase 045). The body is split out so the same
/// content fills the desktop Settings detail pane, exactly like every other
/// settings leaf.
class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key, this.initialState});

  @visibleForTesting
  final ConnectionSettingsState? initialState;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const ConnectionPage(),
    settings: const RouteSettings(name: '/settings/connection'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(
      title: context.l10n.settingsConnectionTitle,
      body: ConnectionBody(initialState: initialState),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';
import 'package:nox_app/presentation/pages/devices_page/devices_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.3 Devices. The body is split out so the same content fills the desktop
/// Settings detail pane, exactly like every other settings leaf.
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, this.initialState});

  @visibleForTesting
  final DevicesState? initialState;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const DevicesPage(),
    settings: const RouteSettings(name: '/settings/devices'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(
      title: context.l10n.settingsDevicesTitle,
      body: DevicesBody(initialState: initialState),
    );
  }
}

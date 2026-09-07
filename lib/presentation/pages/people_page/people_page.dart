import 'package:flutter/material.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/pages/people_page/bloc/people_bloc.dart';
import 'package:nox_app/presentation/pages/people_page/people_body.dart';
import 'package:nox_app/presentation/widgets/shell/app_detail_scaffold_widget.dart';

/// 7.4 People. The body is split out so the same content fills the desktop
/// Settings detail pane, exactly like every other settings leaf.
class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key, this.initialState});

  @visibleForTesting
  final PeopleState? initialState;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const PeoplePage(),
    settings: const RouteSettings(name: '/settings/people'),
  );

  @override
  Widget build(BuildContext context) {
    return AppDetailScaffoldWidget(
      title: context.l10n.settingsPeopleTitle,
      body: PeopleBody(initialState: initialState),
    );
  }
}

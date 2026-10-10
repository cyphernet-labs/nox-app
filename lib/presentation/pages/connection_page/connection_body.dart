import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/helpers/connection_problem_text.dart';
import 'package:nox_app/presentation/pages/connection_page/bloc/connection_settings_bloc.dart';
import 'package:nox_app/presentation/widgets/connection/app_connection_fields_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_group_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_settings_switch_row_widget.dart';

/// Settings > Connection (phase 045), chrome-less so the same body fills the
/// desktop Settings detail pane (7.1) - the split every settings leaf uses.
///
/// From the top: a line saying why there is no connection, while there is
/// none; the server address and the onion address with `Save`, which applies
/// them; and `Use Tor` with its caption, applied the moment it is switched.
class ConnectionBody extends StatefulWidget {
  const ConnectionBody({super.key, this.initialState});

  /// Seeds a state a golden could not otherwise reach - a connection that is
  /// down needs a server. Test-only; the real flow always reads.
  @visibleForTesting
  final ConnectionSettingsState? initialState;

  @override
  State<ConnectionBody> createState() => _ConnectionBodyState();
}

class _ConnectionBodyState extends State<ConnectionBody> {
  late final ConnectionSettingsBloc _bloc;
  final TextEditingController _server = TextEditingController();
  final TextEditingController _onion = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bloc = ConnectionSettingsBloc();
    final seeded = widget.initialState;
    if (seeded == null) {
      _bloc.add(const ConnectionSettingsEvent.initialize());
    } else {
      _server.text = seeded.serverAddress;
      _onion.text = seeded.onionAddress;
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _onion.dispose();
    _bloc.close();
    super.dispose();
  }

  /// Puts what the bloc holds into a field the person is not typing in -
  /// the first read, a server that stated new addresses, a Save.
  void _follow(ConnectionSettingsState state) {
    if (_server.text != state.serverAddress) _server.value = TextEditingValue(text: state.serverAddress);
    if (_onion.text != state.onionAddress) _onion.value = TextEditingValue(text: state.onionAddress);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConnectionSettingsBloc, ConnectionSettingsState>(
      bloc: _bloc,
      // Only what came from outside the fields - the first read, the server
      // stating new addresses, a Save - moves them; the person's own typing
      // is already in them.
      listenWhen: (previous, current) =>
          previous.loading != current.loading ||
          previous.appliedServerAddress != current.appliedServerAddress ||
          previous.appliedOnionAddress != current.appliedOnionAddress,
      listener: (context, state) => _follow(state),
      builder: (context, live) {
        final state = widget.initialState ?? live;
        if (state.loading) return const Center(child: CircularProgressIndicator());
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final line = state.problem?.text(context.l10n) ?? (state.offline ? context.l10n.noConnection : null);
        return ListView(
          // Vertical only: the group card sets its own screen inset, and
          // everything else is inset explicitly, as on Devices.
          padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s16),
          children: [
            if (line != null) ...[
              _inset(
                Semantics(
                  liveRegion: true,
                  child: Text(line, style: textTheme.bodyMedium?.copyWith(color: colorScheme.error)),
                ),
              ),
              SizedBox(height: AppSpacingTokens.s16),
            ],
            _inset(
              AppConnectionFieldsWidget(
                serverController: _server,
                onionController: _onion,
                onServerChanged: (value) => _bloc.add(ConnectionSettingsEvent.serverAddressChanged(value)),
                onOnionChanged: (value) => _bloc.add(ConnectionSettingsEvent.onionAddressChanged(value)),
                serverError: state.showServerAddressError ? context.l10n.connectInvalidServerAddress : null,
                onionError: state.showOnionAddressError ? context.l10n.connectionProblemInvalidOnion : null,
                enabled: !state.saving,
              ),
            ),
            SizedBox(height: AppSpacingTokens.s16),
            _inset(
              FilledButton(
                onPressed: state.canSave ? () => _bloc.add(const ConnectionSettingsEvent.saveRequested()) : null,
                child: Text(context.l10n.actionSave),
              ),
            ),
            if (state.saveFailed) ...[
              SizedBox(height: AppSpacingTokens.s8),
              _inset(
                Text(
                  context.l10n.settingsSaveError,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                ),
              ),
            ],
            SizedBox(height: AppSpacingTokens.s24),
            AppSettingsGroupWidget(
              children: [
                AppSettingsSwitchRowWidget(
                  leadingIcon: NoxIcons.lan,
                  title: context.l10n.connectUseTor,
                  supportingText: context.l10n.connectUseTorCaption,
                  value: state.useTor,
                  onChanged: (value) => _bloc.add(ConnectionSettingsEvent.useTorChanged(value)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _inset(Widget child) => Padding(
    padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16),
    child: child,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/helpers/connection_problem_text.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/connect_page/bloc/connect_bloc.dart';
import 'package:nox_app/presentation/widgets/connection/app_connection_fields_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboarding_scaffold_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_primary_button_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// The connection screen (phase 045, FR-013): every pairing link - pasted,
/// scanned with the camera, or read from a QR image - comes here before it
/// pairs. The server address and the onion address stand filled in from the
/// link and can be changed; the server key the link names is never shown and
/// never editable. `Use Tor` starts off, its caption says when Tor is used,
/// and `Connect` pairs - directly first, then through Tor if it was ticked.
/// Why an attempt failed is said under `Connect`; an onion address that is
/// not one, at its own field.
///
/// The same layout as the sign-in screen it is pushed over: on a phone the
/// wordmark app bar - with a back arrow - over the fields and a pinned
/// `Connect`; on a wide window the onboarding card under the window title
/// bar, with `Cancel` the way back. Owns [ConnectBloc].
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.link, this.initialState});

  /// The pairing link, as it arrived.
  final String link;

  /// Seeds a state a golden could not otherwise reach - a failure needs a
  /// server. Test-only; the real flow never passes it.
  @visibleForTesting
  final ConnectState? initialState;

  static Route<void> route({required String link}) => MaterialPageRoute<void>(
    builder: (_) => ConnectPage(link: link),
    settings: const RouteSettings(name: '/onboarding/connect'),
  );

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends BaseStatePage<ConnectPage> {
  late final ConnectBloc _bloc;
  late final TextEditingController _server;
  late final TextEditingController _onion;

  @override
  void initState() {
    super.initState();
    _bloc = ConnectBloc(link: widget.link, initialState: widget.initialState);
    _server = TextEditingController(text: _bloc.state.serverAddress);
    _onion = TextEditingController(text: _bloc.state.onionAddress);
  }

  @override
  void dispose() {
    _server.dispose();
    _onion.dispose();
    _bloc.close();
    super.dispose();
  }

  void _connect() => _bloc.add(const ConnectEvent.connectRequested());

  void _back() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConnectBloc>.value(
      value: _bloc,
      child: BlocBuilder<ConnectBloc, ConnectState>(
        builder: (context, state) => PopScope(
          // Not while a pairing is under way: leaving it would let a second
          // link start a second pairing over the first, and whichever lost
          // would roll back the session the other had just stored.
          canPop: !state.isConnecting,
          child: AppOnboardingScaffoldWidget(
            subtitle: context.l10n.windowSubtitleSignIn,
            leading: IconButton(
              tooltip: context.l10n.tooltipBack,
              icon: AppIconWidget(NoxIcons.arrowBack),
              onPressed: state.isConnecting ? null : _back,
            ),
            field: _form(context, state),
            actions: _actions(context, state),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ConnectState state) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.connectTitle, textAlign: TextAlign.center, style: textTheme.titleLarge),
        SizedBox(height: AppSpacingTokens.s24),
        AppConnectionFieldsWidget(
          serverController: _server,
          onionController: _onion,
          onServerChanged: (value) => _bloc.add(ConnectEvent.serverAddressChanged(value)),
          onOnionChanged: (value) => _bloc.add(ConnectEvent.onionAddressChanged(value)),
          serverError: state.showServerAddressError ? context.l10n.connectInvalidServerAddress : null,
          onionError: state.showOnionAddressError ? context.l10n.connectionProblemInvalidOnion : null,
          enabled: !state.isConnecting,
        ),
        SizedBox(height: AppSpacingTokens.s8),
        CheckboxListTile(
          value: state.useTor,
          onChanged: state.isConnecting ? null : (value) => _bloc.add(ConnectEvent.useTorChanged(value ?? false)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.connectUseTor),
          subtitle: Text(context.l10n.connectUseTorCaption),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context, ConnectState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reason = _reason(context, state);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPrimaryButtonWidget(
          label: context.l10n.connectAction,
          onPressed: state.isConnecting ? null : _connect,
          loading: state.isConnecting,
        ),
        if (reason != null)
          Padding(
            padding: EdgeInsets.only(top: AppSpacingTokens.s12),
            // A live region: the reason can arrive while the attempt is still
            // under way, and assistive technology has to say it when it does.
            child: Semantics(
              liveRegion: true,
              child: Text(
                reason,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              ),
            ),
          ),
        SizedBox(height: AppSpacingTokens.s8),
        SizedBox(
          width: double.infinity,
          child: TextButton(onPressed: state.isConnecting ? null : _back, child: Text(context.l10n.actionCancel)),
        ),
      ],
    );
  }

  /// What is said under `Connect`. The token refusals are the sign-in
  /// screen's own sentences; an onion address that is not one is said at its
  /// field, not twice.
  String? _reason(BuildContext context, ConnectState state) {
    final l10n = context.l10n;
    final problem = state.problem == ConnectionProblem.invalidOnion ? null : state.problem;
    return switch (state.status) {
      ConnectStatus.linkExpired => l10n.loginLinkExpired,
      ConnectStatus.linkRejected => l10n.loginLinkRejected,
      ConnectStatus.failed when state.problem == ConnectionProblem.invalidOnion => null,
      ConnectStatus.failed => problem?.text(l10n) ?? l10n.loginNetworkError,
      ConnectStatus.connecting => problem?.text(l10n),
      ConnectStatus.idle => null,
    };
  }
}

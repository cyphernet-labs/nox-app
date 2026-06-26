import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_id_field_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// 2.1 Login / ID entry — the onboarding entry screen. Mono multi-line ID field
/// + `Paste` + `Sign in` (outcome via the mock dataset / debug selector) +
/// `Scan QR` (stubbed). Mobile: full-screen `AppBar` (wordmark + hairline).
/// Desktop: centered `AppOnboardCardWidget` under a window `TitleBar`. `demo: true`
/// (gallery) shows a dev outcome selector. Owns [LoginBloc].
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.demo = false});

  final bool demo;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const LoginPage(),
    settings: const RouteSettings(name: '/onboarding/login'),
  );

  /// Gallery entry: adds the dev sign-in-outcome selector.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const LoginPage(demo: true),
    settings: const RouteSettings(name: '/onboarding/login'),
  );

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends BaseStatePage<LoginPage> with WidgetsBindingObserver {
  late final LoginBloc _bloc;
  final TextEditingController _controller = TextEditingController();
  LoginOutcome _outcome = LoginOutcome.auto;

  @override
  void initState() {
    super.initState();
    _bloc = LoginBloc(demo: widget.demo);
    WidgetsBinding.instance.addObserver(this);
    _refreshClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _bloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check the clipboard on resume (the user may have copied an ID in another
    // app) so `Paste` reflects the current buffer rather than the init-time check.
    if (state == AppLifecycleState.resumed) _refreshClipboard();
  }

  Future<void> _refreshClipboard() async {
    final hasText = await Clipboard.hasStrings();
    if (mounted) _bloc.add(LoginEvent.clipboardChecked(hasText: hasText));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    _bloc.add(LoginEvent.idChanged(text));
  }

  void _submit() => _bloc.add(LoginEvent.signInRequested(outcome: _outcome));

  void _scanQr() {
    // TODO(backend): wire to the real QR scanner (2.2) — the QR-success auto-submit
    // flow is out of scope this phase (screens are fully standalone, FR-016).
    Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'QR scan (2.2)'));
  }

  void _onStatus(BuildContext context, LoginState state) {
    switch (state.status) {
      case LoginStatus.navNewId:
        Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Set username (2.3)'));
        _bloc.add(const LoginEvent.navigationHandled());
      case LoginStatus.navRegistered:
        Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Chats shell (4.1)'));
        _bloc.add(const LoginEvent.navigationHandled());
      case LoginStatus.navFatal:
        Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal()));
        _bloc.add(const LoginEvent.navigationHandled());
      case LoginStatus.idle:
      case LoginStatus.loading:
      case LoginStatus.errorFormat:
      case LoginStatus.errorNetwork:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginBloc>.value(
      value: _bloc,
      child: BlocConsumer<LoginBloc, LoginState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: _onStatus,
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= Constants.railBreakpoint;
              return wide ? _wide(context, state) : _narrow(context, state);
            },
          );
        },
      ),
    );
  }

  Widget _narrow(BuildContext context, LoginState state) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const AppWordmarkWidget(), bottom: const AppSplashHairlineWidget()),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s24, AppSpacingTokens.s16, 0),
                child: _idField(state),
              ),
            ),
            Padding(padding: EdgeInsets.all(AppSpacingTokens.s16), child: _actions(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _wide(BuildContext context, LoginState state) {
    return Scaffold(
      body: Column(
        children: [
          const AppWindowTitlebarWidget(title: TextConstants.onboardTitleSignIn),
          Expanded(
            child: AppOnboardCardWidget(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _idField(state),
                  SizedBox(height: AppSpacingTokens.s24),
                  _actions(context, state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _idField(LoginState state) {
    return AppIdFieldWidget(
      controller: _controller,
      canPaste: state.canPaste,
      onPaste: _paste,
      onChanged: (value) => _bloc.add(LoginEvent.idChanged(value)),
      errorText: state.errorText,
      enabled: !state.isLoading,
    );
  }

  Widget _actions(BuildContext context, LoginState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: state.canSubmit ? _submit : null,
            child: state.isLoading ? AppSpinnerWidget(size: 18, color: colorScheme.onPrimary) : const Text(TextConstants.loginSignIn),
          ),
        ),
        SizedBox(height: AppSpacingTokens.s8),
        SizedBox(
          width: double.infinity,
          child: TextButton(onPressed: state.isLoading ? null : _scanQr, child: const Text(TextConstants.loginScanQr)),
        ),
        if (kDebugMode && widget.demo) _OutcomeControl(value: _outcome, onChanged: (value) => setState(() => _outcome = value)),
      ],
    );
  }
}

/// Dev-only sign-in outcome selector (gallery preview). Inline English copy, like
/// the screens gallery / route placeholder.
class _OutcomeControl extends StatelessWidget {
  const _OutcomeControl({required this.value, required this.onChanged});

  final LoginOutcome value;
  final ValueChanged<LoginOutcome> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacingTokens.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Outcome:'),
          SizedBox(width: AppSpacingTokens.s8),
          DropdownButton<LoginOutcome>(
            value: value,
            onChanged: (selected) {
              if (selected != null) onChanged(selected);
            },
            items: const [
              DropdownMenuItem(value: LoginOutcome.auto, child: Text('auto')),
              DropdownMenuItem(value: LoginOutcome.newId, child: Text('new id')),
              DropdownMenuItem(value: LoginOutcome.registered, child: Text('registered')),
              DropdownMenuItem(value: LoginOutcome.errorFormat, child: Text('format error')),
              DropdownMenuItem(value: LoginOutcome.errorNetwork, child: Text('network error')),
              DropdownMenuItem(value: LoginOutcome.fatal, child: Text('fatal')),
            ],
          ),
        ],
      ),
    );
  }
}

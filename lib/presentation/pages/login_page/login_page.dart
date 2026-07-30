import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:nox_app/general/qr_image_sign_in_capability.dart';
import 'package:nox_app/general/qr_scanner_capability.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/pages/base/base_state_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/login_page/bloc/login_bloc.dart';
import 'package:nox_app/presentation/pages/set_username_page/set_username_page.dart';
import 'package:nox_app/presentation/widgets/shell/tab_bar_shell_widget.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/qr_scan_page.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_id_field_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboarding_scaffold_widget.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_primary_button_widget.dart';

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

  /// In-flight guard for the QR-image pick+decode (P14). The camera `_scanQr` can't
  /// re-enter (its route covers the page); the image pick leaves the page live, so without
  /// this a second tap during the async decode would open a second picker + double-submit.
  bool _pickingQrImage = false;

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

  Future<void> _scanQr() async {
    // Gallery preview: open the demo scanner (no camera/storage), don't submit.
    if (widget.demo) {
      await Navigator.of(context).push(QrScanPage.routeDemo());
      return;
    }
    // Real flow: a successful scan returns the decoded id, which flows down the
    // exact same path as manual entry (idChanged → submit → spine navigates).
    final id = await Navigator.of(context).push(QrScanPage.route());
    if (id == null || !mounted) return; // back / Enter manually → no submit, field kept (FR-013)
    _controller.text = id;
    _bloc.add(LoginEvent.idChanged(id));
    _submit();
  }

  Future<void> _scanQrImage() async {
    // Windows/Linux fallback (no camera scanner): pick an image, decode its QR locally,
    // then feed the SAME sign-in path as a scan / manual entry. A cancelled pick keeps the
    // field; an image with no valid NOX QR shows a notice and does not submit.
    if (_pickingQrImage) return; // a pick+decode is already running — ignore the re-tap
    setState(() => _pickingQrImage = true);
    try {
      final picked = await getIt<FilePickerService>().pickFile();
      final path = picked?.path;
      if (path == null || !mounted) return;
      final raw = await qrImageDecodeService.decodeQr(path);
      final id = raw == null ? null : NoxQrEnvelope.decode(raw);
      if (!mounted) return;
      if (id == null) {
        showAppSnackBar(context, text: context.l10n.loginQrImageError, error: true);
        return;
      }
      _controller.text = id;
      _bloc.add(LoginEvent.idChanged(id));
      _submit();
    } finally {
      if (mounted) setState(() => _pickingQrImage = false);
    }
  }

  void _onStatus(BuildContext context, LoginState state) {
    switch (state.status) {
      case LoginStatus.navNewId:
        Navigator.of(context).push(SetUsernamePage.route());
        _bloc.add(const LoginEvent.navigationHandled());
      case LoginStatus.navRegistered:
        Navigator.of(context).push(TabBarShell.route());
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
        builder: (context, state) => AppOnboardingScaffoldWidget(
          subtitle: 'Sign in',
          mobileActionsPadding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, AppSpacingTokens.s16, AppSpacingTokens.s16, AppSpacingTokens.s24),
          field: _idField(context, state),
          actions: _actions(context, state),
        ),
      ),
    );
  }

  Widget _idField(BuildContext context, LoginState state) {
    return AppIdFieldWidget(
      controller: _controller,
      canPaste: state.canPaste,
      onPaste: _paste,
      onChanged: (value) => _bloc.add(LoginEvent.idChanged(value)),
      errorText: _errorText(context, state.status),
      enabled: !state.isLoading,
    );
  }

  /// Resolves the inline ID-field error copy from the current status. Lives on the
  /// widget (not the BLoC state) so it can read locale-aware strings via context.
  String? _errorText(BuildContext context, LoginStatus status) => switch (status) {
    LoginStatus.errorFormat => context.l10n.loginInvalidId,
    LoginStatus.errorNetwork => context.l10n.loginNetworkError,
    _ => null,
  };

  Widget _actions(BuildContext context, LoginState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPrimaryButtonWidget(label: context.l10n.loginSignIn, onPressed: state.canSubmit ? _submit : null, loading: state.isLoading),
        // `Scan QR` is shown only where the camera scanner exists (iOS/Android/macOS);
        // on Windows/Linux it is hidden. There, a "pick a QR image" fallback stands in so
        // those desktops keep a QR sign-in at parity (P14; FR-016/FR-017).
        if (QrScannerCapability.isAvailable) ...[
          SizedBox(height: AppSpacingTokens.s8),
          SizedBox(
            width: double.infinity,
            child: TextButton(onPressed: state.isLoading ? null : _scanQr, child: Text(context.l10n.loginScanQr)),
          ),
        ] else if (QrImageSignInCapability.isAvailable) ...[
          SizedBox(height: AppSpacingTokens.s8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: (state.isLoading || _pickingQrImage) ? null : _scanQrImage,
              child: Text(context.l10n.loginScanQrImage),
            ),
          ),
        ],
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

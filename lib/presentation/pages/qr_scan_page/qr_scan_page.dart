import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_scrims.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/qr_scan_page/bloc/qr_scan_bloc.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/qr/app_qr_overlay_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

/// 2.2 QR scan — the camera alternative to manual ID entry (2.1). On a valid
/// `nox://id/<id>` scan the screen pops the decoded id, which Login submits down
/// the same path as a typed id (single-shot, no confirm/sound). Owns a pure
/// [QrScanBloc] (state machine) plus a widget-local [MobileScannerController]; the
/// widget orchestrates the camera permission (permission_handler on iOS/Android,
/// the controller on macOS) and feeds the bloc [QrScanEvent]s. Mobile (`_narrow`):
/// full-screen feed + reticle/mask + torch/switch. Desktop macOS (`_wide`):
/// windowed viewfinder, no camera actions. Permission-denied is an opaque surface
/// (on mobile) / OnboardCard (desktop).
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.demo = false, this.previewBuilder, this.bloc});

  final bool demo;

  /// Test seam: replaces the live [MobileScanner] with a deterministic widget so
  /// goldens render the scanning frame without a camera.
  @visibleForTesting
  final WidgetBuilder? previewBuilder;

  /// Test seam: inject a pre-seeded [QrScanBloc] to drive a specific state
  /// (denied / invalid / fatal) in widget tests without the camera/permission.
  @visibleForTesting
  final QrScanBloc? bloc;

  /// The scanner controller config. Single place that pins `returnImage: false`
  /// (privacy — FR-018/SC-007: frames are never captured as images) and the
  /// QR-only, no-duplicate detection. Exposed so a test can assert the privacy
  /// posture without a live camera.
  @visibleForTesting
  static MobileScannerController createController() => MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  static Route<String?> route() => MaterialPageRoute<String?>(
    builder: (_) => const QrScanPage(),
    settings: const RouteSettings(name: '/onboarding/qr-scan'),
  );

  /// Gallery entry: adds the dev state control (returns no value).
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const QrScanPage(demo: true),
    settings: const RouteSettings(name: '/onboarding/qr-scan'),
  );

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with WidgetsBindingObserver {
  late final QrScanBloc _bloc;
  late final bool _ownsBloc;
  MobileScannerController? _controller;
  bool _torchOn = false;
  bool _cameraStarted = false;

  /// True only at real runtime: a live camera + permission service. Demo
  /// (gallery), goldens (previewBuilder) and widget tests (injected bloc) stay
  /// camera- and DI-free.
  bool get _live => !widget.demo && widget.previewBuilder == null && widget.bloc == null;

  @override
  void initState() {
    super.initState();
    _ownsBloc = widget.bloc == null;
    _bloc = widget.bloc ?? QrScanBloc();
    WidgetsBinding.instance.addObserver(this);
    if (_ownsBloc) _bloc.add(const QrScanEvent.started());
    if (_live) {
      _controller = QrScanPage.createController();
      _resolve(initial: true);
    } else if (widget.demo) {
      // Gallery opens on the scanning layout; dev controls drive the rest.
      _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    if (_ownsBloc) _bloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_live) return;
    // The page owns the controller, so MobileScanner does NOT auto-manage the feed
    // on lifecycle — we start/stop it explicitly. On resume re-check permission with
    // the cheap non-prompting status() (FR-006: returning from system settings
    // auto-restarts without a re-tap); on background, stop the camera.
    switch (state) {
      case AppLifecycleState.resumed:
        _resolve(initial: false);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _stopCamera();
    }
  }

  /// Resolve camera permission and drive the camera: request() raises the OS prompt
  /// on the initial open; status() is the cheap non-prompting re-check on resume.
  /// macOS has no permission_handler, so the controller's own prompt + errorBuilder
  /// drive it there.
  Future<void> _resolve({required bool initial}) async {
    final CameraPermissionStatus status;
    if (PlatformUtils.isMobile) {
      status = initial ? await cameraPermissionService.request() : await cameraPermissionService.status();
    } else {
      status = CameraPermissionStatus.granted; // macOS: controller-driven (errorBuilder corrects on denial)
    }
    if (!mounted) return;
    _bloc.add(QrScanEvent.permissionResolved(status));
    if (status == CameraPermissionStatus.granted) {
      await _startCamera();
    } else {
      await _stopCamera();
    }
  }

  Future<void> _startCamera() async {
    if (_controller == null || _cameraStarted) return;
    _cameraStarted = true;
    try {
      await _controller!.start();
    } catch (e, s) {
      _cameraStarted = false;
      logRepository.error(target: this, error: e, stackTrace: s);
    }
  }

  Future<void> _stopCamera() async {
    if (_controller == null || !_cameraStarted) return;
    _cameraStarted = false;
    try {
      await _controller!.stop();
    } catch (_) {
      // Stopping an already-stopped controller is harmless.
    }
  }

  void _openSettings() => cameraPermissionService.openSettings();

  void _toggleTorch() {
    _controller?.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _switchCamera() => _controller?.switchCamera();

  void _enterManually() => Navigator.of(context).pop();

  void _onSignal(BuildContext context, QrScanState state) {
    if (state.decodedId != null) {
      _controller?.stop();
      Navigator.of(context).pop(state.decodedId);
      return;
    }
    if (state.invalid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(TextConstants.qrInvalidSnackbar)));
      _bloc.add(const QrScanEvent.signalHandled());
      return;
    }
    if (state.status == QrScanStatus.fatal) {
      Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<QrScanBloc>.value(
      value: _bloc,
      child: BlocConsumer<QrScanBloc, QrScanState>(
        listenWhen: (previous, current) =>
            (current.decodedId != null && previous.decodedId == null) ||
            (current.invalid && !previous.invalid) ||
            (current.status == QrScanStatus.fatal && previous.status != QrScanStatus.fatal),
        listener: _onSignal,
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

  /// The live camera (real runtime), a deterministic placeholder (goldens) or a
  /// neutral surface (demo / no camera).
  Widget _cameraPreview(BuildContext context) {
    if (widget.previewBuilder != null) return widget.previewBuilder!(context);
    if (!_live) return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      onDetect: (capture) {
        final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
        if (raw != null && raw.isNotEmpty) _bloc.add(QrScanEvent.detected(raw));
      },
      errorBuilder: (context, error) {
        final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        // A denial is a recoverable in-screen state (Open settings); any other camera
        // error is logged and treated as fatal → 3.1, itself recoverable (Back to Login,
        // re-tapping Scan QR builds a fresh controller).
        if (!denied) logRepository.error(target: this, error: error);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _bloc.add(QrScanEvent.permissionResolved(denied ? CameraPermissionStatus.permanentlyDenied : CameraPermissionStatus.unavailable));
        });
        return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
      },
    );
  }

  // --- Mobile: full-bleed camera + overlay -----------------------------------

  Widget _narrow(BuildContext context, QrScanState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final denied = state.status == QrScanStatus.permissionDenied;
    return Scaffold(
      extendBodyBehindAppBar: !denied,
      appBar: AppBar(
        backgroundColor: denied ? colorScheme.surface : Colors.transparent,
        elevation: denied ? null : 0,
        scrolledUnderElevation: denied ? null : 0,
        foregroundColor: denied ? null : NoxBrand.white,
        actions: denied
            ? null
            : [
                IconButton(
                  tooltip: TextConstants.tooltipFlashlight,
                  onPressed: _toggleTorch,
                  icon: AppIconWidget(_torchOn ? NoxIcons.flashlightOnFill : NoxIcons.flashlightOff),
                ),
                IconButton(
                  tooltip: TextConstants.tooltipSwitchCamera,
                  onPressed: _switchCamera,
                  icon: AppIconWidget(NoxIcons.cameraswitch),
                ),
              ],
      ),
      body: denied
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacingTokens.s24),
                child: _DeniedPanel(onOpenSettings: _openSettings),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(child: _cameraPreview(context)),
                const Positioned.fill(child: AppQrOverlayWidget()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacingTokens.s16),
                      child: Center(child: _enterManuallyPill(context)),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _devControl(),
    );
  }

  /// "Enter manually" rendered as a tappable dark-scrim pill over the camera feed:
  /// the label is forced [NoxBrand.white] and the fill is the brand-fixed ~35%
  /// black scrim (theme-invariant, like the overlay mask).
  Widget _enterManuallyPill(BuildContext context) {
    return Material(
      color: NoxScrims.qrPill,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _enterManually,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s20, vertical: AppSpacingTokens.s8),
          child: Text(TextConstants.qrEnterManually, style: AppTextStyleTokens.labelLarge(color: NoxBrand.white)),
        ),
      ),
    );
  }

  // --- Desktop (macOS): windowed viewfinder (corpus 06-qr.md) ----------------

  Widget _wide(BuildContext context, QrScanState state) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final Widget content = state.status == QrScanStatus.permissionDenied
        ? AppOnboardCardWidget(child: _DeniedPanel(onOpenSettings: _openSettings))
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(TextConstants.qrDesktopTitle, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
                SizedBox(height: AppSpacingTokens.s24),
                SizedBox(
                  width: AppDimensionTokens.size.qrScanWindow,
                  height: AppDimensionTokens.size.qrScanWindow,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensionTokens.radius.md),
                    child: Stack(
                      children: [
                        Positioned.fill(child: _cameraPreview(context)),
                        const Positioned.fill(child: AppQrOverlayWidget(reticleFraction: 0.78, showInstruction: false)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: AppSpacingTokens.s16),
                Text(
                  TextConstants.qrDesktopHelper,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                TextButton(onPressed: _enterManually, child: const Text(TextConstants.qrEnterManually)),
              ],
            ),
          );
    final dev = _devControl();
    return Scaffold(
      body: Column(
        children: [
          const AppWindowTitlebarWidget(subtitle: 'Scan QR'),
          Expanded(child: content),
          ?dev,
        ],
      ),
    );
  }

  /// Dev-only state control (gallery preview) — drives the real bloc with
  /// synthetic events, so the gallery exercises the flow with no camera/storage.
  Widget? _devControl() {
    if (!(kDebugMode && widget.demo)) return null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacingTokens.s8,
          children: [
            OutlinedButton(
              onPressed: () => _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.granted)),
              child: const Text('scanning'),
            ),
            OutlinedButton(
              onPressed: () => _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.permanentlyDenied)),
              child: const Text('denied'),
            ),
            OutlinedButton(onPressed: () => _bloc.add(const QrScanEvent.detected('https://example.com')), child: const Text('invalid')),
            OutlinedButton(
              onPressed: () => _bloc.add(QrScanEvent.detected(NoxQrEnvelope.encode('registered'))),
              child: const Text('success'),
            ),
            OutlinedButton(
              onPressed: () => _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.unavailable)),
              child: const Text('fatal'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Permission-denied content (opaque surface on mobile, OnboardCard on desktop).
class _DeniedPanel extends StatelessWidget {
  const _DeniedPanel({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconWidget(NoxIcons.noPhotography, size: AppDimensionTokens.icon.heroLg, color: colorScheme.onSurfaceVariant),
        SizedBox(height: AppSpacingTokens.s16),
        Text(
          TextConstants.qrPermissionTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s16),
        Text(
          TextConstants.qrPermissionMessage,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: AppSpacingTokens.s24),
        FilledButton(onPressed: onOpenSettings, child: const Text(TextConstants.actionOpenSettings)),
      ],
    );
  }
}

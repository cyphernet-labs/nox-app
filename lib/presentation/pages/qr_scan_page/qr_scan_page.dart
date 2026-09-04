import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_scrims.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/qr/camera_permission_status.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/general/platform_utils.dart';
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
  bool _cameraErrorHandled = false;

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
    _cameraErrorHandled = false;
    try {
      await _controller!.start();
    } on MobileScannerException catch (e) {
      _cameraStarted = false;
      _handleCameraError(e);
    } catch (e, s) {
      _cameraStarted = false;
      if (mounted) {
        logRepository.error(target: this, error: e, stackTrace: s);
        _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.unavailable));
      }
    }
  }

  /// Maps a mobile_scanner error to a recoverable in-screen state. Permission
  /// denial → the denied surface; a missing camera (`unsupported`, e.g. the iOS
  /// simulator) → the camera-unavailable surface. Both are EXPECTED, recoverable
  /// conditions logged at debug, not error; anything else is logged as an error.
  /// Guarded so the per-frame `errorBuilder` does not spam.
  void _handleCameraError(MobileScannerException error) {
    if (_cameraErrorHandled || !mounted) return;
    _cameraErrorHandled = true;
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.permanentlyDenied));
      return;
    }
    if (error.errorCode == MobileScannerErrorCode.unsupported) {
      logRepository.debug(target: this, message: 'Camera unavailable: $error');
    } else {
      logRepository.error(target: this, error: error);
    }
    _bloc.add(const QrScanEvent.permissionResolved(CameraPermissionStatus.unavailable));
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
        ..showSnackBar(SnackBar(content: Text(context.l10n.qrInvalidSnackbar)));
      _bloc.add(const QrScanEvent.signalHandled());
    }
    // `fatal` (camera unavailable) is handled in-screen by the builder (the
    // camera-unavailable panel) — no dead-end navigation to the error screen.
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<QrScanBloc>.value(
      value: _bloc,
      child: BlocConsumer<QrScanBloc, QrScanState>(
        listenWhen: (previous, current) =>
            (current.decodedId != null && previous.decodedId == null) || (current.invalid && !previous.invalid),
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

  /// Neutral fill behind/instead of the camera feed (demo / no camera / a frame error).
  static Widget _neutralSurface(ColorScheme colorScheme) => ColoredBox(color: colorScheme.surfaceContainerHighest);

  /// The live camera (real runtime), a deterministic placeholder (goldens) or a
  /// neutral surface (demo / no camera).
  Widget _cameraPreview(BuildContext context) {
    if (widget.previewBuilder != null) return widget.previewBuilder!(context);
    // Resolve once and reuse — the errorBuilder below runs per camera frame, so a
    // Theme.of() there would re-look-up the theme on every frame.
    final colorScheme = Theme.of(context).colorScheme;
    if (!_live) return _neutralSurface(colorScheme);
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      onDetect: (capture) {
        final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
        if (raw != null && raw.isNotEmpty) _bloc.add(QrScanEvent.detected(raw));
      },
      errorBuilder: (context, error) {
        // Errors that surface after start() (e.g. permission revoked mid-session)
        // funnel through the same recoverable handler as the explicit start failure.
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleCameraError(error));
        return _neutralSurface(colorScheme);
      },
    );
  }

  // --- Mobile: full-bleed camera + overlay -----------------------------------

  Widget _narrow(BuildContext context, QrScanState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final panel = _panelFor(context, state.status); // permission-denied / camera-unavailable surface
    final scanning = state.status == QrScanStatus.scanning;
    return Scaffold(
      // Over-camera chrome only when there's no opaque panel.
      extendBodyBehindAppBar: panel == null,
      appBar: AppBar(
        backgroundColor: panel == null ? Colors.transparent : colorScheme.surface,
        elevation: panel == null ? 0 : null,
        scrolledUnderElevation: panel == null ? 0 : null,
        foregroundColor: panel == null ? NoxBrand.white : null,
        // Torch / switch-camera sit over the live feed → forced brand white for
        // contrast, and only while the camera is active (FR-005, mobile-only).
        actions: scanning
            ? [
                IconButton(
                  tooltip: context.l10n.tooltipFlashlight,
                  onPressed: _toggleTorch,
                  icon: AppIconWidget(_torchOn ? NoxIcons.flashlightOnFill : NoxIcons.flashlightOff, color: NoxBrand.white),
                ),
                IconButton(
                  tooltip: context.l10n.tooltipSwitchCamera,
                  onPressed: _switchCamera,
                  icon: AppIconWidget(NoxIcons.cameraswitch, color: NoxBrand.white),
                ),
              ]
            : null,
      ),
      body: panel != null
          ? Center(
              child: Padding(padding: EdgeInsets.all(AppSpacingTokens.s24), child: panel),
            )
          : Stack(
              children: [
                // The live camera is only mounted once permission is granted
                // (scanning); during initializing show a neutral surface.
                Positioned.fill(child: scanning ? _cameraPreview(context) : _neutralSurface(colorScheme)),
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

  /// The opaque surface for a non-scanning terminal state — permission-denied
  /// (Open settings) or camera-unavailable (Enter manually). `null` for the
  /// camera states (initializing / scanning).
  Widget? _panelFor(BuildContext context, QrScanStatus status) => switch (status) {
    QrScanStatus.permissionDenied => _QrStatePanel(
      icon: NoxIcons.noPhotography,
      title: context.l10n.qrPermissionTitle,
      message: context.l10n.qrPermissionMessage,
      actionLabel: context.l10n.actionOpenSettings,
      onAction: _openSettings,
    ),
    QrScanStatus.fatal => _QrStatePanel(
      icon: NoxIcons.noPhotography,
      title: context.l10n.qrUnavailableTitle,
      message: context.l10n.qrUnavailableMessage,
      actionLabel: context.l10n.qrEnterManually,
      onAction: _enterManually,
    ),
    QrScanStatus.initializing || QrScanStatus.scanning => null,
  };

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
          child: Text(context.l10n.qrEnterManually, style: AppTextStyleTokens.labelLarge(color: NoxBrand.white)),
        ),
      ),
    );
  }

  // --- Desktop (macOS): windowed viewfinder (corpus 06-qr.md) ----------------

  Widget _wide(BuildContext context, QrScanState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final panel = _panelFor(context, state.status);
    final Widget content = panel != null
        ? AppOnboardCardWidget(child: panel)
        : _QrDesktopViewfinder(
            // The camera feed is built only while scanning; otherwise a neutral fill.
            preview: state.status == QrScanStatus.scanning ? _cameraPreview(context) : _neutralSurface(colorScheme),
            onEnterManually: _enterManually,
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
            OutlinedButton(onPressed: () => _bloc.add(const QrScanEvent.detected(PairingLink.demo)), child: const Text('success')),
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

/// Opaque state surface for the scanner's non-camera terminal states — denied
/// (Open settings) and camera-unavailable (Enter manually). Centered on a plain
/// `surface` (mobile) / inside an `OnboardCard` (desktop). Icon + title + message
/// + a single filled action (corpus `2-2-qr-scan.md` denied anatomy).
class _QrStatePanel extends StatelessWidget {
  const _QrStatePanel({required this.icon, required this.title, required this.message, required this.actionLabel, required this.onAction});

  final SvgGenImage icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconWidget(icon, size: AppDimensionTokens.icon.heroLg, color: colorScheme.onSurfaceVariant),
        SizedBox(height: AppSpacingTokens.s16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s16),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.errorMsgW),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        SizedBox(height: AppSpacingTokens.s24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

/// Desktop QR viewfinder (the `_wide` no-panel state): a titled square window with
/// the reticle overlay over [preview] (the camera feed while scanning, or a neutral
/// fill), a helper line and the manual-entry fallback. [preview] is resolved by the
/// caller so the camera is built only while scanning.
class _QrDesktopViewfinder extends StatelessWidget {
  const _QrDesktopViewfinder({required this.preview, required this.onEnterManually});

  /// Reticle side as a fraction of the (smaller) desktop viewfinder window — a touch
  /// larger than the mobile default since the desktop window is a fixed small square.
  static const double _reticleFraction = 0.78;

  final Widget preview;
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.qrDesktopTitle, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
          SizedBox(height: AppSpacingTokens.s24),
          SizedBox(
            width: AppDimensionTokens.size.qrScanWindow,
            height: AppDimensionTokens.size.qrScanWindow,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppDimensionTokens.radius.md),
              child: Stack(
                children: [
                  Positioned.fill(child: preview),
                  const Positioned.fill(child: AppQrOverlayWidget(reticleFraction: _reticleFraction, showInstruction: false)),
                ],
              ),
            ),
          ),
          SizedBox(height: AppSpacingTokens.s16),
          Text(
            context.l10n.qrDesktopHelper,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          TextButton(onPressed: onEnterManually, child: Text(context.l10n.qrEnterManually)),
        ],
      ),
    );
  }
}

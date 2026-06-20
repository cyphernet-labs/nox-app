import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/pages/error_page/error_page.dart';
import 'package:nox_app/presentation/pages/error_page/error_page_params.dart';
import 'package:nox_app/presentation/pages/placeholder/route_placeholder_page.dart';
import 'package:nox_app/presentation/widgets/onboarding/app_onboard_card_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/qr/app_qr_overlay_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_window_titlebar_widget.dart';

/// Persistent visual states of the scanner (the OS Permission-prompt is not
/// reproducible in UI-only; invalid / success / fatal are one-shot events).
enum _QrPreview { scanning, permissionDenied }

/// 2.2 QR scan — alternative to manual ID entry. Camera is a Phase-2 plugin, so a
/// neutral placeholder stands in behind the real brand-fixed reticle/mask overlay;
/// every state is reproduced by a debug control. No BLoC (camera/permission are
/// stubbed). Mobile: full-screen with a solid AppBar (torch / switch-camera no-ops).
/// Desktop: a windowed `TitleBar` + ≈300dp viewfinder + manual-entry, with the
/// permission-denied state inside an `AppOnboardCardWidget` (corpus `06-qr.md`).
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.demo = false});

  final bool demo;

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const QrScanPage(),
    settings: const RouteSettings(name: '/onboarding/qr-scan'),
  );

  /// Gallery entry: adds the dev state control.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const QrScanPage(demo: true),
    settings: const RouteSettings(name: '/onboarding/qr-scan'),
  );

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  _QrPreview _preview = _QrPreview.scanning;
  bool _torchOn = false;

  // TODO(backend): torch / camera-switch / permission / Open-settings are no-ops
  // until the camera plugin (mobile_scanner) + permission_handler land (Phase 2).
  void _toggleTorch() => setState(() => _torchOn = !_torchOn);
  void _switchCamera() {}
  void _openSettings() {}

  void _enterManually() {
    // TODO(backend): real flow returns to Login (2.1) keeping the field; standalone stub.
    Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Login manual entry (2.1)'));
  }

  void _fireSuccess() {
    // Single-shot: the real flow auto-submits the scanned id into Login (2.1).
    Navigator.of(context).push(RoutePlaceholderPage.route(destinationLabel: 'Login auto-submit (2.1)'));
  }

  void _fireInvalid() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(TextConstants.qrInvalidSnackbar)));
  }

  void _fireFatal() => Navigator.of(context).push(AppErrorPage.route(params: ErrorPageParams.fatal()));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Constants.railBreakpoint;
        return wide ? _wide(context) : _narrow(context);
      },
    );
  }

  // --- Mobile: full-bleed camera placeholder + overlay -----------------------

  Widget _narrow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        actions: [
          IconButton(
            tooltip: TextConstants.tooltipFlashlight,
            onPressed: _toggleTorch,
            icon: AppIconWidget(_torchOn ? NoxIcons.flashlightOnFill : NoxIcons.flashlightOff),
          ),
          IconButton(tooltip: TextConstants.tooltipSwitchCamera, onPressed: _switchCamera, icon: AppIconWidget(NoxIcons.cameraswitch)),
        ],
      ),
      body: _preview == _QrPreview.permissionDenied
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacingTokens.s24),
                child: _DeniedPanel(onOpenSettings: _openSettings),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: colorScheme.surfaceContainerHighest)),
                const Positioned.fill(child: AppQrOverlayWidget()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacingTokens.s16),
                      child: TextButton(onPressed: _enterManually, child: const Text(TextConstants.qrEnterManually)),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _devControl(),
    );
  }

  // --- Desktop: windowed viewfinder (corpus 06-qr.md) ------------------------

  Widget _wide(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final Widget content = _preview == _QrPreview.permissionDenied
        ? AppOnboardCardWidget(child: _DeniedPanel(onOpenSettings: _openSettings))
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(TextConstants.qrDesktopTitle, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
                SizedBox(height: AppSpacingTokens.s24),
                SizedBox(
                  width: 300,
                  height: 300,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: colorScheme.surfaceContainerHighest)),
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
          const AppWindowTitlebarWidget(title: TextConstants.onboardTitleScanQr),
          Expanded(child: content),
          ?dev,
        ],
      ),
    );
  }

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
            OutlinedButton(onPressed: () => setState(() => _preview = _QrPreview.scanning), child: const Text('scanning')),
            OutlinedButton(onPressed: () => setState(() => _preview = _QrPreview.permissionDenied), child: const Text('denied')),
            OutlinedButton(onPressed: _fireInvalid, child: const Text('invalid')),
            OutlinedButton(onPressed: _fireSuccess, child: const Text('success')),
            OutlinedButton(onPressed: _fireFatal, child: const Text('fatal')),
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
        AppIconWidget(NoxIcons.noPhotography, size: 48, color: colorScheme.onSurfaceVariant),
        SizedBox(height: AppSpacingTokens.s16),
        Text(
          TextConstants.qrPermissionTitle,
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s8),
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

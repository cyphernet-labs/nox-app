import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/nox_qr_envelope.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Brand-fixed light QR surface for the user's identifier (7.1 Show QR). The
/// surface is ALWAYS light and sits OUTSIDE the ColorScheme — the project's second
/// brand-fixed theming exception (after the dark splash), per design-system §9.10:
/// background `NoxBrand.qrSurface` (#FFFFFF), modules `NoxBrand.qrInk` (#0C0C0C),
/// identical in light and dark.
///
/// [data] is the raw `Your ID`; it is encoded as the `nox://id/<id>` envelope so
/// another device's scanner (2.2) decodes back to the same identifier (FR-014,
/// round-trip SC-005).
class AppQrSurfaceWidget extends StatefulWidget {
  const AppQrSurfaceWidget({super.key, required this.data, this.size = 220});

  final String data;
  final double size;

  @override
  State<AppQrSurfaceWidget> createState() => _AppQrSurfaceWidgetState();
}

class _AppQrSurfaceWidgetState extends State<AppQrSurfaceWidget> {
  // The QR matrix is cached and only rebuilt when [data] changes, so a parent that
  // rebuilds for unrelated reasons (e.g. a Settings name-edit keystroke) does not
  // re-run the Reed-Solomon encoding on a stable id.
  late Widget _qr;

  @override
  void initState() {
    super.initState();
    _qr = _buildQr();
  }

  @override
  void didUpdateWidget(AppQrSurfaceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _qr = _buildQr();
  }

  Widget _buildQr() => QrImageView(
    data: NoxQrEnvelope.encode(widget.data),
    version: QrVersions.auto,
    backgroundColor: NoxBrand.qrSurface,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: NoxBrand.qrInk),
    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: NoxBrand.qrInk),
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
    padding: EdgeInsets.zero,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: TextConstants.qrSheetTitle,
      image: true,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: NoxBrand.qrSurface, borderRadius: BorderRadius.circular(NoxRadius.m)),
        // Quiet zone around the modules (always white). The outer Container owns it,
        // so the QrImageView's own padding is zeroed.
        padding: EdgeInsets.all(widget.size * 0.1),
        child: _qr,
      ),
    );
  }
}

/// Shows the identifier QR: a modal bottom sheet on mobile, a centered dialog on
/// desktop ([wide]). Brand-fixed light surface; the raw identifier is never shown
/// as text (only QR-encoded).
Future<void> showIdQr(BuildContext context, {required String data, required bool wide}) {
  final content = _IdQrContent(data: data);
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(child: content),
    );
  }
  return showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => content);
}

class _IdQrContent extends StatelessWidget {
  const _IdQrContent({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(TextConstants.qrSheetTitle, style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
          SizedBox(height: AppSpacingTokens.s16),
          AppQrSurfaceWidget(data: data),
          SizedBox(height: AppSpacingTokens.s16),
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text(TextConstants.actionClose)),
        ],
      ),
    );
  }
}

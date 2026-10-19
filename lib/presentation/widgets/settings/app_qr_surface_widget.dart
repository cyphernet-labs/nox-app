import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Brand-fixed light QR surface for a pairing link (the device invite of 7.8).
/// The surface is ALWAYS light and sits OUTSIDE the ColorScheme — the project's
/// second brand-fixed theming exception (after the dark splash), per
/// design-system §9.10: background `NoxBrand.qrSurface` (#FFFFFF), modules
/// `NoxBrand.qrInk` (#0C0C0C), identical in light and dark.
///
/// [data] is the link itself, encoded verbatim, so another device's scanner
/// (2.2) reads back exactly the string it has to present.
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
    // Rendered verbatim: the caller hands in a pairing link, which is
    // already the exact string the other device has to read.
    data: widget.data,
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
      label: context.l10n.inviteQrLabel,
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

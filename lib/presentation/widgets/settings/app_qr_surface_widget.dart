import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';

/// Brand-fixed light QR surface for the user's identifier (7.1 Show QR). The
/// surface is ALWAYS light and sits OUTSIDE the ColorScheme — the project's second
/// brand-fixed theming exception (after the dark splash), per design-system §9.10:
/// background `NoxBrand.qrSurface` (#FFFFFF), modules `NoxBrand.qrInk` (#0C0C0C),
/// identical in light and dark.
///
/// The modules are a NEUTRAL deterministic placeholder pattern (finder squares +
/// hashed cells) — NOT a real encoding. Real QR generation needs a dependency and
/// the real identifier, deferred to the backend phase. `// TODO(backend):` encode
/// the real identifier (e.g. qr_flutter).
class AppQrSurfaceWidget extends StatelessWidget {
  const AppQrSurfaceWidget({super.key, required this.data, this.size = 220});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: TextConstants.qrSheetTitle,
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: NoxBrand.qrSurface, borderRadius: BorderRadius.circular(NoxRadius.m)),
        // Quiet zone around the modules (always white).
        padding: EdgeInsets.all(size * 0.1),
        child: CustomPaint(painter: _FakeQrPainter(data)),
      ),
    );
  }
}

/// Draws a neutral, deterministic QR-like grid (three finder patterns + hashed
/// data modules). Purely decorative — does NOT encode [data].
class _FakeQrPainter extends CustomPainter {
  _FakeQrPainter(this.data);

  final String data;

  static const int _modules = 21; // v1 QR module count

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = NoxBrand.qrInk;
    final cell = size.width / _modules;

    void square(int col, int row) {
      canvas.drawRect(Rect.fromLTWH(col * cell, row * cell, cell, cell), paint);
    }

    // Three finder patterns (top-left, top-right, bottom-left).
    void finder(int ox, int oy) {
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 7; c++) {
          final onRing = r == 0 || r == 6 || c == 0 || c == 6;
          final inCore = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          if (onRing || inCore) square(ox + c, oy + r);
        }
      }
    }

    finder(0, 0);
    finder(_modules - 7, 0);
    finder(0, _modules - 7);

    // Hashed data modules in the remaining area (skip the finder zones).
    var h = 0;
    for (final cu in data.codeUnits) {
      h = (h * 31 + cu) & 0x7FFFFFFF;
    }
    bool inFinder(int c, int r) => (c < 8 && r < 8) || (c > _modules - 9 && r < 8) || (c < 8 && r > _modules - 9);
    for (var r = 0; r < _modules; r++) {
      for (var c = 0; c < _modules; c++) {
        if (inFinder(c, r)) continue;
        h = (h * 1103515245 + 12345) & 0x7FFFFFFF;
        if ((h >> 16) & 1 == 1) square(c, r);
      }
    }
  }

  @override
  bool shouldRepaint(_FakeQrPainter oldDelegate) => oldDelegate.data != data;
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
          Text(TextConstants.qrSheetTitle, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
          SizedBox(height: AppSpacingTokens.s16),
          AppQrSurfaceWidget(data: data),
          SizedBox(height: AppSpacingTokens.s16),
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text(TextConstants.actionClose)),
        ],
      ),
    );
  }
}

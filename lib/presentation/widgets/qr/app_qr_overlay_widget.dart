import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/text_constants.dart';

/// QR scanner overlay (2.2): a centered reticle, a dimming mask around it and the
/// top instruction — drawn over the (stubbed) camera surface. BRAND-FIXED: the
/// mask (`#000000` @ 55%), reticle stroke and instruction (`NoxBrand.white`,
/// #FAFAFA) are theme-INVARIANT, per `design-system.md` §9.9 — they do NOT read
/// from `ColorScheme`. This is the one brand-fixed exception of milestone M2.
class AppQrOverlayWidget extends StatelessWidget {
  const AppQrOverlayWidget({super.key, this.reticleFraction = 0.7, this.showInstruction = true});

  /// Reticle side as a fraction of the available width (≈70%).
  final double reticleFraction;

  /// Whether to draw the top instruction. Disabled on the small desktop viewfinder,
  /// which carries its own title/helper outside the overlay (avoids overlap).
  final bool showInstruction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ReticlePainter(reticleFraction: reticleFraction)),
        ),
        if (showInstruction)
          Positioned(
            top: AppSpacingTokens.s32,
            left: AppSpacingTokens.s24,
            right: AppSpacingTokens.s24,
            child: Text(
              TextConstants.qrAimHint,
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                color: NoxBrand.white,
                shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 4)],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter({required this.reticleFraction});

  final double reticleFraction;

  /// `#000000` @ 55% — brand-fixed dimming mask (design-system.md §9.9).
  static const Color _mask = Color(0x8C000000);
  static const Color _reticle = NoxBrand.white; // #FAFAFA, 3dp
  static const double _stroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * reticleFraction;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: side, height: side);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(NoxRadius.m));

    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(mask, Paint()..color = _mask);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = _reticle,
    );
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) => oldDelegate.reticleFraction != reticleFraction;
}

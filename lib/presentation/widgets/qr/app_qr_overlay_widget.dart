import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/design/theme/nox_scrims.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';

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
            // Sit just below the transparent AppBar (status bar + toolbar height), so
            // the instruction never slides under the notch / Dynamic Island.
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + AppSpacingTokens.s8,
            left: AppSpacingTokens.s24,
            right: AppSpacingTokens.s24,
            child: Text(
              context.l10n.qrAimHint,
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                color: NoxBrand.white,
                shadows: [Shadow(color: NoxScrims.qrTextShadow, blurRadius: AppSpacingTokens.s4)],
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
  static const Color _mask = NoxScrims.qrMask;
  static const Color _reticle = NoxBrand.white; // #FAFAFA, 3dp
  static double get _stroke => AppDimensionTokens.border.heavy;

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

    // Reticle = four corner brackets (not a full frame). Each corner is a vertical +
    // horizontal leg joined by a quarter-circle arc of radius `r` (= the mask hole's
    // corner radius), so the brackets trace the rounded corners of the hole exactly
    // instead of meeting at a sharp right angle.
    const r = NoxRadius.m;
    final leg = AppSpacingTokens.s40;
    final brackets = Path()
      // Top-left.
      ..moveTo(rect.left, rect.top + r + leg)
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: const Radius.circular(r))
      ..lineTo(rect.left + r + leg, rect.top)
      // Top-right.
      ..moveTo(rect.right - r - leg, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: const Radius.circular(r))
      ..lineTo(rect.right, rect.top + r + leg)
      // Bottom-right.
      ..moveTo(rect.right, rect.bottom - r - leg)
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: const Radius.circular(r))
      ..lineTo(rect.right - r - leg, rect.bottom)
      // Bottom-left.
      ..moveTo(rect.left + r + leg, rect.bottom)
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: const Radius.circular(r))
      ..lineTo(rect.left, rect.bottom - r - leg);

    canvas.drawPath(
      brackets,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _reticle,
    );
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) => oldDelegate.reticleFraction != reticleFraction;
}

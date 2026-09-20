import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Empty-list state — the design's `EmptyState`: a 132 outlined square holding a
/// 56 Material glyph, with two brand dots pinned inside it (teal top-right, gold
/// bottom-left), over a headline and a message.
///
/// It used to draw one of three bespoke SVG illustrations from
/// `Assets.svg.illustrations`. Those are drawings of nothing in particular — thin
/// strokes at 132 that read as a rendering fault rather than as art — and the
/// design never asked for them: it composes this state from a stock glyph and the
/// brand accents. The three SVGs stay in the bundle, referenced by nothing.
class AppEmptyContentWidget extends StatelessWidget {
  const AppEmptyContentWidget({super.key, required this.glyph, required this.title, required this.message});

  /// The stock Material Symbols glyph at the centre of the art box.
  final SvgGenImage glyph;

  final String title;
  final String message;

  static double get _artSize => AppDimensionTokens.size.emptyArt;
  static double get _messageMaxWidth => AppDimensionTokens.layout.messageMaxW;

  /// Design metrics with no role token of their own: the box's 20 corner (between
  /// `radius.lg` 16 and `radius.xl` 28) and the 56 glyph (between `icon.hero` 48
  /// and `icon.heroLg` 72).
  static double get _artRadius => AppSpacingTokens.s20;
  static double get _glyphSize => AppSpacingTokens.s56;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _art(context),
            SizedBox(height: AppSpacingTokens.s14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
            ),
            SizedBox(height: AppSpacingTokens.s14),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _messageMaxWidth),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _art(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _artSize,
      height: _artSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_artRadius),
                border: Border.all(color: colorScheme.outlineVariant, width: AppDimensionTokens.border.regular),
              ),
              child: Center(
                child: AppIconWidget(glyph, size: _glyphSize, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          // The two brand accents, at the design's insets. Theme-invariant on
          // purpose: they are the brand ramp, not a `ColorScheme` role.
          Positioned(
            top: AppSpacingTokens.s18,
            right: AppSpacingTokens.s20,
            child: _Dot(color: NoxBrand.teal, size: AppSpacingTokens.s14),
          ),
          Positioned(
            bottom: AppSpacingTokens.s22,
            left: AppSpacingTokens.s22,
            child: _Dot(color: NoxBrand.gold, size: AppSpacingTokens.s10),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

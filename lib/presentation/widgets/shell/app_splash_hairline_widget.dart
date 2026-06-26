import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';

/// Brand-splash hairline — the C-direction signature: a 3dp horizontal gradient
/// rule (teal→lime→gold→coral→red) under the app bar. Implements
/// [PreferredSizeWidget] → drop into `AppBar.bottom`. Brand-fixed (outside the
/// ColorScheme). Source: nox_scaffold.dart `NoxSplashHairline`.
class AppSplashHairlineWidget extends StatelessWidget implements PreferredSizeWidget {
  const AppSplashHairlineWidget({super.key});

  /// Gradient-rule thickness (dp); the rendered bar height.
  static double get thickness => AppDimensionTokens.border.heavy;

  /// Bottom gap (dp) below the rule; `preferredSize.height` is `thickness + gap`.
  static double get gap => AppSpacingTokens.s14;
  static double get _radius => AppDimensionTokens.border.thick;
  static const LinearGradient _gradient = LinearGradient(
    colors: [NoxBrand.teal, NoxBrand.lime, NoxBrand.gold, NoxBrand.coral, NoxBrand.red],
  );

  @override
  Size get preferredSize => Size.fromHeight(thickness + gap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Bottom gap is the unscaled `gap` so the rendered height (thickness + gap)
      // matches `preferredSize` on every device (a scaled value would overflow AppBar.bottom).
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, 0, AppSpacingTokens.s16, gap),
      child: Container(
        height: thickness,
        decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(_radius)),
      ),
    );
  }
}

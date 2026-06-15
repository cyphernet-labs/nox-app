import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_brand.dart';

/// Brand-splash hairline — the C-direction signature: a 3dp horizontal gradient
/// rule (teal→lime→gold→coral→red) under the app bar. Implements
/// [PreferredSizeWidget] → drop into `AppBar.bottom`. Brand-fixed (outside the
/// ColorScheme). Source: nox_scaffold.dart `NoxSplashHairline`.
class AppSplashHairlineWidget extends StatelessWidget implements PreferredSizeWidget {
  const AppSplashHairlineWidget({super.key});

  static const double _thickness = 3;
  static const double _gap = 14;
  static const double _radius = 2;
  static const LinearGradient _gradient = LinearGradient(
    colors: [NoxBrand.teal, NoxBrand.lime, NoxBrand.gold, NoxBrand.coral, NoxBrand.red],
  );

  @override
  Size get preferredSize => const Size.fromHeight(_thickness + _gap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Bottom gap is the unscaled `_gap` so the rendered height (_thickness + _gap)
      // matches `preferredSize` on every device (a scaled value would overflow AppBar.bottom).
      padding: EdgeInsets.fromLTRB(AppSpacingTokens.s16, 0, AppSpacingTokens.s16, _gap),
      child: Container(
        height: _thickness,
        decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(_radius)),
      ),
    );
  }
}

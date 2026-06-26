import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// Onboarding chrome — a centered, elevated card (surfaceContainerLowest, xl
/// radius, hairline outlineVariant border) whose head is the brand identity
/// (logo + `NOX` wordmark + splash hairline) above a screen-specific [child].
/// Used as the desktop layout of Login (2.1), Set username (2.3) and the
/// permission-denied state of QR scan (2.2). Source: desktop corpus
/// `04-login.md` / `05-username.md` / `06-qr.md` ("centered OnboardCard (440):
/// logo + wordmark + brand hairline, ...").
class AppOnboardCardWidget extends StatelessWidget {
  const AppOnboardCardWidget({super.key, required this.child, this.maxWidth});

  /// Screen-specific content below the head (fields + actions, or denied panel).
  final Widget child;

  /// Desktop card width cap; null falls back to `layout.onboardCardW` (440) — a
  /// token getter can't be a const default.
  final double? maxWidth;

  static double get _logoHeight => AppDimensionTokens.size.onboardLogoH;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacingTokens.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? AppDimensionTokens.layout.onboardCardW),
          child: Card(
            color: colorScheme.surfaceContainerLowest,
            elevation: NoxElevation.level2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensionTokens.radius.xl),
              side: BorderSide(color: colorScheme.outlineVariant, width: AppDimensionTokens.border.hairline),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppSpacingTokens.s32, AppSpacingTokens.s32, AppSpacingTokens.s32, AppSpacingTokens.s28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Assets.png.logo.image(height: _logoHeight),
                  SizedBox(height: AppSpacingTokens.s16),
                  const AppWordmarkWidget(),
                  const AppSplashHairlineWidget(),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

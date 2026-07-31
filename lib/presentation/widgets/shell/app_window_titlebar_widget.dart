import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// Faux desktop window chrome — the branded title strip drawn at the top of a
/// wide-window screen: a `surfaceContainerLow` strip with the NOX logo glyph + the
/// styled wordmark and an optional screen label (e.g. 'Sign in'), with the
/// brand-splash gradient hairline beneath it. This is NOT native OS window chrome;
/// truly hiding/replacing the native title bar (and its min/max/close controls) is
/// out of scope (desktop-infra phase). Reused by the onboarding desktop layouts,
/// the error screen and the desktop Chats shell.
class AppWindowTitlebarWidget extends StatelessWidget {
  const AppWindowTitlebarWidget({super.key, this.subtitle});

  /// Optional screen label shown after the wordmark (e.g. 'Sign in'). Null → wordmark only.
  final String? subtitle;

  static double get _height => AppDimensionTokens.size.windowTitlebarH;

  /// Compact wordmark size for the window titlebar strip (design TitleBar: 13).
  static const double _wordmarkSize = 13;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _height,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16),
          color: colorScheme.surfaceContainerLow,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Assets.png.logo.image(height: AppDimensionTokens.icon.md),
              SizedBox(width: AppSpacingTokens.s8),
              // Compact titlebar wordmark (design TitleBar: 13px, +0.14em), smaller
              // than the app-bar / card wordmark.
              const AppWordmarkWidget(fontSize: _wordmarkSize, letterSpacingEm: 0.14),
              if (subtitle != null) ...[
                SizedBox(width: AppSpacingTokens.s8),
                // Design: `— <label>` in bodyMedium regular (not middle-dot / titleSmall medium).
                Text('— $subtitle', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        const AppSplashHairlineWidget(),
      ],
    );
  }
}

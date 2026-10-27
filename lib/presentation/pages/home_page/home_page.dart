import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/pages/screens_gallery_page/screens_gallery_page.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// Minimal dev launcher (UI-kit + screens gallery). NOT mounted: the app boots to
/// `SplashPage` under the app-state spine, and the galleries are reached from the
/// Settings dev rows (kDebugMode). Retained as a standalone dev launcher; will be
/// dropped once real product features land.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static double get _heroSize => AppSpacingTokens.s96;
  static double get _heroGlyphSize => AppDimensionTokens.icon.hero;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const AppWordmarkWidget(), bottom: const AppSplashHairlineWidget(), actions: const [AppThemeToggle()]),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacingTokens.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _heroSize,
                height: _heroSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colorScheme.primaryContainer, shape: BoxShape.circle),
                child: AppIconWidget(NoxIcons.forumFill, size: _heroGlyphSize, color: colorScheme.onPrimaryContainer),
              ),
              SizedBox(height: AppSpacingTokens.s24),
              Text(context.l10n.uiKitTitle, style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface)),
              SizedBox(height: AppSpacingTokens.s8),
              Text(
                context.l10n.uiKitSubtitle,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: AppSpacingTokens.s32),
              FilledButton(onPressed: () => Navigator.of(context).push(UiKitPage.route()), child: Text(context.l10n.actionOpenUiKit)),
              SizedBox(height: AppSpacingTokens.s16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(ScreensGalleryPage.route()),
                child: Text(context.l10n.actionOpenScreens),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

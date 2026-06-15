import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/app/widgets/app_theme_toggle.dart';
import 'package:nox_app/presentation/pages/ui_kit_page/ui_kit_page.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_splash_hairline_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_wordmark_widget.dart';

/// App home for the current phase: a minimal launcher. No real product features
/// exist yet, so the start screen simply opens the UI-kit gallery. It will be
/// replaced by the real chats shell once product features land.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const double _heroSize = 96;
  static const double _heroGlyphSize = 48;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const AppWordmarkWidget(),
        bottom: const AppSplashHairlineWidget(),
        actions: const [AppThemeToggle()],
      ),
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
              Text(TextConstants.uiKitTitle, style: textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface)),
              SizedBox(height: AppSpacingTokens.s8),
              Text(
                TextConstants.uiKitSubtitle,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: AppSpacingTokens.s32),
              FilledButton(
                onPressed: () => Navigator.of(context).push(UiKitPage.route()),
                child: const Text(TextConstants.actionOpenUiKit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

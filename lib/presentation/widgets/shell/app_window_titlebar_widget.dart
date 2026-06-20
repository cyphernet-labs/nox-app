import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// Faux desktop title bar — a thin titled strip drawn at the top of a wide-window
/// screen (e.g. the error screen). This is NOT native OS window chrome; truly
/// hiding/replacing the native title bar is out of scope (desktop-infra phase).
/// Reused by onboarding desktop layouts later.
class AppWindowTitlebarWidget extends StatelessWidget {
  const AppWindowTitlebarWidget({super.key, required this.title});

  final String title;

  static const double _height = 40;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: _height,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Text(title, style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
    );
  }
}

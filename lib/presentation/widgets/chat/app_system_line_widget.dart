import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// Inline system line at the start of a thread (5.2): `Chat created by {username}`.
/// Not a message (no bubble). Centered `bodyMedium` on `onSurfaceVariant`.
class AppSystemLineWidget extends StatelessWidget {
  const AppSystemLineWidget({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s8, horizontal: AppSpacingTokens.s16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

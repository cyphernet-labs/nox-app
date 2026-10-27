import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';

/// Centered date capsule between days in the chat thread (5.2): `Today` /
/// `Yesterday` / `12 May` (see `DateFormatter.daySeparator`). `surfaceContainer`
/// pill, `labelMedium` on `onSurfaceVariant`.
class AppDateSeparatorWidget extends StatelessWidget {
  const AppDateSeparatorWidget({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s12, vertical: AppSpacingTokens.s4),
          decoration: BoxDecoration(color: colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(NoxRadius.full)),
          child: Text(label, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

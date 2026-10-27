import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';

/// Author label above a group of consecutive messages from the same other author
/// (5.2). Grouping uses the stable author id; the label shown is the author's
/// current display name. Own messages have no header. `titleMedium` on `onSurfaceVariant`.
class AppAuthorHeaderWidget extends StatelessWidget {
  const AppAuthorHeaderWidget({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: AppSpacingTokens.s8, bottom: AppSpacingTokens.s2, left: AppSpacingTokens.s4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';

/// Says that this person owns the server they are paired with (contract §3).
///
/// A widget rather than a private helper because ownership stops being a
/// settings-only fact with feature 034: once several people share a server, the
/// same mark is wanted wherever a person is named. A chip built inline would be
/// copied at that point rather than reused.
///
/// It renders only when the caller has an answer — the three-state rule lives
/// with whoever holds it, because "the server has not said" and "not the owner"
/// draw the same thing for different reasons.
///
/// Text, not an icon: the design corpus has no symbol for ownership, and adding
/// one is separate work with a separate owner. A word needs no legend.
class AppOwnerBadgeWidget extends StatelessWidget {
  const AppOwnerBadgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s8, vertical: AppSpacingTokens.s2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppDimensionTokens.radius.sm),
      ),
      child: Text(
        context.l10n.settingsOwnerBadge,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

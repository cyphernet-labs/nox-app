import 'package:flutter/material.dart';
import 'package:nox_app/presentation/widgets/primitives/app_hairline_divider_widget.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Identity card (7.1): a Name block (inline-editable) + `Your ID`
/// block (masked value + Copy / Show QR / optional reveal on one row). Parameterized
/// per layout (Principle I — minimize secret exposure):
///   - mobile: `revealable = true` → a Show/Hide toggle reveals the raw identifier;
///   - desktop: `revealable = false` (the raw ID is never shown); the account QR is
///     rendered as a separate block below the card (see settings_root_page).
/// While [initialLoading], a spinner stands in for the identifier (FR-038).
class AppIdentityCardWidget extends StatelessWidget {
  const AppIdentityCardWidget({
    super.key,
    required this.name,
    required this.maskedId,
    required this.rawId,
    required this.revealable,
    required this.initialLoading,
    required this.editing,
    required this.onEditName,
    required this.onCopy,
    required this.onShowQr,
    this.nameEditField,
    this.idRevealed = false,
    this.onToggleReveal,
  });

  final String name;
  final String maskedId;
  final String rawId;
  final bool revealable;
  final bool initialLoading;
  final bool editing;
  final VoidCallback onEditName;
  final VoidCallback onCopy;
  final VoidCallback onShowQr;
  final Widget? nameEditField;
  final bool idRevealed;
  final VoidCallback? onToggleReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _nameBlock(context),
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s12),
              child: const AppHairlineDividerWidget(),
            ),
            // Its own string. It used to borrow the login screen's label, and
            // when that became "Pairing link" this row started calling the
            // person's public author id a pairing link.
            Text(context.l10n.settingsYourIdLabel, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            SizedBox(height: AppSpacingTokens.s4),
            _idBlock(context),
          ],
        ),
      ),
    );
  }

  Widget _nameBlock(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    if (editing && nameEditField != null) return nameEditField!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.usernameLabel, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
        SizedBox(height: AppSpacingTokens.s2),
        Row(
          children: [
            Expanded(
              child: Text(name, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
            ),
            IconButton(
              tooltip: context.l10n.settingsNameEditTooltip,
              icon: AppIconWidget(NoxIcons.edit, size: AppDimensionTokens.icon.lg),
              onPressed: onEditName,
            ),
          ],
        ),
      ],
    );
  }

  Widget _idBlock(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    if (initialLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s8),
        child: AppSpinnerWidget(size: AppDimensionTokens.icon.lg),
      );
    }
    final revealed = revealable && idRevealed;
    final actions = <Widget>[
      if (revealable)
        IconButton(
          tooltip: idRevealed ? context.l10n.idHideTooltip : context.l10n.idShowTooltip,
          icon: AppIconWidget(idRevealed ? NoxIcons.visibilityOff : NoxIcons.visibility, size: AppDimensionTokens.icon.lg),
          onPressed: onToggleReveal,
        ),
      IconButton(
        tooltip: context.l10n.idCopyTooltip,
        icon: AppIconWidget(NoxIcons.contentCopy, size: AppDimensionTokens.icon.lg),
        onPressed: onCopy,
      ),
      IconButton(
        tooltip: context.l10n.idShowQrTooltip,
        icon: AppIconWidget(NoxIcons.qrCode, size: AppDimensionTokens.icon.lg),
        onPressed: onShowQr,
      ),
    ];
    // Revealed raw ID is long + monospace → keep it on its own line above the actions.
    if (revealed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rawId, style: AppTextStyleTokens.monoBody(color: colorScheme.onSurfaceVariant)),
          SizedBox(height: AppSpacingTokens.s4),
          Row(children: actions),
        ],
      );
    }
    // Masked (design): the masked value fills the row, actions aligned to its right.
    return Row(
      children: [
        Expanded(
          child: Text(maskedId, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
        ),
        ...actions,
      ],
    );
  }
}

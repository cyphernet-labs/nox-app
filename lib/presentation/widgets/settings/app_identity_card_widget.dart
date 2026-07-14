import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

/// Identity card (7.1): a Name block (inline-editable) + `Your ID`
/// block (masked, with Copy / Show QR / optional reveal). Parameterized per layout
/// (Principle I — minimize secret exposure):
///   - mobile: `revealable = true` → a Show/Hide toggle reveals the raw identifier;
///   - desktop: `revealable = false` (the raw ID is never shown) + `showInlineQr`
///     renders the account QR inline instead.
/// While [initialLoading], a spinner stands in for the identifier (FR-038).
class AppIdentityCardWidget extends StatelessWidget {
  const AppIdentityCardWidget({
    super.key,
    required this.name,
    required this.maskedId,
    required this.rawId,
    required this.revealable,
    required this.showInlineQr,
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
  final bool showInlineQr;
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _nameBlock(context),
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s12),
              child: Divider(height: AppDimensionTokens.border.hairline),
            ),
            Text(context.l10n.loginIdLabel, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            SizedBox(height: AppSpacingTokens.s4),
            _idBlock(context),
            if (showInlineQr && !initialLoading) ...[
              SizedBox(height: AppSpacingTokens.s16),
              Center(
                child: AppQrSurfaceWidget(data: rawId, size: AppDimensionTokens.size.qrSurface),
              ),
              SizedBox(height: AppSpacingTokens.s8),
              Center(
                child: Text(
                  context.l10n.qrAccountCaption,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nameBlock(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (initialLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacingTokens.s8),
        child: AppSpinnerWidget(size: AppDimensionTokens.icon.lg),
      );
    }
    final revealed = revealable && idRevealed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          revealed ? rawId : maskedId,
          style: revealed
              ? AppTextStyleTokens.monoBody(color: colorScheme.onSurfaceVariant)
              : textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s4),
        Row(
          children: [
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
          ],
        ),
      ],
    );
  }
}

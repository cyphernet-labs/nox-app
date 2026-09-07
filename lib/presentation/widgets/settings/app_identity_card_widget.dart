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
///   - `revealable = false` on both widths since feature 032: the id is the
///     PUBLIC author id, so there is nothing to hide behind a toggle. What the
///     row shows is what Copy copies. The reveal existed when this string was
///     the login secret;
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
    this.isOwner,
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

  /// Whether this person owns the server (contract §3).
  ///
  /// Three states, and only two of them draw anything: `true` shows the badge,
  /// `false` and `null` show nothing. They are kept apart anyway because they
  /// mean different things — `null` is "the server has not said yet" — and
  /// rendering "not the owner" before the answer arrives would be a claim the
  /// app is not entitled to make, followed by a flicker when it is corrected.
  final bool? isOwner;

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
            // Wrap, not a row of flexibles. Two flexible children would split
            // the free space by flex and cap the NAME at half of it: it would
            // ellipsize early with blank space beside it, badge or no badge.
            // Wrap gives the name the full width and drops the badge onto its
            // own line once it no longer fits - which is what happens at large
            // text scales and in the longer localisation.
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacingTokens.s8,
                runSpacing: AppSpacingTokens.s4,
                children: [
                  Text(name, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                  if (isOwner ?? false) _ownerBadge(context, theme),
                ],
              ),
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

  /// The badge itself. Text rather than an icon: the design corpus has no
  /// symbol for ownership, and adding one is a separate piece of work with a
  /// separate owner — while a word needs no legend.
  Widget _ownerBadge(BuildContext context, ThemeData theme) {
    // Theme handed in: the only caller resolved it two lines above the call,
    // and looking it up again buys nothing.
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
          // An em dash rather than a blank line: the id is simply not known
          // yet, and an empty row reads as a rendering fault.
          child: Text(maskedId.isEmpty ? '—' : maskedId, style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
        ),
        ...actions,
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/app_text_style_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_brand.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_ringed_avatar_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Identity card (7.1) — the account as a header: the ringed initials avatar the
/// shell already shows for this person, the name under it, the public id under
/// that, and two labelled tonal actions at the foot.
///
/// It used to be two label-over-value rows, each with a bare glyph pinned to the
/// far right. That is a form field's idiom with no form behind it; the glyph
/// carried no container, so nothing said it could be pressed; and in the desktop
/// Settings pane it sat most of a pane's width away from the value it acted on.
/// Naming the actions is the other half of the fix - a pencil has to be guessed
/// at, `Edit name` does not.
///
/// The Show/Hide reveal is gone with the rest: since feature 032 the id is the
/// PUBLIC author id, both call sites passed `revealable: false`, and a card that
/// shows the value in full has nothing left to reveal.
///
/// While [initialLoading] a spinner stands in for the id (FR-038).
class AppIdentityCardWidget extends StatelessWidget {
  const AppIdentityCardWidget({
    super.key,
    required this.name,
    required this.rawId,
    required this.initialLoading,
    required this.editing,
    required this.onEditName,
    required this.onCopy,
    this.nameEditField,
  });

  final String name;
  final String rawId;
  final bool initialLoading;
  final bool editing;
  final VoidCallback onEditName;
  final VoidCallback onCopy;

  /// The inline rename field, supplied by the page and shown in place of the name
  /// while [editing].
  final Widget? nameEditField;

  /// Stands in for an id the app does not have yet.
  static const String _unknownId = '—';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      // Zero, not Material's default 4: the caller places this card with the same
      // margin `AppSettingsGroupWidget` gives itself, and a 4 of its own put it
      // out of line with every card under it by exactly that much.
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s16, vertical: AppSpacingTokens.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: AppRingedAvatarWidget(name: name, initials: noxAccountInitials(name), size: AppDimensionTokens.size.avatarLg),
            ),
            SizedBox(height: AppSpacingTokens.s16),
            if (editing && nameEditField != null)
              nameEditField!
            else
              Text(
                name,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
              ),
            SizedBox(height: AppSpacingTokens.s8),
            _idLine(context),
            SizedBox(height: AppSpacingTokens.s20),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _idLine(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (initialLoading) return Center(child: AppSpinnerWidget(size: AppDimensionTokens.icon.lg));
    // An em dash rather than a blank line. `authorId` is null until a greeting
    // brings one - always, on the mock flavours, and for the window between
    // pairing and the first greeting on a live one - and `rawId` is then ''.
    // Rendered bare that is a ~23px gap between the name and the buttons, which
    // reads as a rendering fault rather than as "not known yet". The card this
    // replaced guarded the same case, and the guard was lost in the rewrite.
    //
    // Monospace, and the whole string: it is a key, and a key reads as one only
    // when its characters line up. `Copy ID` below is what it is here for.
    return Text(
      rawId.isEmpty ? _unknownId : rawId,
      textAlign: TextAlign.center,
      style: AppTextStyleTokens.monoBody(color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _actions(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final iconSize = AppDimensionTokens.icon.base;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacingTokens.s12,
      // Wrap, not Row: at a doubled text scale the two labels are wider than a
      // phone, and stacking them beats clipping one.
      runSpacing: AppSpacingTokens.s8,
      children: [
        // Withdrawn while the field is open. The state it offers to enter is the
        // one the card is already in, and a button that changes nothing is worse
        // than no button.
        if (!editing)
          FilledButton.tonalIcon(
            onPressed: onEditName,
            icon: AppIconWidget(NoxIcons.edit, size: iconSize, color: colorScheme.onSecondaryContainer),
            label: Text(l10n.settingsEditNameAction),
          ),
        // Disabled while there is no id. `_copyId` already refuses to write an
        // empty clipboard - confirming one would leave somebody pasting nothing -
        // so an enabled button here is a button that does nothing and says nothing.
        FilledButton.tonalIcon(
          onPressed: rawId.isEmpty ? null : onCopy,
          icon: AppIconWidget(NoxIcons.contentCopy, size: iconSize, color: colorScheme.onSecondaryContainer),
          label: Text(l10n.settingsCopyIdAction),
        ),
      ],
    );
  }
}

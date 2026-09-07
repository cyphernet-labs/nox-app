@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/l10n/app_localizations_en.dart';
import 'package:nox_app/presentation/widgets/settings/app_identity_card_widget.dart';

import '../../../utils/golden.dart';

final l10nEn = AppLocalizationsEn();

void main() {
  goldenTest(
    'app_identity_card_widget',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppIdentityCardWidget(
        name: 'Aria',
        maskedId: l10nEn.idMask,
        rawId: 'RAWID-0123456789',
        revealable: true,
        initialLoading: false,
        editing: false,
        onToggleReveal: () {},
        onEditName: () {},
        onCopy: () {},
        onShowQr: () {},
      ),
    ),
  );

  // The owner's variant. Its own baseline rather than a flag on the one above:
  // the badge sits on the name row, and a row that has to fit a name, a badge
  // and an edit button is exactly where a layout regression would hide.
  goldenTest(
    'app_identity_card_widget_owner',
    () => Padding(
      padding: const EdgeInsets.all(16),
      child: AppIdentityCardWidget(
        name: 'Aria',
        maskedId: l10nEn.idMask,
        rawId: 'RAWID-0123456789',
        revealable: true,
        initialLoading: false,
        editing: false,
        isOwner: true,
        onToggleReveal: () {},
        onEditName: () {},
        onCopy: () {},
        onShowQr: () {},
      ),
    ),
  );
}

import 'package:flutter/widgets.dart';
import 'package:nox_app/l10n/app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)` so widgets read localized copy as
/// `context.l10n.chats`. The generated getters are the migration target for the
/// [TextConstants] strings (i18n rollout, batch by screen).
extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

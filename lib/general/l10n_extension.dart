import 'package:flutter/widgets.dart';
import 'package:nox_app/l10n/app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)` so widgets read localized copy as
/// `context.l10n.chats`. All user-facing strings live in the ARB (`lib/l10n/*.arb`,
/// EN + UK) and are reached through these generated getters.
extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

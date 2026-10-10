import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/l10n/app_localizations.dart';

/// The message each cause of a failed connection has (phase 045, FR-017):
/// one place, so the banners of 5.1, 5.2 and 5.4, Settings > Connection and
/// the connection screen can never word the same cause two ways.
extension ConnectionProblemText on ConnectionProblem {
  String text(AppLocalizations l10n) => switch (this) {
    ConnectionProblem.invalidOnion => l10n.connectionProblemInvalidOnion,
    ConnectionProblem.onionNotFound => l10n.connectionProblemOnionNotFound,
    ConnectionProblem.onionUnreachable => l10n.connectionProblemOnionUnreachable,
    ConnectionProblem.otherServer => l10n.connectionProblemOtherServer,
    ConnectionProblem.torNetwork => l10n.connectionProblemTorNetwork,
    ConnectionProblem.turnOnTor => l10n.connectionProblemTurnOnTor,
  };
}

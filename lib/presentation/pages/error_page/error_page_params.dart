import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';

/// Display mode of the universal error screen (3.1).
/// - [blocking]: no back affordance, last in the stack (system back minimizes the app).
/// - [embedded]: has a back arrow; returns to the previous screen.
enum ErrorPageMode { blocking, embedded }

/// Which localized copy the universal error screen renders. Params carry only the
/// discriminator — the title/message strings are resolved from `context.l10n` at
/// render time (i18n), never baked into these no-context params.
/// - [fatal]: fatal/unexpected error copy.
/// - [network]: network/connectivity error copy.
enum ErrorPageKind { fatal, network }

/// Immutable parameters for the universal error screen. The icon is a NOX SVG
/// glyph ([SvgGenImage]) — never a Material icon font (FR-025). `onRetry` is the
/// caller-owned recovery action; while it runs the `Try again` button shows a spinner.
class ErrorPageParams {
  const ErrorPageParams({required this.icon, required this.kind, this.mode = ErrorPageMode.embedded, this.onRetry});

  final SvgGenImage icon;
  final ErrorPageKind kind;
  final ErrorPageMode mode;
  final Future<void> Function()? onRetry;

  /// Fatal/unexpected error — blocking by default (last in the stack).
  factory ErrorPageParams.fatal({ErrorPageMode mode = ErrorPageMode.blocking, Future<void> Function()? onRetry}) =>
      ErrorPageParams(icon: NoxIcons.error, kind: ErrorPageKind.fatal, mode: mode, onRetry: onRetry);

  /// Network/connectivity error — embedded by default.
  factory ErrorPageParams.network({ErrorPageMode mode = ErrorPageMode.embedded, Future<void> Function()? onRetry}) =>
      ErrorPageParams(icon: NoxIcons.error, kind: ErrorPageKind.network, mode: mode, onRetry: onRetry);
}

import 'package:nox_app/design/gen/assets.gen.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/text_constants.dart';

/// Display mode of the universal error screen (3.1).
/// - [blocking]: no back affordance, last in the stack (system back minimizes the app).
/// - [embedded]: has a back arrow; returns to the previous screen.
enum ErrorPageMode { blocking, embedded }

/// Immutable parameters for the universal error screen. The icon is a NOX SVG
/// glyph ([SvgGenImage]) — never a Material icon font (FR-025). `onRetry` is the
/// caller-owned recovery action; while it runs the `Try again` button shows a spinner.
class ErrorPageParams {
  const ErrorPageParams({required this.icon, required this.title, required this.message, this.mode = ErrorPageMode.embedded, this.onRetry});

  final SvgGenImage icon;
  final String title;
  final String message;
  final ErrorPageMode mode;
  final Future<void> Function()? onRetry;

  /// Fatal/unexpected error — blocking by default (last in the stack).
  factory ErrorPageParams.fatal({ErrorPageMode mode = ErrorPageMode.blocking, Future<void> Function()? onRetry}) => ErrorPageParams(
    icon: NoxIcons.error,
    title: TextConstants.errorGeneralTitle,
    message: TextConstants.errorFatalMessage,
    mode: mode,
    onRetry: onRetry,
  );

  /// Network/connectivity error — embedded by default.
  factory ErrorPageParams.network({ErrorPageMode mode = ErrorPageMode.embedded, Future<void> Function()? onRetry}) => ErrorPageParams(
    icon: NoxIcons.error,
    title: TextConstants.noConnection,
    message: TextConstants.errorNetworkMessage,
    mode: mode,
    onRetry: onRetry,
  );
}

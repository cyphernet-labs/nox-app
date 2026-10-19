import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// What became of the logout the dialog asked about.
enum LogoutDialogResult { cancelled, done, failed }

/// Logout confirmation dialog (7.1). On confirm it runs [logout] itself and stays
/// modal (back blocked, both buttons off) with a spinner in the destructive button
/// until the logout has gone through - the device revokes its own key, then the
/// whole local wipe runs - and only then answers. `Cancel` answers
/// [LogoutDialogResult.cancelled]. A logout that went through replaces the whole
/// stack with the pairing screen, this dialog included, so the answer may never
/// arrive; a failed one closes the dialog as [LogoutDialogResult.failed] for the
/// caller to say so.
class AppLogoutDialogWidget extends StatefulWidget {
  const AppLogoutDialogWidget({super.key, this.logout});

  /// Runs the logout; `true` when it went through. Null in the gallery, where
  /// there is nothing to run and confirming answers at once.
  final Future<bool> Function()? logout;

  /// Shows the dialog and resolves to how it ended.
  static Future<LogoutDialogResult?> show(BuildContext context, {Future<bool> Function()? logout}) => showDialog<LogoutDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppLogoutDialogWidget(logout: logout),
  );

  @override
  State<AppLogoutDialogWidget> createState() => _AppLogoutDialogWidgetState();
}

class _AppLogoutDialogWidgetState extends State<AppLogoutDialogWidget> {
  bool _loading = false;

  Future<void> _confirm() async {
    if (_loading) return;
    setState(() => _loading = true);
    final logout = widget.logout;
    final done = logout == null || await logout();
    if (!mounted) return;
    // Its OWN route, not whatever is on top: the request dialog 8.2 can come up
    // over this one while the logout runs, and a plain pop would close that
    // instead - leaving this dialog spinning for good.
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final result = done ? LogoutDialogResult.done : LogoutDialogResult.failed;
    if (route.isCurrent) {
      Navigator.of(context).pop(result);
    } else {
      Navigator.of(context).removeRoute(route, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope<Object?>(
      canPop: !_loading, // modal until the logout has gone through
      child: AlertDialog(
        title: Text(context.l10n.logoutDialogTitle),
        content: Text(context.l10n.logoutDialogMessage),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(LogoutDialogResult.cancelled),
            child: Text(context.l10n.actionCancel),
          ),
          TextButton(
            onPressed: _loading ? null : _confirm,
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: _loading ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.error) : Text(context.l10n.logoutRow),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// Logout confirmation dialog (7.1). Self-contained: on confirm it shows a loading
/// spinner in the destructive button and stays modal (back blocked) while a stubbed
/// local wipe runs, then pops with `true`. `Cancel` pops with `false`. The caller
/// navigates to Splash (1.1) on `true`. `// TODO(backend):` real full local wipe of
/// the identifier + local data.
class AppLogoutDialogWidget extends StatefulWidget {
  const AppLogoutDialogWidget({super.key});

  /// Shows the dialog; resolves to `true` when logout was confirmed and completed.
  static Future<bool?> show(BuildContext context) =>
      showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const AppLogoutDialogWidget());

  @override
  State<AppLogoutDialogWidget> createState() => _AppLogoutDialogWidgetState();
}

class _AppLogoutDialogWidgetState extends State<AppLogoutDialogWidget> {
  bool _loading = false;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    // TODO(backend): wipe the identifier + all local data, then sign out.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope<Object?>(
      canPop: !_loading, // modal until the wipe completes
      child: AlertDialog(
        title: const Text(TextConstants.logoutDialogTitle),
        content: const Text(TextConstants.logoutDialogMessage),
        actions: [
          TextButton(onPressed: _loading ? null : () => Navigator.of(context).pop(false), child: const Text(TextConstants.actionCancel)),
          FilledButton(
            onPressed: _loading ? null : _confirm,
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
            child: _loading
                ? AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.onError)
                : const Text(TextConstants.logoutRow),
          ),
        ],
      ),
    );
  }
}

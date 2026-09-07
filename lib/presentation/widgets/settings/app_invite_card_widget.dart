import 'package:flutter/material.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/settings/app_qr_surface_widget.dart';

/// A freshly minted pairing link, shown as a QR and as text.
///
/// Shared between 7.3 Devices and 7.4 People because the two differ in exactly
/// one thing — how long the link lives, which the caller states in [message].
/// Everything else is identical, and a second copy would drift the moment one
/// of them changed.
///
/// The text under the QR matters as much as the code: Windows and Linux have no
/// camera, so copying is the only path that works everywhere.
class AppInviteCardWidget extends StatelessWidget {
  const AppInviteCardWidget({super.key, required this.link, required this.message, required this.onDismiss});

  final String link;

  /// What this particular link is and how long it lasts.
  final String message;

  /// "Hide", never "Cancel": nothing here revokes anything. The token stays
  /// usable for its whole life whatever this button says, and calling it Cancel
  /// would promise a revocation that does not happen.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacingTokens.s16),
        child: Column(
          children: [
            AppQrSurfaceWidget(data: link),
            SizedBox(height: AppSpacingTokens.s12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: AppSpacingTokens.s8),
            SelectableText(link, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            TextButton(onPressed: onDismiss, child: Text(context.l10n.actionHide)),
          ],
        ),
      ),
    );
  }
}

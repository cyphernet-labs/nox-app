import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/l10n/app_localizations.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// The question a device is asked when a new device presents an invite it
/// issued (phase 046, FR-008): `New device: <family>. Allow it to join?`, with
/// `Deny` and `Allow`. Shown by AppRoot over whatever screen is up, on both
/// widths, for as long as the request waits and the app is connected.
///
/// Presentational: the answer goes out through [onAnswer], and AppRoot closes
/// the dialog when the request is over - answered here, refused by its time,
/// or withdrawn by the new device. There is no way to put it aside unanswered:
/// the barrier, back and Escape do nothing, because a request left standing
/// would only come back.
class AppPairRequestDialogWidget extends StatelessWidget {
  const AppPairRequestDialogWidget({super.key, required this.platform, this.answering, this.failed = false, this.onAnswer});

  /// The new device's OS family - one of the app's own words, never text from
  /// the wire.
  final DevicePlatform platform;

  /// The answer on its way - `true` for Allow, `false` for Deny - or null.
  final bool? answering;

  /// The last answer did not get through.
  final bool failed;

  /// Sends the answer: `true` for Allow. Null when there is nothing left to
  /// answer.
  final ValueChanged<bool>? onAnswer;

  /// The family as the dialog names it.
  static String platformName(AppLocalizations l10n, DevicePlatform platform) => switch (platform) {
    DevicePlatform.ios => l10n.devicePlatformIos,
    DevicePlatform.android => l10n.devicePlatformAndroid,
    DevicePlatform.macos => l10n.devicePlatformMacos,
    DevicePlatform.windows => l10n.devicePlatformWindows,
    DevicePlatform.linux => l10n.devicePlatformLinux,
    DevicePlatform.unknown => l10n.devicePlatformUnknown,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final answer = onAnswer;
    final enabled = answer != null && answering == null;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: AppIconWidget(NoxIcons.devices, color: colorScheme.secondary),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.pairRequestMessage(platformName(l10n, platform)),
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
            ),
            if (failed) ...[
              SizedBox(height: AppSpacingTokens.s12),
              // A live region: the line appears under a dialog the person is
              // already in, and assistive technology has to say it.
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.pairRequestAnswerError,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: enabled ? () => answer(false) : null,
            child: answering == false ? _spinner(colorScheme) : Text(l10n.pairRequestDeny),
          ),
          TextButton(
            onPressed: enabled ? () => answer(true) : null,
            child: answering == true ? _spinner(colorScheme) : Text(l10n.pairRequestAllow),
          ),
        ],
      ),
    );
  }

  Widget _spinner(ColorScheme colorScheme) => AppSpinnerWidget(size: AppDimensionTokens.icon.md, color: colorScheme.primary);
}

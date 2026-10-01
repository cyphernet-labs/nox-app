import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/general/l10n_extension.dart';

/// What a transfer says in words: `Sending… 45%` under a file, and the name a
/// screen reader gives the ring over a picture.
///
/// A download has no percent caption of its own on screen - the only thing a
/// received picture shows is the ring - so its words are the ones the file
/// view already uses.
String transferCaption(BuildContext context, AttachmentTransfer transfer) {
  final l10n = context.l10n;
  final percent = transfer.percent;
  return switch (transfer.direction) {
    TransferDirection.upload => percent == null ? l10n.transferSending : l10n.transferSendingProgress(percent),
    TransferDirection.download => percent == null ? l10n.transferDownloading : l10n.downloadingProgress(percent),
  };
}

/// The ring of a transfer (5.2): it spins until the first bytes move, then
/// fills with them. Indeterminate first because asking the server for a pass
/// can take seconds through Tor, and a ring parked at zero would look stuck.
class AppTransferRingWidget extends StatelessWidget {
  const AppTransferRingWidget({super.key, required this.transfer, this.size, this.color, this.trackColor});

  final AttachmentTransfer transfer;

  /// Null falls back to `icon.xl` (24), the spinner's own size.
  final double? size;

  /// Null falls back to `primary`, the spinner's own colour, so a placeholder
  /// swapping its spinner for this ring does not change colour mid-fetch.
  final Color? color;

  /// The unfilled part, once there is a fraction to fill. Null falls back to
  /// [color] at the disabled alpha, the same track the file chip's bar has:
  /// without one, 30% of a ring is an arc that looks like a spinner frame.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? AppDimensionTokens.icon.xl;
    final percent = transfer.percent;
    final ring = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: dimension,
      height: dimension,
      child: CircularProgressIndicator(
        value: transfer.fraction,
        strokeWidth: AppDimensionTokens.border.heavy,
        color: ring,
        // No track while spinning: the spinner it replaces has none.
        backgroundColor: transfer.fraction == null ? null : trackColor ?? ring.withValues(alpha: NoxOpacity.disabled),
        semanticsLabel: switch (transfer.direction) {
          TransferDirection.upload => context.l10n.transferSending,
          TransferDirection.download => context.l10n.transferDownloading,
        },
        // Floored like the caption: a ring announced as 100% must be done.
        semanticsValue: percent == null ? null : '$percent%',
      ),
    );
  }
}

/// The ring over a picture whose bytes are being sent (5.2). The disc behind
/// it is the contrast pair the draft thumbnail's remove button already uses,
/// because a ring drawn straight onto an unknown photo can vanish into it.
class AppTransferBadgeWidget extends StatelessWidget {
  const AppTransferBadgeWidget({super.key, required this.transfer});

  final AttachmentTransfer transfer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final diameter = AppDimensionTokens.size.transferBadge;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface.withValues(alpha: NoxOpacity.scrim),
        shape: BoxShape.circle,
      ),
      child: AppTransferRingWidget(
        transfer: transfer,
        size: AppDimensionTokens.icon.glyph,
        color: colorScheme.onInverseSurface,
        trackColor: colorScheme.onInverseSurface.withValues(alpha: NoxOpacity.disabled),
      ),
    );
  }
}

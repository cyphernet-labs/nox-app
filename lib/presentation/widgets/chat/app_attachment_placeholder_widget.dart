import 'package:flutter/material.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/presentation/widgets/chat/app_image_attachment_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_spinner_widget.dart';

/// A picture that has arrived as a message but whose bytes are still coming
/// (5.2).
///
/// It exists because the honest state was missing from the screen. A received
/// image is fetched by `AttachmentPrefetchService` the moment the thread loads,
/// but that happens silently: until this widget, the person saw a type chip —
/// the same inert thing an unopenable file shows — and reasonably concluded
/// nothing was happening. Then they tapped it, which started a SECOND download
/// of the same bytes through the file screen, and only that one had a progress
/// bar. The bytes were always on their way; nothing said so.
///
/// It occupies exactly the thumbnail's box, so the bubble does not jump when
/// the picture replaces it — the swap is the image appearing, not the layout
/// rearranging around it.
///
/// Deliberately not a failure surface. A fetch that will never succeed (the
/// server no longer has the file) still shows this, and the honest report lives
/// one tap away on the file screen, which already says `attachmentGone` in the
/// words the contract gives it. Surfacing that inline needs the prefetch
/// service's per-message verdict, which it does not publish yet.
class AppAttachmentPlaceholderWidget extends StatelessWidget {
  const AppAttachmentPlaceholderWidget({super.key, required this.name, this.width, this.height, this.onTap});

  /// Whether [attachment] should stand in for a picture still arriving, rather
  /// than draw the type chip.
  ///
  /// [inBubble] is what separates a received message from a composer draft: a
  /// draft's file is on disk by the time it is a draft, and nothing is fetching
  /// it, so a spinner there would wait for an event that never comes.
  static bool wants(MessageAttachment attachment, {required bool inBubble}) =>
      inBubble && !AppImageAttachmentWidget.canRender(attachment) && AppImageAttachmentWidget.wouldRender(attachment);

  /// The file's name — not drawn, but spoken: a screen reader otherwise meets an
  /// unlabelled box where a picture is going to be.
  final String name;

  final double? width;
  final double? height;

  /// Opens the file screen, which is where a real failure is reported.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: name,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NoxRadius.xs),
          child: Container(
            width: width ?? AppDimensionTokens.layout.imageThumbMaxW,
            height: height ?? AppDimensionTokens.layout.imageThumbMaxH,
            color: colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            // The glyph, not the spinner, is what makes the box legible at a
            // glance: a bare indeterminate ring in an empty rectangle says
            // "something" is happening, while a picture glyph says WHAT is.
            // It also gives the state a readable first frame - a golden of a
            // spinner alone is a dot.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconWidget(
                  NoxIcons.image,
                  size: AppDimensionTokens.icon.lg,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: NoxOpacity.disabled),
                ),
                SizedBox(height: AppSpacingTokens.s8),
                AppSpinnerWidget(size: AppDimensionTokens.icon.base),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Inline image attachment (feature F4): renders the picture itself (from the device-
/// local [localPath]) as a rounded thumbnail; tapping it opens the full-screen viewer.
/// A compact size + [onRemove] × turns it into the composer draft preview (P2). If the
/// file cannot be decoded/read (stale path after restart, deleted file), it falls back
/// GRACEFULLY to the [AppFileChipWidget] — never a broken image. Only used for
/// [FileType.image] attachments with an existing local file; every other case renders
/// the chip (callers gate via [canRender]).
class AppImageAttachmentWidget extends StatelessWidget {
  const AppImageAttachmentWidget({
    super.key,
    required this.localPath,
    required this.type,
    required this.name,
    required this.size,
    this.inBubble = true,
    this.onColor,
    this.onTap,
    this.width,
    this.height,
    this.onRemove,
  });

  final String localPath;
  final FileType type;
  final String name;
  final String size; // pre-formatted, for the fallback chip
  final bool inBubble;
  final Color? onColor;
  final VoidCallback? onTap;

  /// Thumbnail box size override (defaults to the bubble thumbnail size). The composer
  /// draft (P2) passes a compact square.
  final double? width;
  final double? height;

  /// When set, overlays a remove × (composer draft preview) — mirrors the chip's remove.
  final VoidCallback? onRemove;

  /// Raster formats Flutter's native codec decodes on ALL five targets. SVG (no native
  /// support anywhere) is excluded so an image-typed file that can't be decoded stays a
  /// normal, tappable file chip (→ File view) rather than a thumbnail whose tap opens a
  /// viewer that can only fail. HEIC is handled separately (Apple-only), see [canRender].
  static const Set<String> _universalDecodableExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  /// Whether [attachment] should render as an inline thumbnail (vs the type-icon chip):
  /// an image whose local file exists and is in a natively-decodable raster format —
  /// keeps the tap destination (viewer) consistent with what actually renders.
  static bool canRender(MessageAttachment attachment) {
    final path = attachment.localPath;
    if (attachment.type != FileType.image || path == null || path.isEmpty || !File(path).existsSync()) return false;
    final ext = attachment.name.contains('.') ? attachment.name.split('.').last.toLowerCase() : '';
    if (_universalDecodableExtensions.contains(ext)) return true;
    // HEIC: Flutter's native codec decodes it on Apple targets (iOS/macOS) but NOT on
    // Linux/Windows/Android — so thumbnail it only there (P7); elsewhere it stays a chip.
    if (ext == 'heic') return Platform.isIOS || Platform.isMacOS;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final chipFallback = Center(
      child: AppFileChipWidget(type: type, name: name, size: size, inBubble: inBubble, onColor: onColor),
    );
    Widget content = Semantics(
      image: true,
      label: name, // screen-reader name for the picture (a11y)
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NoxRadius.xs),
          child: Image.file(
            File(localPath),
            // A stable thumbnail box (no layout jump while decoding, and a definite tap
            // target); the picture is cropped to fill it.
            width: width ?? AppDimensionTokens.layout.imageThumbMaxW,
            height: height ?? AppDimensionTokens.layout.imageThumbMaxH,
            fit: BoxFit.cover,
            // Any decode/read failure → the type-icon chip (graceful, FR-007).
            errorBuilder: (context, error, stackTrace) => chipFallback,
          ),
        ),
      ),
    );
    if (onRemove != null) {
      final colorScheme = Theme.of(context).colorScheme;
      content = Stack(
        children: [
          content,
          Positioned(
            top: AppSpacingTokens.s4,
            right: AppSpacingTokens.s4,
            // inverseSurface + onInverseSurface = a contrast-guaranteed pair in BOTH
            // themes (over an unpredictable photo); a ≥48 tap target (a11y), which still
            // fits the 72 box (4 + 48 = 52 < 72).
            child: Material(
              color: colorScheme.inverseSurface.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: context.l10n.tooltipRemove,
                onPressed: onRemove,
                icon: AppIconWidget(NoxIcons.close, size: AppDimensionTokens.icon.lg, color: colorScheme.onInverseSurface),
              ),
            ),
          ),
        ],
      );
    }
    return content;
  }
}

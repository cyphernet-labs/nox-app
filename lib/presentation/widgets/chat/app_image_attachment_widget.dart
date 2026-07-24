import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/presentation/widgets/chat/app_file_chip_widget.dart';

/// Inline image attachment (feature F4): renders the picture itself (from the device-
/// local [localPath]) as a rounded, bubble-bounded thumbnail; tapping it opens the
/// full-screen viewer. If the file cannot be decoded/read (stale path after restart,
/// deleted file), it falls back GRACEFULLY to the [AppFileChipWidget] — never a broken
/// image. Only used for [FileType.image] attachments that have an existing local file;
/// every other case renders the chip (the thread view guards the choice).
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
  });

  final String localPath;
  final FileType type;
  final String name;
  final String size; // pre-formatted, for the fallback chip
  final bool inBubble;
  final Color? onColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chipFallback = Center(
      child: AppFileChipWidget(type: type, name: name, size: size, inBubble: inBubble, onColor: onColor),
    );
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NoxRadius.xs),
        child: Image.file(
          File(localPath),
          // A stable thumbnail box (no layout jump while decoding, and a definite tap
          // target); the picture is cropped to fill it.
          width: AppDimensionTokens.layout.imageThumbMaxW,
          height: AppDimensionTokens.layout.imageThumbMaxH,
          fit: BoxFit.cover,
          // Any decode/read failure → the type-icon chip (graceful, FR-007).
          errorBuilder: (context, error, stackTrace) => chipFallback,
        ),
      ),
    );
  }
}

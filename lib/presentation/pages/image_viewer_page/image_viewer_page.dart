import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nox_app/presentation/helpers/adaptive_lightbox.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';

/// Open the full-screen image viewer (feature F4) adaptively: mobile pushes a full
/// screen; desktop shows a centered lightbox dialog (mirrors `showFileView`). The tap
/// target is the inline image thumbnail in the chat thread (5.2).
Future<void> openImageViewer(BuildContext context, String localPath) => showAdaptiveLightbox(
  context,
  dialogChild: () => ImageViewerPage(localPath: localPath, inDialog: true),
  route: () => ImageViewerPage.route(localPath),
  insetPadding: EdgeInsets.all(AppSpacingTokens.s24),
);

/// Full-screen image viewer (feature F4). Zoomable ([InteractiveViewer]) view of the
/// picked/sent image at [localPath], with close/back. A missing/unreadable file shows a
/// graceful placeholder (never a crash / broken image). Local state only — no BLoC
/// (blueprint 05 §5.1 carve-out for a presentational screen).
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.localPath, this.inDialog = false});

  final String localPath;

  /// When shown inside the desktop lightbox [Dialog], drop the full-screen Scaffold.
  final bool inDialog;

  static Route<void> route(String localPath) => MaterialPageRoute<void>(
    builder: (_) => ImageViewerPage(localPath: localPath),
    settings: const RouteSettings(name: '/image'),
  );

  @override
  Widget build(BuildContext context) {
    if (inDialog) {
      // Desktop lightbox: the viewer + a visible close affordance (the Dialog is also
      // barrier-dismissible, but a visible control matches showFileView's panel header).
      return Stack(
        children: [
          _viewer(context, maxHeightFactor: 0.8),
          Positioned(
            top: AppSpacingTokens.s8,
            right: AppSpacingTokens.s8,
            child: IconButton(
              tooltip: context.l10n.actionClose,
              icon: AppIconWidget(NoxIcons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.scrim,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onInverseSurface,
        leading: IconButton(
          tooltip: context.l10n.actionClose,
          icon: AppIconWidget(NoxIcons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _viewer(context),
    );
  }

  Widget _viewer(BuildContext context, {double? maxHeightFactor}) {
    Widget image = Image.file(File(localPath), fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => _missing(context));
    if (maxHeightFactor != null) {
      image = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor),
        child: image,
      );
    }
    return Center(child: InteractiveViewer(minScale: 1, maxScale: 5, child: image));
  }

  Widget _missing(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onColor = inDialog ? colorScheme.onSurfaceVariant : colorScheme.onInverseSurface;
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconWidget(NoxIcons.image, size: AppDimensionTokens.icon.heroLg, color: onColor),
          SizedBox(height: AppSpacingTokens.s12),
          Text(context.l10n.imageUnavailable, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onColor)),
        ],
      ),
    );
  }
}

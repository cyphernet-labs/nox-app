import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:nox_app/presentation/helpers/adaptive_lightbox.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';
import 'package:nox_app/general/l10n_extension.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_panel_header_widget.dart';

/// Open the file view (5.3) adaptively: mobile pushes the full screen; desktop
/// shows a centered lightbox dialog (corpus `08-file`). The tap target lives in the
/// chat thread (5.2) and the chat card (5.4).
Future<void> showFileView(BuildContext context, MessageAttachment file) => showAdaptiveLightbox(
  context,
  dialogChild: () => FileViewPage(file: file, inDialog: true),
  route: () => FileViewPage.route(file),
  maxWidth: AppDimensionTokens.layout.contentMaxW,
);

/// 5.3 File view — inspect / download a file attachment. No content preview: only
/// the type glyph, name and size. Auto-downloads to cache with a determinate
/// progress bar, then enables Save (to Downloads). UI-phase stub: the progress is
/// timer-driven and Save is a no-op + snackbar (`// TODO(backend):`). Local state
/// only — no BLoC (blueprint 05 §5.1 carve-out for a presentational screen).
class FileViewPage extends StatefulWidget {
  const FileViewPage({super.key, required this.file, this.demo = false, this.inDialog = false});

  final MessageAttachment file;
  final bool demo;

  /// When shown inside the desktop lightbox [Dialog], render the lightbox content
  /// only (the Dialog provides the surface + scrim).
  final bool inDialog;

  static Route<void> route(MessageAttachment file) => MaterialPageRoute<void>(
    builder: (_) => FileViewPage(file: file),
    settings: const RouteSettings(name: '/file'),
  );

  /// Gallery entry: a sample file with the dev download controls.
  static Route<void> routeDemo() => MaterialPageRoute<void>(
    builder: (_) => const FileViewPage(file: _sampleFile, demo: true),
    settings: const RouteSettings(name: '/file'),
  );

  static const MessageAttachment _sampleFile = MessageAttachment(
    id: 'sample',
    type: FileType.pdf,
    name: 'design-spec.pdf',
    sizeBytes: 2516582,
  );

  @override
  State<FileViewPage> createState() => _FileViewPageState();
}

class _FileViewPageState extends State<FileViewPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _cached = false;

  @override
  void initState() {
    super.initState();
    // TODO(backend): real download + cache (Phase 2). UI-phase: a timed progress.
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) setState(() => _cached = true);
      });
    _startDownload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startDownload() {
    // A real local file (picked/sent, feature 020) already has its bytes on disk —
    // there is nothing to fetch, so enable Save immediately (P4). Only a seeded /
    // backend-sourced file with no local copy runs the timed mock "download", which
    // stands in for the real network fetch (TBD until the backend lands).
    final path = widget.file.localPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      _controller.stop();
      setState(() => _cached = true);
      return;
    }
    setState(() => _cached = false);
    _controller.forward(from: 0);
  }

  Future<void> _save() async {
    final path = widget.file.localPath;
    // No real local file (seeded / backend-TBD / stale path after restart) → the honest
    // UI-phase mock confirmation (there are no bytes to copy).
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      showAppSnackBar(context, text: context.l10n.savedToDownloads);
      return;
    }
    try {
      // Real save (F2): the user picks a destination, then the file is copied there.
      final dest = await getIt<FilePickerService>().pickSaveLocation(suggestedName: widget.file.name);
      if (dest == null || !mounted) return; // cancelled
      // Streamed copy — never materializes the whole file in RAM (Save is reachable for
      // any type, incl. large video/archive attachments).
      await File(path).copy(dest);
      if (!mounted) return;
      showAppSnackBar(context, text: context.l10n.savedToDownloads);
    } catch (_) {
      // Any IO failure degrades gracefully — never a crash.
      if (!mounted) return;
      showAppSnackBar(context, text: context.l10n.fileDownloadError, error: true);
    }
  }

  void _simulateError() {
    _controller.stop();
    setState(() {});
    showAppSnackBar(
      context,
      text: context.l10n.fileDownloadError,
      actionLabel: context.l10n.actionTryAgain,
      onAction: _startDownload,
      error: true,
    );
  }

  double get _progress => _controller.value;

  int get _percent => (_controller.value * 100).round();

  @override
  Widget build(BuildContext context) {
    if (widget.inDialog) return _lightboxContent(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Constants.railBreakpoint;
        return wide ? _wide(context) : _mobile(context);
      },
    );
  }

  // ---- Mobile (full screen) --------------------------------------------------

  Widget _mobile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          tooltip: context.l10n.tooltipBack,
          icon: AppIconWidget(NoxIcons.arrowBack),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: context.l10n.tooltipSave,
            onPressed: _cached ? _save : null,
            icon: AppIconWidget(
              NoxIcons.download,
              color: _cached ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: NoxOpacity.disabled),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_cached) LinearProgressIndicator(value: _progress),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s32),
              child: _info(context),
            ),
          ),
          if (kDebugMode && widget.demo) Align(alignment: Alignment.bottomCenter, child: _debugControls()),
        ],
      ),
    );
  }

  // ---- Desktop standalone (lightbox over a scrim) ----------------------------

  Widget _wide(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.scrim.withValues(alpha: NoxOpacity.scrim),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.of(context).maybePop()),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.contentMaxW),
              child: Padding(
                padding: EdgeInsets.all(AppSpacingTokens.s24),
                child: Material(
                  color: colorScheme.surfaceContainerHigh,
                  elevation: NoxElevation.level5,
                  borderRadius: BorderRadius.circular(NoxRadius.xl),
                  clipBehavior: Clip.antiAlias,
                  child: _lightboxContent(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Lightbox content (shared by the dialog + the wide scaffold) -----------

  Widget _lightboxContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPanelHeaderWidget(title: widget.file.name, onClose: () => Navigator.of(context).maybePop()),
        if (!_cached) LinearProgressIndicator(value: _progress),
        Padding(padding: EdgeInsets.all(AppSpacingTokens.s24), child: _info(context)),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s24, 0, AppSpacingTokens.s24, AppSpacingTokens.s24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _cached ? _save : null,
              child: Text(_cached ? context.l10n.actionDownload : context.l10n.downloadingProgress(_percent)),
            ),
          ),
        ),
        if (kDebugMode && widget.demo) _debugControls(),
      ],
    );
  }

  // ---- Shared file info (glyph + name + size [+ progress caption]) ------------

  Widget _info(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFileGlyphWidget(type: widget.file.type, iconSize: AppDimensionTokens.icon.heroLg, box: AppDimensionTokens.size.fileGlyphHero),
        SizedBox(height: AppSpacingTokens.s18),
        Text(
          widget.file.name,
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s18),
        Text(
          _cached ? FileSizeFormatter.format(widget.file.sizeBytes) : context.l10n.downloadingProgress(_percent),
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _debugControls() {
    return Padding(
      padding: EdgeInsets.all(AppSpacingTokens.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(onPressed: _startDownload, child: const Text('re-download')),
          SizedBox(width: AppSpacingTokens.s8),
          TextButton(onPressed: _simulateError, child: const Text('simulate error')),
        ],
      ),
    );
  }
}

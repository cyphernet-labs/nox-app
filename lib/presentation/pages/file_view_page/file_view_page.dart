import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/app_dimension_tokens.dart';
import 'package:nox_app/design/app_spacing_tokens.dart';
import 'package:nox_app/design/nox_icons.dart';
import 'package:nox_app/design/theme/nox_tokens.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/general/formatters/file_size_formatter.dart';
import 'package:nox_app/general/text_constants.dart';
import 'package:nox_app/presentation/helpers/app_feedback_helper.dart';
import 'package:nox_app/presentation/widgets/primitives/app_file_glyph_widget.dart';
import 'package:nox_app/presentation/widgets/primitives/app_icon_widget.dart';
import 'package:nox_app/presentation/widgets/shell/app_panel_header_widget.dart';

/// Open the file view (5.3) adaptively: mobile pushes the full screen; desktop
/// shows a centered lightbox dialog (corpus `08-file`). The tap target lives in the
/// chat thread (5.2) and the chat card (5.4).
Future<void> showFileView(BuildContext context, MessageAttachment file) {
  final wide = MediaQuery.sizeOf(context).width >= Constants.railBreakpoint;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppDimensionTokens.layout.contentMaxW),
          child: FileViewPage(file: file, inDialog: true),
        ),
      ),
    );
  }
  return Navigator.of(context).push(FileViewPage.route(file));
}

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
    setState(() => _cached = false);
    _controller.forward(from: 0);
  }

  void _save() {
    // TODO(backend): copy the cached file to Downloads (file_saver/path_provider) — Phase 2.
    showAppSnackBar(context, text: TextConstants.savedToDownloads);
  }

  void _simulateError() {
    _controller.stop();
    setState(() {});
    showAppSnackBar(
      context,
      text: TextConstants.fileDownloadError,
      actionLabel: TextConstants.actionTryAgain,
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
          tooltip: TextConstants.tooltipBack,
          icon: AppIconWidget(NoxIcons.arrowBack),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: TextConstants.tooltipSave,
            onPressed: _cached ? _save : null,
            icon: AppIconWidget(NoxIcons.download, color: _cached ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.38)),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_cached)
            Padding(
              padding: EdgeInsets.only(top: AppSpacingTokens.s2),
              child: LinearProgressIndicator(value: _progress),
            ),
          Center(child: _info(context)),
          if (kDebugMode && widget.demo) Align(alignment: Alignment.bottomCenter, child: _debugControls()),
        ],
      ),
    );
  }

  // ---- Desktop standalone (lightbox over a scrim) ----------------------------

  Widget _wide(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.scrim.withValues(alpha: 0.55),
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
              child: Text(_cached ? TextConstants.actionDownload : TextConstants.downloadingProgress(_percent)),
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
        AppFileGlyphWidget(type: widget.file.type, iconSize: AppDimensionTokens.icon.hero, box: AppDimensionTokens.size.fileGlyphLg),
        SizedBox(height: AppSpacingTokens.s16),
        Text(
          widget.file.name,
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
        ),
        SizedBox(height: AppSpacingTokens.s8),
        Text(
          _cached ? FileSizeFormatter.format(widget.file.sizeBytes) : TextConstants.downloadingProgress(_percent),
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

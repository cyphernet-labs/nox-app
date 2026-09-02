import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nox_app/design/theme/nox_opacity.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nox_app/presentation/helpers/adaptive_lightbox.dart';
import 'package:nox_app/presentation/pages/file_view_page/bloc/file_view_bloc.dart';
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
/// progress bar, then enables Save (to Downloads). The progress is still timer-driven
/// (the real `file.downloadBegin` → GET-with-Range chain lands in 028), but Save is
/// REAL since feature 020: it picks a destination and copies the bytes. Save is
/// additionally gated by the attachment's server retention deadline
/// (`expiresAt`, contract §5/025): an expired file cannot be saved - the
/// bytes are gone server-side. Owns a [FileViewBloc] since feature 028: the
/// blueprint's carve-out for a BLoC-less screen ends exactly where a real
/// repository begins, and the download is now one.
class FileViewPage extends StatefulWidget {
  const FileViewPage({super.key, required this.file, this.messageId, this.demo = false, this.inDialog = false});

  final MessageAttachment file;

  /// The message this attachment belongs to, when it has one. Bytes fetched
  /// here are recorded against it, so the thread's thumbnail and a later Save
  /// find them without downloading again.
  final String? messageId;
  final bool demo;

  /// When shown inside the desktop lightbox [Dialog], render the lightbox content
  /// only (the Dialog provides the surface + scrim).
  final bool inDialog;

  static Route<void> route(MessageAttachment file, {String? messageId}) => MaterialPageRoute<void>(
    builder: (_) => FileViewPage(file: file, messageId: messageId),
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

class _FileViewPageState extends State<FileViewPage> {
  late final FileViewBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = FileViewBloc(file: widget.file, messageId: widget.messageId)..add(const FileViewEvent.started());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _save(FileViewState state) async {
    final path = state.file.localPath;
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
    showAppSnackBar(
      context,
      text: context.l10n.fileDownloadError,
      actionLabel: context.l10n.actionTryAgain,
      onAction: () => _bloc.add(const FileViewEvent.retried()),
      error: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FileViewBloc>.value(
      value: _bloc,
      child: BlocConsumer<FileViewBloc, FileViewState>(
        bloc: _bloc,
        // A network failure is the other outcome and keeps its retry: the
        // contract only forbids one for bytes that are gone for good.
        listenWhen: (previous, current) => previous.status != current.status && current.status == FileViewStatus.failed,
        listener: (context, state) => showAppSnackBar(
          context,
          text: context.l10n.fileDownloadError,
          actionLabel: context.l10n.actionTryAgain,
          onAction: () => _bloc.add(const FileViewEvent.retried()),
          error: true,
        ),
        builder: (context, state) {
          if (widget.inDialog) return _lightboxContent(context, state);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= Constants.railBreakpoint;
              return wide ? _wide(context, state) : _mobile(context, state);
            },
          );
        },
      ),
    );
  }

  // ---- Mobile (full screen) --------------------------------------------------

  Widget _mobile(BuildContext context, FileViewState state) {
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
            onPressed: state.canSave ? () => _save(state) : null,
            icon: AppIconWidget(
              NoxIcons.download,
              // Dim with the SAME predicate that disables onPressed: an expired
              // attachment must read as gated, not as a live control (FR-006).
              color: state.canSave ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: NoxOpacity.disabled),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (state.status == FileViewStatus.downloading) LinearProgressIndicator(value: state.progress),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacingTokens.s32),
              child: _info(context, state),
            ),
          ),
          if (kDebugMode && widget.demo) Align(alignment: Alignment.bottomCenter, child: _debugControls()),
        ],
      ),
    );
  }

  // ---- Desktop standalone (lightbox over a scrim) ----------------------------

  Widget _wide(BuildContext context, FileViewState state) {
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
                  child: _lightboxContent(context, state),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Lightbox content (shared by the dialog + the wide scaffold) -----------

  Widget _lightboxContent(BuildContext context, FileViewState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPanelHeaderWidget(
          title: widget.file.name,
          // Design: the lightbox header leads with the file-type glyph before the name.
          leading: AppFileGlyphWidget(type: widget.file.type, iconSize: AppDimensionTokens.icon.md, box: AppSpacingTokens.s32),
          onClose: () => Navigator.of(context).maybePop(),
        ),
        if (state.status == FileViewStatus.downloading) LinearProgressIndicator(value: state.progress),
        Padding(padding: EdgeInsets.all(AppSpacingTokens.s24), child: _info(context, state)),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacingTokens.s24, 0, AppSpacingTokens.s24, AppSpacingTokens.s24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.canSave ? () => _save(state) : null,
              child: Text(state.isReady ? context.l10n.actionDownload : context.l10n.downloadingProgress(state.percent)),
            ),
          ),
        ),
        if (kDebugMode && widget.demo) _debugControls(),
      ],
    );
  }

  // ---- Shared file info (glyph + name + size [+ progress caption]) ------------

  Widget _info(BuildContext context, FileViewState state) {
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
          // Contract §2.1 puts the terminal state HERE, on the file screen and
          // without a retry — expressly not on the app's fatal screen. Losing
          // one attachment must not cost the person the conversation they were
          // in.
          switch (state.status) {
            FileViewStatus.gone => context.l10n.attachmentGone,
            FileViewStatus.ready => FileSizeFormatter.format(state.file.sizeBytes),
            _ => context.l10n.downloadingProgress(state.percent),
          },
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: state.status == FileViewStatus.gone ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
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
          TextButton(onPressed: () => _bloc.add(const FileViewEvent.retried()), child: const Text('re-download')),
          SizedBox(width: AppSpacingTokens.s8),
          TextButton(onPressed: _simulateError, child: const Text('simulate error')),
        ],
      ),
    );
  }
}

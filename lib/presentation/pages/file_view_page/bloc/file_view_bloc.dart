import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';

part 'file_view_bloc.freezed.dart';
part 'file_view_event.dart';
part 'file_view_state.dart';

/// 5.3 File view. Fetches the attachment's bytes and reports how far it got.
///
/// This screen was BLoC-less under the blueprint's UI-first carve-out, whose
/// text ends with this very phase: "as soon as a screen is connected to a real
/// repository/async (client track 025-028) it gets its own Freezed BLoC". The
/// fake `AnimationController` it used to run was the carve-out's whole
/// justification, and it is gone.
class FileViewBloc extends BaseBloc<FileViewEvent, FileViewState> {
  FileViewBloc({required MessageAttachment file, this.messageId}) : super(FileViewState(file: file)) {
    on<Started>(_onStarted);
    on<Retried>(_onStarted);
  }

  final FileRepository _files = getIt<FileRepository>();
  final AttachmentDownloadService _downloads = getIt<AttachmentDownloadService>();
  final SessionPhaseService _phase = getIt<SessionPhaseService>();

  /// The message this attachment belongs to, when it has one. The download
  /// service records the fetched bytes against it, so the thumbnail and Save
  /// find them next time - even when this screen was closed long before the
  /// last byte arrived (phase 043).
  final String? messageId;

  Future<void> _onStarted(FileViewEvent event, Emitter<FileViewState> emit) async {
    // Everything below can throw — a directory query on a locked volume, a
    // filesystem error. Unguarded, the screen would sit at "Downloading… 0%"
    // for as long as the person is willing to watch it, with no error and no
    // way to try again.
    try {
      await _fetch(emit);
    } catch (error, stackTrace) {
      logRepository.error(target: this, error: error, stackTrace: stackTrace);
      if (!isClosed) emit(state.copyWith(status: FileViewStatus.failed));
    }
  }

  Future<void> _fetch(Emitter<FileViewState> emit) async {
    final file = state.file;

    // Already on this device — picked here, sent from here, or fetched before.
    // Checked for EXISTENCE, not just for a non-null string: iOS rewrites the
    // app-container path on every update, so a path stored months ago routinely
    // points at nothing. Trusting it would leave the screen claiming to be
    // ready over a file that is not there, and Save would fail on a button the
    // screen said was live.
    final stored = file.localPath;
    final existing = (stored != null && File(stored).existsSync())
        ? stored
        : await _files.localPathFor(fileId: file.id, suggestedName: file.name);
    if (existing != null) {
      emit(
        state.copyWith(
          file: file.copyWith(localPath: existing),
          progress: 1,
          status: FileViewStatus.ready,
        ),
      );
      return;
    }

    // The OTHER downloader. It reaches Dio directly, without going through the
    // socket, so the phase that stopped everything else does not reach it on
    // its own - and a tap here would ask a machine that just failed to prove
    // who it is for this person's file.
    //
    // `failed`, not `gone`: the bytes exist and the screen keeps its retry,
    // which is the same way out the banner offers.
    if (_phase.phase.isServerMismatch) {
      emit(state.copyWith(status: FileViewStatus.failed));
      return;
    }

    emit(state.copyWith(status: FileViewStatus.downloading, progress: 0));
    // The download belongs to the app, not to this screen: closing it does not
    // stop the bytes, and opening it again joins the same download where it
    // stands. A broken link only pauses it - this screen hears an error only
    // when the automation gave up, which is when Try again means something.
    final result = await _downloads.fetch(
      messageId: messageId,
      attachment: file,
      onProgress: (fraction) {
        if (isClosed) return;
        final live = state;
        if (live.status == FileViewStatus.downloading) emit(live.copyWith(progress: fraction));
      },
    );

    result.match<void>(
      onData: (path) {
        emit(
          state.copyWith(
            file: state.file.copyWith(localPath: path),
            progress: 1,
            status: FileViewStatus.ready,
          ),
        );
      },
      onError: (exception) {
        // Contract §2.1 draws the line here, and draws it deliberately: bytes
        // that are gone are a TERMINAL state on this screen, without a retry
        // button — and expressly "not the fatal screen of the whole app". A
        // server that kept refusing is the other thing entirely and keeps its
        // retry, which starts the ladder over.
        final gone = exception == RepositoryException.attachmentGone || exception == RepositoryException.notFound;
        emit(state.copyWith(status: gone ? FileViewStatus.gone : FileViewStatus.failed));
      },
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
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
  final MessageRepository _messages = getIt<MessageRepository>();

  /// The message this attachment belongs to, when it has one. Fetched bytes are
  /// recorded against it so the thumbnail and Save find them next time without
  /// downloading again.
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

    emit(state.copyWith(status: FileViewStatus.downloading, progress: 0));
    final result = await _files.download(
      fileId: file.id,
      suggestedName: file.name,
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
        final id = messageId;
        if (id != null) unawaited(_messages.attachLocalFile(messageId: id, localPath: path));
      },
      onError: (exception) {
        // Contract §2.1 draws the line here, and draws it deliberately: bytes
        // that are gone are a TERMINAL state on this screen, without a retry
        // button — and expressly "not the fatal screen of the whole app". A
        // connection failure is the other thing entirely and keeps its retry.
        final gone = exception == RepositoryException.attachmentGone || exception == RepositoryException.notFound;
        emit(state.copyWith(status: gone ? FileViewStatus.gone : FileViewStatus.failed));
      },
    );
  }
}

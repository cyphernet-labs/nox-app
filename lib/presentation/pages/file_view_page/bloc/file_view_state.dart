part of 'file_view_bloc.dart';

/// Where the screen stands. `gone` and `failed` are different on purpose: one
/// says "these bytes will never arrive", the other "not right now".
enum FileViewStatus { downloading, ready, failed, gone }

@freezed
abstract class FileViewState with _$FileViewState {
  const FileViewState._();

  const factory FileViewState({
    required MessageAttachment file,
    @Default(FileViewStatus.downloading) FileViewStatus status,
    @Default(0.0) double progress,

    /// The plain copy a video plays from (phase 048): the file on the disk is
    /// sealed, and a player reads only a plain file. Deleted when the screen -
    /// and its player - closes.
    String? playbackPath,

    /// The plain copy could not be made - most likely no room on the disk.
    /// The file itself is whole; the screen says so, and closing and opening
    /// it again tries again.
    @Default(false) bool openFailed,
  }) = _FileViewState;

  int get percent => (progress * 100).round();

  /// The bytes are here, so Save has something to copy.
  bool get isReady => status == FileViewStatus.ready;

  /// Saving is additionally gated by the server's retention deadline (contract
  /// §5): an expired file cannot be fetched again, so offering Save would be a
  /// button that can only fail.
  bool get canSave => isReady && !isExpired;

  bool get isExpired {
    final expiresAt = file.expiresAt;
    return expiresAt != null && expiresAt.isBefore(AppClock.now());
  }
}

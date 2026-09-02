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

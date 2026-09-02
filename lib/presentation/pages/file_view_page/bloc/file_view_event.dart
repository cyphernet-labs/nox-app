part of 'file_view_bloc.dart';

@freezed
sealed class FileViewEvent with _$FileViewEvent {
  /// Bring the bytes to this device, unless they are already here.
  const factory FileViewEvent.started() = Started;

  /// Try again after a failure a retry can fix. Deliberately NOT offered for
  /// the terminal state: contract §2.1 says that one has no retry button.
  const factory FileViewEvent.retried() = Retried;
}

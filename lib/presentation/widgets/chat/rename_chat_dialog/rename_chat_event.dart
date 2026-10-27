part of 'rename_chat_bloc.dart';

@freezed
sealed class RenameChatEvent with _$RenameChatEvent {
  /// The name text changed (unrestricted charset).
  const factory RenameChatEvent.nameChanged(String name) = RenameNameChanged;

  /// Debounced uniqueness check for [name] (excludes the chat's own id).
  const factory RenameChatEvent.availabilityRequested(String name) = RenameAvailabilityRequested;

  /// `Save` tapped.
  const factory RenameChatEvent.saveRequested() = RenameSaveRequested;

  /// The dialog consumed the terminal `navSuccess` status (closed) → reset to valid.
  const factory RenameChatEvent.navigationHandled() = RenameNavigationHandled;
}

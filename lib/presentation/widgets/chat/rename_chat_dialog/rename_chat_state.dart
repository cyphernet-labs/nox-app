part of 'rename_chat_bloc.dart';

/// Rename-chat form status. `navSuccess` is terminal (the dialog closes).
enum RenameChatStatus { empty, checking, valid, taken, submitting, navSuccess }

@freezed
abstract class RenameChatState with _$RenameChatState {
  const RenameChatState._();

  const factory RenameChatState({
    /// The chat's name when the dialog opened — the field starts here, and a save is only
    /// offered once the name actually changes.
    required String initialName,
    @Default('') String name,
    @Default(RenameChatStatus.valid) RenameChatStatus status,
    @Default(false) bool networkError,
  }) = _RenameChatState;

  bool get isChecking => status == RenameChatStatus.checking;

  bool get isSubmitting => status == RenameChatStatus.submitting;

  /// Submittable only when the name is valid AND actually changed — a no-op save of the
  /// current name is pointless (an empty/checking/taken/submitting name is blocked by the
  /// status guard).
  bool get canSubmit => status == RenameChatStatus.valid && name != initialName;
}

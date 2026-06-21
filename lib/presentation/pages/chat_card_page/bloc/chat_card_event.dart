part of 'chat_card_bloc.dart';

@freezed
sealed class ChatCardEvent with _$ChatCardEvent {
  /// Bind the card to a chat and load its files.
  const factory ChatCardEvent.initialize(String chatId) = Initialize;

  /// Toggle the files List ⇄ Grid view.
  const factory ChatCardEvent.viewModeChanged(FilesViewMode mode) = ViewModeChanged;

  /// Debug-only: reproduce a scenario (empty / offline / fatal).
  const factory ChatCardEvent.setScenario(ChatCardScenario scenario) = SetScenario;
}

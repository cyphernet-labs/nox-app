part of 'chat_card_bloc.dart';

@freezed
sealed class ChatCardEvent with _$ChatCardEvent {
  /// Bind the card to a chat and load its files.
  const factory ChatCardEvent.initialize(String chatId) = Initialize;

  /// Toggle the files List ⇄ Grid view.
  const factory ChatCardEvent.viewModeChanged(FilesViewMode mode) = ViewModeChanged;

  /// Invisible live re-derive of the files (feature 017 / R5): re-reads the chat's
  /// attachments and swaps them in on the current [Initialized] state — WITHOUT the
  /// loading flash or resetting the user's List/Grid choice (unlike a full re-init).
  const factory ChatCardEvent.filesRefreshed() = FilesRefreshed;

  /// Live device-connectivity change (P1): drives the real offline banner.
  const factory ChatCardEvent.connectivityChanged(bool online) = ConnectivityChanged;

  /// Debug-only: reproduce a scenario (empty / offline / fatal).
  const factory ChatCardEvent.setScenario(ChatCardScenario scenario) = SetScenario;
}

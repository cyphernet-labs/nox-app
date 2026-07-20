part of 'chat_thread_bloc.dart';

@freezed
sealed class ChatThreadEvent with _$ChatThreadEvent {
  /// Bind the thread to a chat and load the first (newest) page.
  const factory ChatThreadEvent.initialize(String chatId) = Initialize;

  /// Load a page of history; [reset] restarts from page 1, otherwise pages OLDER.
  /// [refresh] is a live change-signal (from `watchMessages`): re-reads the loaded page
  /// prefix and re-folds `items` without touching the optimistic `outgoing` list.
  const factory ChatThreadEvent.loadMessages({@Default(false) bool reset, @Default(false) bool refresh}) = LoadMessages;

  /// Send a message (optimistic): text and/or the current draft attachment.
  const factory ChatThreadEvent.messageSent({String? text, MessageAttachment? attachment}) = MessageSent;

  /// Retry a previously failed optimistic send by its local id.
  const factory ChatThreadEvent.sendRetried(String localId) = SendRetried;

  /// Attach a file (UI-phase: a no-op picker that synthesizes a draft attachment).
  const factory ChatThreadEvent.attachmentPicked() = AttachmentPicked;

  /// Remove the pending draft attachment.
  const factory ChatThreadEvent.attachmentRemoved() = AttachmentRemoved;

  /// Debug-only: reproduce a thread scenario (empty / offline / fatal / send-error).
  const factory ChatThreadEvent.setScenario(ChatThreadScenario scenario) = SetScenario;
}

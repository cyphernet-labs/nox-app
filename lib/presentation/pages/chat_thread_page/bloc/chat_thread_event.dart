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

  /// Retry a previously failed queued send by its client_message_id. The key is
  /// unchanged on purpose — that is what makes the server recognise the resend
  /// instead of storing a second copy.
  const factory ChatThreadEvent.sendRetried(String localId) = SendRetried;

  /// Discard a queued send by its client_message_id: it leaves the queue and is
  /// never sent. The escape hatch for a message that will not go — without it,
  /// a failed bubble now outlives the screen AND the process, i.e. forever.
  const factory ChatThreadEvent.sendDiscarded(String localId) = SendDiscarded;

  /// The durable outgoing queue changed (from `watchQueue`). The snapshot
  /// travels WITH the event rather than being re-read in the handler: the
  /// stream already carries it, and asking the store again would be a second
  /// round-trip per tick for an answer we were just handed.
  const factory ChatThreadEvent.outboxChanged(List<OutboxEntry> entries) = OutboxChanged;

  /// Attach a file (UI-phase: a no-op picker that synthesizes a draft attachment).
  const factory ChatThreadEvent.attachmentPicked() = AttachmentPicked;

  /// Remove the pending draft attachment.
  const factory ChatThreadEvent.attachmentRemoved() = AttachmentRemoved;

  /// Live device-connectivity change (P1): drives the real offline banner + send-queue.
  /// The live channel's phase changed. The PHASE, not a boolean: a server
  /// presenting the wrong key is not a dead network, and collapsing the two
  /// made the app blame the network and keep calling that server for ever.
  const factory ChatThreadEvent.sessionPhaseChanged(SessionPhase phase) = SessionPhaseChanged;

  /// Where the connection stands changed (phase 040): drives the banners.
  /// Sending stays on the phase above - only a current channel takes a send,
  /// whatever the corner says.
  const factory ChatThreadEvent.connectionStatusChanged(ConnectionStatus status) = ConnectionStatusChanged;

  /// The server's newest window has been asked for and is in the cache, or
  /// could not be had. [hasMore] is what the server said about older history;
  /// [generation] numbers the read, so only the newest ends the spinner.
  const factory ChatThreadEvent.windowSynced({bool? hasMore, required int generation}) = WindowSynced;

  /// The attachment transfers in flight changed. The map travels with the
  /// event, like the queue snapshot above.
  const factory ChatThreadEvent.transfersChanged(Map<String, AttachmentTransfer> transfers) = TransfersChanged;

  /// The person asked for another attempt, from the banner.
  const factory ChatThreadEvent.retryConnection() = RetryConnection;

  /// The person asked to create this chat on the server again, from the
  /// banner of a chat the server refused (phase 041).
  const factory ChatThreadEvent.creationRetried() = CreationRetried;

  /// Debug-only: reproduce a thread scenario (empty / offline / fatal / send-error).
  const factory ChatThreadEvent.setScenario(ChatThreadScenario scenario) = SetScenario;
}

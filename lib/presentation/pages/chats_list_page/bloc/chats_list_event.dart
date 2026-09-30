part of 'chats_list_bloc.dart';

@freezed
sealed class ChatsListEvent with _$ChatsListEvent {
  const factory ChatsListEvent.initialize() = Initialize;

  /// Load a page; [reset] restarts from page 1 (initial load / search). [refresh] is a
  /// live change-signal (from `watchChats()`): re-reads the currently-loaded page prefix
  /// invisibly and re-folds it onto the live state (no spinner, preserves scroll/selection).
  const factory ChatsListEvent.loadChats({@Default(false) bool reset, @Default(false) bool refresh}) = LoadChats;

  /// Search query changed (debounced) → re-query from page 1.
  const factory ChatsListEvent.searchChanged(String query) = SearchChanged;

  /// Desktop list-detail row selection (view-state, no navigation push).
  const factory ChatsListEvent.chatSelected(String id) = ChatSelected;

  /// Debug-only: reproduce a load scenario (offline / inline-error / fatal / empty).
  const factory ChatsListEvent.setScenario(ChatsListScenario scenario) = SetScenario;

  /// Where the connection stands changed (phase 040). The whole status, not a
  /// boolean: a server presenting the wrong key is not a dead network, and a
  /// path that is still coming up is neither.
  const factory ChatsListEvent.connectionStatusChanged(ConnectionStatus status) = ConnectionStatusChanged;

  /// The person asked for another attempt, from the banner. Nothing about a
  /// terminal phase changes on its own, so without this the app never comes
  /// back — not even once the cause is fixed.
  const factory ChatsListEvent.retryConnection() = RetryConnection;
}

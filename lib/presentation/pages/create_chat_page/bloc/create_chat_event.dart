part of 'create_chat_bloc.dart';

@freezed
sealed class CreateChatEvent with _$CreateChatEvent {
  /// The chat-name text changed (unrestricted charset).
  const factory CreateChatEvent.nameChanged(String name) = ChatNameChanged;

  /// Debounced uniqueness check for [name].
  const factory CreateChatEvent.availabilityRequested(String name) = ChatAvailabilityRequested;

  /// `Create` tapped; [outcome] is the (debug) create result.
  const factory CreateChatEvent.createRequested({@Default(CreateChatOutcome.success) CreateChatOutcome outcome}) = CreateRequested;
}

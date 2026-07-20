part of 'create_chat_bloc.dart';

/// Debug-selectable create outcome (6.1, dev-only).
enum CreateChatOutcome { success, network, fatal }

/// Create-chat form status. `nav*` values are terminal (the page navigates).
enum CreateChatStatus { empty, checking, valid, taken, submitting, navSuccess, navFatal }

@freezed
abstract class CreateChatState with _$CreateChatState {
  const CreateChatState._();

  const factory CreateChatState({
    @Default('') String name,
    @Default(CreateChatStatus.empty) CreateChatStatus status,
    @Default(false) bool networkError,
    // The chat created on a `navSuccess` outcome — handed back to the caller (the shell)
    // so it can open the new thread / refresh the list. Null until a successful create.
    ChatModel? createdChat,
  }) = _CreateChatState;

  bool get isChecking => status == CreateChatStatus.checking;

  bool get isSubmitting => status == CreateChatStatus.submitting;

  bool get canSubmit => status == CreateChatStatus.valid;
}

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

part 'create_chat_bloc.freezed.dart';
part 'create_chat_event.dart';
part 'create_chat_state.dart';

/// Create-chat form (6.1). Charset is UNRESTRICTED (no charset error); the
/// availability check is debounced (~300ms), by the local store and by the
/// server when it can answer at once. `Create` makes the chat on this device
/// and opens it without waiting for the server (phase 041); the outbox drain
/// creates it there, so there is no network failure left on this path - only a
/// failed local write re-enables `Create`.
class CreateChatBloc extends BaseBloc<CreateChatEvent, CreateChatState> {
  CreateChatBloc() : super(const CreateChatState()) {
    on<ChatNameChanged>(_onNameChanged);
    on<ChatAvailabilityRequested>(_onAvailabilityRequested, transformer: debounceRestartable());
    on<CreateRequested>(_onCreateRequested);
    on<NavigationHandled>(_onNavigationHandled);
  }

  void _onNavigationHandled(NavigationHandled event, Emitter<CreateChatState> emit) {
    emit(state.copyWith(status: CreateChatStatus.valid, networkError: false));
  }

  void _onNameChanged(ChatNameChanged event, Emitter<CreateChatState> emit) {
    final name = event.name;
    if (name.isEmpty) {
      emit(state.copyWith(name: name, status: CreateChatStatus.empty, networkError: false));
      return;
    }
    emit(state.copyWith(name: name, status: CreateChatStatus.checking, networkError: false));
    add(CreateChatEvent.availabilityRequested(name));
  }

  Future<void> _onAvailabilityRequested(ChatAvailabilityRequested event, Emitter<CreateChatState> emit) async {
    if (state.name != event.name || state.status != CreateChatStatus.checking) return;
    await executeLogic(() async {
      if (state.name != event.name) return;
      // The server is the ONLY authority on whether a chat name is free. It used
      // to be OR-ed with a frozen list of three words, which declared those
      // three taken even when the server was handing them out.
      // Fail-OPEN on a read error (onError → false): a transient failure must
      // not block typing, and creation itself still refuses a taken name.
      final dbResult = await chatRepository.isChatNameTaken(name: event.name);
      final taken = dbResult.match(onData: (t) => t, onError: (_) => false);
      emit(state.copyWith(status: taken ? CreateChatStatus.taken : CreateChatStatus.valid));
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: CreateChatStatus.valid)));
  }

  Future<void> _onCreateRequested(CreateRequested event, Emitter<CreateChatState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: CreateChatStatus.submitting, networkError: false));
    await executeLogic(() async {
      // The outcome selector still models network/fatal for previews; a `success`
      // persists the chat to the local DB via the cache-first repository.
      switch (event.outcome) {
        case CreateChatOutcome.success:
          // Created on this device, at once. The server is the authority on the
          // name and has the last word when the queue creates it there: a taken
          // name marks the chat for a rename instead of failing here.
          final result = await chatRepository.createChat(name: state.name);
          result.match<void>(
            onData: (chat) {
              emit(state.copyWith(status: CreateChatStatus.navSuccess, createdChat: chat));
              unawaited(getIt<OutboxService>().flush());
            },
            onError: (_) => emit(state.copyWith(status: CreateChatStatus.valid, networkError: true)),
          );
        case CreateChatOutcome.network:
          emit(state.copyWith(status: CreateChatStatus.valid, networkError: true));
        case CreateChatOutcome.fatal:
          emit(state.copyWith(status: CreateChatStatus.navFatal));
      }
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: CreateChatStatus.valid, networkError: true)));
  }
}

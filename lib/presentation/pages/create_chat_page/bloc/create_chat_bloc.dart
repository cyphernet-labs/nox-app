import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

part 'create_chat_bloc.freezed.dart';
part 'create_chat_event.dart';
part 'create_chat_state.dart';

/// Create-chat form (6.1). Charset is UNRESTRICTED (no charset error); the
/// uniqueness check is debounced (~300ms) against the mock dataset. On a network
/// failure `Create` re-enables for retry. `// TODO(backend): real create.`
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
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (state.name != event.name) return;
      // Uniqueness against the ACCUMULATING local DB (seeded + already-created chats,
      // D4), OR a small reserved demo set. `// TODO(backend): real server check.`
      final dbResult = await chatRepository.isChatNameTaken(name: event.name);
      final taken = dbResult.match(onData: (t) => t, onError: (_) => false) || OnboardingMockData.takenChatNames.contains(event.name);
      emit(state.copyWith(status: taken ? CreateChatStatus.taken : CreateChatStatus.valid));
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: CreateChatStatus.valid)));
  }

  Future<void> _onCreateRequested(CreateRequested event, Emitter<CreateChatState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: CreateChatStatus.submitting, networkError: false));
    await executeLogic(() async {
      // The outcome selector still models network/fatal for previews; a `success`
      // now persists the chat to the local DB via the cache-first repository.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      switch (event.outcome) {
        case CreateChatOutcome.success:
          final result = await chatRepository.createChat(name: state.name);
          result.match<void>(
            onData: (chat) => emit(state.copyWith(status: CreateChatStatus.navSuccess, createdChat: chat)),
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

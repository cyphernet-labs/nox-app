import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
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
      // TODO(backend): real server uniqueness check.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (state.name != event.name) return;
      final taken = OnboardingMockData.takenChatNames.contains(event.name);
      emit(state.copyWith(status: taken ? CreateChatStatus.taken : CreateChatStatus.valid));
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: CreateChatStatus.valid)));
  }

  Future<void> _onCreateRequested(CreateRequested event, Emitter<CreateChatState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: CreateChatStatus.submitting, networkError: false));
    await executeLogic(() async {
      // TODO(backend): real create; the outcome is a debug stand-in.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      switch (event.outcome) {
        case CreateChatOutcome.success:
          emit(state.copyWith(status: CreateChatStatus.navSuccess));
        case CreateChatOutcome.network:
          emit(state.copyWith(status: CreateChatStatus.valid, networkError: true));
        case CreateChatOutcome.fatal:
          emit(state.copyWith(status: CreateChatStatus.navFatal));
      }
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: CreateChatStatus.valid, networkError: true)));
  }
}

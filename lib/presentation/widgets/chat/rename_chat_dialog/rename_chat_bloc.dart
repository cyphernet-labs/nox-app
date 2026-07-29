import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/general/onboarding_mock_data.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';

part 'rename_chat_bloc.freezed.dart';
part 'rename_chat_event.dart';
part 'rename_chat_state.dart';

/// Rename-chat dialog form (edit chat name, launched from the 5.4 card). Mirrors
/// [CreateChatBloc]: unrestricted charset, debounced (~200ms) uniqueness check — but
/// EXCLUDING the chat's own current name (a chat never collides with itself, incl. case
/// variants). Save persists via `updateChatName`; a network failure re-enables for retry.
/// The current name is trivially valid but not submittable (a no-op save is pointless).
/// `// TODO(backend): real rename.`
class RenameChatBloc extends BaseBloc<RenameChatEvent, RenameChatState> {
  RenameChatBloc({required this.chatId, required String currentName})
    : super(RenameChatState(initialName: currentName, name: currentName, status: RenameChatStatus.valid)) {
    on<RenameNameChanged>(_onNameChanged);
    on<RenameAvailabilityRequested>(_onAvailabilityRequested, transformer: debounceRestartable());
    on<RenameSaveRequested>(_onSaveRequested);
    on<RenameNavigationHandled>(_onNavigationHandled);
  }

  final String chatId;

  void _onNavigationHandled(RenameNavigationHandled event, Emitter<RenameChatState> emit) {
    emit(state.copyWith(status: RenameChatStatus.valid, networkError: false));
  }

  void _onNameChanged(RenameNameChanged event, Emitter<RenameChatState> emit) {
    // Trim once and validate/persist the trimmed value: rename's no-op guard is
    // load-bearing, so a trailing-space "Foo " must read as unchanged (not a near-duplicate)
    // and a whitespace-only name must read as empty.
    final name = event.name.trim();
    if (name.isEmpty) {
      emit(state.copyWith(name: name, status: RenameChatStatus.empty, networkError: false));
      return;
    }
    if (name == state.initialName) {
      // The unchanged current name is trivially valid (no uniqueness check); `canSubmit`
      // still blocks the no-op save.
      emit(state.copyWith(name: name, status: RenameChatStatus.valid, networkError: false));
      return;
    }
    emit(state.copyWith(name: name, status: RenameChatStatus.checking, networkError: false));
    add(RenameChatEvent.availabilityRequested(name));
  }

  Future<void> _onAvailabilityRequested(RenameAvailabilityRequested event, Emitter<RenameChatState> emit) async {
    if (state.name != event.name || state.status != RenameChatStatus.checking) return;
    await executeLogic(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (state.name != event.name) return;
      // Exclude THIS chat (a rename never collides with its own name), OR a reserved demo
      // name. The reserved check is self-excluded case-insensitively too — recapitalizing a
      // chat's own name ('general' → 'General') must never read as taken. Fail-OPEN on a read
      // error (mirrors create-chat) — the server is the authority.
      final dbResult = await chatRepository.isChatNameTaken(name: event.name, excludeChatId: chatId);
      final ownVariant = event.name.toLowerCase() == state.initialName.toLowerCase();
      final reserved = !ownVariant && OnboardingMockData.takenChatNames.contains(event.name);
      final taken = dbResult.match(onData: (t) => t, onError: (_) => false) || reserved;
      emit(state.copyWith(status: taken ? RenameChatStatus.taken : RenameChatStatus.valid));
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: RenameChatStatus.valid)));
  }

  Future<void> _onSaveRequested(RenameSaveRequested event, Emitter<RenameChatState> emit) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: RenameChatStatus.submitting, networkError: false));
    await executeLogic(() async {
      final result = await chatRepository.updateChatName(chatId: chatId, name: state.name);
      result.match<void>(
        onData: (_) => emit(state.copyWith(status: RenameChatStatus.navSuccess)),
        onError: (_) => emit(state.copyWith(status: RenameChatStatus.valid, networkError: true)),
      );
    }, onError: (error, exception, stackTrace) => emit(state.copyWith(status: RenameChatStatus.valid, networkError: true)));
  }
}

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'chat_card_bloc.freezed.dart';
part 'chat_card_event.dart';
part 'chat_card_state.dart';

/// Chat card (5.4) — read-only chat header + its shared files (List / Grid).
/// Sealed Initializing/Initialized/Error over [ChatRepository.getChatFiles]
/// (mock-backed, no pagination). Empty / offline / fatal are reproduced by
/// [ChatCardScenario] (debug).
class ChatCardBloc extends BaseBloc<ChatCardEvent, ChatCardState> {
  ChatCardBloc() : super(const ChatCardState.initializing()) {
    on<Initialize>(_onInitialize);
    on<ViewModeChanged>(_onViewModeChanged);
    on<SetScenario>(_onSetScenario);
  }

  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final MessageRepository _messageRepository = getIt<MessageRepository>();

  late String _chatId;
  ChatCardScenario _scenario = ChatCardScenario.normal;

  // Live change-signal (feature 017 / R5): a new attachment sent to this chat writes
  // to the message store → re-derive the files. Value ignored — getChatFiles stays the
  // single projection path. `add(initialize)` re-runs the derive invisibly.
  StreamSubscription<List<MessageModel>>? _filesSub;

  @override
  Future<void> close() {
    _filesSub?.cancel();
    return super.close();
  }

  Future<void> _onInitialize(Initialize event, Emitter<ChatCardState> emit) async {
    _chatId = event.chatId;
    // skip(1) drops the initial snapshot the reset load already covers; debounce coalesces bursts.
    _filesSub ??= _messageRepository
        .watchMessages(_chatId)
        .skip(1)
        .debounceTime(const Duration(milliseconds: 100))
        .listen((_) => add(ChatCardEvent.initialize(_chatId)));
    emit(const ChatCardState.initializing());

    if (_scenario == ChatCardScenario.fatal) {
      emit(const ChatCardState.error());
      return;
    }

    await executeLogic(() async {
      if (_scenario == ChatCardScenario.empty) {
        emit(const ChatCardState.initialized(files: []));
        return;
      }
      final result = await _chatRepository.getChatFiles(chatId: _chatId);
      result.match<void>(
        onData: (files) => emit(ChatCardState.initialized(files: files, isOffline: _scenario == ChatCardScenario.offline)),
        onError: (_) => emit(const ChatCardState.error()),
      );
    }, onError: (error, exception, stackTrace) => emit(const ChatCardState.error()));
  }

  void _onViewModeChanged(ViewModeChanged event, Emitter<ChatCardState> emit) {
    final current = state;
    if (current is Initialized) emit(current.copyWith(viewMode: event.mode));
  }

  FutureOr<void> _onSetScenario(SetScenario event, Emitter<ChatCardState> emit) async {
    _scenario = event.scenario;
    add(ChatCardEvent.initialize(_chatId));
  }
}

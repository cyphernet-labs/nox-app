import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';
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
    on<FilesRefreshed>(_onFilesRefreshed);
    on<ConnectivityChanged>(_onConnectivityChanged);
    on<SetScenario>(_onSetScenario);
  }

  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final MessageRepository _messageRepository = getIt<MessageRepository>();
  final ConnectivityService _connectivityService = getIt<ConnectivityService>();

  late String _chatId;
  ChatCardScenario _scenario = ChatCardScenario.normal;

  // Live device-online state (P1): the offline banner is reachable in the real flow, not
  // just via the debug scenario. Mirrors ChatsListBloc / ChatThreadBloc.
  StreamSubscription<bool>? _connSub;
  bool _deviceOnline = true;

  /// The card is offline when the device is offline OR the debug scenario forces it.
  bool _isOffline() => !_deviceOnline || _scenario == ChatCardScenario.offline;

  // Live change-signal (feature 017 / R5): a new attachment sent to this chat writes
  // to the message store → re-derive the files. Value ignored — getChatFiles stays the
  // single projection path. Emits FilesRefreshed (an INVISIBLE re-derive that preserves
  // the loading-free Initialized view + the user's List/Grid choice), NOT a full re-init.
  StreamSubscription<List<MessageModel>>? _filesSub;

  @override
  Future<void> close() {
    _filesSub?.cancel();
    _connSub?.cancel();
    return super.close();
  }

  Future<void> _onInitialize(Initialize event, Emitter<ChatCardState> emit) async {
    _chatId = event.chatId;
    // skip(1) drops the initial snapshot the reset load already covers; debounce coalesces bursts.
    _filesSub ??= _messageRepository
        .watchMessages(_chatId)
        .skip(1)
        .debounceTime(const Duration(milliseconds: 100))
        .listen((_) => add(const ChatCardEvent.filesRefreshed()));
    // Live connectivity → the offline banner (seeded current value, then every change).
    _connSub ??= _connectivityService.watchOnline().listen((online) => add(ChatCardEvent.connectivityChanged(online)));
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
        onData: (files) => emit(ChatCardState.initialized(files: files, isOffline: _isOffline())),
        onError: (_) => emit(const ChatCardState.error()),
      );
    }, onError: (error, exception, stackTrace) => emit(const ChatCardState.error()));
  }

  void _onViewModeChanged(ViewModeChanged event, Emitter<ChatCardState> emit) {
    final current = state;
    if (current is Initialized) emit(current.copyWith(viewMode: event.mode));
  }

  /// Live re-derive (R5): re-read the files and swap them into the current view,
  /// preserving viewMode/isOffline and never flashing the loading state (contrast a
  /// full re-init). Best-effort — a transient read error keeps the last good files.
  Future<void> _onFilesRefreshed(FilesRefreshed event, Emitter<ChatCardState> emit) async {
    final current = state;
    // Nothing to refresh invisibly while initializing / in a fatal error; the empty
    // scenario is pinned empty (no source to re-derive from).
    if (current is! Initialized || _scenario == ChatCardScenario.empty) return;
    final result = await _chatRepository.getChatFiles(chatId: _chatId);
    result.match<void>(
      onData: (files) {
        final live = state;
        if (live is Initialized) emit(live.copyWith(files: files));
      },
      onError: (_) {}, // keep the current view — the refresh is invisible and best-effort
    );
  }

  void _onConnectivityChanged(ConnectivityChanged event, Emitter<ChatCardState> emit) {
    _deviceOnline = event.online;
    final current = state;
    // Update the banner in place (no reload) — like the reactive files re-derive.
    if (current is Initialized) emit(current.copyWith(isOffline: _isOffline()));
  }

  FutureOr<void> _onSetScenario(SetScenario event, Emitter<ChatCardState> emit) async {
    _scenario = event.scenario;
    add(ChatCardEvent.initialize(_chatId));
  }
}

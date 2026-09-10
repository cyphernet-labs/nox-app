import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/constants.dart';
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
  /// [initialScenario] pins the debug scenario BEFORE the first [Initialize] so the very
  /// first (and only) load reflects it — avoiding the setScenario re-init racing an
  /// in-flight files re-derive (which would clobber `empty` with the real files). Runtime
  /// leaves it null (→ normal); the demo dropdown still switches live via [SetScenario].
  ChatCardBloc({ChatCardScenario? initialScenario}) : super(const ChatCardState.initializing()) {
    if (initialScenario != null) _scenario = initialScenario;
    on<Initialize>(_onInitialize);
    on<ViewModeChanged>(_onViewModeChanged);
    on<FilesRefreshed>(_onFilesRefreshed);
    on<ConnectivityChanged>(_onConnectivityChanged);
    on<SetScenario>(_onSetScenario);
    on<PersonLabelChanged>(_onPersonLabelChanged);
  }

  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final MessageRepository _messageRepository = getIt<MessageRepository>();
  final SessionPhaseService _sessionPhaseService = getIt<SessionPhaseService>();
  final SessionRepository _sessionRepository = getIt<SessionRepository>();

  StreamSubscription<String?>? _labelSub;
  String _person = Constants.defaultUserLabel;

  late String _chatId;
  ChatCardScenario _scenario = ChatCardScenario.normal;

  // Live device-online state (P1): the offline banner is reachable in the real flow, not
  // just via the debug scenario. Mirrors ChatsListBloc / ChatThreadBloc.
  StreamSubscription<SessionPhase>? _connSub;
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
    _labelSub?.cancel();
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
    // The session phase, not raw device connectivity, is what says whether the
    // data on screen is current: a device can be online while the socket is
    // down, and the socket can be open while replay is still running (FR-005).
    _connSub ??= _sessionPhaseService.watchPhase().listen((phase) => add(ChatCardEvent.connectivityChanged(phase.isCurrent)));
    // Watched, not read once. The desktop side sheet stays open while the
    // person renames themselves from another device, and a snapshot would keep
    // rendering the old name until the card was closed and reopened - the exact
    // reason WatchChat exists forty lines above for the chat's own name.
    //
    // It also removes the await that used to sit in front of the fatal
    // short-circuit: a suspension point there let a second Initialize (the demo
    // dropdown re-dispatches one) interleave with the first.
    _labelSub ??= _sessionRepository.watchLabel().listen((label) => add(ChatCardEvent.personLabelChanged(label)));
    emit(const ChatCardState.initializing());

    if (_scenario == ChatCardScenario.fatal) {
      emit(const ChatCardState.error());
      return;
    }

    await executeLogic(() async {
      if (_scenario == ChatCardScenario.empty) {
        emit(ChatCardState.initialized(files: const [], personLabel: _person));
        return;
      }
      // Opening the card pulls the newest window; the live re-derive below does not.
      final result = await _chatRepository.getChatFiles(chatId: _chatId, refresh: true);
      // Stale-guard: the read is no longer instant (it may reach the server), so
      // the debug scenario can have changed while it was in flight. Emitting the
      // late result would overwrite the state the user just selected.
      if (_scenario == ChatCardScenario.empty) {
        emit(ChatCardState.initialized(files: const [], personLabel: _person));
        return;
      }
      result.match<void>(
        onData: (files) => emit(ChatCardState.initialized(files: files, isOffline: _isOffline(), personLabel: _person)),
        onError: (_) => emit(const ChatCardState.error()),
      );
    }, onError: (error, exception, stackTrace) => emit(const ChatCardState.error()));
  }

  void _onPersonLabelChanged(PersonLabelChanged event, Emitter<ChatCardState> emit) {
    // Null is logout, and the fallback is what every other surface shows then.
    final next = event.label ?? Constants.defaultUserLabel;
    if (next == _person) return;
    _person = next;
    final current = state;
    if (current is Initialized) emit(current.copyWith(personLabel: next));
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

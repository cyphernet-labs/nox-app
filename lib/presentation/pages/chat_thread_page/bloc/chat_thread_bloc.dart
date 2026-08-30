import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/mime_types.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

part 'chat_thread_bloc.freezed.dart';
part 'chat_thread_event.dart';
part 'chat_thread_state.dart';

/// Chat thread (5.2) over the cache-first message repository. PagingState-in-state
/// with a SEQ CURSOR rather than page numbers (feature 025): [Initialized.oldestLoadedSeq]
/// is the `before_seq` of the next older batch, pulled in on scroll-up via sequential();
/// plus an `outgoing` list for optimistic sends (pending → sent / error + retry).
/// Resolves [MessageRepository] from DI (mock-backed until the 016 flip). Offline /
/// empty / fatal / send-error are reproduced by [ChatThreadScenario] (debug).
class ChatThreadBloc extends BaseBloc<ChatThreadEvent, ChatThreadState> {
  ChatThreadBloc() : super(const ChatThreadState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadMessages>(_onLoadMessages, transformer: sequential());
    on<MessageSent>(_onMessageSent);
    on<SendRetried>(_onSendRetried);
    on<AttachmentPicked>(_onAttachmentPicked);
    on<AttachmentRemoved>(_onAttachmentRemoved);
    // sequential() so a rapid connectivity flap can't run two overlapping re-deliveries
    // of the same queued pending send (which would double-post in the open no-delete space).
    on<ConnectivityChanged>(_onConnectivityChanged, transformer: sequential());
    on<SetScenario>(_onSetScenario);
  }

  final MessageRepository _messageRepository = getIt<MessageRepository>();
  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final SessionRepository _sessionRepository = getIt<SessionRepository>();
  final FilePickerService _filePickerService = getIt<FilePickerService>();
  final SessionPhaseService _sessionPhaseService = getIt<SessionPhaseService>();

  late String _chatId;
  // The signed-in own-identity resolved from the session at thread init (feature 015).
  // Own-detection uses `_identity.id`; own optimistic sends author with `_identity.label`.
  Identity _identity = resolveIdentity(null);
  ChatThreadScenario _scenario = ChatThreadScenario.normal;
  int _localCounter = 0;

  // Live change-signal over the cache-first DB (Feature 014): a new persisted message
  // (own send / debug inbound) re-reads the loaded prefix. Value ignored — getMessages
  // stays the single projection path.
  StreamSubscription<List<MessageModel>>? _messagesSub;

  // Live device-online state (P1): the offline banner AND the offline send-queue are
  // reachable in the real flow, not just via the debug scenario. Real offline keeps
  // sends `pending`; reconnecting re-delivers them (mirrors the offline→normal scenario).
  StreamSubscription<SessionPhase>? _connSub;
  bool _deviceOnline = true;

  /// The thread is offline when the device is offline OR the debug scenario forces it.
  bool _isOffline() => !_deviceOnline || _scenario == ChatThreadScenario.offline;

  FutureOr<void> _onInitialize(Initialize event, Emitter<ChatThreadState> emit) async {
    _chatId = event.chatId;
    // Resolve the signed-in own-identity from the session (fallback on absent/failed
    // read — the thread still renders). Own rows in the DB were reconciled to this id
    // at seed time, so own-detection is consistent (feature 015).
    _identity = resolveIdentity((await _sessionRepository.readSession()).data);
    emit(ChatThreadState.initialized(pagingState: PagingState<String, MessageModel>(), currentId: _identity.id));
    add(const ChatThreadEvent.loadMessages(reset: true));
    // Viewing the thread marks the chat read (mobile push / desktop select) — resets the
    // list badge live. No-op at 0.
    unawaited(_chatRepository.markChatRead(chatId: _chatId));
    // skip(1) drops the initial snapshot the reset load already covers; debounceTime
    // coalesces write bursts into one refresh.
    _messagesSub ??= _messageRepository
        .watchMessages(_chatId)
        .skip(1)
        .debounceTime(const Duration(milliseconds: 100))
        .listen((_) => add(const ChatThreadEvent.loadMessages(refresh: true)));
    // Live connectivity → the offline banner + the offline send-queue (seed then live).
    // The session phase, not raw device connectivity, is what says whether the
    // data on screen is current: a device can be online while the socket is
    // down, and the socket can be open while replay is still running (FR-005).
    _connSub ??= _sessionPhaseService.watchPhase().listen((phase) => add(ChatThreadEvent.connectivityChanged(phase.isCurrent)));
  }

  @override
  Future<void> close() {
    _messagesSub?.cancel();
    _connSub?.cancel();
    return super.close();
  }

  FutureOr<void> _onLoadMessages(LoadMessages event, Emitter<ChatThreadState> emit) async {
    final current = state;
    if (current is! Initialized) return;

    // Live refresh: re-read the loaded prefix invisibly (serialised on this handler).
    if (event.refresh) {
      await _refreshMessages(current, emit);
      return;
    }

    if (current.loadingInProgress) return;

    // Fatal short-circuits to the error state (3.1).
    if (_scenario == ChatThreadScenario.fatal) {
      emit(const ChatThreadState.error());
      return;
    }

    final isReset = event.reset;
    if (!isReset && !current.pagingState.hasNextPage) return;

    final existingList = isReset ? <MessageModel>[] : current.items;
    final basePagingState = isReset
        ? PagingState<String, MessageModel>(isLoading: true)
        : current.pagingState.copyWith(isLoading: true, error: null);

    emit(current.copyWith(loadingInProgress: true, items: existingList, pagingState: basePagingState));

    await executeLogic(
      () async {
        // Empty scenario: return an empty page without hitting the repository.
        if (_scenario == ChatThreadScenario.empty) {
          final live = state;
          if (live is! Initialized) return;
          final r = basePagingState.applyPage(
            existingList: const [],
            response: (const [], const PageMetadata(hasMore: false)),
            keyExtractor: (m) => m.id,
          );
          emit(
            live.copyWith(items: const [], pagingState: r.pagingState, oldestLoadedSeq: null, loadingInProgress: false, isOffline: false),
          );
          return;
        }

        // Cursor request: the tail on reset/first load, otherwise the batch
        // older than the oldest loaded seq.
        final oldest = current.oldestLoadedSeq;
        final config = isReset || oldest == null
            ? GetMessagesConfig.tail(chatId: _chatId)
            : GetMessagesConfig.olderThan(chatId: _chatId, beforeSeq: oldest);
        final result = await _messageRepository.getMessages(config: config);

        final live = state;
        if (live is! Initialized) return;

        result.match<void>(
          onData: (data) {
            final (messages, PageMetadata metadata) = data;
            final r = basePagingState.applyPage(existingList: existingList, response: (messages, metadata), keyExtractor: (m) => m.id);
            // Batches ascend by seq, so their first row is their oldest.
            final batchOldest = messages.isEmpty ? null : messages.first.seq;
            final newOldest = isReset
                ? batchOldest
                : switch ((live.oldestLoadedSeq, batchOldest)) {
                    (null, final b) => b,
                    (final a, null) => a,
                    (final a?, final b?) => a < b ? a : b,
                  };
            emit(
              live.copyWith(
                items: r.updatedList,
                pagingState: r.pagingState,
                oldestLoadedSeq: newOldest,
                loadingInProgress: false,
                isOffline: _isOffline(),
              ),
            );
          },
          onError: (exception) {
            emit(live.copyWith(pagingState: live.pagingState.copyWith(isLoading: false, error: exception), loadingInProgress: false));
          },
        );
      },
      onError: (error, exception, stackTrace) {
        final live = state;
        if (live is Initialized) {
          emit(live.copyWith(loadingInProgress: false, pagingState: live.pagingState.copyWith(isLoading: false)));
        }
      },
    );
  }

  Future<void> _onMessageSent(MessageSent event, Emitter<ChatThreadState> emit) async {
    final current = state;
    if (current is! Initialized) return;

    final text = (event.text != null && event.text!.trim().isNotEmpty) ? event.text!.trim() : null;
    if (text == null && event.attachment == null) return; // nothing to send

    // The optimistic row's id doubles as the contract's idempotency key, so it
    // must be globally unique — NOT a per-bloc counter, which restarts with
    // every thread open and would collide across chats and sessions, making two
    // different messages look like a retry of each other to the server.
    final localId = 'local_${const Uuid().v4()}';
    final optimistic = MessageModel(
      id: localId,
      chatId: _chatId,
      authorId: current.currentId,
      authorLabel: _identity.label,
      text: text,
      attachment: event.attachment,
      sentAt: AppClock.now(), // AppClock (frozen in tests) → deterministic; real clock in prod
      status: MessageStatus.pending,
    );
    emit(current.copyWith(outgoing: [...current.outgoing, optimistic], draftAttachment: null));

    await _deliver(localId, text: text, attachment: event.attachment, emit: emit);
  }

  Future<void> _onSendRetried(SendRetried event, Emitter<ChatThreadState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    final matches = current.outgoing.where((m) => m.id == event.localId);
    if (matches.isEmpty) return;
    final msg = matches.first;
    _updateOutgoing(event.localId, MessageStatus.pending, emit);
    await _deliver(event.localId, text: msg.text, attachment: msg.attachment, emit: emit);
  }

  /// Delivers an optimistic message: offline keeps it `pending`; send-error flips it
  /// to `error`; otherwise the (mock) repository ack marks it `sent`.
  Future<void> _deliver(String localId, {String? text, MessageAttachment? attachment, required Emitter<ChatThreadState> emit}) async {
    if (_isOffline()) return; // offline (device or debug) → queued as pending until restored
    await executeLogic(() async {
      if (_scenario == ChatThreadScenario.sendError) {
        _updateOutgoing(localId, MessageStatus.error, emit);
        return;
      }
      // localId is stable across retries (RetrySend re-delivers the same one),
      // so it doubles as the contract's idempotency key: a resend after a lost
      // reply is recognised by the server instead of stored twice.
      final result = await _messageRepository.sendMessage(
        chatId: _chatId,
        // Stable across retries (RetrySend and the queue flush re-deliver the
        // same localId), and globally unique — the two properties the key needs.
        clientMessageId: localId,
        text: text,
        attachment: attachment,
      );
      result.match<void>(
        // Adopt the persisted server message (srv_<uuid> id + sent) so the watch tick's
        // copy is deduped by id in `allMessages` → exactly one bubble (no flicker).
        onData: (persisted) => _adoptOutgoing(localId, persisted, emit),
        onError: (_) => _updateOutgoing(localId, MessageStatus.error, emit),
      );
    }, onError: (error, exception, stackTrace) => _updateOutgoing(localId, MessageStatus.error, emit));
  }

  void _updateOutgoing(String localId, MessageStatus status, Emitter<ChatThreadState> emit) {
    final live = state;
    if (live is! Initialized) return;
    emit(
      live.copyWith(
        outgoing: [
          for (final m in live.outgoing)
            if (m.id == localId) m.copyWith(status: status) else m,
        ],
      ),
    );
  }

  /// Replace an optimistic outgoing entry with the persisted server message (id adoption).
  void _adoptOutgoing(String localId, MessageModel persisted, Emitter<ChatThreadState> emit) {
    final live = state;
    if (live is! Initialized) return;
    emit(
      live.copyWith(
        outgoing: [
          for (final m in live.outgoing)
            if (m.id == localId) persisted else m,
        ],
      ),
    );
  }

  /// Invisible live re-read of the loaded span, served from the CACHE.
  ///
  /// Reading locally is what makes it safe to ask for the whole span: the wire
  /// ceiling is a wire concern, and events have already put everything new into
  /// the cache. Fetching here instead would persist, wake the change-signal
  /// that triggered this refresh, and fetch again — a loop that never settles.
  ///
  /// Re-folds `items` WITHOUT touching the optimistic `outgoing`, the draft or
  /// the loading state, and merges rather than replaces so the loaded span can
  /// only grow.
  Future<void> _refreshMessages(Initialized live0, Emitter<ChatThreadState> emit) async {
    if (_scenario == ChatThreadScenario.fatal || _scenario == ChatThreadScenario.empty) return;
    // An inbound that lands in the currently-viewed chat stays read (no-op at 0 otherwise).
    unawaited(_chatRepository.markChatRead(chatId: _chatId));
    // Only the newest batch: asking for the whole loaded span would exceed the
    // contract's ceiling past ~100 rows and come back CLAMPED, collapsing the
    // thread the refresh was meant to keep current. Older rows cannot change —
    // contract v0 has neither edit nor delete — so re-reading them buys nothing.
    final result = await _messageRepository.getMessages(
      config: GetMessagesConfig.tail(chatId: _chatId, limit: live0.items.length + GetMessagesConfig.pageSize, cachedOnly: true),
    );
    if (!result.hasData) return; // swallow a background error — keep the current thread
    final (all, meta) = result.data!;
    final live = state;
    if (live is! Initialized) return;
    // MERGE onto what is already loaded rather than replacing it: the batch is
    // the newest window, and dropping the rest would shrink the thread and jump
    // the scroll-up cursor forward.
    final byId = {for (final m in live.items) m.id: m};
    for (final m in all) {
      byId[m.id] = m;
    }
    final merged = byId.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
    final r = PagingState<String, MessageModel>().applyPage(
      existingList: const [],
      response: (merged, PageMetadata(hasMore: live.pagingState.hasNextPage)),
      keyExtractor: (m) => m.id,
    );
    emit(
      live.copyWith(
        items: r.updatedList,
        pagingState: r.pagingState,
        // The scroll-up cursor only ever moves DOWN.
        oldestLoadedSeq: merged.isEmpty ? live.oldestLoadedSeq : merged.first.seq,
      ),
    );
  }

  Future<void> _onAttachmentPicked(AttachmentPicked event, Emitter<ChatThreadState> emit) async {
    if (state is! Initialized) return;
    // Real native file picker (feature 017) — metadata only, no bytes read.
    final picked = await _filePickerService.pickFile();
    final live = state;
    if (live is! Initialized || picked == null) return; // cancelled / unsupported → composer unchanged
    emit(
      live.copyWith(
        draftAttachment: MessageAttachment(
          id: 'att_${_localCounter++}',
          name: picked.name,
          sizeBytes: picked.sizeBytes,
          type: FileType.fromExtension(picked.extension),
          // Derived client-side from the extension (contract §7) — this is the
          // value file.uploadBegin is told; the picker never reads bytes.
          mime: MimeTypes.forExtension(picked.extension),
          localPath: picked.path, // drives the image thumbnail + real save (F4/F2)
        ),
      ),
    );
  }

  void _onAttachmentRemoved(AttachmentRemoved event, Emitter<ChatThreadState> emit) {
    final current = state;
    if (current is! Initialized) return;
    emit(current.copyWith(draftAttachment: null));
  }

  FutureOr<void> _onSetScenario(SetScenario event, Emitter<ChatThreadState> emit) async {
    final wasOffline = _isOffline();
    _scenario = event.scenario;
    // send-error only affects the next send.
    if (event.scenario == ChatThreadScenario.sendError) return;

    final current = state;
    // Offline → NORMAL via the debug scenario (only if the device is actually online):
    // re-deliver the messages queued as pending while offline, keeping the loaded history.
    // Scoped to `normal` so offline→empty / offline→fatal fall through to the reset branch
    // below and render the target debug state (they are NOT a reconnect).
    if (event.scenario == ChatThreadScenario.normal && wasOffline && !_isOffline() && current is Initialized) {
      await _redeliverQueued(emit);
      return;
    }

    // Any other scenario switch is a debug reset: drop stale optimistic bubbles so a
    // previous scenario's sends don't leak into (e.g.) the empty state.
    if (current is Initialized) emit(current.copyWith(outgoing: const [], draftAttachment: null));
    add(state is Initialized ? const ChatThreadEvent.loadMessages(reset: true) : ChatThreadEvent.initialize(_chatId));
  }

  /// Re-deliver every message queued as `pending` while offline (own optimistic sends
  /// held back by [_deliver]'s offline guard). Called on the offline→online transition.
  Future<void> _redeliverQueued(Emitter<ChatThreadState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    final queued = current.outgoing.where((message) => message.status == MessageStatus.pending).toList();
    for (final message in queued) {
      await _deliver(message.id, text: message.text, attachment: message.attachment, emit: emit);
    }
  }

  Future<void> _onConnectivityChanged(ConnectivityChanged event, Emitter<ChatThreadState> emit) async {
    final wasOffline = _isOffline();
    _deviceOnline = event.online;
    final nowOffline = _isOffline();
    if (wasOffline == nowOffline) return; // no effective change (a debug scenario may pin offline)
    final current = state;
    if (current is Initialized) emit(current.copyWith(isOffline: nowOffline)); // banner in place, no reload
    // Reconnected → flush the offline send-queue.
    if (!nowOffline) await _redeliverQueued(emit);
  }
}

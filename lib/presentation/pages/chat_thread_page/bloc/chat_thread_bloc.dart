import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/chat/outbox_entry.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/mime_types.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/general/identity/identity_resolver.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';
import 'package:rxdart/rxdart.dart';

part 'chat_thread_bloc.freezed.dart';
part 'chat_thread_event.dart';
part 'chat_thread_state.dart';

/// Chat thread (5.2) over the cache-first message repository. PagingState-in-state
/// with a SEQ CURSOR rather than page numbers (feature 025): [Initialized.oldestLoadedSeq]
/// is the `before_seq` of the next older batch, pulled in on scroll-up via sequential();
/// plus `outgoing` — a PROJECTION of the durable outbox (feature 027), not a
/// list this bloc owns. Unsent messages therefore survive leaving the screen and
/// restarting the app, and this bloc no longer sends anything itself: it
/// enqueues and asks [OutboxService] to drain.
/// Resolves [MessageRepository] from DI (mock-backed until the 016 flip). Offline /
/// empty / fatal / send-error are reproduced by [ChatThreadScenario] (debug).
class ChatThreadBloc extends BaseBloc<ChatThreadEvent, ChatThreadState> {
  ChatThreadBloc() : super(const ChatThreadState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadMessages>(_onLoadMessages, transformer: sequential());
    on<MessageSent>(_onMessageSent);
    on<SendRetried>(_onSendRetried);
    on<SendDiscarded>(_onSendDiscarded);
    // sequential() so a burst of queue ticks cannot interleave two re-projections
    // and emit a stale `outgoing` after a fresh one.
    on<OutboxChanged>(_onOutboxChanged, transformer: sequential());
    on<AttachmentPicked>(_onAttachmentPicked);
    on<AttachmentRemoved>(_onAttachmentRemoved);
    on<ConnectivityChanged>(_onConnectivityChanged, transformer: sequential());
    on<SetScenario>(_onSetScenario);
  }

  final MessageRepository _messageRepository = getIt<MessageRepository>();
  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final SessionRepository _sessionRepository = getIt<SessionRepository>();
  final FilePickerService _filePickerService = getIt<FilePickerService>();
  final SessionPhaseService _sessionPhaseService = getIt<SessionPhaseService>();
  final OutboxRepository _outboxRepository = getIt<OutboxRepository>();
  final OutboxService _outboxService = getIt<OutboxService>();

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

  // Live projection of the durable queue for THIS chat. What makes an unsent
  // message reappear after a restart: the bloc reads the queue, it does not
  // hold it.
  StreamSubscription<List<OutboxEntry>>? _outboxSub;
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
    // The durable queue for this chat. No skip(1): the FIRST snapshot is the
    // point — it is what restores a message written before the app was closed.
    _outboxSub ??= _outboxRepository.watchQueue(chatId: _chatId).listen((entries) => add(ChatThreadEvent.outboxChanged(entries)));
  }

  @override
  Future<void> close() {
    _messagesSub?.cancel();
    _connSub?.cancel();
    _outboxSub?.cancel();
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

    // Enqueue FIRST: the repository mints and persists the idempotency key in
    // the same write, so from this point on the message survives leaving the
    // screen, and a retry — even after a restart — carries the same key.
    final queued = await _outboxRepository.enqueue(chatId: _chatId, text: text, attachment: event.attachment);
    final entry = queued.data;
    // A failed write means the local store is unusable, which the thread cannot
    // paper over: `outgoing` is a projection of the queue, so there is nowhere
    // to put a bubble that is not in it. The draft attachment survives (it is
    // only cleared on the success path below) and the repository has already
    // logged the failure; the message simply never appears, which is at least
    // honest — the alternative is a bubble that nothing can ever deliver.
    if (entry == null) return;

    // Render the bubble NOW rather than waiting for the queue's own tick:
    // waiting would put its appearance at the mercy of the scheduler, and the
    // send goldens pump a bounded number of frames. The tick arrives moments
    // later and re-projects the same row under the same key, so the state it
    // produces is equal and the bloc drops it.
    emit(current.copyWith(outgoing: [...current.outgoing, _project(entry)], draftAttachment: null));

    if (_scenario == ChatThreadScenario.sendError) {
      // Debug-only: reproduce the failed-send state without a real refusal.
      await _outboxRepository.recordFailure(clientMessageId: entry.clientMessageId, code: 'internal', terminal: true);
      return;
    }
    if (_isOffline()) return; // stays queued until the channel is back
    unawaited(_outboxService.flush());
  }

  Future<void> _onSendRetried(SendRetried event, Emitter<ChatThreadState> emit) async {
    await _outboxRepository.markPending(clientMessageId: event.localId);
    if (_scenario == ChatThreadScenario.sendError) {
      await _outboxRepository.recordFailure(clientMessageId: event.localId, code: 'internal', terminal: true);
      return;
    }
    if (_isOffline()) return;
    unawaited(_outboxService.flush());
  }

  Future<void> _onSendDiscarded(SendDiscarded event, Emitter<ChatThreadState> emit) async {
    // The message is thrown away deliberately, so nothing is left behind: the
    // record goes, and the projection tick removes the bubble.
    await _outboxRepository.remove(clientMessageId: event.localId);
  }

  /// Re-projects the queue, and re-reads the cache only when it SHRANK.
  ///
  /// The shrink is the interesting case: an entry leaves the queue exactly when
  /// the server accepted it, so the message has just been persisted and the two
  /// have to swap in a SINGLE emit — reacting to them separately would blank
  /// the bubble in between. The drain's ordering is what makes one pass
  /// correct: the record is removed only after the message is in the store.
  ///
  /// Growth and status changes need no read at all. Skipping it is not just an
  /// optimisation: a read fired on every tick would keep the store busy long
  /// after the screen is gone, and in a widget test it outlives the tree.
  Future<void> _onOutboxChanged(OutboxChanged event, Emitter<ChatThreadState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    final projected = [for (final entry in event.entries) _project(entry)];
    // The optimistic emit in _onMessageSent already produced this exact list, so
    // the tick that follows it is a no-op rather than a second frame.
    if (_sameQueue(current.outgoing, projected)) return;

    final vanished = projected.map((m) => m.id).toSet();
    final accepted = current.outgoing.any((m) => !vanished.contains(m.id));
    if (!accepted) {
      emit(current.copyWith(outgoing: projected));
      return;
    }
    await _refreshMessages(current, emit, outgoing: projected);
  }

  bool _sameQueue(List<MessageModel> a, List<MessageModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Renders a queued send as the same optimistic bubble the thread drew before
  /// the queue was durable: same id (the idempotency key), same statuses.
  MessageModel _project(OutboxEntry entry) {
    return MessageModel(
      id: entry.clientMessageId,
      chatId: entry.chatId,
      authorId: _identity.id,
      authorLabel: _identity.label,
      text: entry.text,
      attachment: entry.attachment,
      sentAt: entry.createdAt,
      status: entry.status == OutboxStatus.error ? MessageStatus.error : MessageStatus.pending,
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
  Future<void> _refreshMessages(Initialized live0, Emitter<ChatThreadState> emit, {List<MessageModel>? outgoing}) async {
    if (_scenario == ChatThreadScenario.fatal || _scenario == ChatThreadScenario.empty) {
      // The debug states own the whole thread, but a queue projection must
      // still land — otherwise a discarded bubble would linger in them.
      if (outgoing != null) {
        final pinned = state;
        if (pinned is Initialized) emit(pinned.copyWith(outgoing: outgoing));
      }
      return;
    }
    // An inbound that lands in the currently-viewed chat stays read (no-op at 0 otherwise).
    unawaited(_chatRepository.markChatRead(chatId: _chatId));
    // Only the newest batch: asking for the whole loaded span would exceed the
    // contract's ceiling past ~100 rows and come back CLAMPED, collapsing the
    // thread the refresh was meant to keep current. Older rows cannot change —
    // contract v0 has neither edit nor delete — so re-reading them buys nothing.
    final result = await _messageRepository.getMessages(
      config: GetMessagesConfig.tail(chatId: _chatId, limit: live0.items.length + GetMessagesConfig.pageSize, cachedOnly: true),
    );
    if (!result.hasData) {
      // Swallow a background read error — but never swallow the projection, or
      // a bubble the drain already sent would stay on screen.
      if (outgoing != null) {
        final pinned = state;
        if (pinned is Initialized) emit(pinned.copyWith(outgoing: outgoing));
      }
      return;
    }
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
        outgoing: outgoing ?? live.outgoing,
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
      unawaited(_outboxService.flush());
      return;
    }

    // Any other scenario switch is a debug reset: drop stale queued bubbles so a
    // previous scenario's sends don't leak into (e.g.) the empty state. The
    // records go too — `outgoing` is a projection now, so clearing only the
    // state would be undone by the queue's very next tick.
    await _outboxRepository.removeForChat(chatId: _chatId);
    if (current is Initialized) emit(current.copyWith(outgoing: const [], draftAttachment: null));
    add(state is Initialized ? const ChatThreadEvent.loadMessages(reset: true) : ChatThreadEvent.initialize(_chatId));
  }

  Future<void> _onConnectivityChanged(ConnectivityChanged event, Emitter<ChatThreadState> emit) async {
    final wasOffline = _isOffline();
    _deviceOnline = event.online;
    final nowOffline = _isOffline();
    if (wasOffline == nowOffline) return; // no effective change (a debug scenario may pin offline)
    final current = state;
    if (current is Initialized) emit(current.copyWith(isOffline: nowOffline)); // banner in place, no reload
    // Reconnected → ask for a drain. Re-delivery itself is no longer this
    // bloc's job: a single sender is what keeps a connectivity flap from
    // posting the same message twice.
    if (!nowOffline) unawaited(_outboxService.flush());
  }
}

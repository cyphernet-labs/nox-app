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
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

part 'chat_thread_bloc.freezed.dart';
part 'chat_thread_event.dart';
part 'chat_thread_state.dart';

/// Chat thread (5.2) — the second blueprint network-only feature after the chats
/// list. PagingState-in-state (older history paged in on scroll-up via sequential()),
/// plus an `outgoing` list for optimistic sends (pending → sent / error + retry).
/// Resolves [MessageRepository] from DI (mock-backed in the UI phase). Offline /
/// empty / fatal / send-error are reproduced by [ChatThreadScenario] (debug).
class ChatThreadBloc extends BaseBloc<ChatThreadEvent, ChatThreadState> {
  ChatThreadBloc() : super(const ChatThreadState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadMessages>(_onLoadMessages, transformer: sequential());
    on<MessageSent>(_onMessageSent);
    on<SendRetried>(_onSendRetried);
    on<AttachmentPicked>(_onAttachmentPicked);
    on<AttachmentRemoved>(_onAttachmentRemoved);
    on<SetScenario>(_onSetScenario);
  }

  final MessageRepository _messageRepository = getIt<MessageRepository>();

  late String _chatId;
  ChatThreadScenario _scenario = ChatThreadScenario.normal;
  int _localCounter = 0;

  FutureOr<void> _onInitialize(Initialize event, Emitter<ChatThreadState> emit) async {
    _chatId = event.chatId;
    emit(ChatThreadState.initialized(pagingState: PagingState<String, MessageModel>(), currentId: IdentityMockData.currentUserId));
    add(const ChatThreadEvent.loadMessages(reset: true));
  }

  FutureOr<void> _onLoadMessages(LoadMessages event, Emitter<ChatThreadState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    if (current.loadingInProgress) return;

    // Fatal short-circuits to the error state (3.1).
    if (_scenario == ChatThreadScenario.fatal) {
      emit(const ChatThreadState.error());
      return;
    }

    final isReset = event.reset;
    if (!isReset && !current.pagingState.hasNextPage) return;

    final nextPageKey = isReset ? GetMessagesConfig.defaultPage : current.nextPage;
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
            response: (const [], const PageMetadata(total: 0)),
            keyExtractor: (m) => m.id,
          );
          emit(live.copyWith(items: const [], pagingState: r.pagingState, loadingInProgress: false, isOffline: false));
          return;
        }

        final config = GetMessagesConfig.nextPage(chatId: _chatId, page: nextPageKey);
        final result = await _messageRepository.getMessages(config: config);

        final live = state;
        if (live is! Initialized) return;

        result.match<void>(
          onData: (data) {
            final (messages, PageMetadata metadata) = data;
            final r = basePagingState.applyPage(existingList: existingList, response: (messages, metadata), keyExtractor: (m) => m.id);
            emit(
              live.copyWith(
                items: r.updatedList,
                pagingState: r.pagingState,
                nextPage: r.nextPage ?? live.nextPage,
                loadingInProgress: false,
                isOffline: _scenario == ChatThreadScenario.offline,
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

    final localId = 'local_${_localCounter++}';
    final optimistic = MessageModel(
      id: localId,
      chatId: _chatId,
      authorId: current.currentId,
      authorLabel: IdentityMockData.currentLabel,
      text: text,
      attachment: event.attachment,
      sentAt: DateTime.now(),
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
    if (_scenario == ChatThreadScenario.offline) return; // queued as pending until restored
    await executeLogic(() async {
      if (_scenario == ChatThreadScenario.sendError) {
        _updateOutgoing(localId, MessageStatus.error, emit);
        return;
      }
      final result = await _messageRepository.sendMessage(chatId: _chatId, text: text, attachment: attachment);
      result.match<void>(
        onData: (_) => _updateOutgoing(localId, MessageStatus.sent, emit),
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

  void _onAttachmentPicked(AttachmentPicked event, Emitter<ChatThreadState> emit) {
    final current = state;
    if (current is! Initialized) return;
    // TODO(backend): real file picker (file_picker) — Phase 2. UI-phase stub.
    emit(
      current.copyWith(
        draftAttachment: const MessageAttachment(id: 'draft', type: FileType.image, name: 'photo.jpg', sizeBytes: 1843200),
      ),
    );
  }

  void _onAttachmentRemoved(AttachmentRemoved event, Emitter<ChatThreadState> emit) {
    final current = state;
    if (current is! Initialized) return;
    emit(current.copyWith(draftAttachment: null));
  }

  FutureOr<void> _onSetScenario(SetScenario event, Emitter<ChatThreadState> emit) async {
    final previous = _scenario;
    _scenario = event.scenario;
    // send-error only affects the next send.
    if (event.scenario == ChatThreadScenario.sendError) return;

    final current = state;
    // Connectivity restored (offline → normal): re-deliver the messages that were
    // queued as pending while offline, keeping the already-loaded history.
    if (event.scenario == ChatThreadScenario.normal && previous == ChatThreadScenario.offline && current is Initialized) {
      final queued = current.outgoing.where((message) => message.status == MessageStatus.pending).toList();
      for (final message in queued) {
        await _deliver(message.id, text: message.text, attachment: message.attachment, emit: emit);
      }
      return;
    }

    // Any other scenario switch is a debug reset: drop stale optimistic bubbles so a
    // previous scenario's sends don't leak into (e.g.) the empty state.
    if (current is Initialized) emit(current.copyWith(outgoing: const [], draftAttachment: null));
    add(state is Initialized ? const ChatThreadEvent.loadMessages(reset: true) : ChatThreadEvent.initialize(_chatId));
  }
}

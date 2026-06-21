import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';

part 'chats_list_bloc.freezed.dart';
part 'chats_list_event.dart';
part 'chats_list_state.dart';

/// Chats list (5.1) — the open shared space. Network-only paginated list mirroring
/// [ItemListBloc] (PagingState-in-state, sequential() loads, executeLogic + onError).
/// Resolves [ChatRepository] from DI (mock-backed in the UI phase). Search filters
/// server-side via [GetChatsConfig.search] (debounced); offline / inline-error /
/// fatal / empty states are reproduced by [ChatsListScenario] (debug). Desktop
/// list-detail selection (`selectedChatId`) is view-state, not a navigation push.
class ChatsListBloc extends BaseBloc<ChatsListEvent, ChatsListState> {
  ChatsListBloc() : super(const ChatsListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadChats>(_onLoadChats, transformer: sequential());
    on<SearchChanged>(_onSearchChanged, transformer: debounceRestartable());
    on<ChatSelected>(_onChatSelected);
    on<SetScenario>(_onSetScenario);
  }

  final ChatRepository _chatRepository = getIt<ChatRepository>();

  // Debug-only stub scenario (offline / inline-error / fatal / empty), selected via
  // the dev control. `// TODO(backend):` real connectivity + error surfacing.
  ChatsListScenario _scenario = ChatsListScenario.normal;

  FutureOr<void> _onInitialize(Initialize event, Emitter<ChatsListState> emit) async {
    emit(ChatsListState.initialized(pagingState: PagingState<String, ChatModel>()));
    add(const ChatsListEvent.loadChats(reset: true));
  }

  void _onChatSelected(ChatSelected event, Emitter<ChatsListState> emit) {
    final current = state;
    if (current is Initialized) emit(current.copyWith(selectedChatId: event.id));
  }

  FutureOr<void> _onSearchChanged(SearchChanged event, Emitter<ChatsListState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    // Drop any desktop selection — the selected chat may be filtered out by the
    // new query (would otherwise leave a stale thread pane / highlight).
    emit(current.copyWith(query: event.query, selectedChatId: null));
    add(const ChatsListEvent.loadChats(reset: true));
  }

  FutureOr<void> _onSetScenario(SetScenario event, Emitter<ChatsListState> emit) async {
    _scenario = event.scenario;
    // From the Error state a plain loadChats early-returns (state is not Initialized);
    // re-initialize so switching the debug scenario away from `fatal` recovers.
    add(state is Initialized ? const ChatsListEvent.loadChats(reset: true) : const ChatsListEvent.initialize());
  }

  FutureOr<void> _onLoadChats(LoadChats event, Emitter<ChatsListState> emit) async {
    final current = state;
    if (current is! Initialized) return;
    if (current.loadingInProgress) return;

    // Fatal short-circuits to the error state (3.1).
    if (_scenario == ChatsListScenario.fatal) {
      emit(const ChatsListState.error());
      return;
    }

    final isReset = event.reset;
    if (!isReset && !current.pagingState.hasNextPage) return;

    final nextPageKey = isReset ? GetChatsConfig.defaultPage : current.nextPage;
    final existingList = isReset ? <ChatModel>[] : current.items;
    final basePagingState = isReset
        ? PagingState<String, ChatModel>(isLoading: true)
        : current.pagingState.copyWith(isLoading: true, error: null);

    emit(current.copyWith(loadingInProgress: true, items: existingList, pagingState: basePagingState));

    await executeLogic(
      () async {
        // Empty scenario: return an empty page without hitting the repository.
        if (_scenario == ChatsListScenario.empty) {
          final live = state;
          if (live is! Initialized) return;
          final r = basePagingState.applyPage(
            existingList: const [],
            response: (const [], const PageMetadata(total: 0)),
            keyExtractor: (c) => c.id,
          );
          emit(live.copyWith(items: const [], pagingState: r.pagingState, loadingInProgress: false, isOffline: false, hasLoadError: false));
          return;
        }

        final config = GetChatsConfig.nextPage(page: nextPageKey, search: current.query.isEmpty ? null : current.query);
        final result = await _chatRepository.getChats(config: config);

        final live = state;
        if (live is! Initialized) return;

        result.match<void>(
          onData: (data) {
            final (chats, PageMetadata metadata) = data;
            final r = basePagingState.applyPage(existingList: existingList, response: (chats, metadata), keyExtractor: (c) => c.id);
            emit(
              live.copyWith(
                items: r.updatedList,
                pagingState: r.pagingState,
                nextPage: r.nextPage ?? live.nextPage,
                loadingInProgress: false,
                // Offline shows the cached list under a banner; inline-error shows the
                // cached list under a retry banner (both keep the data visible).
                isOffline: _scenario == ChatsListScenario.offline,
                hasLoadError: _scenario == ChatsListScenario.inlineError,
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
          emit(
            live.copyWith(
              loadingInProgress: false,
              pagingState: live.pagingState.copyWith(isLoading: false, error: RepositoryException.unknown),
            ),
          );
        }
      },
    );
  }
}

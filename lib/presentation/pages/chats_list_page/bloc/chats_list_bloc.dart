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
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/repository/base/repository_result_handling.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/presentation/base/base_bloc.dart';
import 'package:nox_app/presentation/base/bloc_transformers.dart';
import 'package:nox_app/presentation/pagination/paging_state_ext.dart';
import 'package:rxdart/rxdart.dart';

part 'chats_list_bloc.freezed.dart';
part 'chats_list_event.dart';
part 'chats_list_state.dart';

/// Chats list (5.1) — the open shared space. Paginated list mirroring [ItemListBloc]
/// (PagingState-in-state, sequential() loads, executeLogic + onError) over the
/// cache-first chat repository, kept live by a `watchChats()` change-signal.
/// Resolves [ChatRepository] from DI (mock-backed until the 016 flip). Search filters
/// via [GetChatsConfig.search] (debounced); offline / inline-error /
/// fatal / empty states are reproduced by [ChatsListScenario] (debug). Desktop
/// list-detail selection (`selectedChatId`) is view-state, not a navigation push.
class ChatsListBloc extends BaseBloc<ChatsListEvent, ChatsListState> {
  ChatsListBloc() : super(const ChatsListState.initializing()) {
    on<Initialize>(_onInitialize);
    on<LoadChats>(_onLoadChats, transformer: sequential());
    on<SearchChanged>(_onSearchChanged, transformer: debounceRestartable());
    on<ChatSelected>(_onChatSelected);
    on<SetScenario>(_onSetScenario);
    on<ConnectivityChanged>(_onConnectivityChanged);
  }

  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final MessageRepository _messageRepository = getIt<MessageRepository>();
  final SessionPhaseService _sessionPhaseService = getIt<SessionPhaseService>();

  // Live change-signal over the cache-first DB (Feature 014): a DB write (create / send /
  // incoming / read) re-reads the loaded page prefix. The stream VALUE is ignored — the
  // authoritative re-read goes through getChats so one projection path serves both loads
  // and refreshes.
  StreamSubscription<List<ChatModel>>? _chatsSub;

  // Debug-only stub scenario (inline-error / fatal / empty), selected via the dev
  // control. The `offline` scenario still forces the banner for previews/goldens, but
  // real device connectivity now ALSO drives it (feature F3) — see `_isOffline`.
  ChatsListScenario _scenario = ChatsListScenario.normal;

  // Live device-online state (feature F3): a real connectivity signal (connectivity_plus,
  // seeded then live). The Offline banner is reachable in the real flow — go offline and
  // the cached list shows under the "No connection" banner. NOTE: the mock phase is
  // local-only (Sembast), so sends still succeed offline; the banner is informational
  // until real sync lands. Backend reachability (vs device connectivity) is the eventual
  // authority — this is the closest real-flow proxy for now.
  StreamSubscription<SessionPhase>? _connSub;
  bool _isDeviceOnline = true;

  /// The Offline banner shows when the device is offline OR the debug scenario forces it.
  bool _isOffline() => !_isDeviceOnline || _scenario == ChatsListScenario.offline;

  /// Marks the first two chats read and drops messages above the mark, so the
  /// list shows badges produced by the recount rather than by a seeded number.
  Future<void> _seedUnreadForDebug() async {
    final page = await _chatRepository.getChats(config: GetChatsConfig.firstPage());
    final chats = page.match<List<ChatModel>>(onData: (data) => data.$1, onError: (_) => const []);
    for (final (index, chat) in chats.take(2).indexed) {
      await _chatRepository.markChatRead(chatId: chat.id);
      for (var i = 0; i <= index * 4; i++) {
        await _messageRepository.simulateIncoming(chatId: chat.id);
      }
    }
  }

  FutureOr<void> _onInitialize(Initialize event, Emitter<ChatsListState> emit) async {
    emit(ChatsListState.initialized(pagingState: PagingState<String, ChatModel>()));
    add(const ChatsListEvent.loadChats(reset: true));
    // skip(1) drops the initial snapshot the reset load already covers; debounceTime
    // coalesces write bursts (e.g. a send's message + chat-row writes) into one refresh.
    _chatsSub ??= _chatRepository
        .watchChats()
        .skip(1)
        .debounceTime(const Duration(milliseconds: 100))
        .listen((_) => add(const ChatsListEvent.loadChats(refresh: true)));
    // Live connectivity → the Offline banner (seeded current value, then every change).
    // The session phase, not raw device connectivity, is what says whether the
    // data on screen is current: a device can be online while the socket is
    // down, and the socket can be open while replay is still running (FR-005).
    _connSub ??= _sessionPhaseService.watchPhase().listen((phase) => add(ChatsListEvent.connectivityChanged(phase.isCurrent)));
  }

  @override
  Future<void> close() {
    _chatsSub?.cancel();
    _connSub?.cancel();
    return super.close();
  }

  void _onConnectivityChanged(ConnectivityChanged event, Emitter<ChatsListState> emit) {
    _isDeviceOnline = event.online;
    final current = state;
    // Update the banner in place (no reload) — like the reactive card's files re-derive.
    if (current is Initialized) emit(current.copyWith(isOffline: _isOffline()));
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

    // Live refresh: re-read the loaded prefix invisibly (serialised with reset/load-more
    // on this same sequential() handler).
    if (event.refresh) {
      await _refresh(current, emit);
      return;
    }

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
            response: (const [], const PageMetadata(hasMore: false)),
            keyExtractor: (c) => c.id,
          );
          emit(
            live.copyWith(
              items: const [],
              pagingState: r.pagingState,
              loadedPageCount: 1,
              loadingInProgress: false,
              isOffline: false,
              hasLoadError: false,
            ),
          );
          return;
        }

        // Debug: produce a badge the way the product does - open a chat, then
        // let messages arrive above the mark. Seeding a number instead would
        // lock a golden against a value nothing in the app can now produce.
        if (_scenario == ChatsListScenario.unread && isReset) await _seedUnreadForDebug();

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
                loadedPageCount: isReset ? 1 : live.loadedPageCount + 1,
                loadingInProgress: false,
                // Offline shows the cached list under a banner; inline-error shows the
                // cached list under a retry banner (both keep the data visible). Offline =
                // real device connectivity OR the debug scenario (feature F3).
                isOffline: _isOffline(),
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

  /// Invisible live re-read of the currently-loaded page prefix (no spinner, never a
  /// full-screen Error). Re-queries pages 1..loadedPageCount and re-folds them onto the
  /// LIVE state so query / selection / scroll / loaded-page-count all carry through.
  Future<void> _refresh(Initialized live0, Emitter<ChatsListState> emit) async {
    // Don't overwrite the stubbed debug scenarios.
    if (_scenario == ChatsListScenario.fatal || _scenario == ChatsListScenario.empty) return;
    // Read the loaded window from the CURRENT state, not from the snapshot this
    // refresh was queued with: a load-more that landed in between would other-
    // wise be undone, silently shrinking the list back to one page.
    final queued = state;
    final loadedPages = queued is Initialized ? queued.loadedPageCount : live0.loadedPageCount;
    final query = live0.query;
    final search = query.isEmpty ? null : query;
    final all = <ChatModel>[];
    PageMetadata? lastMeta;
    for (var page = GetChatsConfig.defaultPage; page < GetChatsConfig.defaultPage + loadedPages; page++) {
      final live = state;
      if (live is! Initialized || live.query != query) return; // superseded by a newer search/reset
      // Cache-only: events keep the store current, so the tick re-projects it
      // instead of firing one command per loaded page every time anything moves.
      final result = await _chatRepository.getChats(
        config: GetChatsConfig.nextPage(page: page, search: search).copyWith(cachedOnly: true),
      );
      if (!result.hasData) return; // swallow a background error — keep the current list
      final (chats, meta) = result.data!;
      all.addAll(chats);
      lastMeta = meta;
    }
    final live = state;
    if (live is! Initialized || live.query != query || lastMeta == null) return;
    final r = PagingState<String, ChatModel>().applyPage(existingList: const [], response: (all, lastMeta), keyExtractor: (c) => c.id);
    emit(live.copyWith(items: r.updatedList, pagingState: r.pagingState, nextPage: r.nextPage ?? live.nextPage));
  }
}

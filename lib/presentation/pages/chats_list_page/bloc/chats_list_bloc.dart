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
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
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

/// Chats list (5.1) — every chat on this person's own server. Paginated list mirroring [ItemListBloc]
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
    on<ConnectionStatusChanged>(_onConnectionStatusChanged);
    on<FirstPageSynced>(_onFirstPageSynced);
    on<RetryConnection>(_onRetryConnection);
  }

  final ChatRepository _chatRepository = getIt<ChatRepository>();
  final MessageRepository _messageRepository = getIt<MessageRepository>();
  final SessionPhaseService _sessionPhaseService = getIt<SessionPhaseService>();
  final ConnectionStatusService _connectionStatus = getIt<ConnectionStatusService>();

  // Live change-signal over the cache-first DB (Feature 014): a DB write (create / send /
  // incoming / read) re-reads the loaded page prefix. The stream VALUE is ignored — the
  // authoritative re-read goes through getChats so one projection path serves both loads
  // and refreshes.
  StreamSubscription<List<ChatModel>>? _chatsSub;

  // Debug-only stub scenario (inline-error / fatal / empty), selected via the dev
  // control. The `offline` scenario still forces the banner for previews/goldens, but
  // real device connectivity now ALSO drives it (feature F3) — see `_isOffline`.
  ChatsListScenario _scenario = ChatsListScenario.normal;

  // Where the connection stands (feature F3, widened by 036 and 040). The whole
  // status is kept, not a boolean derived from it: a server presenting the
  // wrong key is not a stale-data problem, and a path still coming up - the
  // corner says `Connecting…` then - is not an outage either.
  StreamSubscription<ConnectionStatus>? _connSub;
  late ConnectionStatus _status = _connectionStatus.status;

  /// The wrong machine answered. Takes precedence over the offline banner: both
  /// would otherwise show at once, and "no connection" is simply false here.
  bool _isServerMismatch() => _status.isServerMismatch || _scenario == ChatsListScenario.pinRefused;

  /// «No connection» is for a whole round of path finding that found nothing,
  /// not for a path still on its way (phase 040) - or the debug scenario.
  bool _isOffline() =>
      !_isServerMismatch() &&
      (_status.showsNoConnection || _scenario == ChatsListScenario.offline || _scenario == ChatsListScenario.turnOnTor);

  /// Why, when that is known (phase 045) - or the debug scenarios' stand-ins.
  ConnectionProblem? _problem() {
    if (_scenario == ChatsListScenario.pinRefused) return ConnectionProblem.otherServer;
    if (_scenario == ChatsListScenario.turnOnTor) return ConnectionProblem.turnOnTor;
    return _isOffline() || _isServerMismatch() ? _status.problem : null;
  }

  /// The server refuses this build (phase 042): the strip stays, its action
  /// does not - trying again cannot change the answer.
  bool _isUnsupported() => _status.state == LinkState.unsupported;

  /// Whether a read reaches the server now: once the greeting is done, the
  /// catch-up included - which is when the socket lets reads out.
  bool _canRead() => _status.state == LinkState.online || _status.state == LinkState.catchingUp;

  /// Numbers the background reads of page 1, so an older one finishing late
  /// cannot end the spinner a newer one is holding.
  int _syncGeneration = 0;

  /// The Tor network refused the client built into this version (FR-026).
  bool _isTorObsolete() => _status.torObsolete || _scenario == ChatsListScenario.torObsolete;

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
    // Where the connection stands → the banners (current value, then every
    // change). Not raw device connectivity: a device can be online while its
    // server is out of reach, and offline is only decided once a whole round
    // of path finding has come back empty (phase 040).
    _connSub ??= _connectionStatus.watchStatus().listen((status) => add(ChatsListEvent.connectionStatusChanged(status)));
  }

  @override
  Future<void> close() {
    _chatsSub?.cancel();
    _connSub?.cancel();
    return super.close();
  }

  void _onConnectionStatusChanged(ConnectionStatusChanged event, Emitter<ChatsListState> emit) {
    final couldRead = _canRead();
    _status = event.status;
    final current = state;
    // Update the banners in place (no reload) — like the reactive card's files re-derive.
    if (current is Initialized) {
      emit(
        current.copyWith(
          isOffline: _isOffline(),
          isServerMismatch: _isServerMismatch(),
          isUnsupported: _isUnsupported(),
          problem: _problem(),
          torObsolete: _isTorObsolete(),
        ),
      );
      // The list was read from the cache while there was no channel; now the
      // server can be asked.
      if (!couldRead && _canRead()) unawaited(_syncFirstPage(current.query));
    }
  }

  /// One more attempt, asked for by the person.
  ///
  /// Nothing is emitted here: the phase stream is what moves the banner, and
  /// guessing at the outcome would clear it before there is an outcome.
  Future<void> _onRetryConnection(RetryConnection event, Emitter<ChatsListState> emit) => _sessionPhaseService.reconnect();

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
    // The list has no pages while it waits for the server's first one, and
    // PagedListView asks for the "next" page of any list without pages. That
    // request read a later page of the PREVIOUS query and ended the spinner.
    if (!event.reset && current.syncing) return;

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

    // A reset does not blank the list: the cache answers in a moment, and a
    // spinner in between flashed on every keystroke of a search. Load-more
    // shows its loader at the bottom as before.
    emit(
      isReset
          ? current.copyWith(loadingInProgress: true)
          : current.copyWith(loadingInProgress: true, items: existingList, pagingState: basePagingState),
    );

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

        // The first page is read from the CACHE: the chats this device holds
        // are on screen at once, whatever the connection is doing, and the
        // server's page follows in the background (_syncFirstPage) through
        // the watch. Asking the server first kept the list behind a spinner
        // for as long as Tor took to come up. A later page still goes to the
        // server - the person scrolled past the cache - and that read never
        // waits for a connection that is not there.
        final config = GetChatsConfig.nextPage(page: nextPageKey, search: current.query.isEmpty ? null : current.query);
        final result = await _chatRepository.getChats(config: isReset ? config.copyWith(cachedOnly: true) : config);

        final live = state;
        if (live is! Initialized) return;

        result.match<void>(
          onData: (data) {
            final (chats, PageMetadata metadata) = data;
            // Nothing on the device yet, and the server is about to be asked:
            // a spinner until it answers rather than "No chats" a moment
            // before they arrive. With no channel the empty list is the truth.
            final syncing = isReset && chats.isEmpty && _canRead();
            final r = basePagingState.applyPage(existingList: existingList, response: (chats, metadata), keyExtractor: (c) => c.id);
            emit(
              live.copyWith(
                items: r.updatedList,
                pagingState: syncing ? PagingState<String, ChatModel>(isLoading: true, hasNextPage: false) : r.pagingState,
                // A reset starts the paging over: the previous list's next page
                // belongs to another query.
                nextPage: r.nextPage ?? (isReset ? GetChatsConfig.defaultPage + 1 : live.nextPage),
                loadedPageCount: isReset ? 1 : live.loadedPageCount + 1,
                loadingInProgress: false,
                syncing: syncing,
                // Offline shows the cached list under a banner; inline-error shows the
                // cached list under a retry banner (both keep the data visible). Offline =
                // real device connectivity OR the debug scenario (feature F3).
                isOffline: _isOffline(),
                isServerMismatch: _isServerMismatch(),
                isUnsupported: _isUnsupported(),
                problem: _problem(),
                torObsolete: _isTorObsolete(),
                hasLoadError: _scenario == ChatsListScenario.inlineError,
              ),
            );
          },
          onError: (exception) {
            emit(
              live.copyWith(
                // A reset no longer blanks the list first, so a failed one has to:
                // the rows on screen belong to the previous query.
                items: isReset ? const <ChatModel>[] : live.items,
                pagingState: (isReset ? PagingState<String, ChatModel>() : live.pagingState).copyWith(isLoading: false, error: exception),
                loadingInProgress: false,
              ),
            );
          },
        );
        if (isReset && result.hasData) unawaited(_syncFirstPage(live.query));
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

  /// Asks the server for the first page, off the load handler: a read awaited
  /// there would hold every refresh behind it. What it brings lands through
  /// the watch. With no live channel the read fails at once and the cache
  /// answers; the status turning current calls this again.
  Future<void> _syncFirstPage(String query) async {
    if (_scenario == ChatsListScenario.fatal || _scenario == ChatsListScenario.empty) return;
    final generation = ++_syncGeneration;
    final result = await _chatRepository.getChats(
      config: GetChatsConfig.nextPage(page: GetChatsConfig.defaultPage, search: query.isEmpty ? null : query),
    );
    if (isClosed) return;
    add(ChatsListEvent.firstPageSynced(query: query, hasMore: result.data?.$2.hasMore, generation: generation));
  }

  /// The server's first page is in the cache, or could not be had: the list
  /// is re-read now. Not left to the watch: a server with no chats writes
  /// nothing, so no tick would end a spinner held for it, and the watch skips
  /// its first snapshot - rows written before that snapshot was taken are in it.
  ///
  /// `hasNextPage` is only ever switched ON here, as in the thread: a load-more
  /// made while the channel was down came back short from the cache and
  /// switched it off, and only page 1 is read again when the channel returns -
  /// without this the chats past the cache stayed out of reach of scrolling.
  /// A load-more that then finds nothing switches it off again.
  void _onFirstPageSynced(FirstPageSynced event, Emitter<ChatsListState> emit) {
    final current = state;
    if (current is! Initialized || current.query != event.query) return;
    final latest = event.generation == _syncGeneration;
    final more = event.hasMore == true && !current.pagingState.hasNextPage && current.items.isNotEmpty;
    if ((current.syncing && latest) || more) {
      emit(
        current.copyWith(
          syncing: latest ? false : current.syncing,
          pagingState: more ? current.pagingState.copyWith(hasNextPage: true) : current.pagingState,
          nextPage: more ? current.loadedPageCount + 1 : current.nextPage,
        ),
      );
    }
    add(const ChatsListEvent.loadChats(refresh: true));
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
    // Still waiting for the server's first page, and the cache is still empty:
    // keep the spinner rather than show "No chats" until the answer is in.
    if (live.syncing && all.isEmpty) return;
    // The cache reads "more" only off a full last page; the server may know of
    // more than the cache holds (_onFirstPageSynced). A refresh keeps that,
    // and a load-more that finds nothing switches it off.
    final meta = lastMeta.copyWith(hasMore: lastMeta.hasMore || live.pagingState.hasNextPage);
    final r = PagingState<String, ChatModel>().applyPage(existingList: const [], response: (all, meta), keyExtractor: (c) => c.id);
    emit(live.copyWith(items: r.updatedList, pagingState: r.pagingState, nextPage: r.nextPage ?? live.nextPage));
  }
}

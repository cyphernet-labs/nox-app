import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Per-test DB isolation — the reactive test mutates the DB (createChat), so each test
  // starts from a clean, freshly-seeded store.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('ChatsListBloc', () {
    blocTest<ChatsListBloc, ChatsListState>(
      'Initialize → Initialized, then a page of mock chats loads',
      build: ChatsListBloc.new,
      act: (bloc) => bloc.add(const ChatsListEvent.initialize()),
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<Initialized>());
        expect((state as Initialized).items, isNotEmpty);
        expect(state.loadingInProgress, isFalse);
      },
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'search filters the list to matching chat names',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.searchChanged('Design'));
      },
      wait: const Duration(milliseconds: 700),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.query, 'Design');
        expect(state.items, isNotEmpty);
        expect(state.items.every((c) => c.name.toLowerCase().contains('design')), isTrue);
      },
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'the empty scenario yields an empty list',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.empty));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) => expect((bloc.state as Initialized).items, isEmpty),
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'the fatal scenario emits the Error state',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.fatal));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) => expect(bloc.state, isA<Error>()),
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'the offline scenario keeps the cached list and flags offline',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.offline));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.isOffline, isTrue);
        expect(state.items, isNotEmpty);
      },
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'chatSelected records the desktop selection without leaving Initialized',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.chatSelected('chat_0'));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) => expect((bloc.state as Initialized).selectedChatId, 'chat_0'),
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'a search clears a stale desktop selection',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.chatSelected('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const ChatsListEvent.searchChanged('Garden'));
      },
      wait: const Duration(milliseconds: 700),
      verify: (bloc) => expect((bloc.state as Initialized).selectedChatId, isNull),
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'switching the scenario away from fatal recovers from the Error state',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.fatal));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.normal));
      },
      wait: const Duration(milliseconds: 600),
      verify: (bloc) {
        expect(bloc.state, isA<Initialized>());
        expect((bloc.state as Initialized).items, isNotEmpty);
      },
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'a second page appends the remaining mock chats, then further loads are a no-op',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        // Page 1: 20 of the 28 mock chats, more pages remain.
        final page1 = bloc.state as Initialized;
        expect(page1.items.length, 20);
        expect(page1.pagingState.hasNextPage, isTrue);

        bloc.add(const ChatsListEvent.loadChats(reset: false));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        // Page 2 appended: all 28 chats, no further pages.
        final page2 = bloc.state as Initialized;
        expect(page2.items.length, 28);
        expect(page2.pagingState.hasNextPage, isFalse);

        // With no next page, another load is a no-op (the list stays at 28).
        bloc.add(const ChatsListEvent.loadChats(reset: false));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.items.length, 28);
        expect(state.pagingState.hasNextPage, isFalse);
      },
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'the inline-error scenario keeps the cached list and flags a load error',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.inlineError));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.hasLoadError, isTrue);
        expect(state.items, isNotEmpty);
      },
    );

    blocTest<ChatsListBloc, ChatsListState>(
      'a chat created in the DB live-refreshes into the list without a manual reload (US1)',
      build: ChatsListBloc.new,
      act: (bloc) async {
        bloc.add(const ChatsListEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 500)); // initial load + seed
        await getIt<ChatRepository>().createChat(name: 'Zebra live chat');
        await Future<void>.delayed(const Duration(milliseconds: 400)); // watchChats change-signal → refresh
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.loadedPageCount, 1); // a live refresh does not change the loaded page count
        expect(state.items.any((c) => c.name == 'Zebra live chat'), isTrue); // appeared reactively, no manual reload
      },
    );

    test('a simulated inbound increments a chat unread badge live in the list (US4/FR-010)', () async {
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // seed + load
      final target = (bloc.state as Initialized).items.first;
      final before = target.unreadCount;

      await getIt<MessageRepository>().simulateIncoming(chatId: target.id);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // watchChats change-signal → refresh

      final after = (bloc.state as Initialized).items.firstWhere((c) => c.id == target.id);
      expect(after.unreadCount, before + 1); // badge incremented live, no manual reload
    });

    // Review finding (medium): the multi-page prefix re-read (pages 1..loadedPageCount) is the
    // heart of the reactive refresh, but was only exercised at loadedPageCount==1. This loads
    // page 2 first, then a live DB tick must re-fold BOTH pages, not collapse to page 1.
    test('a live refresh with 2 pages loaded preserves all loaded pages (loadedPageCount > 1)', () async {
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      bloc.add(const ChatsListEvent.loadChats(reset: false)); // load page 2
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect((bloc.state as Initialized).items.length, 28);
      expect((bloc.state as Initialized).loadedPageCount, 2);

      await getIt<ChatRepository>().createChat(name: 'Prefix-preserve chat');
      await Future<void>.delayed(const Duration(milliseconds: 500)); // debounced live refresh

      final state = bloc.state as Initialized;
      expect(state.loadedPageCount, 2); // pages not dropped by the refresh
      expect(state.items.length, 29); // all 28 prior + the new one (no collapse to 20)
      expect(state.items.any((c) => c.name == 'Prefix-preserve chat'), isTrue);
    });

    // Review finding (low): a live refresh while a search is active must re-query WITH the filter
    // and preserve the query (covers _refresh's filtered path + the stale-guard).
    test('a live refresh during an active search stays filtered and preserves the query', () async {
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      bloc.add(const ChatsListEvent.searchChanged('Design'));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect((bloc.state as Initialized).items.every((c) => c.name.toLowerCase().contains('design')), isTrue);

      await getIt<ChatRepository>().createChat(name: 'Design extra reactive');
      await Future<void>.delayed(const Duration(milliseconds: 600)); // debounced refresh with the active query

      final state = bloc.state as Initialized;
      expect(state.query, 'Design'); // query preserved through the refresh
      expect(state.items.every((c) => c.name.toLowerCase().contains('design')), isTrue); // stays filtered
      expect(state.items.any((c) => c.name == 'Design extra reactive'), isTrue); // the matching new chat appears
    });
  });

  group('offline banner from real connectivity (F3)', () {
    void useConnectivity(ConnectivityService service) {
      getIt.allowReassignment = true;
      getIt.registerSingleton<ConnectivityService>(service);
    }

    test('online connectivity keeps the offline banner down', () async {
      // The test-env ConnectivityService is always-online (default).
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((bloc.state as Initialized).isOffline, isFalse);
    });

    test('offline connectivity shows the banner while keeping the cached list visible', () async {
      useConnectivity(_FakeConnectivity(false));
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final state = bloc.state as Initialized;
      expect(state.isOffline, isTrue); // banner up
      expect(state.items, isNotEmpty); // the cached list is still shown under it
    });

    test('going offline live flips the banner without a reload (no item change)', () async {
      final conn = _FakeConnectivity(true);
      useConnectivity(conn);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final before = (bloc.state as Initialized);
      expect(before.isOffline, isFalse);

      // Capture whether any spinner-visible reload happens during the flip. The
      // connectivity handler emits an in-place copyWith (loadingInProgress stays false);
      // a reset-reload would flip loadingInProgress true. (A stricter items-reference
      // check is unreliable — the reactive watchChats refresh rebuilds the list
      // reference asynchronously, unrelated to the connectivity change.)
      var sawReloadSpinner = false;
      final sub = bloc.stream.listen((s) {
        if (s is Initialized && s.loadingInProgress) sawReloadSpinner = true;
      });
      addTearDown(sub.cancel);

      conn.emit(false); // device drops offline
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final after = bloc.state as Initialized;
      expect(after.isOffline, isTrue);
      expect(after.items, before.items); // the list content is preserved under the banner
      expect(sawReloadSpinner, isFalse); // banner flips in place — no reset-reload spinner
    });

    test('reconnecting clears the offline banner (recovery path)', () async {
      final conn = _FakeConnectivity(false); // start offline
      useConnectivity(conn);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((bloc.state as Initialized).isOffline, isTrue); // banner up

      conn.emit(true); // device reconnects
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((bloc.state as Initialized).isOffline, isFalse); // banner cleared
    });
  });
}

/// A controllable [ConnectivityService] for the F3 tests (seed-then-live).
class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity(this._online);
  bool _online;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> watchOnline() async* {
    yield _online;
    yield* _controller.stream;
  }
}

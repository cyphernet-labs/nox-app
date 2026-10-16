import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chats_wire_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/fixed_connection_status.dart';

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

    test('an inbound message raises the badge live, but only for a chat that was opened', () async {
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // seed + load
      final target = (bloc.state as Initialized).items.first;
      expect(target.unreadCount, 0, reason: 'nothing has been opened yet, so nothing is unread');

      // A chat nobody has opened shows no badge no matter what arrives - the
      // product rule, and now true by construction: the badge is a recount
      // from the read mark, and an unopened chat has none.
      await getIt<MessageRepository>().simulateIncoming(chatId: target.id);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((bloc.state as Initialized).items.firstWhere((c) => c.id == target.id).unreadCount, 0);

      // Open it, then let one more arrive: now there is a mark to count above.
      await getIt<ChatRepository>().markChatRead(chatId: target.id);
      await getIt<MessageRepository>().simulateIncoming(chatId: target.id);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // watchChats tick → refresh

      final after = (bloc.state as Initialized).items.firstWhere((c) => c.id == target.id);
      expect(after.unreadCount, 1, reason: 'the one that arrived after the open, live and unreloaded');
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

  group('the connection status (phase 040)', () {
    late FixedConnectionStatusService status;

    Future<ChatsListBloc> boot(ConnectionStatus initial) async {
      status = FixedConnectionStatusService(initial);
      getIt.allowReassignment = true;
      getIt.registerSingleton<ConnectionStatusService>(status);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return bloc;
    }

    test('a path still coming up is not an outage: no banner, the corner speaks', () async {
      final bloc = await boot(FixedConnectionStatusService.connectingTor);

      final state = bloc.state as Initialized;
      expect(state.isOffline, isFalse);
      expect(state.isServerMismatch, isFalse);
    });

    test('a whole failed round is: the banner goes up, and comes down on a greeting', () async {
      final bloc = await boot(const ConnectionStatus(state: LinkState.offline));
      expect((bloc.state as Initialized).isOffline, isTrue);

      status.emit(FixedConnectionStatusService.tor);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((bloc.state as Initialized).isOffline, isFalse);
    });

    test('a refused Tor client asks for an update, whatever the path (FR-026)', () async {
      final bloc = await boot(const ConnectionStatus(state: LinkState.online, path: ConnectionPath.direct, torObsolete: true));

      final state = bloc.state as Initialized;
      expect(state.torObsolete, isTrue);
      expect(state.isOffline, isFalse);
    });

    test('a failed round with a known cause carries it, and a greeting takes it away (phase 045)', () async {
      final bloc = await boot(const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.onionNotFound));
      expect((bloc.state as Initialized).isOffline, isTrue);
      expect((bloc.state as Initialized).problem, ConnectionProblem.onionNotFound);

      status.emit(const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.torNetwork));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((bloc.state as Initialized).problem, ConnectionProblem.torNetwork, reason: 'the last round says why');

      status.emit(FixedConnectionStatusService.direct);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((bloc.state as Initialized).problem, isNull);
    });

    test('another server behind the onion address is the mismatch banner with its own cause', () async {
      final bloc = await boot(const ConnectionStatus(state: LinkState.serverMismatch, problem: ConnectionProblem.otherServer));

      final state = bloc.state as Initialized;
      expect(state.isServerMismatch, isTrue);
      expect(state.problem, ConnectionProblem.otherServer);
    });

    test('the debug stand-in plays a failed round whose cause is a switched-off Use Tor', () async {
      final bloc = await boot(FixedConnectionStatusService.direct);

      bloc.add(const ChatsListEvent.setScenario(ChatsListScenario.turnOnTor));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = bloc.state as Initialized;
      expect(state.isOffline, isTrue);
      expect(state.problem, ConnectionProblem.turnOnTor);
    });
  });

  group('Try again on No connection (phase 042)', () {
    late _FakePhase phase;

    Future<ChatsListBloc> boot(SessionPhase initial) async {
      phase = _FakePhase(initial);
      getIt.allowReassignment = true;
      getIt.registerSingleton<SessionPhaseService>(phase);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return bloc;
    }

    test('no path: the strip, and something to try', () async {
      final state = (await boot(SessionPhase.disconnected)).state as Initialized;

      expect(state.isOffline, isTrue);
      expect(state.isUnsupported, isFalse);
    });

    test('a server that refuses this build: the strip, and nothing to try', () async {
      final state = (await boot(SessionPhase.unsupported)).state as Initialized;

      expect(state.isOffline, isTrue);
      expect(state.isUnsupported, isTrue);
    });

    test('the action asks for another attempt, once', () async {
      final bloc = await boot(SessionPhase.disconnected);

      bloc.add(const ChatsListEvent.retryConnection());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(phase.reconnects, 1);
    });
  });

  group('the server that is not the one the link named (036)', () {
    late _FakePhase phase;

    Future<ChatsListBloc> boot(SessionPhase initial) async {
      phase = _FakePhase(initial);
      getIt.allowReassignment = true;
      getIt.registerSingleton<SessionPhaseService>(phase);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return bloc;
    }

    test('a refused server raises its own banner, and not the offline one', () async {
      final bloc = await boot(SessionPhase.serverMismatch);

      final state = bloc.state as Initialized;
      expect(state.isServerMismatch, isTrue);
      // The mutation that matters: "no connection" over a server that answered
      // promptly sends the person to check a network that is working, and the
      // two banners at once would say two different things about one fact.
      expect(state.isOffline, isFalse);
    });

    test('nothing local is thrown away - the chats are still there under it', () async {
      final bloc = await boot(SessionPhase.serverMismatch);

      expect((bloc.state as Initialized).items, isNotEmpty);
    });

    test('the refusal arriving live flips the banner without a reload', () async {
      final bloc = await boot(SessionPhase.live);
      final before = bloc.state as Initialized;
      expect(before.isServerMismatch, isFalse);

      var sawReloadSpinner = false;
      final sub = bloc.stream.listen((s) {
        if (s is Initialized && s.loadingInProgress) sawReloadSpinner = true;
      });
      addTearDown(sub.cancel);

      phase.emit(SessionPhase.serverMismatch);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final after = bloc.state as Initialized;
      expect(after.isServerMismatch, isTrue);
      expect(after.items, before.items);
      expect(sawReloadSpinner, isFalse);
    });

    test('the banner action asks for another attempt', () async {
      // Without this the app never comes back: a terminal phase has no ladder
      // left to climb, so nothing else will ever try again.
      final bloc = await boot(SessionPhase.serverMismatch);

      bloc.add(const ChatsListEvent.retryConnection());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(phase.reconnects, 1);
    });

    test('a fixed cause clears it', () async {
      final bloc = await boot(SessionPhase.serverMismatch);
      expect((bloc.state as Initialized).isServerMismatch, isTrue);

      phase.emit(SessionPhase.live);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = bloc.state as Initialized;
      expect(state.isServerMismatch, isFalse);
      expect(state.isOffline, isFalse);
    });
  });

  group('the cache first: the connection never holds the list', () {
    ChatModel chat(String id, String name) => ChatModel(id: id, name: name, lastMessagePreview: '', lastMessageAt: DateTime(2026, 10, 4));

    void useChats(ChatRepository chats) {
      getIt.allowReassignment = true;
      getIt.registerSingleton<ChatRepository>(chats);
    }

    void useStatus(FixedConnectionStatusService status) {
      getIt.allowReassignment = true;
      getIt.registerSingleton<ConnectionStatusService>(status);
    }

    test('the chats the device holds are on screen at once while the server has not answered', () async {
      // The bug on the stand: launched with a bad network, the list sat on a
      // spinner while Tor came up, and the cached chats appeared only once the
      // connection failed.
      final chats = _SlowServerChats([chat('c1', 'Holiday'), chat('c2', 'Work')]);
      useChats(chats);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = bloc.state as Initialized;
      expect(state.items.map((c) => c.id), ['c1', 'c2']);
      expect(state.loadingInProgress, isFalse);
      expect(chats.serverReads, 1, reason: 'the server is still asked, in the background');
    });

    test('with nothing cached, the list waits for the server rather than saying there are no chats', () async {
      useChats(_SlowServerChats(const []));
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = bloc.state as Initialized;
      expect(state.syncing, isTrue);
      expect(state.pagingState.isLoading, isTrue, reason: 'the spinner, not the empty state');
    });

    test('with nothing cached and no channel, the empty list is the answer at once', () async {
      useStatus(FixedConnectionStatusService(FixedConnectionStatusService.connectingTor));
      useChats(_SlowServerChats(const []));
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = bloc.state as Initialized;
      expect(state.syncing, isFalse);
      expect(state.pagingState.isLoading, isFalse);
    });

    test('chats past the cache can still be reached once the channel is back', () async {
      // Scrolled to the end of the cache while Tor came up: the load-more came
      // back short from the cache and switched paging off, and only page 1 is
      // read again on the way back - so the rest stayed out of reach.
      final server = _PagedServer();
      getIt.allowReassignment = true;
      getIt.registerSingleton<ChatRemoteDataSource>(server);
      await getIt<ChatRepository>().getChats(config: GetChatsConfig.firstPage()); // an earlier session cached page 1
      server.greeted = false;
      final status = FixedConnectionStatusService(FixedConnectionStatusService.connectingTor);
      useStatus(status);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      bloc.add(const ChatsListEvent.loadChats()); // the end of the cached list
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((bloc.state as Initialized).pagingState.hasNextPage, isFalse, reason: 'precondition: the cache ran out');

      server.greeted = true;
      status.emit(FixedConnectionStatusService.tor);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect((bloc.state as Initialized).pagingState.hasNextPage, isTrue);
      bloc.add(const ChatsListEvent.loadChats());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((bloc.state as Initialized).items.length, greaterThan(GetChatsConfig.pageSize));
    });

    test('a list waiting on the spinner does not read a later page of the previous list', () async {
      // PagedListView asks for the "next page" of any list without pages, and
      // that request ended the spinner with a page that belonged elsewhere.
      final chats = _SlowServerChats(const []);
      useChats(chats);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((bloc.state as Initialized).syncing, isTrue, reason: 'precondition');

      bloc.add(const ChatsListEvent.loadChats()); // what PagedListView sends
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect((bloc.state as Initialized).syncing, isTrue);
      expect(chats.serverReads, 1, reason: 'only the first page, asked once');
    });

    test('the server is asked again when the channel comes back', () async {
      final status = FixedConnectionStatusService(FixedConnectionStatusService.connectingTor);
      useStatus(status);
      final chats = _SlowServerChats([chat('c1', 'Holiday')]);
      useChats(chats);
      final bloc = ChatsListBloc()..add(const ChatsListEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final before = chats.serverReads;

      status.emit(FixedConnectionStatusService.tor);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(chats.serverReads, before + 1);
    });
  });
}

/// 50 chats on the server; `chats.list` fails at once until [greeted], the
/// way a read with a cache behind it does while the channel comes up.
class _PagedServer implements ChatRemoteDataSource {
  bool greeted = true;
  final List<ChatWireEntity> all = [
    for (var i = 0; i < 50; i++)
      ChatWireEntity(
        chatId: 'c$i',
        name: 'Chat $i',
        createdAt: 1759000000,
        createdByLabel: 'Aria',
        lastMessagePreview: '',
        lastActivityAt: 1759600000 - i * 60,
      ),
  ];

  @override
  Future<ResponseEntity<ChatsWireEntity>> getChats({required GetChatsConfig config}) async {
    if (!greeted) throw const SocketUnavailableException('not connected');
    final start = (config.page - 1) * GetChatsConfig.pageSize;
    final slice = all.skip(start).take(GetChatsConfig.pageSize).toList();
    return ResponseEntity<ChatsWireEntity>(
      success: true,
      data: ChatsWireEntity(chats: slice, hasMore: start + GetChatsConfig.pageSize < all.length),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A cache that answers at once and a server that never does - Tor still
/// coming up. Everything else about a chat repository is left out.
class _SlowServerChats implements ChatRepository {
  _SlowServerChats(this.cached);

  final List<ChatModel> cached;
  int serverReads = 0;
  final Completer<void> _never = Completer<void>();

  @override
  Future<RepositoryResult<(List<ChatModel>, PageMetadata)>> getChats({required GetChatsConfig config}) async {
    if (!config.cachedOnly) {
      serverReads++;
      await _never.future;
    }
    return RepositoryResult<(List<ChatModel>, PageMetadata)>.success(data: (cached, const PageMetadata(hasMore: false)));
  }

  @override
  Stream<List<ChatModel>> watchChats() => const Stream<List<ChatModel>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/// A session phase this test drives by hand, plus a count of how many times the
/// screen asked for another attempt.
class _FakePhase implements SessionPhaseService {
  _FakePhase([this._phase = SessionPhase.live]);

  SessionPhase _phase;
  final StreamController<SessionPhase> _controller = StreamController<SessionPhase>.broadcast();

  int reconnects = 0;

  void emit(SessionPhase next) {
    _phase = next;
    _controller.add(next);
  }

  @override
  SessionPhase get phase => _phase;

  @override
  Stream<SessionPhase> watchPhase() async* {
    yield _phase;
    yield* _controller.stream;
  }

  @override
  Future<void> reconnect() async => reconnects++;
}

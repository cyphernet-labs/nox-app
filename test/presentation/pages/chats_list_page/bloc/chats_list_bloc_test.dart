import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
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
  });
}

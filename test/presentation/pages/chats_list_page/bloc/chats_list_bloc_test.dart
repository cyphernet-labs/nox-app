import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/chats_list_page/bloc/chats_list_bloc.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
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
  });
}

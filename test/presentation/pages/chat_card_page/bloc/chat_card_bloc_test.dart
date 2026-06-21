import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatCardBloc', () {
    blocTest<ChatCardBloc, ChatCardState>(
      'Initialize → Initialized with the chat files',
      build: ChatCardBloc.new,
      act: (bloc) => bloc.add(const ChatCardEvent.initialize('chat_0')),
      wait: const Duration(milliseconds: 400),
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<Initialized>());
        expect((state as Initialized).files, isNotEmpty);
      },
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'viewModeChanged switches list ⇄ grid',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.viewModeChanged(FilesViewMode.grid));
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) => expect((bloc.state as Initialized).viewMode, FilesViewMode.grid),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'the empty scenario yields no files',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.setScenario(ChatCardScenario.empty));
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) => expect((bloc.state as Initialized).files, isEmpty),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'the offline scenario keeps the files and flags offline',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.setScenario(ChatCardScenario.offline));
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.isOffline, isTrue);
        expect(state.files, isNotEmpty);
      },
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'the fatal scenario emits the Error state',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.setScenario(ChatCardScenario.fatal));
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) => expect(bloc.state, isA<Error>()),
    );
  });
}

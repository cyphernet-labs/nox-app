import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
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

    test('a newly sent attachment appears in the files view without a reload (R5)', () async {
      // A dedicated chat id (seeded fresh with the generic thread → one attachment).
      final bloc = ChatCardBloc()..add(const ChatCardEvent.initialize('chat_r5'));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // seed + derive
      expect((bloc.state as Initialized).files, hasLength(1)); // seeded design-spec.pdf

      const att = MessageAttachment(id: 'r5', type: FileType.image, name: 'live.png', sizeBytes: 50);
      await getIt<MessageRepository>().sendMessage(chatId: 'chat_r5', attachment: att);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // watch tick + debounce + re-derive

      final files = (bloc.state as Initialized).files;
      expect(files, hasLength(2)); // grew live, no manual reload
      expect(files.first.name, 'live.png'); // newest-first
    });
  });
}

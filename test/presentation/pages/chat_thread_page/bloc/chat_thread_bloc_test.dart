import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatThreadBloc', () {
    blocTest<ChatThreadBloc, ChatThreadState>(
      'Initialize → Initialized, then a page of mock messages loads',
      build: ChatThreadBloc.new,
      act: (bloc) => bloc.add(const ChatThreadEvent.initialize('chat_0')),
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<Initialized>());
        final initialized = state as Initialized;
        expect(initialized.items, isNotEmpty);
        expect(initialized.hasMessages, isTrue);
        expect(initialized.loadingInProgress, isFalse);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'an optimistic send goes pending → sent',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.messageSent(text: 'hello there'));
      },
      wait: const Duration(milliseconds: 800),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.outgoing, hasLength(1));
        expect(state.outgoing.first.text, 'hello there');
        expect(state.outgoing.first.status, MessageStatus.sent);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'the send-error scenario flips the optimistic message to error',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.sendError));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const ChatThreadEvent.messageSent(text: 'oops'));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.outgoing.first.status, MessageStatus.error);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'attachmentPicked sets a draft; attachmentRemoved clears it',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.attachmentPicked());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((bloc.state as Initialized).draftAttachment, isNotNull);
        bloc.add(const ChatThreadEvent.attachmentRemoved());
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) => expect((bloc.state as Initialized).draftAttachment, isNull),
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'the empty scenario yields no real messages',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.empty));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.hasMessages, isFalse);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'the offline scenario keeps the history and flags offline',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.offline));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.isOffline, isTrue);
        expect(state.items, isNotEmpty);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'the fatal scenario emits the Error state, then recovers',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.fatal));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(bloc.state, isA<Error>());
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.normal));
      },
      wait: const Duration(milliseconds: 600),
      verify: (bloc) {
        expect(bloc.state, isA<Initialized>());
        expect((bloc.state as Initialized).items, isNotEmpty);
      },
    );
  });
}

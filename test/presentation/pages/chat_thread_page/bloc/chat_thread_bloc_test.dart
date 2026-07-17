import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
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
      'an offline send is re-delivered (pending → sent) once connection is restored',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.offline));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        bloc.add(const ChatThreadEvent.messageSent(text: 'queued offline'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // While offline the message stays pending.
        expect((bloc.state as Initialized).outgoing.first.status, MessageStatus.pending);
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.normal));
      },
      wait: const Duration(milliseconds: 800),
      verify: (bloc) {
        final outgoing = (bloc.state as Initialized).outgoing.where((m) => m.text == 'queued offline');
        expect(outgoing, isNotEmpty);
        expect(outgoing.first.status, MessageStatus.sent);
      },
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

    // SendRetried — the retry event carried no coverage. Note: the literal
    // "failed bubble -> setScenario(normal) -> flips to sent" is unreachable
    // mock-free, because the sendError -> normal switch hits the debug-reset
    // branch in _onSetScenario and drops the optimistic bubble before a retry
    // could re-deliver it. So we lock the reachable real behaviours: the
    // ack-to-sent branch and the send-error re-fail branch reached via retry,
    // plus the unknown-id no-op guard.
    blocTest<ChatThreadBloc, ChatThreadState>(
      'sendRetried re-delivers an existing outgoing bubble and the mock repository acks it to sent',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.messageSent(text: 'retry me'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        // Retry the same optimistic bubble by its local id (looks like 'local_<n>').
        bloc.add(ChatThreadEvent.sendRetried((bloc.state as Initialized).outgoing.first.id));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.outgoing, hasLength(1));
        expect(state.outgoing.first.status, MessageStatus.sent);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'sendRetried re-attempts a failed bubble; under the persistent send-error scenario it stays error',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.setScenario(ChatThreadScenario.sendError));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const ChatThreadEvent.messageSent(text: 'oops'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final failed = (bloc.state as Initialized).outgoing.first;
        expect(failed.status, MessageStatus.error); // precondition: the send failed
        bloc.add(ChatThreadEvent.sendRetried(failed.id));
      },
      wait: const Duration(milliseconds: 400),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.outgoing, hasLength(1));
        expect(state.outgoing.first.status, MessageStatus.error);
      },
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'sendRetried for an unknown local id is a no-op on a fresh Initialized (matches.isEmpty guard)',
      build: ChatThreadBloc.new,
      seed: () => ChatThreadState.initialized(pagingState: PagingState<String, MessageModel>(), currentId: 'user'),
      act: (bloc) => bloc.add(const ChatThreadEvent.sendRetried('nope')),
      expect: () => const <ChatThreadState>[],
    );
  });
}

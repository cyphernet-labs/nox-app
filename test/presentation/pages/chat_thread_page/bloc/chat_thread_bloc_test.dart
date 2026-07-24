import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/service/file_picker_service.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';

/// A fake picker: returns a fixed [PickedFile] (or null on "cancel"). Registered into
/// the test DI so `attachmentPicked` runs without an OS dialog (feature 017).
class _FakePicker implements FilePickerService {
  _FakePicker(this._result);
  final PickedFile? _result;
  @override
  Future<PickedFile?> pickFile() async => _result;
  @override
  Future<String?> pickSaveLocation({required String suggestedName}) async => null;
}

void _usePicker(PickedFile? result) {
  getIt.allowReassignment = true;
  getIt.registerSingleton<FilePickerService>(_FakePicker(result));
}

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
      'attachmentPicked sets a draft from the real picked file (name/size/type); attachmentRemoved clears it',
      setUp: () => _usePicker((name: 'report.pdf', sizeBytes: 2048, extension: 'pdf', path: '/tmp/report.pdf')),
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.attachmentPicked());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final draft = (bloc.state as Initialized).draftAttachment;
        expect(draft, isNotNull);
        expect(draft!.name, 'report.pdf'); // real name, not the photo.jpg stub
        expect(draft.sizeBytes, 2048);
        expect(draft.type, FileType.pdf); // derived from the extension
        bloc.add(const ChatThreadEvent.attachmentRemoved());
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) => expect((bloc.state as Initialized).draftAttachment, isNull),
    );

    blocTest<ChatThreadBloc, ChatThreadState>(
      'attachmentPicked leaves the composer unchanged when the picker is cancelled',
      setUp: () => _usePicker(null), // cancel / unsupported
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        bloc.add(const ChatThreadEvent.attachmentPicked());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) => expect((bloc.state as Initialized).draftAttachment, isNull), // unchanged
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

    blocTest<ChatThreadBloc, ChatThreadState>(
      'a sent message shows exactly one bubble across pending -> sent and arrives live in items (US3)',
      build: ChatThreadBloc.new,
      act: (bloc) async {
        bloc.add(const ChatThreadEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 500)); // seed + load
        bloc.add(const ChatThreadEvent.messageSent(text: 'Unique-US3-live-message'));
        await Future<void>.delayed(const Duration(milliseconds: 700)); // ack + id adoption + watch refresh
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        final matches = state.allMessages.where((m) => m.text == 'Unique-US3-live-message').toList();
        expect(matches, hasLength(1)); // exactly one bubble — id adoption + dedup-by-id, no duplicate
        expect(matches.first.status, MessageStatus.sent); // acked
        // It also arrived in `items` via the live watch refresh, not only the optimistic outgoing list.
        expect(state.items.any((m) => m.text == 'Unique-US3-live-message'), isTrue);
      },
    );

    test('opening a chat thread marks it read — its unread count resets to 0 (US4)', () async {
      await getIt<ChatRepository>().getChats(config: GetChatsConfig.firstPage()); // seed chat rows
      final chatDao = getIt<ChatDao>();
      final unread = (await chatDao.getAllSorted()).firstWhere((c) => c.unreadCount > 0);
      expect(unread.unreadCount, greaterThan(0)); // precondition

      final bloc = ChatThreadBloc()..add(ChatThreadEvent.initialize(unread.id));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 400)); // init fires markChatRead

      expect((await chatDao.getById(unread.id))!.unreadCount, 0);
    });

    group('signed-in identity (feature 015)', () {
      test('currentId is the session identifier and seeded own history reconciles to it', () async {
        await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-abc', onboardingComplete: true, label: 'Alice');
        addTearDown(() => getIt<SessionRepository>().clear());

        // A fresh chat id so it seeds under the active session (not a chat seeded earlier without one).
        final bloc = ChatThreadBloc()..add(const ChatThreadEvent.initialize('chat_identity_015'));
        addTearDown(bloc.close);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final state = bloc.state as Initialized;
        expect(state.currentId, 'sess-abc'); // own-id sourced from the session, not the sentinel
        expect(state.items.any((m) => m.authorId == 'sess-abc'), isTrue); // seeded own rows reconciled
        expect(state.items.any((m) => m.authorId == 'me'), isFalse); // no un-reconciled sentinel own rows
      });

      test('own-detection keys on the identifier, not the label — a rename reclassifies nothing (FR-011/SC-006)', () async {
        await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-def', onboardingComplete: true, label: 'Bob');
        addTearDown(() => getIt<SessionRepository>().clear());

        final bloc = ChatThreadBloc()..add(const ChatThreadEvent.initialize('chat_identity_015b'));
        addTearDown(bloc.close);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final state0 = bloc.state as Initialized;

        // Own-detection is IDENTIFIER-keyed: currentId is the technical identifier, not the
        // display label — so it would be wrong if the code keyed classification on the label.
        expect(state0.currentId, 'sess-def');
        expect(state0.currentId, isNot('Bob'));
        final ownBefore = state0.items.where((m) => m.authorId == state0.currentId).map((m) => m.id).toSet();
        expect(ownBefore, isNotEmpty); // seeded own history is attributed to the identifier
        expect(state0.items.every((m) => m.authorId != 'Bob'), isTrue); // nothing authored by the label

        await getIt<SessionRepository>().updateLabel(label: 'Bob-renamed');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        final state1 = bloc.state as Initialized;
        // The rename persisted (label changed) but the identifier — hence currentId and every
        // message's own/other side — is untouched. No row is ever authored by the label.
        expect((await getIt<SessionRepository>().readSession()).data!.label, 'Bob-renamed');
        expect(state1.currentId, 'sess-def');
        final ownAfter = state1.items.where((m) => m.authorId == state1.currentId).map((m) => m.id).toSet();
        expect(ownAfter, ownBefore); // identical own set → 0 reclassifications (SC-006)
        expect(state1.items.every((m) => m.authorId != 'Bob-renamed'), isTrue);
      });
    });
  });
}

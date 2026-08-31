import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';

import 'chat_thread_bloc_send_error_test.mocks.dart';

/// Covers the REAL repository-failure path (not the debug send-error scenario).
///
/// Since feature 027 the outcome depends on the KIND of refusal: one a retry
/// cannot fix leaves the bubble in `error` for a person to act on, while a
/// retryable one keeps it queued as `pending` and tries again. Collapsing both
/// into `error` would tell the user their message is dead when it is merely
/// waiting out a server restart.
@GenerateMocks([MessageRepository])
void main() {
  late MockMessageRepository repository;
  // Set per test before the bloc runs: the classification is the thing on trial.
  late RepositoryException failure;

  setUp(() async {
    await configureDependencies(Environment.test);
    // Mockito needs dummy values for the generic RepositoryResult return types.
    provideDummy<RepositoryResult<(List<MessageModel>, PageMetadata)>>(
      RepositoryResult.success(data: (const [], const PageMetadata(hasMore: false))),
    );
    provideDummy<RepositoryResult<MessageModel>>(RepositoryResult.error(exception: RepositoryException.unknown));
    repository = MockMessageRepository();
    when(repository.chatFiles(chatId: anyNamed('chatId'), refresh: anyNamed('refresh'))).thenAnswer((_) async => const []);
    // The bloc subscribes to watchMessages() on init (Feature 014) — an empty stream
    // means no live refresh, isolating the send-failure path under test.
    when(repository.watchMessages(any)).thenAnswer((_) => Stream<List<MessageModel>>.empty());
    when(repository.getMessages(config: anyNamed('config'))).thenAnswer(
      (_) async => RepositoryResult<(List<MessageModel>, PageMetadata)>.success(data: (const [], const PageMetadata(hasMore: false))),
    );
    when(
      repository.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((_) async => RepositoryResult<MessageModel>.error(exception: failure));
    getIt.allowReassignment = true;
    getIt.registerSingleton<MessageRepository>(repository);
    // A previous test's queue lives in the same in-memory DB for the isolate.
    await getIt<OutboxRepository>().clean();
  });

  tearDown(() async {
    await getIt.reset();
  });

  blocTest<ChatThreadBloc, ChatThreadState>(
    'a refusal a retry cannot fix flips the queued message to error',
    // payload_too_large will be just as too large on the tenth attempt.
    setUp: () => failure = RepositoryException.payloadTooLarge,
    build: ChatThreadBloc.new,
    act: (bloc) async {
      bloc.add(const ChatThreadEvent.initialize('chat_0'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      bloc.add(const ChatThreadEvent.messageSent(text: 'will fail'));
    },
    wait: const Duration(milliseconds: 400),
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.outgoing.first.status, MessageStatus.error);
      expect(state.outgoing.first.text, 'will fail'); // still there to retry or discard
    },
  );

  blocTest<ChatThreadBloc, ChatThreadState>(
    'a refusal a retry CAN fix keeps the message queued rather than calling it dead',
    setUp: () => failure = RepositoryException.connection,
    build: ChatThreadBloc.new,
    act: (bloc) async {
      bloc.add(const ChatThreadEvent.initialize('chat_0'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      bloc.add(const ChatThreadEvent.messageSent(text: 'will wait'));
    },
    wait: const Duration(milliseconds: 400),
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.outgoing.first.status, MessageStatus.pending);
    },
  );

  blocTest<ChatThreadBloc, ChatThreadState>(
    'discarding a stuck message removes it for good (SC-007)',
    setUp: () => failure = RepositoryException.payloadTooLarge,
    build: ChatThreadBloc.new,
    act: (bloc) async {
      bloc.add(const ChatThreadEvent.initialize('chat_0'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      bloc.add(const ChatThreadEvent.messageSent(text: 'unwanted'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final queued = (bloc.state as Initialized).outgoing.first.id;
      bloc.add(ChatThreadEvent.sendDiscarded(queued));
    },
    wait: const Duration(milliseconds: 400),
    verify: (bloc) async {
      expect((bloc.state as Initialized).outgoing, isEmpty);
      // Gone from the store too, so a restart cannot resurrect it. Read the
      // WHOLE queue, not just the pending slice: a discarded entry that had
      // been marked `error` would be invisible to pending() and the assertion
      // would pass on a record that is still there.
      expect(await getIt<OutboxRepository>().watchQueue().first, isEmpty);
    },
  );
}

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
import 'package:nox_app/presentation/pages/chat_thread_page/bloc/chat_thread_bloc.dart';

import 'chat_thread_bloc_send_error_test.mocks.dart';

/// Covers the REAL repository-failure path (not the debug send-error scenario):
/// a failed `sendMessage` must flip the optimistic bubble to `error`.
@GenerateMocks([MessageRepository])
void main() {
  late MockMessageRepository repository;

  setUp(() async {
    await configureDependencies(Environment.test);
    // Mockito needs dummy values for the generic RepositoryResult return types.
    provideDummy<RepositoryResult<(List<MessageModel>, PageMetadata)>>(
      RepositoryResult.success(data: (const [], const PageMetadata(hasMore: false))),
    );
    provideDummy<RepositoryResult<MessageModel>>(RepositoryResult.error(exception: RepositoryException.unknown));
    repository = MockMessageRepository();
    // The bloc subscribes to watchMessages() on init (Feature 014) — an empty stream
    // means no live refresh, isolating the send-failure path under test.
    when(repository.watchMessages(any)).thenAnswer((_) => Stream<List<MessageModel>>.empty());
    when(repository.getMessages(config: anyNamed('config'))).thenAnswer(
      (_) async => RepositoryResult<(List<MessageModel>, PageMetadata)>.success(data: (const [], const PageMetadata(hasMore: false))),
    );
    when(
      repository.sendMessage(chatId: anyNamed('chatId'), text: anyNamed('text'), attachment: anyNamed('attachment')),
    ).thenAnswer((_) async => RepositoryResult<MessageModel>.error(exception: RepositoryException.unknown));
    getIt.allowReassignment = true;
    getIt.registerSingleton<MessageRepository>(repository);
  });

  tearDown(() async {
    await getIt.reset();
  });

  blocTest<ChatThreadBloc, ChatThreadState>(
    'a repository send failure flips the optimistic message to error',
    build: ChatThreadBloc.new,
    act: (bloc) async {
      bloc.add(const ChatThreadEvent.initialize('chat_0'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      bloc.add(const ChatThreadEvent.messageSent(text: 'will fail'));
    },
    wait: const Duration(milliseconds: 300),
    verify: (bloc) {
      final state = bloc.state as Initialized;
      expect(state.outgoing.first.status, MessageStatus.error);
    },
  );
}

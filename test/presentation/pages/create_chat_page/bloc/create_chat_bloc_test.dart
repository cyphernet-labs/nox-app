import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/entity/chat/wire/name_availability_wire_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/data/repository/chat/chat_repository_impl.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_creation.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_transfer_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/id/chat_id.dart';
import 'package:nox_app/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'create_chat_bloc_test.mocks.dart';

/// A server that never answers a create and whose name check finds no channel
/// - the shape of a device away from home while Tor is still coming up.
class _QuietServer implements ChatRemoteDataSource {
  int creates = 0;

  @override
  Future<ResponseEntity<ChatWireEntity>> createChat({required String name, String? chatId}) {
    creates++;
    return Completer<ResponseEntity<ChatWireEntity>>().future;
  }

  @override
  Future<ResponseEntity<NameAvailabilityWireEntity>> isNameAvailable({required String name, String? excludeChatId}) async =>
      throw RepositoryException.connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts the requests to drain, and drains nothing.
class _CountingOutbox extends OutboxService {
  _CountingOutbox()
    : super(
        getIt<OutboxRepository>(),
        getIt<MessageRepository>(),
        getIt<SessionPhaseService>(),
        getIt<FileRepository>(),
        getIt<AttachmentTransferService>(),
        getIt<ChatRepository>(),
      );

  int flushes = 0;

  @override
  Future<void> flush() async => flushes++;
}

@GenerateMocks([ChatRepository])
void main() {
  setUpAll(() {
    provideDummy<RepositoryResult<ChatModel>>(const RepositoryResult<ChatModel>.error(exception: RepositoryException.unknown));
    // D4: the availability check now calls chatRepository.isChatNameTaken; an unstubbed
    // mock returns this dummy (not taken) so the mock-repo tests stay behaviour-stable.
    provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: false));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('CreateChatBloc', () {
    blocTest<CreateChatBloc, CreateChatState>(
      'empty name disables create',
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('')),
      expect: () => [predicate<CreateChatState>((s) => s.status == CreateChatStatus.empty && !s.canSubmit)],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'a free name (any charset) resolves to valid after the debounced check',
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('Fresh chat ✨')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid && s.canSubmit),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'a reserved name resolves to taken',
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('General')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.taken),
      ],
    );

    // D4: a name persisted in the DB (NOT in the reserved set) must resolve to taken
    // through the real DB uniqueness path — proves the DB check, not just the reserved OR.
    blocTest<CreateChatBloc, CreateChatState>(
      'a name already persisted in the DB (not reserved) resolves to taken via the DB check',
      setUp: () async => getIt<ChatRepository>().createChat(name: 'Persisted D4 name'),
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('Persisted D4 name')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.taken),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'create with the success outcome navigates',
      build: CreateChatBloc.new,
      act: (bloc) async {
        bloc.add(const CreateChatEvent.nameChanged('Fresh chat'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        bloc.add(const CreateChatEvent.createRequested());
      },
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.submitting),
        // navSuccess carries the created chat so the caller can open its thread (N1).
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.navSuccess && s.createdChat != null),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'create with a network error re-enables create and shows the inline error',
      build: CreateChatBloc.new,
      act: (bloc) async {
        bloc.add(const CreateChatEvent.nameChanged('Another chat'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        bloc.add(const CreateChatEvent.createRequested(outcome: CreateChatOutcome.network));
      },
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.submitting),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid && s.networkError && s.canSubmit),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'create with the fatal outcome routes to the terminal navFatal status',
      build: CreateChatBloc.new,
      act: (bloc) async {
        bloc.add(const CreateChatEvent.nameChanged('Fresh'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        bloc.add(const CreateChatEvent.createRequested(outcome: CreateChatOutcome.fatal));
      },
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.submitting),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.navFatal),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'a success outcome whose repository createChat fails falls back to valid with the network error set',
      build: () {
        final mockChatRepository = MockChatRepository();
        when(
          mockChatRepository.createChat(name: anyNamed('name')),
        ).thenAnswer((_) async => const RepositoryResult<ChatModel>.error(exception: RepositoryException.connection));
        getIt.allowReassignment = true;
        getIt.registerSingleton<ChatRepository>(mockChatRepository);
        return CreateChatBloc();
      },
      act: (bloc) async {
        bloc.add(const CreateChatEvent.nameChanged('Fresh chat'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        bloc.add(const CreateChatEvent.createRequested());
      },
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.submitting),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid && s.networkError && s.canSubmit),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'navigationHandled resets a terminal status to valid and clears the network error',
      build: CreateChatBloc.new,
      seed: () => const CreateChatState(name: 'Chat', status: CreateChatStatus.navSuccess),
      act: (bloc) => bloc.add(const CreateChatEvent.navigationHandled()),
      expect: () => [predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid && !s.networkError)],
    );
  });

  group('a chat created on this device (phase 041)', () {
    late _QuietServer server;
    late _CountingOutbox outbox;

    setUp(() {
      server = _QuietServer();
      getIt.allowReassignment = true;
      getIt.registerSingleton<ChatRepository>(
        ChatRepositoryImpl(
          getIt<ChatDao>(),
          server,
          getIt<ChatMapper>(),
          getIt<ChatWireMapper>(),
          getIt<MessageRepository>(),
          getIt<MessageDao>(),
          getIt<SessionRepository>(),
        ),
      );
      outbox = _CountingOutbox();
      getIt.registerSingleton<OutboxService>(outbox);
    });

    blocTest<CreateChatBloc, CreateChatState>(
      'Create opens the chat at once under an id this device minted, with a server that never answers',
      build: CreateChatBloc.new,
      act: (bloc) async {
        bloc.add(const CreateChatEvent.nameChanged('Kitchen'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
        bloc.add(const CreateChatEvent.createRequested());
      },
      wait: const Duration(milliseconds: 300),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.submitting),
        predicate<CreateChatState>(
          (s) =>
              s.status == CreateChatStatus.navSuccess &&
              deviceChatIdPattern.hasMatch(s.createdChat!.id) &&
              s.createdChat!.creation == ChatCreation.pending,
        ),
      ],
      verify: (_) {
        expect(server.creates, 0, reason: 'creating never waits for the server');
        expect(outbox.flushes, 1, reason: 'the queue is asked to take it there now');
      },
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'a name check the server cannot answer leaves the name valid and Create enabled',
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('Kitchen')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid && s.canSubmit),
      ],
    );

    blocTest<CreateChatBloc, CreateChatState>(
      'the name of a chat still waiting to be created is taken here, before any server is asked',
      setUp: () async => getIt<ChatRepository>().createChat(name: 'Kitchen'),
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('kitchen')),
      wait: const Duration(milliseconds: 700),
      expect: () => [
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.checking),
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.taken),
      ],
    );
  });
}

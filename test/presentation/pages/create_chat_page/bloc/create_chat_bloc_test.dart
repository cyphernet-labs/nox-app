import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'create_chat_bloc_test.mocks.dart';

@GenerateMocks([ChatRepository])
void main() {
  setUpAll(() {
    provideDummy<RepositoryResult<ChatModel>>(const RepositoryResult<ChatModel>.error(exception: RepositoryException.unknown));
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
      'a taken name resolves to taken',
      build: CreateChatBloc.new,
      act: (bloc) => bloc.add(const CreateChatEvent.nameChanged('General')),
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
}

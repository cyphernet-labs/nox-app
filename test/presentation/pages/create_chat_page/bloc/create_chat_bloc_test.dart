import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/presentation/pages/create_chat_page/bloc/create_chat_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
        predicate<CreateChatState>((s) => s.status == CreateChatStatus.navSuccess),
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
      'navigationHandled resets a terminal status to valid and clears the network error',
      build: CreateChatBloc.new,
      seed: () => const CreateChatState(name: 'Chat', status: CreateChatStatus.navSuccess),
      act: (bloc) => bloc.add(const CreateChatEvent.navigationHandled()),
      expect: () => [predicate<CreateChatState>((s) => s.status == CreateChatStatus.valid && !s.networkError)],
    );
  });
}

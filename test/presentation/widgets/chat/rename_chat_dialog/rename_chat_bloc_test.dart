import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/presentation/widgets/chat/rename_chat_dialog/rename_chat_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RenameChatBloc (edit chat name) over the real test-env repo (Sembast). A target chat
/// 'Design crit' is created per test; the bloc opens prefilled with its name.
void main() {
  late String chatId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    chatId = (await getIt<ChatRepository>().createChat(name: 'Design crit')).data!.id;
  });

  tearDown(() async {
    await getIt.reset();
  });

  RenameChatBloc build() => RenameChatBloc(chatId: chatId, currentName: 'Design crit');

  group('RenameChatBloc', () {
    blocTest<RenameChatBloc, RenameChatState>(
      'opens prefilled with the current name — valid but not submittable (nothing changed)',
      build: build,
      verify: (bloc) {
        expect(bloc.state.name, 'Design crit');
        expect(bloc.state.status, RenameChatStatus.valid);
        expect(bloc.state.canSubmit, isFalse);
      },
    );

    blocTest<RenameChatBloc, RenameChatState>(
      'the unchanged current name stays valid but not submittable (no uniqueness check)',
      build: build,
      act: (bloc) => bloc.add(const RenameChatEvent.nameChanged('Design crit')),
      expect: () => [predicate<RenameChatState>((s) => s.status == RenameChatStatus.valid && !s.canSubmit)],
    );

    blocTest<RenameChatBloc, RenameChatState>(
      'an empty name is not submittable',
      build: build,
      act: (bloc) => bloc.add(const RenameChatEvent.nameChanged('')),
      expect: () => [predicate<RenameChatState>((s) => s.status == RenameChatStatus.empty && !s.canSubmit)],
    );

    blocTest<RenameChatBloc, RenameChatState>(
      'a changed free name resolves to valid + submittable after the debounced check',
      build: build,
      act: (bloc) => bloc.add(const RenameChatEvent.nameChanged('Brand New Name ✨')),
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<RenameChatState>((s) => s.status == RenameChatStatus.checking),
        predicate<RenameChatState>((s) => s.status == RenameChatStatus.valid && s.canSubmit),
      ],
    );

    blocTest<RenameChatBloc, RenameChatState>(
      'a name taken by ANOTHER chat is rejected',
      build: build,
      setUp: () async => getIt<ChatRepository>().createChat(name: 'Occupied'),
      act: (bloc) => bloc.add(const RenameChatEvent.nameChanged('Occupied')),
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<RenameChatState>((s) => s.status == RenameChatStatus.checking),
        predicate<RenameChatState>((s) => s.status == RenameChatStatus.taken && !s.canSubmit),
      ],
    );

    blocTest<RenameChatBloc, RenameChatState>(
      'a case-only change of the OWN name is allowed (self-exclusion in the uniqueness check)',
      build: build,
      act: (bloc) => bloc.add(const RenameChatEvent.nameChanged('design crit')), // vs 'Design crit'
      wait: const Duration(milliseconds: 600),
      expect: () => [
        predicate<RenameChatState>((s) => s.status == RenameChatStatus.checking),
        predicate<RenameChatState>((s) => s.status == RenameChatStatus.valid && s.canSubmit),
      ],
    );

    blocTest<RenameChatBloc, RenameChatState>(
      'save persists the new name and ends in navSuccess',
      build: build,
      act: (bloc) async {
        bloc.add(const RenameChatEvent.nameChanged('Renamed Live'));
        await Future<void>.delayed(const Duration(milliseconds: 700)); // let the debounced check resolve to valid
        bloc.add(const RenameChatEvent.saveRequested());
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) async {
        expect(bloc.state.status, RenameChatStatus.navSuccess);
        expect((await getIt<ChatDao>().getById(chatId))!.name, 'Renamed Live');
      },
    );
  });
}

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_model.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/device/pair_request.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/settings/settings_repository.dart';
import 'package:nox_app/presentation/app/bloc/app_root_bloc.dart';

import '../../../utils/fake_pair_request_service.dart';

/// Settings store with a configurable theme read and write outcome — drives the
/// AppRootBloc theme-persistence branches (read-applied-on-Initialize, save-revert).
class _StubSettingsRepository implements SettingsRepository {
  _StubSettingsRepository({this.themeRead = ThemeMode.system, this.writeSucceeds = true});

  final ThemeMode themeRead;
  final bool writeSucceeds;

  @override
  Future<RepositoryResult<ThemeMode>> readThemeMode() async => RepositoryResult.success(data: themeRead);

  @override
  Future<RepositoryResult<bool>> setThemeMode(ThemeMode mode) async =>
      writeSucceeds ? const RepositoryResult.success(data: true) : const RepositoryResult.error(exception: RepositoryException.unknown);

  @override
  Future<RepositoryResult<bool>> readNotificationsEnabled() async => const RepositoryResult.success(data: true);

  @override
  Future<RepositoryResult<bool>> setNotificationsEnabled(bool enabled) async => const RepositoryResult.success(data: true);
}

void main() {
  // The error branch of _onUpdateAppState logs via the global LogRepository, so the
  // DI graph must be up (test-env serves a real LogRepository).
  setUp(() async {
    await configureDependencies(Environment.test);
    await getIt.allReady();
  });

  tearDown(() async {
    await getIt.reset();
  });

  RepositoryResult<AppStateModel> resolved(AppStateType state) =>
      RepositoryResult<AppStateModel>.success(data: AppStateModel(state: state, session: null));

  group('AppRootBloc two-phase apply', () {
    blocTest<AppRootBloc, AppRootState>(
      'holds the first resolved state behind the splash until ApplyAppState',
      build: AppRootBloc.new,
      act: (bloc) => bloc
        ..add(AppRootEvent.updateAppState(result: resolved(AppStateType.unauthorized)))
        ..add(const AppRootEvent.applyAppState()),
      expect: () => [
        isA<AppRootState>()
            .having((s) => s.isReady, 'isReady', isTrue)
            .having((s) => s.lastAppState.state, 'lastAppState', AppStateType.unauthorized)
            .having((s) => s.appliedAppState.state, 'appliedAppState (held)', AppStateType.init),
        isA<AppRootState>().having((s) => s.appliedAppState.state, 'appliedAppState (released)', AppStateType.unauthorized),
      ],
    );

    blocTest<AppRootBloc, AppRootState>(
      'applies later transitions immediately once ready',
      build: AppRootBloc.new,
      act: (bloc) => bloc
        ..add(AppRootEvent.updateAppState(result: resolved(AppStateType.unauthorized)))
        ..add(const AppRootEvent.applyAppState())
        ..add(AppRootEvent.updateAppState(result: resolved(AppStateType.authorized))),
      verify: (bloc) {
        expect(bloc.state.appliedAppState.state, AppStateType.authorized);
        expect(bloc.state.lastAppState.state, AppStateType.authorized);
      },
    );

    blocTest<AppRootBloc, AppRootState>(
      'an error emission still lands — releases the splash to a safe unauthorized (Login), never stalls',
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.updateAppState(result: RepositoryResult.error(exception: RepositoryException.unknown))),
      expect: () => [
        isA<AppRootState>()
            .having((s) => s.isReady, 'isReady', isTrue)
            .having((s) => s.lastAppState.state, 'lastAppState', AppStateType.unauthorized)
            // First emission → held behind the splash (not yet applied).
            .having((s) => s.appliedAppState.state, 'appliedAppState', AppStateType.init),
      ],
    );
  });

  group('AppRootBloc theme persistence', () {
    blocTest<AppRootBloc, AppRootState>(
      'applies the persisted theme on Initialize',
      setUp: () {
        getIt.allowReassignment = true;
        getIt.registerSingleton<SettingsRepository>(_StubSettingsRepository(themeRead: ThemeMode.dark));
      },
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.initialize()),
      wait: const Duration(milliseconds: 100),
      // The persisted theme survives later app-state emissions (copyWith preserves it).
      verify: (bloc) => expect(bloc.state.themeMode, ThemeMode.dark),
    );

    blocTest<AppRootBloc, AppRootState>(
      'a failed theme save reverts the theme and bumps the save-error tick',
      setUp: () {
        getIt.allowReassignment = true;
        getIt.registerSingleton<SettingsRepository>(_StubSettingsRepository(writeSucceeds: false));
      },
      build: AppRootBloc.new,
      act: (bloc) => bloc.add(const AppRootEvent.setTheme(themeMode: ThemeMode.dark)),
      expect: () => [
        // Optimistic apply — new theme, tick unchanged.
        isA<AppRootState>().having((s) => s.themeMode, 'themeMode', ThemeMode.dark).having((s) => s.settingsSaveErrorTick, 'tick', 0),
        // Save failed → revert to the previous theme and bump the tick.
        isA<AppRootState>().having((s) => s.themeMode, 'themeMode', ThemeMode.system).having((s) => s.settingsSaveErrorTick, 'tick', 1),
      ],
    );
  });

  // A new device presented an invite this device issued, and waits for the
  // answer here (phase 046): the one question asked over any screen.
  group('AppRootBloc asking about a request to join (phase 046)', () {
    late FakePairRequestService requests;
    const windows = PairRequest(requestId: 'r_1', platform: DevicePlatform.windows);
    const ipad = PairRequest(requestId: 'r_2', platform: DevicePlatform.ios);

    setUp(() => requests = registerFakePairRequests());
    tearDown(() => requests.close());

    Future<AppRootBloc> initialized() async {
      final bloc = AppRootBloc()..add(const AppRootEvent.initialize());
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return bloc;
    }

    test('nothing to ask, nothing asked', () async {
      final bloc = await initialized();
      expect(bloc.state.pairRequest, isNull);
    });

    test('the oldest waiting request is the one asked about, and the next takes its turn', () async {
      final bloc = await initialized();

      requests
        ..ask(windows)
        ..ask(ipad);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.pairRequest, windows);

      requests.resolve('r_1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.pairRequest, ipad);

      requests.resolve('r_2');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.pairRequest, isNull);
    });

    test('Allow is sent for the request on screen, which then goes', () async {
      final bloc = await initialized();
      requests.ask(windows);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc.add(const AppRootEvent.pairRequestAnswered(requestId: 'r_1', allow: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requests.answers, [(requestId: 'r_1', allow: true)]);
      expect(bloc.state.pairRequest, isNull);
      expect(bloc.state.pairAnswering, isNull);
    });

    test('while an answer is on its way it is shown, and a second press sends nothing', () async {
      final bloc = await initialized();
      final reply = Completer<RepositoryResult<bool>>();
      requests.reply = (_, _) => reply.future;
      requests.ask(windows);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc
        ..add(const AppRootEvent.pairRequestAnswered(requestId: 'r_1', allow: false))
        ..add(const AppRootEvent.pairRequestAnswered(requestId: 'r_1', allow: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.pairAnswering, isFalse, reason: 'Deny is on its way');
      expect(requests.answers, hasLength(1));
      reply.complete(const RepositoryResult<bool>.success(data: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.pairRequest, isNull);
    });

    test('an answer that did not get through says so, and can be given again', () async {
      final bloc = await initialized();
      requests.reply = (_, _) async => const RepositoryResult<bool>.error(exception: RepositoryException.internal);
      requests.ask(windows);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc.add(const AppRootEvent.pairRequestAnswered(requestId: 'r_1', allow: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.pairAnswerFailed, isTrue);
      expect(bloc.state.pairAnswering, isNull);
      expect(bloc.state.pairRequest, windows, reason: 'the question still stands');

      requests.reply = null;
      bloc.add(const AppRootEvent.pairRequestAnswered(requestId: 'r_1', allow: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests.answers, hasLength(2));
      expect(bloc.state.pairRequest, isNull);
    });

    test('a new question starts clean', () async {
      final bloc = await initialized();
      requests.reply = (_, _) async => const RepositoryResult<bool>.error(exception: RepositoryException.internal);
      requests
        ..ask(windows)
        ..ask(ipad);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bloc.add(const AppRootEvent.pairRequestAnswered(requestId: 'r_1', allow: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.pairAnswerFailed, isTrue);

      // The first request ran out meanwhile.
      requests.resolve('r_1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.pairRequest, ipad);
      expect(bloc.state.pairAnswerFailed, isFalse);
    });

    test('an answer to a request that is not on screen sends nothing', () async {
      final bloc = await initialized();
      requests.ask(windows);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc.add(const AppRootEvent.pairRequestAnswered(requestId: 'r_gone', allow: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requests.answers, isEmpty);
    });
  });
}

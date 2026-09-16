import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/service/connectivity_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/constants.dart';
import 'package:nox_app/presentation/pages/chat_card_page/bloc/chat_card_bloc.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatCardBloc', () {
    blocTest<ChatCardBloc, ChatCardState>(
      'Initialize → Initialized with the chat files',
      build: ChatCardBloc.new,
      act: (bloc) => bloc.add(const ChatCardEvent.initialize('chat_0')),
      wait: const Duration(milliseconds: 400),
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<Initialized>());
        expect((state as Initialized).files, isNotEmpty);
      },
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'a rename from another device reaches the open card',
      // The whole reason the label is WATCHED rather than read once. The desktop
      // side sheet stays open across a rename, and a snapshot would keep drawing
      // the old name until the card was closed and reopened. Every other test
      // here leaves the label at its fallback, where the watch and a missing
      // watch are indistinguishable - so this one has to move it.
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await getIt<SessionRepository>().updateLabel(label: 'Renamed');
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) => expect((bloc.state as Initialized).personLabel, 'Renamed'),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'signing out does not leave the card naming the person who left',
      // Logout emits null on the same channel. It must resolve to the fallback,
      // not to the name that was there a moment ago.
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await getIt<SessionRepository>().updateLabel(label: 'Renamed');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await getIt<SessionRepository>().clear();
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) => expect((bloc.state as Initialized).personLabel, Constants.defaultUserLabel),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'viewModeChanged switches list ⇄ grid',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.viewModeChanged(FilesViewMode.grid));
      },
      wait: const Duration(milliseconds: 200),
      verify: (bloc) => expect((bloc.state as Initialized).viewMode, FilesViewMode.grid),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'the empty scenario yields no files',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        // The first derive now reaches the source, so give it time to land
        // before switching scenarios — otherwise the assertion races it.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        bloc.add(const ChatCardEvent.setScenario(ChatCardScenario.empty));
      },
      wait: const Duration(milliseconds: 500),
      verify: (bloc) => expect((bloc.state as Initialized).files, isEmpty),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'the offline scenario keeps the files and flags offline',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.setScenario(ChatCardScenario.offline));
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) {
        final state = bloc.state as Initialized;
        expect(state.isOffline, isTrue);
        expect(state.files, isNotEmpty);
      },
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'the fatal scenario emits the Error state',
      build: ChatCardBloc.new,
      act: (bloc) async {
        bloc.add(const ChatCardEvent.initialize('chat_0'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        bloc.add(const ChatCardEvent.setScenario(ChatCardScenario.fatal));
      },
      wait: const Duration(milliseconds: 300),
      verify: (bloc) => expect(bloc.state, isA<Error>()),
    );

    // The construction-time seam (P10): pinning the scenario BEFORE the first Initialize
    // makes the load deterministic — unlike setScenario, no normal load runs first, so an
    // in-flight files re-derive can't clobber `empty` back to the seeded file.
    blocTest<ChatCardBloc, ChatCardState>(
      'initialScenario: empty loads empty and stays empty (no re-derive clobber)',
      build: () => ChatCardBloc(initialScenario: ChatCardScenario.empty),
      act: (bloc) => bloc.add(const ChatCardEvent.initialize('chat_0')),
      wait: const Duration(milliseconds: 600), // long enough for any watch tick + debounce
      verify: (bloc) => expect((bloc.state as Initialized).files, isEmpty),
    );

    blocTest<ChatCardBloc, ChatCardState>(
      'initialScenario: fatal emits Error on the first load',
      build: () => ChatCardBloc(initialScenario: ChatCardScenario.fatal),
      act: (bloc) => bloc.add(const ChatCardEvent.initialize('chat_0')),
      wait: const Duration(milliseconds: 300),
      verify: (bloc) => expect(bloc.state, isA<Error>()),
    );

    test('a newly sent attachment appears in the files view without a reload (R5)', () async {
      // A chat the generator knows, so it carries the generic thread with its
      // one attachment; ids it does not know answer empty, as a server would
      // for a brand-new chat.
      final bloc = ChatCardBloc()..add(const ChatCardEvent.initialize('chat_12'));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // seed + derive
      expect((bloc.state as Initialized).files, hasLength(1)); // seeded design-spec.pdf

      const att = MessageAttachment(id: 'r5', type: FileType.image, name: 'live.png', sizeBytes: 50);
      await getIt<MessageRepository>().sendMessage(chatId: 'chat_12', clientMessageId: 'cmid-r5', attachment: att);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // watch tick + debounce + re-derive

      final files = (bloc.state as Initialized).files;
      expect(files, hasLength(2)); // grew live, no manual reload
      expect(files.first.name, 'live.png'); // newest-first
    });

    test('the live re-derive preserves the Grid choice and never flashes the loading state (R5)', () async {
      final emitted = <ChatCardState>[];
      final bloc = ChatCardBloc()..add(const ChatCardEvent.initialize('chat_13'));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // seed + derive

      // User switches to Grid, then a new file lands — the reactive re-derive must NOT
      // reset the view to List nor blink the spinner (regression: full re-init did both).
      bloc.add(const ChatCardEvent.viewModeChanged(FilesViewMode.grid));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((bloc.state as Initialized).viewMode, FilesViewMode.grid);

      bloc.stream.listen(emitted.add); // capture only what the reactive refresh emits
      const att = MessageAttachment(id: 'g5', type: FileType.image, name: 'shot.png', sizeBytes: 42);
      await getIt<MessageRepository>().sendMessage(chatId: 'chat_13', clientMessageId: 'cmid-r5-grid', attachment: att);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // watch tick + debounce + re-derive

      final state = bloc.state as Initialized;
      expect(state.viewMode, FilesViewMode.grid); // Grid survived the live refresh
      expect(state.files.first.name, 'shot.png'); // and the new file is in, newest-first
      expect(emitted.whereType<Initializing>(), isEmpty); // no loading flash during the refresh
    });
  });

  group('offline banner from real connectivity (P1)', () {
    void useConnectivity(ConnectivityService service) {
      getIt.allowReassignment = true;
      getIt.registerSingleton<ConnectivityService>(service);
      // Restore the always-online default so later tests aren't affected (shared getIt).
      addTearDown(() => getIt.registerSingleton<ConnectivityService>(_FakeConnectivity(true)));
    }

    test('offline connectivity flags the card offline (banner) while keeping the files', () async {
      useConnectivity(_FakeConnectivity(false));
      final bloc = ChatCardBloc()..add(const ChatCardEvent.initialize('chat_0'));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final state = bloc.state as Initialized;
      expect(state.isOffline, isTrue);
      expect(state.files, isNotEmpty); // files still shown under the banner
    });

    test('going offline live flips the banner, reconnecting clears it (no reload)', () async {
      final conn = _FakeConnectivity(true);
      useConnectivity(conn);
      final bloc = ChatCardBloc()..add(const ChatCardEvent.initialize('chat_0'));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect((bloc.state as Initialized).isOffline, isFalse);

      conn.emit(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((bloc.state as Initialized).isOffline, isTrue); // banner up

      conn.emit(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((bloc.state as Initialized).isOffline, isFalse); // banner cleared
    });
  });

  group('the server that is not the one the link named (036)', () {
    late _FakePhase phase;

    Future<ChatCardBloc> boot(SessionPhase initial) async {
      phase = _FakePhase(initial);
      getIt.allowReassignment = true;
      getIt.registerSingleton<SessionPhaseService>(phase);
      addTearDown(() => getIt.registerSingleton<SessionPhaseService>(_FakePhase()));
      final bloc = ChatCardBloc()..add(const ChatCardEvent.initialize('chat_0'));
      addTearDown(bloc.close);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return bloc;
    }

    test('a refused server raises its own banner, and not the offline one', () async {
      final bloc = await boot(SessionPhase.serverMismatch);

      final state = bloc.state as Initialized;
      expect(state.isServerMismatch, isTrue);
      expect(state.isOffline, isFalse);
    });

    test('the files stay listed under it - nothing local is thrown away', () async {
      final bloc = await boot(SessionPhase.serverMismatch);

      expect((bloc.state as Initialized).files, isNotEmpty);
    });

    test('the banner action asks for another attempt', () async {
      final bloc = await boot(SessionPhase.serverMismatch);

      bloc.add(const ChatCardEvent.retryConnection());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(phase.reconnects, 1);
    });

    test('a fixed cause clears it', () async {
      final bloc = await boot(SessionPhase.serverMismatch);
      expect((bloc.state as Initialized).isServerMismatch, isTrue);

      phase.emit(SessionPhase.live);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = bloc.state as Initialized;
      expect(state.isServerMismatch, isFalse);
      expect(state.isOffline, isFalse);
    });
  });
}

/// A controllable [ConnectivityService] for the P1 tests (seed-then-live).
class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity(this._online);
  bool _online;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> watchOnline() async* {
    yield _online;
    yield* _controller.stream;
  }
}

/// A session phase this test drives by hand, plus a count of how many times the
/// screen asked for another attempt.
class _FakePhase implements SessionPhaseService {
  _FakePhase([this._phase = SessionPhase.live]);

  SessionPhase _phase;
  final StreamController<SessionPhase> _controller = StreamController<SessionPhase>.broadcast();

  int reconnects = 0;

  void emit(SessionPhase next) {
    _phase = next;
    _controller.add(next);
  }

  @override
  SessionPhase get phase => _phase;

  @override
  Stream<SessionPhase> watchPhase() async* {
    yield _phase;
    yield* _controller.stream;
  }

  @override
  Future<void> reconnect() async => reconnects++;
}

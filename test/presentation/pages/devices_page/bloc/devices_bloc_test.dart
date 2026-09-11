import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/device/device_model.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';

import 'devices_bloc_test.mocks.dart';

@GenerateMocks([DeviceRepository])
void main() {
  provideDummy<RepositoryResult<List<DeviceModel>>>(const RepositoryResult<List<DeviceModel>>.success(data: []));
  provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));
  provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.success(data: ''));

  late MockDeviceRepository devices;
  // Drives the "another device was paired" signal. A controller rather than a
  // fixed stream because the tests below need to decide WHEN it fires.
  late StreamController<void> paired;

  final phone = DeviceModel(
    deviceKey: 'k-phone',
    platform: 'ios',
    pairedAt: DateTime(2026, 9, 1),
    lastSeenAt: DateTime(2026, 9, 4),
    isCurrent: true,
  );
  final tablet = DeviceModel(
    deviceKey: 'k-tablet',
    platform: 'android',
    pairedAt: DateTime(2026, 8, 1),
    lastSeenAt: DateTime(2026, 8, 20),
    isCurrent: false,
  );

  setUp(() async {
    await configureDependencies(Environment.test);
    getIt.allowReassignment = true;
    devices = MockDeviceRepository();
    paired = StreamController<void>.broadcast();
    // Stubbed for EVERY test, not only the ones that use it: the bloc
    // subscribes during initialize, and mockito cannot invent a Stream — an
    // unstubbed call throws and would take down cases that have nothing to do
    // with pairing.
    when(devices.watchDeviceListChanged()).thenAnswer((_) => paired.stream);
    getIt.registerSingleton<DeviceRepository>(devices);
  });
  tearDown(() async {
    await paired.close();
    await getIt.reset();
  });

  blocTest<DevicesBloc, DevicesState>(
    'loads the list and tells this device apart from the others',
    build: () {
      when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone, tablet]));
      return DevicesBloc();
    },
    act: (bloc) => bloc.add(const DevicesEvent.initialize()),
    expect: () => [
      predicate<DevicesState>((s) => s.loading),
      predicate<DevicesState>((s) => !s.loading && s.current?.deviceKey == 'k-phone' && s.others.length == 1),
    ],
  );

  blocTest<DevicesBloc, DevicesState>(
    'a failed load says so rather than showing an empty list',
    build: () {
      when(
        devices.getDevices(),
      ).thenAnswer((_) async => const RepositoryResult<List<DeviceModel>>.error(exception: RepositoryException.connection));
      return DevicesBloc();
    },
    act: (bloc) => bloc.add(const DevicesEvent.initialize()),
    expect: () => [predicate<DevicesState>((s) => s.loading), predicate<DevicesState>((s) => !s.loading && s.failed)],
  );

  blocTest<DevicesBloc, DevicesState>(
    'revoking re-reads from the server instead of dropping the row locally',
    build: () {
      when(devices.revoke(deviceKey: anyNamed('deviceKey'))).thenAnswer((_) async => const RepositoryResult<bool>.success(data: true));
      when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
      return DevicesBloc();
    },
    act: (bloc) => bloc.add(const DevicesEvent.revokeRequested('k-tablet')),
    wait: const Duration(milliseconds: 100),
    verify: (_) {
      verify(devices.revoke(deviceKey: 'k-tablet')).called(1);
      // The server is the authority on what is still allowed: a revoke that
      // silently failed would otherwise leave a device looking gone while it
      // is still connecting.
      verify(devices.getDevices()).called(1);
    },
  );

  blocTest<DevicesBloc, DevicesState>(
    'an invite is held in state, because every request burns a new token',
    build: () {
      when(devices.inviteDevice()).thenAnswer((_) async => const RepositoryResult<String>.success(data: 'https://nox.app/p/#abc'));
      return DevicesBloc();
    },
    act: (bloc) => bloc.add(const DevicesEvent.inviteRequested()),
    wait: const Duration(milliseconds: 100),
    expect: () => [predicate<DevicesState>((s) => s.inviteLink == 'https://nox.app/p/#abc')],
  );

  blocTest<DevicesBloc, DevicesState>(
    'a failed revoke says so instead of pretending the device is gone',
    build: () {
      when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone, tablet]));
      when(
        devices.revoke(deviceKey: anyNamed('deviceKey')),
      ).thenAnswer((_) async => const RepositoryResult<bool>.error(exception: RepositoryException.connection));
      return DevicesBloc();
    },
    act: (bloc) async {
      bloc.add(const DevicesEvent.initialize());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bloc.add(const DevicesEvent.revokeRequested('k-tablet'));
    },
    wait: const Duration(milliseconds: 100),
    verify: (bloc) {
      expect(bloc.state.failed, isTrue);
      // And the row is still there: a device that is still connecting must not
      // look gone.
      expect(bloc.state.others.length, 1);
    },
  );

  blocTest<DevicesBloc, DevicesState>(
    'a failed invite raises a flag the screen can render',
    build: () {
      when(devices.inviteDevice()).thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.connection));
      return DevicesBloc();
    },
    act: (bloc) => bloc.add(const DevicesEvent.inviteRequested()),
    wait: const Duration(milliseconds: 100),
    // Without this the button is simply dead: tapping it does nothing at all.
    expect: () => [predicate<DevicesState>((s) => s.inviteFailed && s.inviteLink == null)],
  );

  blocTest<DevicesBloc, DevicesState>(
    'revoking THIS device goes through logout, not through a bare delete',
    build: () {
      when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone, tablet]));
      return DevicesBloc();
    },
    act: (bloc) async {
      bloc.add(const DevicesEvent.initialize());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bloc.add(const DevicesEvent.revokeRequested('k-phone'));
    },
    wait: const Duration(milliseconds: 100),
    verify: (_) {
      // Deleting the row alone would leave the app sitting there with a session
      // the server no longer honours. Logout wipes and moves the navigation.
      verifyNever(devices.revoke(deviceKey: 'k-phone'));
    },
  );
  group('the list keeps up with the server (038)', () {
    // The defect this closes: the screen read the list once, when it was built,
    // so a device added from another device stayed invisible until somebody
    // left the section and came back.
    blocTest<DevicesBloc, DevicesState>(
      'a device paired elsewhere lands in the open list without anyone touching it',
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone, tablet]));
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) {
        // Asserted on the state, not on the call count: "it asked again" is not
        // the promise — "the screen shows what the server has" is.
        expect(bloc.state.devices, hasLength(2));
        verify(devices.getDevices()).called(2);
      },
    );

    blocTest<DevicesBloc, DevicesState>(
      'the spent invite card goes with it',
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        when(devices.inviteDevice()).thenAnswer((_) async => const RepositoryResult<String>.success(data: 'https://nox.app/p/#tok'));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const DevicesEvent.inviteRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) => expect(bloc.state.inviteLink, isNull, reason: 'the QR stayed up for a token the server will now refuse'),
    );

    blocTest<DevicesBloc, DevicesState>(
      'and a new invite can still be minted afterwards',
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        when(devices.inviteDevice()).thenAnswer((_) async => const RepositoryResult<String>.success(data: 'https://nox.app/p/#second'));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const DevicesEvent.inviteRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) => expect(bloc.state.inviteLink, 'https://nox.app/p/#second'),
    );
    blocTest<DevicesBloc, DevicesState>(
      'the screen never blanks while it catches up',
      // The first cut of this delivered US1 as "the list vanishes, then comes
      // back": both new triggers re-entered initialize, which raised `loading`,
      // and the body renders a bare spinner whenever that is set. Nobody asked
      // for anything, and on a flapping link it strobes.
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // A DIFFERENT list on the second read, so the catch-up actually emits:
        // a bloc swallows a state equal to the one before it, and with an
        // identical list this test would pass without proving anything.
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone, tablet]));
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      // Exactly three states, and the spinner appears in the first only. A
      // `loading: true` raised by the catch-up would show up here as a fourth.
      expect: () => [
        predicate<DevicesState>((s) => s.loading, 'the opening load shows a spinner'),
        predicate<DevicesState>((s) => !s.loading && s.devices.length == 1, 'the list arrives'),
        predicate<DevicesState>(
          (s) => !s.loading && s.devices.length == 2,
          'the fresh list replaces it in place, with no blank in between',
        ),
      ],
    );

    blocTest<DevicesBloc, DevicesState>(
      'a catch-up that fails leaves the list on screen',
      // The list shown is the last thing the server actually said. Replacing it
      // with an error screen would trade the truth we have for news about a
      // request nobody made.
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone, tablet]));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        when(
          devices.getDevices(),
        ).thenAnswer((_) async => const RepositoryResult<List<DeviceModel>>.error(exception: RepositoryException.connection));
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) {
        expect(bloc.state.devices, hasLength(2), reason: 'a failed catch-up threw away a list the server had confirmed');
        expect(bloc.state.failed, isFalse, reason: 'an unasked-for refresh reported itself as a screen-level failure');
      },
    );
    blocTest<DevicesBloc, DevicesState>(
      'a failed catch-up does not erase an error that is already on screen',
      // The first cut of this guard overshot: it cleared `failed` on every
      // refresh instead of leaving it alone. Open the section while the channel
      // is down and the error screen is right; when the channel comes back and
      // that read ALSO fails, clearing the flag swaps a truthful "we could not
      // load your devices" for an empty list and an `Add a device` button —
      // with no retry and no way back short of leaving the section.
      build: () {
        when(
          devices.getDevices(),
        ).thenAnswer((_) async => const RepositoryResult<List<DeviceModel>>.error(exception: RepositoryException.connection));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // Still broken when the catch-up runs.
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) {
        expect(bloc.state.failed, isTrue, reason: 'the catch-up wiped an error the person still needed to see');
        expect(bloc.state.devices, isEmpty);
      },
    );

    blocTest<DevicesBloc, DevicesState>(
      'and a catch-up that works clears it',
      // The other direction, so the flag cannot become sticky: once the server
      // has actually answered, the error is over.
      build: () {
        when(
          devices.getDevices(),
        ).thenAnswer((_) async => const RepositoryResult<List<DeviceModel>>.error(exception: RepositoryException.connection));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        paired.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) {
        expect(bloc.state.failed, isFalse);
        expect(bloc.state.devices, hasLength(1));
      },
    );
  });

  group('the channel coming back (038)', () {
    late _FakePhase phase;

    setUp(() {
      // Starts LIVE, because that is the ordinary case: by the time somebody
      // opens Settings the channel is usually already up, and the value the
      // stream replays on listen is the baseline rather than news.
      phase = _FakePhase(SessionPhase.live);
      getIt.registerSingleton<SessionPhaseService>(phase);
    });

    blocTest<DevicesBloc, DevicesState>(
      'the list is re-read when the connection returns',
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        phase.emit(SessionPhase.connecting);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        phase.emit(SessionPhase.live);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      // Twice: the opening read, and the one the channel's return caused. The
      // replayed value on subscribe is the baseline and must NOT count - it
      // says what is already true, not that anything changed.
      verify: (_) => verify(devices.getDevices()).called(2),
    );

    blocTest<DevicesBloc, DevicesState>(
      'a phase that repeats itself re-reads nothing',
      build: () {
        when(devices.getDevices()).thenAnswer((_) async => RepositoryResult<List<DeviceModel>>.success(data: [phone]));
        return DevicesBloc();
      },
      act: (bloc) async {
        bloc.add(const DevicesEvent.initialize());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        phase.emit(SessionPhase.live);
        phase.emit(SessionPhase.live);
        phase.emit(SessionPhase.live);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      // Without the edge check this reads on every tick, which is the same
      // defect as polling and just as invisible.
      verify: (_) => verify(devices.getDevices()).called(1),
    );
  });
}

/// A [SessionPhaseService] the test drives by hand.
///
/// Replays its current value on listen, like the real one: that replay is what
/// the bloc's baseline tick exists for, and a fake without it would let a
/// broken edge check pass.
class _FakePhase implements SessionPhaseService {
  _FakePhase(this._phase);

  final StreamController<SessionPhase> _controller = StreamController<SessionPhase>.broadcast();
  SessionPhase _phase;

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
}

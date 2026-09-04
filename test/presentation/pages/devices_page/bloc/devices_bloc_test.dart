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
import 'package:nox_app/presentation/pages/devices_page/bloc/devices_bloc.dart';

import 'devices_bloc_test.mocks.dart';

@GenerateMocks([DeviceRepository])
void main() {
  provideDummy<RepositoryResult<List<DeviceModel>>>(const RepositoryResult<List<DeviceModel>>.success(data: []));
  provideDummy<RepositoryResult<bool>>(const RepositoryResult<bool>.success(data: true));
  provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.success(data: ''));

  late MockDeviceRepository devices;

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
    getIt.registerSingleton<DeviceRepository>(devices);
  });
  tearDown(() async => getIt.reset());

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
}

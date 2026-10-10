import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/presentation/pages/connection_page/bloc/connection_settings_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/fake_session_repository.dart';
import '../../../../utils/fixed_connection_status.dart';
import '../../../../utils/fixed_session_phase.dart';

/// A real v3 address (RFC 8032 test 1's key); format only is checked here -
/// the test environment has no Tor module to derive the checksum with.
const String _onion = '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion';
const String _link = '192.168.1.20:8443';

/// Settings > Connection (phase 045, US4, FR-014, FR-015).
void main() {
  late ServerAddressesRepository addresses;
  late FixedSessionPhaseService phase;
  late FixedConnectionStatusService status;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    getIt.allowReassignment = true;
    phase = FixedSessionPhaseService();
    getIt.registerSingleton<SessionPhaseService>(phase);
    status = FixedConnectionStatusService(FixedConnectionStatusService.direct);
    getIt.registerSingleton<ConnectionStatusService>(status);
    addresses = getIt<ServerAddressesRepository>();
    await getIt<SessionRepository>().saveServer(address: _link, serverKey: 'oJql9HpnWYAv+VX43C0qFKXJnSO+l/hkEn/5ODRVpPA=');
  });

  tearDown(() async => getIt.reset());

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

  Future<ConnectionSettingsBloc> open() async {
    final bloc = ConnectionSettingsBloc()..add(const ConnectionSettingsEvent.initialize());
    addTearDown(bloc.close);
    await settle();
    return bloc;
  }

  group('what the fields show', () {
    test('the link\'s address, no onion address, Use Tor off - before the server has said anything', () async {
      final bloc = await open();

      expect(bloc.state.loading, isFalse);
      expect(bloc.state.serverAddress, _link);
      expect(bloc.state.onionAddress, isEmpty);
      expect(bloc.state.useTor, isFalse);
      expect(bloc.state.canSave, isFalse, reason: 'nothing changed');
    });

    test('the server\'s public address over the link\'s, and its onion address as a host', () async {
      await addresses.saveFromServer(direct: const ['192.168.1.20:8443'], public: 'nox.example.org:8443', onion: '$_onion:443');
      await addresses.setUseTor(true);

      final bloc = await open();

      expect(bloc.state.serverAddress, 'nox.example.org:8443');
      expect(bloc.state.onionAddress, _onion);
      expect(bloc.state.useTor, isTrue);
    });

    test('the person\'s own edit over what the server says', () async {
      await addresses.saveFromServer(direct: const [], onion: '$_onion:443');
      await addresses.saveManual(manualAddress: '10.8.0.2:8443', manualOnion: '');

      final bloc = await open();

      expect(bloc.state.serverAddress, '10.8.0.2:8443');
      expect(bloc.state.onionAddress, isEmpty, reason: 'cleared by hand: no onion address');
    });

    test('new addresses from the server show up while the section is open, in untouched fields only (US4, scenario 3)', () async {
      final bloc = await open();
      bloc.add(const ConnectionSettingsEvent.onionAddressChanged('half-typed'));
      await settle();

      await addresses.saveFromServer(direct: const [], public: 'nox.example.org:8443', onion: '$_onion:443');
      await settle();

      expect(bloc.state.serverAddress, 'nox.example.org:8443');
      expect(bloc.state.onionAddress, 'half-typed', reason: 'what the person is typing stays');
      expect(bloc.state.appliedOnionAddress, _onion);
    });
  });

  group('Save', () {
    test('is offered for a change that passes the format check, and only then (FR-014)', () async {
      final bloc = await open();

      bloc.add(const ConnectionSettingsEvent.serverAddressChanged('nox.example'));
      await settle();
      expect(bloc.state.canSave, isFalse);
      expect(bloc.state.showServerAddressError, isTrue, reason: 'Save is off, and the field says why');

      bloc.add(const ConnectionSettingsEvent.serverAddressChanged('nox.example.org:8443'));
      await settle();
      expect(bloc.state.canSave, isTrue);
      expect(bloc.state.showServerAddressError, isFalse);

      bloc.add(const ConnectionSettingsEvent.onionAddressChanged('example.onion'));
      await settle();
      expect(bloc.state.canSave, isFalse);
      expect(bloc.state.showOnionAddressError, isTrue);
    });

    test('stores the edits, and starts the channel again at once', () async {
      final bloc = await open();

      bloc
        ..add(const ConnectionSettingsEvent.serverAddressChanged('10.8.0.2:8443'))
        ..add(const ConnectionSettingsEvent.onionAddressChanged(_onion))
        ..add(const ConnectionSettingsEvent.saveRequested());
      await settle();

      final stored = (await addresses.read()).data!;
      expect(stored.manualAddress, '10.8.0.2:8443');
      expect(stored.manualOnion, '$_onion:443');
      expect(phase.reconnects, 1);
      expect(bloc.state.changed, isFalse, reason: 'what is typed is what is applied now');
      expect(bloc.state.canSave, isFalse);
    });

    test('a value equal to what the server says is no edit: the server keeps the field (FR-015)', () async {
      await addresses.saveFromServer(direct: const [], public: 'nox.example.org:8443', onion: '$_onion:443');
      await addresses.saveManual(manualAddress: '10.8.0.2:8443', manualOnion: null);
      final bloc = await open();
      expect(bloc.state.serverAddress, '10.8.0.2:8443');

      bloc
        ..add(const ConnectionSettingsEvent.serverAddressChanged('nox.example.org:8443'))
        ..add(const ConnectionSettingsEvent.saveRequested());
      await settle();

      final stored = (await addresses.read()).data!;
      expect(stored.manualAddress, isNull);
      expect(stored.manualOnion, isNull);
    });

    test('a changed onion address is just typed in - no pairing again (US4)', () async {
      await addresses.saveFromServer(direct: const [], onion: '${'a' * 56}.onion:443');
      final bloc = await open();

      bloc
        ..add(const ConnectionSettingsEvent.onionAddressChanged(_onion))
        ..add(const ConnectionSettingsEvent.saveRequested());
      await settle();

      expect((await addresses.read()).data!.effectiveOnion, '$_onion:443');
    });

    test('an emptied onion field stores no onion address over the server\'s', () async {
      await addresses.saveFromServer(direct: const [], onion: '$_onion:443');
      final bloc = await open();

      bloc
        ..add(const ConnectionSettingsEvent.onionAddressChanged(''))
        ..add(const ConnectionSettingsEvent.saveRequested());
      await settle();

      final stored = (await addresses.read()).data!;
      expect(stored.manualOnion, '');
      expect(stored.effectiveOnion, isNull);
    });

    test('a write that does not land says so, and nothing restarts', () async {
      getIt.registerSingleton<ServerAddressesRepository>(_Refusing(addresses));
      final bloc = await open();

      bloc
        ..add(const ConnectionSettingsEvent.serverAddressChanged('10.8.0.2:8443'))
        ..add(const ConnectionSettingsEvent.saveRequested());
      await settle();

      expect(bloc.state.saveFailed, isTrue);
      expect(phase.reconnects, 0);
    });
  });

  group('Use Tor', () {
    test('applies the moment it is switched, and starts the channel again', () async {
      final bloc = await open();

      bloc.add(const ConnectionSettingsEvent.useTorChanged(true));
      await settle();

      expect(bloc.state.useTor, isTrue);
      expect((await addresses.read()).data!.useTor, isTrue);
      expect(phase.reconnects, 1);

      bloc.add(const ConnectionSettingsEvent.useTorChanged(false));
      await settle();
      expect((await addresses.read()).data!.useTor, isFalse);
      expect(phase.reconnects, 2);
    });

    test('a switch that does not land goes back, and says so', () async {
      getIt.registerSingleton<ServerAddressesRepository>(_Refusing(addresses));
      final bloc = await open();

      bloc.add(const ConnectionSettingsEvent.useTorChanged(true));
      await settle();

      expect(bloc.state.useTor, isFalse);
      expect(bloc.state.saveFailed, isTrue);
    });
  });

  group('the line above the fields', () {
    test('says the cause while there is no connection, and goes when it is back', () async {
      final bloc = await open();
      expect(bloc.state.offline, isFalse);

      status.emit(const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.onionNotFound));
      await settle();
      expect(bloc.state.offline, isTrue);
      expect(bloc.state.problem, ConnectionProblem.onionNotFound);

      status.emit(FixedConnectionStatusService.tor);
      await settle();
      expect(bloc.state.offline, isFalse);
      expect(bloc.state.problem, isNull);
    });

    test('another server behind the onion address is a cause too', () async {
      final bloc = await open();

      status.emit(const ConnectionStatus(state: LinkState.serverMismatch, problem: ConnectionProblem.otherServer));
      await settle();

      expect(bloc.state.problem, ConnectionProblem.otherServer);
    });
  });

  group('leaving the section', () {
    test('while the link\'s address is still being read subscribes to nothing afterwards', () async {
      final read = Completer<void>();
      getIt.registerSingleton<SessionRepository>(_HeldAddressRead(read.future));
      final watched = _Watched(addresses);
      getIt.registerSingleton<ServerAddressesRepository>(watched);
      final counting = _CountingStatus();
      getIt.registerSingleton<ConnectionStatusService>(counting);

      final bloc = ConnectionSettingsBloc()..add(const ConnectionSettingsEvent.initialize());
      await settle();
      await bloc.close();
      read.complete();
      await settle();
      // Both sources move on after the section is gone: a subscription made
      // after close() would add() to the closed bloc and throw here.
      counting.emit(FixedConnectionStatusService.tor);
      await addresses.setUseTor(true);
      await settle();

      expect(watched.listens, 0);
      expect(counting.listens, 0);
    });
  });
}

/// The secure-storage read of the link's address, held until [_released] -
/// how a test leaves the section while it is still under way.
class _HeldAddressRead extends FakeSessionRepository {
  _HeldAddressRead(this._released);

  final Future<void> _released;

  @override
  Future<RepositoryResult<String?>> serverAddress() async {
    await _released;
    return const RepositoryResult<String?>.success(data: _link);
  }
}

/// The real store, counting who starts watching it.
class _Watched implements ServerAddressesRepository {
  _Watched(this._real);

  final ServerAddressesRepository _real;
  int listens = 0;

  @override
  Stream<ServerAddresses> watch() async* {
    listens++;
    yield* _real.watch();
  }

  @override
  Future<RepositoryResult<ServerAddresses>> read() => _real.read();

  @override
  Future<RepositoryResult<bool>> saveManual({required String? manualAddress, required String? manualOnion}) =>
      _real.saveManual(manualAddress: manualAddress, manualOnion: manualOnion);

  @override
  Future<RepositoryResult<bool>> setUseTor(bool useTor) => _real.setUseTor(useTor);

  @override
  Future<RepositoryResult<bool>> saveFromServer({required List<String> direct, String? public, String? onion}) =>
      _real.saveFromServer(direct: direct, public: public, onion: onion);

  @override
  Future<RepositoryResult<bool>> saveFromLink({
    required List<String> direct,
    String? onion,
    String? manualAddress,
    String? manualOnion,
    required bool useTor,
  }) => _real.saveFromLink(direct: direct, onion: onion, manualAddress: manualAddress, manualOnion: manualOnion, useTor: useTor);

  @override
  Future<RepositoryResult<bool>> recordLastGood(String address) => _real.recordLastGood(address);

  @override
  Future<RepositoryResult<bool>> recordGreetedViaTor() => _real.recordGreetedViaTor();

  @override
  Future<RepositoryResult<bool>> clear() => _real.clear();
}

/// A status service counting who starts watching it.
class _CountingStatus extends FixedConnectionStatusService {
  _CountingStatus() : super(FixedConnectionStatusService.direct);

  int listens = 0;

  @override
  Stream<ConnectionStatus> watchStatus() async* {
    listens++;
    yield* super.watchStatus();
  }
}

/// Reads like the real repository and refuses every write.
class _Refusing implements ServerAddressesRepository {
  _Refusing(this._real);

  final ServerAddressesRepository _real;

  static const RepositoryResult<bool> _refused = RepositoryResult<bool>.error(exception: RepositoryException.unknown);

  @override
  Future<RepositoryResult<ServerAddresses>> read() => _real.read();

  @override
  Stream<ServerAddresses> watch() => _real.watch();

  @override
  Future<RepositoryResult<bool>> saveManual({required String? manualAddress, required String? manualOnion}) async => _refused;

  @override
  Future<RepositoryResult<bool>> setUseTor(bool useTor) async => _refused;

  @override
  Future<RepositoryResult<bool>> saveFromServer({required List<String> direct, String? public, String? onion}) async => _refused;

  @override
  Future<RepositoryResult<bool>> saveFromLink({
    required List<String> direct,
    String? onion,
    String? manualAddress,
    String? manualOnion,
    required bool useTor,
  }) async => _refused;

  @override
  Future<RepositoryResult<bool>> recordLastGood(String address) async => _refused;

  @override
  Future<RepositoryResult<bool>> recordGreetedViaTor() async => _refused;

  @override
  Future<RepositoryResult<bool>> clear() async => _refused;
}

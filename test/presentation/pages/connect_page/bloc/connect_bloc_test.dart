import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/service/tor/fake_tor_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/pairing_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/connection/connection_problem.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/service/connection_status_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';
import 'package:nox_app/presentation/pages/connect_page/bloc/connect_bloc.dart';

import '../../../../utils/fixed_connection_status.dart';
import 'connect_bloc_test.mocks.dart';

/// A link with one direct address and nothing else (the contract's `minimal`
/// vector).
const String _homeLink = 'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7';

/// The contract's `full` vector: 192.168.1.20:8443, nox.example.org:8443 and
/// an onion service.
const String _onionLink =
    'nox://pair/A6CapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTwAAECAwQFBgcICQoLDA0ODwEGwKgBFCD7AxFub3guZXhhbXBsZS5vcmcg-wQgF8t5-ytBIPKx7GXkGY1uCLKOgT_rAeSkAIObheGAgM4';

/// A real v3 address, checksum and all: the onion address of RFC 8032 test
/// 1's public key.
const String _validOnion = '25njqamcweflpvkl73j4szahhihoc4xt3ktcgjnpaingr5yhkenl5sid.onion';
final Uint8List _validOnionKey = Uint8List.fromList([
  0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a, //
  0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
]);

/// What the link's own onion key derives to, here.
const String _linkOnion = 'linkonionlinkonionlinkonionlinkonionlinkonionlinkonio.onion';

@GenerateMocks([AuthRepository])
void main() {
  provideDummy<RepositoryResult<bool>>(const RepositoryResult.success(data: true));

  late MockAuthRepository auth;
  late FixedConnectionStatusService status;
  late FakeTorService tor;
  late StreamController<bool> approval;

  setUp(() async {
    await configureDependencies(Environment.test);
    getIt.allowReassignment = true;
    auth = MockAuthRepository();
    approval = StreamController<bool>.broadcast();
    addTearDown(approval.close);
    when(auth.watchAwaitingApproval()).thenAnswer((_) => approval.stream);
    when(auth.cancelPairing()).thenAnswer((_) async {});
    getIt.registerSingleton<AuthRepository>(auth);
    status = FixedConnectionStatusService(const ConnectionStatus(state: LinkState.connecting));
    getIt.registerSingleton<ConnectionStatusService>(status);
    // The module's arithmetic, stood in for: the link's key, and the one real
    // address the tests type.
    tor = getIt<TorService>() as FakeTorService
      ..onionOf = (key) {
        if (_same(key, _validOnionKey)) return _validOnion;
        return _linkOnion;
      };
  });
  tearDown(() async => getIt.reset());

  /// The settings the one pairing went out with.
  ConnectionSettings? sentSettings() {
    final captured = verify(auth.signIn(identifier: anyNamed('identifier'), connection: captureAnyNamed('connection'))).captured;
    return captured.single as ConnectionSettings?;
  }

  group('what the link puts in the fields (FR-013)', () {
    test('its first direct address, its onion address, and Use Tor off', () {
      final bloc = ConnectBloc(link: _onionLink);
      addTearDown(bloc.close);

      expect(bloc.state.serverAddress, '192.168.1.20:8443');
      expect(bloc.state.onionAddress, _linkOnion);
      expect(bloc.state.useTor, isFalse);
      expect(bloc.state.status, ConnectStatus.idle);
      expect(bloc.state.showServerAddressError, isFalse);
    });

    test('a link without an onion address leaves that field empty', () {
      final bloc = ConnectBloc(link: _homeLink);
      addTearDown(bloc.close);

      expect(bloc.state.serverAddress, '192.168.1.20:8443');
      expect(bloc.state.onionAddress, isEmpty);
    });

    test('where the module cannot derive it, the onion field stays empty', () {
      tor.onionOf = (_) => null;
      final bloc = ConnectBloc(link: _onionLink);
      addTearDown(bloc.close);

      expect(bloc.state.onionAddress, isEmpty);
    });
  });

  group('Connect', () {
    blocTest<ConnectBloc, ConnectState>(
      'pairs by the link with what stands in the fields, as they are',
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return ConnectBloc(link: _onionLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final captured = verify(auth.signIn(identifier: captureAnyNamed('identifier'), connection: captureAnyNamed('connection'))).captured;
        expect(captured, [_onionLink, const ConnectionSettings(serverAddress: '192.168.1.20:8443', onionAddress: '$_linkOnion:443')]);
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'what the person changed goes with it: another address, a typed onion address, and Use Tor',
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc
        ..add(const ConnectEvent.serverAddressChanged(' nox.example.org:8443 '))
        ..add(ConnectEvent.onionAddressChanged(_validOnion.toUpperCase()))
        ..add(const ConnectEvent.useTorChanged(true))
        ..add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (_) => expect(
        sentSettings(),
        const ConnectionSettings(serverAddress: 'nox.example.org:8443', onionAddress: '$_validOnion:443', useTor: true),
      ),
    );

    blocTest<ConnectBloc, ConnectState>(
      'an emptied onion field is no onion address at all',
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')),
        ).thenAnswer((_) async => const RepositoryResult.success(data: true));
        return ConnectBloc(link: _onionLink);
      },
      act: (bloc) => bloc
        ..add(const ConnectEvent.onionAddressChanged('  '))
        ..add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (_) => expect(sentSettings()?.onionAddress, isNull),
    );

    blocTest<ConnectBloc, ConnectState>(
      'shows the wait, and leaves the moving on to the app-state spine',
      build: () {
        final answer = Completer<RepositoryResult<bool>>();
        when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) => answer.future);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      expect: () => [predicate<ConnectState>((s) => s.isConnecting)],
    );

    blocTest<ConnectBloc, ConnectState>(
      'a second press while one attempt is under way starts no second pairing',
      build: () {
        final answer = Completer<RepositoryResult<bool>>();
        when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) => answer.future);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) async {
        bloc.add(const ConnectEvent.connectRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc
          ..add(const ConnectEvent.connectRequested())
          ..add(const ConnectEvent.serverAddressChanged('10.0.0.1:1'));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        verify(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).called(1);
        expect(bloc.state.serverAddress, '192.168.1.20:8443', reason: 'the fields are locked while it runs');
      },
    );
  });

  group('an invite that waits for approval (phase 046)', () {
    /// A sign-in that waits: the repository says so, then holds until [answer].
    void waitsFor(Completer<RepositoryResult<bool>> answer) {
      when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) async {
        approval.add(true);
        return answer.future;
      });
    }

    blocTest<ConnectBloc, ConnectState>(
      'the screen waits once the request does, and keeps the fields from changing under it',
      build: () {
        waitsFor(Completer<RepositoryResult<bool>>());
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) async {
        bloc.add(const ConnectEvent.connectRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc
          ..add(const ConnectEvent.serverAddressChanged('10.0.0.1:1'))
          ..add(const ConnectEvent.useTorChanged(true))
          ..add(const ConnectEvent.connectRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.status, ConnectStatus.waiting);
        expect(bloc.state.isBusy, isTrue);
        expect(bloc.state.serverAddress, '192.168.1.20:8443');
        expect(bloc.state.useTor, isFalse);
        verify(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).called(1);
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'a wait reported while nothing was pressed is not this screen\'s',
      build: () => ConnectBloc(link: _homeLink),
      act: (bloc) => approval.add(true),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) => expect(bloc.state.status, ConnectStatus.idle),
    );

    blocTest<ConnectBloc, ConnectState>(
      'Allow on the other device: the spine moves on, and the screen stops waiting',
      build: () {
        final answer = Completer<RepositoryResult<bool>>();
        waitsFor(answer);
        Future<void>.delayed(const Duration(milliseconds: 30), () => answer.complete(const RepositoryResult.success(data: true)));
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 60),
      expect: () => [
        predicate<ConnectState>((s) => s.isConnecting),
        predicate<ConnectState>((s) => s.isWaiting),
        predicate<ConnectState>((s) => s.status == ConnectStatus.idle),
      ],
    );

    blocTest<ConnectBloc, ConnectState>(
      'Deny on the other device is said as such',
      build: () {
        final answer = Completer<RepositoryResult<bool>>();
        waitsFor(answer);
        Future<void>.delayed(
          const Duration(milliseconds: 30),
          () => answer.complete(const RepositoryResult.error(exception: PairingException.declined)),
        );
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        expect(bloc.state.status, ConnectStatus.declined);
        expect(bloc.state.isBusy, isFalse, reason: 'the way back is open again');
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'no answer in time reads as an expired link',
      build: () {
        final answer = Completer<RepositoryResult<bool>>();
        waitsFor(answer);
        Future<void>.delayed(
          const Duration(milliseconds: 30),
          () => answer.complete(const RepositoryResult.error(exception: RepositoryException.notFound)),
        );
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 60),
      verify: (bloc) => expect(bloc.state.status, ConnectStatus.linkExpired),
    );

    blocTest<ConnectBloc, ConnectState>(
      'Cancel withdraws the request, once, and the screen closes when the sign-in ends so',
      build: () {
        final answer = Completer<RepositoryResult<bool>>();
        waitsFor(answer);
        when(auth.cancelPairing()).thenAnswer((_) async {
          answer.complete(const RepositoryResult.error(exception: PairingException.cancelled));
        });
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) async {
        bloc.add(const ConnectEvent.connectRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc
          ..add(const ConnectEvent.cancelRequested())
          ..add(const ConnectEvent.cancelRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        verify(auth.cancelPairing()).called(1);
        expect(bloc.state.status, ConnectStatus.cancelled);
        expect(bloc.state.cancelling, isFalse);
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'Cancel does nothing while nothing waits',
      build: () => ConnectBloc(link: _homeLink),
      act: (bloc) => bloc.add(const ConnectEvent.cancelRequested()),
      verify: (_) => verifyNever(auth.cancelPairing()),
    );

    blocTest<ConnectBloc, ConnectState>(
      'a wait the app was closed in comes back with what was set for it, and presents the link at once (FR-011)',
      build: () {
        when(
          auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')),
        ).thenAnswer((_) => Completer<RepositoryResult<bool>>().future);
        return ConnectBloc(
          link: _homeLink,
          resume: true,
          settings: const ConnectionSettings(serverAddress: '10.8.0.2:8443', onionAddress: '$_validOnion:443', useTor: true),
        );
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.serverAddress, '10.8.0.2:8443');
        expect(bloc.state.onionAddress, _validOnion);
        expect(bloc.state.useTor, isTrue);
        expect(sentSettings(), const ConnectionSettings(serverAddress: '10.8.0.2:8443', onionAddress: '$_validOnion:443', useTor: true));
      },
    );
  });

  group('format checks (US5, scenario 1)', () {
    blocTest<ConnectBloc, ConnectState>(
      'an address that is not host:port is refused at its field, and nothing goes out',
      build: () => ConnectBloc(link: _homeLink),
      act: (bloc) => bloc
        ..add(const ConnectEvent.serverAddressChanged('nox.example.org'))
        ..add(const ConnectEvent.connectRequested()),
      verify: (bloc) {
        expect(bloc.state.showServerAddressError, isTrue);
        expect(bloc.state.isConnecting, isFalse);
        verifyNever(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')));
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'no error is shown while the person is still typing, before Connect',
      build: () => ConnectBloc(link: _homeLink),
      act: (bloc) => bloc.add(const ConnectEvent.serverAddressChanged('nox.exam')),
      verify: (bloc) {
        expect(bloc.state.serverAddressInvalid, isTrue);
        expect(bloc.state.showServerAddressError, isFalse);
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'after Connect the field error follows the typing',
      build: () => ConnectBloc(link: _homeLink),
      act: (bloc) => bloc
        ..add(const ConnectEvent.serverAddressChanged('nope'))
        ..add(const ConnectEvent.connectRequested())
        ..add(const ConnectEvent.serverAddressChanged('nox.example.org:8443')),
      verify: (bloc) => expect(bloc.state.showServerAddressError, isFalse),
    );

    for (final bad in ['abc.onion', '${'a' * 56}.onion', '$_validOnion:8443', 'http://$_validOnion']) {
      blocTest<ConnectBloc, ConnectState>(
        '"$bad" is not an onion address: refused at its field, and nothing goes out',
        build: () => ConnectBloc(link: _homeLink),
        act: (bloc) => bloc
          ..add(ConnectEvent.onionAddressChanged(bad))
          ..add(const ConnectEvent.connectRequested()),
        verify: (bloc) {
          expect(bloc.state.showOnionAddressError, isTrue);
          verifyNever(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')));
        },
      );
    }

    blocTest<ConnectBloc, ConnectState>(
      'a typo the checksum catches is refused too',
      build: () => ConnectBloc(link: _homeLink),
      act: (bloc) => bloc
        // One character off in the key: still base32, still version 3 - but
        // the key it carries derives to another address.
        ..add(ConnectEvent.onionAddressChanged('25njqb${_validOnion.substring(6)}'))
        ..add(const ConnectEvent.connectRequested()),
      verify: (bloc) => expect(bloc.state.showOnionAddressError, isTrue),
    );
  });

  group('when it does not work', () {
    void signInFails(RepositoryException exception) {
      when(
        auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection')),
      ).thenAnswer((_) async => RepositoryResult.error(exception: exception));
    }

    blocTest<ConnectBloc, ConnectState>(
      'an expired link says so, as on the sign-in screen',
      build: () {
        signInFails(RepositoryException.notFound);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.status, ConnectStatus.linkExpired),
    );

    blocTest<ConnectBloc, ConnectState>(
      'a rejected link says so, apart from an expired one',
      build: () {
        signInFails(RepositoryException.authentication);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.status, ConnectStatus.linkRejected),
    );

    blocTest<ConnectBloc, ConnectState>(
      'no server reached, and no cause known: failed, with nothing to name',
      build: () {
        signInFails(RepositoryException.connection);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.status, ConnectStatus.failed);
        expect(bloc.state.problem, isNull);
        expect(bloc.state.isConnecting, isFalse, reason: 'Connect can be pressed again');
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'the cause the attempt met is said as soon as it shows, and kept when the attempt ends (US3, scenario 2)',
      build: () {
        when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) async {
          // The status stream is listened to a turn after the bloc is built.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          status.emit(const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.turnOnTor));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          // The rollback takes the selector's answer away before sign-in returns.
          status.emit(const ConnectionStatus(state: LinkState.offline));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const RepositoryResult.error(exception: RepositoryException.connection);
        });
        return ConnectBloc(link: _onionLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        predicate<ConnectState>((s) => s.isConnecting && s.problem == null),
        predicate<ConnectState>((s) => s.isConnecting && s.problem == ConnectionProblem.turnOnTor),
        predicate<ConnectState>((s) => s.status == ConnectStatus.failed && s.problem == ConnectionProblem.turnOnTor),
      ],
    );

    blocTest<ConnectBloc, ConnectState>(
      'another server behind the onion address is its own cause, and the token never went out (US3, scenario 4)',
      build: () {
        when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) async {
          // The status stream is listened to a turn after the bloc is built.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          status.emit(const ConnectionStatus(state: LinkState.serverMismatch, problem: ConnectionProblem.otherServer));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const RepositoryResult.error(exception: RepositoryException.connection);
        });
        return ConnectBloc(link: _onionLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state.status, ConnectStatus.failed);
        expect(bloc.state.problem, ConnectionProblem.otherServer);
      },
    );

    blocTest<ConnectBloc, ConnectState>(
      'an onion address the module refused as malformed is said at its field',
      build: () {
        when(auth.signIn(identifier: anyNamed('identifier'), connection: anyNamed('connection'))).thenAnswer((_) async {
          // The status stream is listened to a turn after the bloc is built.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          status.emit(const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.invalidOnion));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const RepositoryResult.error(exception: RepositoryException.connection);
        });
        return ConnectBloc(link: _onionLink);
      },
      act: (bloc) => bloc.add(const ConnectEvent.connectRequested()),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) => expect(bloc.state.showOnionAddressError, isTrue),
    );

    blocTest<ConnectBloc, ConnectState>(
      'a cause seen while nothing was being attempted is not this attempt\'s',
      build: () {
        signInFails(RepositoryException.connection);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) async {
        status.emit(const ConnectionStatus(state: LinkState.offline, problem: ConnectionProblem.torNetwork));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const ConnectEvent.connectRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.problem, isNull),
    );

    blocTest<ConnectBloc, ConnectState>(
      'changing anything takes back what the last attempt said',
      build: () {
        signInFails(RepositoryException.notFound);
        return ConnectBloc(link: _homeLink);
      },
      act: (bloc) async {
        bloc.add(const ConnectEvent.connectRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const ConnectEvent.useTorChanged(true));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.status, ConnectStatus.idle);
        expect(bloc.state.useTor, isTrue);
      },
    );
  });
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

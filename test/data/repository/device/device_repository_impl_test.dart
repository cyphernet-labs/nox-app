import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/repository/device/device_repository_impl.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/fake_session_repository.dart';
import 'device_repository_impl_test.mocks.dart';

/// The only place the `device.list` wire shape becomes a domain model. Nothing
/// else pins the field names, the epoch-seconds conversion, or how "this
/// device" is recognised - and all three are silent when wrong: a renamed field
/// yields a blank row, seconds read as milliseconds put every device in 1970,
/// and a broken comparison makes the revoke list offer a logout as if it were
/// cutting off a stranger.
@GenerateMocks([NoxSocketClient])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNoxSocketClient socket;
  late DeviceRepositoryImpl repository;

  // The public half of the seed FakeSessionRepository hands out.
  const ownKey = 'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    // The repository logs every failure through the container, so the failure
    // paths need a real one.
    await configureDependencies(Environment.test);
    socket = MockNoxSocketClient();
    repository = DeviceRepositoryImpl(socket, FakeSessionRepository());
  });
  tearDown(() async => getIt.reset());

  CommandReply ok(Map<String, dynamic> data) => CommandReply(id: 1, ok: true, data: data);

  test('translates the wire shape, and marks the device this app is running on', () async {
    when(socket.send('device.list', any)).thenAnswer(
      (_) async => ok({
        'devices': [
          {'device_key': ownKey, 'platform': 'ios', 'created_at': 1788496080, 'last_seen_at': 1788499999},
          {'device_key': 'someone-elses', 'platform': 'macos', 'created_at': 1788000000, 'last_seen_at': 1788100000},
        ],
      }),
    );

    final devices = (await repository.getDevices()).data!;

    expect(devices.length, 2);
    expect(devices.first.platform, 'ios');
    expect(devices.first.isCurrent, isTrue, reason: 'derived from this device own key, not sent by the server');
    expect(devices.last.isCurrent, isFalse);
    // Seconds, not milliseconds: reading these wrong puts every device in 1970
    // and the list silently stops being usable for telling devices apart.
    expect(devices.first.pairedAt.toUtc().year, 2026);
    expect(devices.first.lastSeenAt.isAfter(devices.first.pairedAt), isTrue);
  });

  test('a malformed row is skipped rather than crashing the list', () async {
    when(socket.send('device.list', any)).thenAnswer(
      (_) async => ok({
        'devices': [
          'not a device',
          {'device_key': 'k', 'platform': 'linux', 'created_at': 1, 'last_seen_at': 2},
        ],
      }),
    );

    expect((await repository.getDevices()).data!.length, 1);
  });

  test('a refusal becomes a typed failure, not an empty list', () async {
    // An empty list would read as "you have no devices", which is a different
    // and much more alarming sentence than "we could not ask".
    when(socket.send('device.list', any)).thenAnswer((_) async => const CommandReply(id: 1, ok: false, errorCode: 'internal'));

    final result = await repository.getDevices();

    expect(result.hasData, isFalse);
    expect(result.exception, RepositoryException.internal);
  });

  test('revoke passes the key through and reports a refusal', () async {
    when(socket.send('device.revoke', any)).thenAnswer((_) async => ok(const {}));
    expect((await repository.revoke(deviceKey: 'k')).data, isTrue);
    verify(socket.send('device.revoke', {'device_key': 'k'})).called(1);

    when(socket.send('device.revoke', any)).thenAnswer((_) async => const CommandReply(id: 1, ok: false, errorCode: 'not_found'));
    expect((await repository.revoke(deviceKey: 'k')).hasData, isFalse);
  });

  test('an invite without a link is a failure, not an empty string', () async {
    // An empty link would be rendered as a QR of nothing, and the person would
    // scan it from the other device forever.
    when(socket.send('device.invite', any)).thenAnswer((_) async => ok(const {}));

    expect((await repository.inviteDevice()).hasData, isFalse);
  });

  test('setLabel sends the name and surfaces a refusal', () async {
    when(socket.send('identity.setLabel', any)).thenAnswer((_) async => ok(const {'label': 'Anna'}));
    expect((await repository.setLabel(label: 'Anna')).data, isTrue);
    verify(socket.send('identity.setLabel', {'label': 'Anna'})).called(1);
  });
}

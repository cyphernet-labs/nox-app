import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/data/repository/connection/server_addresses_repository_impl.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ServerAddressesRepositoryImpl repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    repository = ServerAddressesRepositoryImpl(const FlutterSecureStorage());
  });

  test('nothing stored reads as empty', () async {
    expect((await repository.read()).data, ServerAddresses.empty);
  });

  test("what the server said is kept, and so is the last good address across the server's updates", () async {
    await repository.saveFromServer(direct: ['192.168.1.20:8443'], onion: 'abc.onion:443');
    await repository.recordLastGood('192.168.1.20:8443');
    await repository.saveFromServer(direct: ['192.168.1.21:8443'], onion: 'abc.onion:443');
    final addresses = (await repository.read()).data!;
    expect(addresses.direct, ['192.168.1.21:8443']);
    expect(addresses.onion, 'abc.onion:443');
    expect(addresses.lastGood, '192.168.1.20:8443');
  });

  test('a server that stops offering onion clears it', () async {
    await repository.saveFromServer(direct: const [], onion: 'abc.onion:443');
    await repository.saveFromServer(direct: const [], onion: null);
    expect((await repository.read()).data!.onion, isNull);
  });

  test('concurrent writes do not lose each other', () async {
    await Future.wait([
      repository.saveFromServer(direct: ['10.0.0.5:8443'], onion: 'abc.onion:443'),
      repository.recordLastGood('10.0.0.5:8443'),
    ]);
    final addresses = (await repository.read()).data!;
    expect(addresses.direct, ['10.0.0.5:8443']);
    expect(addresses.lastGood, '10.0.0.5:8443');
  });

  test('a record this build cannot read is treated as absent', () async {
    FlutterSecureStorage.setMockInitialValues({ConnectionStorage.serverAddresses: '{not json'});
    expect((await repository.read()).data, ServerAddresses.empty);
  });
}

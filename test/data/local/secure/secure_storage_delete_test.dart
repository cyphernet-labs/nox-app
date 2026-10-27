import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/local/secure/secure_storage_delete.dart';

/// Deleting a record that may not be there. On a real macOS keychain a plain
/// delete of an absent record fails (-34018); the in-memory storage here cannot
/// show that, so these pin the behaviour the callers rely on instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a record that is not there is left alone, without an error', () async {
    await storage.deleteIfPresent(key: 'session.server_addresses');

    expect(await storage.readAll(), isEmpty);
  });

  test('a record that is there is deleted, and nothing else', () async {
    FlutterSecureStorage.setMockInitialValues({'session.server_addresses': '{}', 'session.identifier': 'id'});

    await storage.deleteIfPresent(key: 'session.server_addresses');

    expect(await storage.read(key: 'session.server_addresses'), isNull);
    expect(await storage.read(key: 'session.identifier'), 'id');
  });
}

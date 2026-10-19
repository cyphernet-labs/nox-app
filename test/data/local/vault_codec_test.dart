import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/vault_codec.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_tor/vault.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const marker = 'a-line-nobody-may-read-on-the-disk';
  final store = stringMapStoreFactory.store('chats');
  late File file;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    file = File(await AppDataRoot.pathOf('app_dev.db'));
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    if (file.existsSync()) file.deleteSync();
    NoxVault.clear();
    await getIt.reset();
  });

  test('a record goes round, sealed afresh every time', () async {
    await getIt<DeviceVault>().ensureOpen();
    const codec = VaultCodec();
    final record = <String, Object?>{
      'key': 'c_1',
      'value': <String, Object?>{'name': marker},
    };

    final first = codec.encode(record);
    final second = codec.encode(record);

    expect(first, isNot(contains(marker)));
    expect(first, isNot(second), reason: 'a fresh nonce for every record');
    expect(base64.decode(first).length, greaterThanOrEqualTo(NoxVault.recordOverhead));
    expect(codec.decode(first), record);
    expect(codec.decode(second), record);
  });

  test('every line on the disk is sealed, and the database reads back what was written (FR-004)', () async {
    final database = AppDatabaseDev(getIt<DeviceVault>());
    await store.record('c_1').put(await database.db, <String, Object?>{'name': marker});
    await database.close();

    final raw = file.readAsStringSync();
    expect(raw, isNot(contains(marker)));
    final lines = const LineSplitter().convert(raw);
    // The first line is sembast's own, and carries only the signature - sealed.
    final meta = json.decode(lines.first) as Map<String, Object?>;
    expect(meta['codec'], isA<String>());
    expect(raw, isNot(contains(VaultCodec.signature)));
    for (final line in lines.skip(1)) {
      expect(base64.decode(line).length, greaterThan(NoxVault.recordOverhead), reason: 'a record, sealed');
    }

    expect(await store.record('c_1').get(await database.db), <String, Object?>{'name': marker});
    await database.close();
  });

  test('under another key the database does not open at all', () async {
    final database = AppDatabaseDev(getIt<DeviceVault>());
    await store.record('c_1').put(await database.db, <String, Object?>{'name': marker});
    await database.close();

    NoxVault.setKey(Uint8List.fromList(List<int>.generate(32, (i) => 0xC0 ^ i)));

    await expectLater(
      databaseFactoryIo.openDatabase(file.path, codec: VaultCodec.sembast),
      throwsA(isA<DatabaseException>().having((e) => e.code, 'code', DatabaseException.errInvalidCodec)),
    );
  });

  test('a record changed on the disk is never read as another one: it is dropped, and the rest reads on', () async {
    final database = AppDatabaseDev(getIt<DeviceVault>());
    await store.record('c_1').put(await database.db, <String, Object?>{'name': marker});
    await store.record('c_2').put(await database.db, <String, Object?>{'name': 'kept'});
    await database.close();
    final lines = file.readAsLinesSync();
    // The line of c_1: the one before last.
    final at = lines.length - 2;
    final record = lines[at];
    lines[at] = record.substring(0, 20) + (record[20] == 'A' ? 'B' : 'A') + record.substring(21);
    file.writeAsStringSync('${lines.join('\n')}\n');

    final reopened = await databaseFactoryIo.openDatabase(file.path, codec: VaultCodec.sembast);
    addTearDown(reopened.close);

    expect(await store.record('c_1').get(reopened), isNull, reason: 'sembast drops a line that does not open');
    expect(await store.record('c_2').get(reopened), <String, Object?>{'name': 'kept'});
  });
}

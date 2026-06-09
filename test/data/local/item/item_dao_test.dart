import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/local/item/item_dao.dart';
import 'package:nox_app/di/configure_dependencies.dart';

ItemEntity _entity(String id) =>
    ItemEntity(id: id, name: 'name-$id', status: 'active', createdAt: '2026-01-02T03:04:05.000Z', description: null);

void main() {
  late ItemDao dao;

  setUp(() async {
    await configureDependencies(Environment.test); // AppDatabaseTest = in-memory Sembast
    dao = getIt<ItemDao>();
    await dao.cleanData();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('saveData then getData round-trips the batch', () async {
    await dao.saveData([_entity('a'), _entity('b')]);
    final all = await dao.getData();
    expect(all.map((e) => e.id).toSet(), {'a', 'b'});
  });

  test('upsert writes, removeById deletes, cleanData empties', () async {
    await dao.upsert(_entity('a'));
    expect((await dao.getById('a'))?.name, 'name-a');

    await dao.removeById('a');
    expect(await dao.getById('a'), isNull);

    await dao.saveData([_entity('x'), _entity('y')]);
    await dao.cleanData();
    expect(await dao.getData(), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/item/item_entity.dart';
import 'package:nox_app/data/mapper/item/item_mapper.dart';
import 'package:nox_app/domain/model/item/item_status.dart';

void main() {
  final mapper = ItemMapper();

  test('ItemMapper round-trips ItemEntity <-> ItemModel losslessly', () {
    const entity = ItemEntity(id: 'i1', name: 'Hello', status: 'active', createdAt: '2026-01-02T03:04:05.000Z', description: 'desc');

    final model = mapper.toModel(entity: entity);
    final back = mapper.toEntity(model: model);

    expect(model.status, ItemStatus.active);
    expect(back.id, entity.id);
    expect(back.name, entity.name);
    expect(back.status, entity.status);
    expect(back.description, entity.description);
    expect(DateTime.parse(back.createdAt), DateTime.parse(entity.createdAt));
  });

  test('unknown status falls back to draft', () {
    const entity = ItemEntity(id: 'i2', name: 'x', status: 'bogus', createdAt: '2026-01-02T03:04:05.000Z', description: null);
    expect(mapper.toModel(entity: entity).status, ItemStatus.draft);
  });
}

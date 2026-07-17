import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';

// BaseMapper is abstract; its generic list helpers are exercised through a
// concrete subclass (ChatMapper). Only the ad==null branch is reachable — the
// ad!=null branch is dead in lib/ and intentionally not covered here.
void main() {
  final mapper = ChatMapper();

  test('toListModel maps every entity through toModel preserving input order and count', () {
    const entities = [
      ChatEntity(id: 'c1', name: 'Alpha', lastMessagePreview: 'hi', lastMessageAt: '2026-01-02T03:04:05.000Z', unreadCount: 1),
      ChatEntity(id: 'c2', name: 'Beta', lastMessagePreview: 'yo', lastMessageAt: '2026-01-03T03:04:05.000Z', unreadCount: 2),
      ChatEntity(id: 'c3', name: 'Gamma', lastMessagePreview: 'ok', lastMessageAt: '2026-01-04T03:04:05.000Z', unreadCount: 0),
    ];

    final models = mapper.toListModel(entities: entities);

    expect(models.length, entities.length);
    expect(models.map((m) => m.id).toList(), ['c1', 'c2', 'c3']);
    expect(models.map((m) => m.name).toList(), ['Alpha', 'Beta', 'Gamma']);
    // Each element delegates to toModel (unreadCount carried through untouched).
    expect(models.map((m) => m.unreadCount).toList(), [1, 2, 0]);
  });

  test('toListEntity maps every model through toEntity preserving input order and count', () {
    final models = [
      ChatModel(id: 'c1', name: 'Alpha', lastMessagePreview: 'hi', lastMessageAt: DateTime.utc(2026, 1, 2, 3, 4, 5), unreadCount: 1),
      ChatModel(id: 'c2', name: 'Beta', lastMessagePreview: 'yo', lastMessageAt: DateTime.utc(2026, 1, 3, 3, 4, 5), unreadCount: 2),
    ];

    final entities = mapper.toListEntity(models: models);

    expect(entities.length, models.length);
    expect(entities.map((e) => e.id).toList(), ['c1', 'c2']);
    expect(entities.map((e) => e.name).toList(), ['Alpha', 'Beta']);
    // Each element delegates to toEntity (DateTime coerced back to UTC ISO String).
    expect(entities.first.lastMessageAt, '2026-01-02T03:04:05.000Z');
  });

  test('empty input yields empty output for both list helpers', () {
    expect(mapper.toListModel(entities: const []), isEmpty);
    expect(mapper.toListEntity(models: const []), isEmpty);
  });
}

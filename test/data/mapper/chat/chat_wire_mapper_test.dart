import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';

void main() {
  final mapper = ChatWireMapper();

  test('toModel(toWire(model)) is loss-free for every field (S4)', () {
    final model = ChatModel(
      id: 'chat_7',
      name: 'Design crit',
      lastMessagePreview: 'Aria: pushed the tokens',
      lastMessageAt: DateTime(2026, 6, 15, 21, 30),
      unreadCount: 142,
    );

    final round = mapper.toModel(entity: mapper.toEntity(model: model));

    expect(round.id, model.id);
    expect(round.name, model.name);
    expect(round.lastMessagePreview, model.lastMessagePreview);
    expect(round.lastMessageAt.toUtc(), model.lastMessageAt.toUtc()); // same instant
    expect(round.unreadCount, model.unreadCount);
  });

  test('toWire encodes lastMessageAt as a UTC ISO-8601 string', () {
    final wire = mapper.toEntity(
      model: ChatModel(id: 'c', name: 'n', lastMessagePreview: '', lastMessageAt: DateTime.utc(2026, 1, 2, 3, 4, 5)),
    );
    expect(wire.lastMessageAt, '2026-01-02T03:04:05.000Z');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';

void main() {
  final mapper = ChatWireMapper();

  test('toModel(toWire(model)) is loss-free for every wire field', () {
    final model = ChatModel(
      id: 'chat_7',
      name: 'Design crit',
      lastMessagePreview: 'Aria: pushed the tokens',
      lastMessageAt: DateTime.utc(2026, 6, 15, 21, 30),
      createdAt: DateTime.utc(2026, 5, 1, 12, 0),
      createdByLabel: 'Aria',
    );

    final round = mapper.toModel(entity: mapper.toEntity(model: model));

    expect(round.id, model.id);
    expect(round.name, model.name);
    expect(round.lastMessagePreview, model.lastMessagePreview);
    expect(round.lastMessageAt.toUtc(), model.lastMessageAt.toUtc()); // same instant
    expect(round.createdAt!.toUtc(), model.createdAt!.toUtc());
    expect(round.createdByLabel, model.createdByLabel);
  });

  test('toWire encodes times as unix seconds and never carries the local unread', () {
    final wire = mapper.toEntity(
      model: ChatModel(
        id: 'c',
        name: 'n',
        lastMessagePreview: '',
        lastMessageAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        unreadCount: 142,
        createdAt: DateTime.utc(2026, 1, 1),
        createdByLabel: 'Anna',
      ),
    );

    expect(wire.lastActivityAt, DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch ~/ 1000);
    expect(wire.createdAt, DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000);
    expect(wire.toJson().containsKey('unread_count'), isFalse);
  });

  test('toModel starts the device-local unread at zero (§8.3)', () {
    final model = mapper.toModel(
      entity: mapper.toEntity(
        model: ChatModel(id: 'c', name: 'n', lastMessagePreview: '', lastMessageAt: DateTime.utc(2026, 1, 2), unreadCount: 99),
      ),
    );
    expect(model.unreadCount, 0);
  });
}

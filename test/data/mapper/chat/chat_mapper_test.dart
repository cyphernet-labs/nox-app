import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  final mapper = ChatMapper();

  tearDown(AppClock.reset);

  test('ChatMapper round-trips the instant losslessly entity ISO -> model -> entity ISO', () {
    const entity = ChatEntity(
      id: 'c1',
      name: 'General',
      lastMessagePreview: 'Hello there',
      lastMessageAt: '2026-01-02T03:04:05.000Z',
      unreadCount: 3,
    );

    final model = mapper.toModel(entity: entity);
    final back = mapper.toEntity(model: model);

    // toLocal() in toModel and toUtc() in toEntity cancel out — same instant.
    expect(DateTime.parse(back.lastMessageAt), DateTime.parse(entity.lastMessageAt));
  });

  test('ChatMapper.toModel converts the stored UTC ISO to a local wall clock', () {
    const entity = ChatEntity(id: 'c2', name: 'Ops', lastMessagePreview: 'ping', lastMessageAt: '2026-01-02T03:04:05.000Z', unreadCount: 0);

    final model = mapper.toModel(entity: entity);

    expect(model.lastMessageAt.isUtc, isFalse);
  });

  test('ChatMapper.toModel falls back to AppClock.now() when lastMessageAt is unparseable', () {
    final frozen = DateTime.utc(2026, 7, 18, 12, 0, 0);
    AppClock.freeze(frozen);

    const entity = ChatEntity(id: 'c3', name: 'Broken', lastMessagePreview: 'x', lastMessageAt: 'not-a-date', unreadCount: 1);

    final model = mapper.toModel(entity: entity);

    expect(model.lastMessageAt, frozen);
  });

  test('ChatMapper passes id/name/lastMessagePreview/unreadCount through unchanged', () {
    const entity = ChatEntity(
      id: 'c4',
      name: 'Payments',
      lastMessagePreview: 'Latest line of text',
      lastMessageAt: '2026-01-02T03:04:05.000Z',
      unreadCount: 42,
    );

    final model = mapper.toModel(entity: entity);
    final back = mapper.toEntity(model: model);

    expect(model.id, entity.id);
    expect(model.name, entity.name);
    expect(model.lastMessagePreview, entity.lastMessagePreview);
    expect(model.unreadCount, entity.unreadCount);

    expect(back.id, entity.id);
    expect(back.name, entity.name);
    expect(back.lastMessagePreview, entity.lastMessagePreview);
    expect(back.unreadCount, entity.unreadCount);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api/chat/get_chats_api.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  final api = GetChatsApi();

  // Seed facts read from lib/data/remote/api/chat/get_chats_api.dart.
  const seedSize = 28;
  const pageSize = GetChatsConfig.pageSize; // 20
  const tailSize = seedSize - pageSize; // 8 rows on the last page

  // Timestamps come from AppClock.now(); pin it so the seed is deterministic.
  setUp(() => AppClock.freeze(DateTime(2026, 6, 15, 21, 30)));
  tearDown(AppClock.reset);

  group('pagination over the seed', () {
    test('first page returns a full pageSize slice with a non-null nextPage', () async {
      final (chats, meta) = await api.execute(config: GetChatsConfig.firstPage());

      expect(chats, hasLength(pageSize));
      expect(meta.total, seedSize);
      expect(meta.nextPage, 2);
    });

    test('the final page returns the remaining tail with a null nextPage', () async {
      final (chats, meta) = await api.execute(config: GetChatsConfig.nextPage(page: 2));

      expect(chats, hasLength(tailSize));
      expect(meta.total, seedSize);
      expect(meta.nextPage, isNull);
    });

    test('a page past the end returns an empty slice with the total unchanged', () async {
      final (chats, meta) = await api.execute(config: GetChatsConfig.nextPage(page: 3));

      expect(chats, isEmpty);
      expect(meta.total, seedSize);
      expect(meta.nextPage, isNull);
    });

    test('the two pages do not overlap and together cover the whole seed', () async {
      final (firstChats, _) = await api.execute(config: GetChatsConfig.firstPage());
      final (secondChats, _) = await api.execute(config: GetChatsConfig.nextPage(page: 2));

      final ids = <String>{...firstChats.map((c) => c.id), ...secondChats.map((c) => c.id)};
      expect(ids, hasLength(seedSize));
    });
  });

  group('name search', () {
    test('an empty search returns the whole seed', () async {
      final (chats, meta) = await api.execute(config: GetChatsConfig.firstPage(search: ''));

      expect(meta.total, seedSize);
      expect(chats, hasLength(pageSize));
    });

    test('a whitespace-only search is trimmed and returns the whole seed', () async {
      final (_, meta) = await api.execute(config: GetChatsConfig.firstPage(search: '   '));

      expect(meta.total, seedSize);
    });

    test('a no-match search returns an empty slice with a zero total', () async {
      final (chats, meta) = await api.execute(config: GetChatsConfig.firstPage(search: 'zzz-no-such-chat'));

      expect(chats, isEmpty);
      expect(meta.total, 0);
      expect(meta.nextPage, isNull);
    });

    test('a matching ASCII substring filters by name and totals only the matches', () async {
      final (chats, meta) = await api.execute(config: GetChatsConfig.firstPage(search: 'garden'));

      expect(meta.total, 2);
      expect(chats.map((c) => c.name), containsAll(<String>['Garden', 'Gardening 2']));
    });

    test('search is trimmed, lowercased and case-insensitive', () async {
      final (lower, lowerMeta) = await api.execute(config: GetChatsConfig.firstPage(search: 'design'));
      final (upper, upperMeta) = await api.execute(config: GetChatsConfig.firstPage(search: '  DESIGN  '));

      expect(lowerMeta.total, 1);
      expect(upperMeta.total, lowerMeta.total);
      expect(lower.single.name, 'Design crit');
      expect(upper.single.name, lower.single.name);
    });
  });

  group('mock-data shape', () {
    test('ids are chat_0.. in newest-first (lastMessageAt descending) order', () async {
      final (firstChats, _) = await api.execute(config: GetChatsConfig.firstPage());
      final (secondChats, _) = await api.execute(config: GetChatsConfig.nextPage(page: 2));
      final all = [...firstChats, ...secondChats];

      expect(all.first.id, 'chat_0');
      expect(all.map((c) => c.id), [for (var i = 0; i < seedSize; i++) 'chat_$i']);

      for (var i = 1; i < all.length; i++) {
        expect(all[i - 1].lastMessageAt.isAfter(all[i].lastMessageAt), isTrue);
      }
    });

    test('unread counts include a value above the 99+ cap and several zero rows', () async {
      final (firstChats, _) = await api.execute(config: GetChatsConfig.firstPage());
      final (secondChats, _) = await api.execute(config: GetChatsConfig.nextPage(page: 2));
      final counts = [
        for (final c in [...firstChats, ...secondChats]) c.unreadCount,
      ];

      expect(counts, contains(142));
      expect(counts.any((n) => n > 99), isTrue);
      expect(counts.where((n) => n == 0).length, greaterThanOrEqualTo(3));
    });
  });
}

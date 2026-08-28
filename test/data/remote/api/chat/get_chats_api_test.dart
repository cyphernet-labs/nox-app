import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/data/remote/api/chat/get_chats_api.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  final mapper = ChatWireMapper();
  final api = GetChatsApi(mapper);

  // The generator returns the contract-shaped ResponseEntity<ChatsWireEntity>
  // page {chats, has_more}. Unwrap it + map wire->model here so the seed
  // assertions (names, ids, ordering) read off the domain model.
  Future<(List<ChatModel>, PageMetadata)> exec(GetChatsConfig config) async {
    final response = await api.execute(config: config);
    final data = response.data!;
    final chats = mapper.toListModel(entities: data.chats);
    return (chats, PageMetadata(hasMore: data.hasMore, nextPage: data.hasMore ? config.page + 1 : null));
  }

  // Seed facts read from lib/data/remote/api/chat/get_chats_api.dart.
  const seedSize = 28;
  const pageSize = GetChatsConfig.pageSize; // 20
  const tailSize = seedSize - pageSize; // 8 rows on the last page

  // Timestamps come from AppClock.now(); pin it so the seed is deterministic.
  setUp(() => AppClock.freeze(DateTime(2026, 6, 15, 21, 30)));
  tearDown(AppClock.reset);

  test('the generator returns a success envelope carrying the wire page', () async {
    final response = await api.execute(config: GetChatsConfig.firstPage());
    expect(response.success, isTrue);
    expect(response.data, isNotNull);
    expect(response.data!.chats, hasLength(pageSize)); // wire rows
    expect(response.data!.hasMore, isTrue); // 28 seeded > one page
  });

  group('pagination over the seed', () {
    test('first page returns a full pageSize slice with a non-null nextPage', () async {
      final (chats, meta) = await exec(GetChatsConfig.firstPage());

      expect(chats, hasLength(pageSize));
      expect(meta.hasMore, isTrue);
      expect(meta.nextPage, 2);
    });

    test('the final page returns the remaining tail with a null nextPage', () async {
      final (chats, meta) = await exec(GetChatsConfig.nextPage(page: 2));

      expect(chats, hasLength(tailSize));
      expect(meta.hasMore, isFalse);
      expect(meta.nextPage, isNull);
    });

    test('a page past the end returns an empty slice with no more pages', () async {
      final (chats, meta) = await exec(GetChatsConfig.nextPage(page: 3));

      expect(chats, isEmpty);
      expect(meta.hasMore, isFalse);
      expect(meta.nextPage, isNull);
    });

    test('the two pages do not overlap and together cover the whole seed', () async {
      final (firstChats, _) = await exec(GetChatsConfig.firstPage());
      final (secondChats, _) = await exec(GetChatsConfig.nextPage(page: 2));

      final ids = <String>{...firstChats.map((c) => c.id), ...secondChats.map((c) => c.id)};
      expect(ids, hasLength(seedSize));
    });
  });

  group('name search', () {
    test('an empty search returns the whole seed', () async {
      final (chats, meta) = await exec(GetChatsConfig.firstPage(search: ''));

      expect(meta.hasMore, isTrue);
      expect(chats, hasLength(pageSize));
    });

    test('a whitespace-only search is trimmed and returns the whole seed', () async {
      final (_, meta) = await exec(GetChatsConfig.firstPage(search: '   '));

      expect(meta.hasMore, isTrue);
    });

    test('a no-match search returns an empty slice with a zero total', () async {
      final (chats, meta) = await exec(GetChatsConfig.firstPage(search: 'zzz-no-such-chat'));

      expect(chats, isEmpty);
      expect(meta.hasMore, isFalse);
      expect(meta.nextPage, isNull);
    });

    test('a matching ASCII substring filters by name to only the matches', () async {
      final (chats, meta) = await exec(GetChatsConfig.firstPage(search: 'garden'));

      expect(chats, hasLength(2));
      expect(meta.hasMore, isFalse);
      expect(chats.map((c) => c.name), containsAll(<String>['Garden', 'Gardening 2']));
    });

    test('search is trimmed, lowercased and case-insensitive', () async {
      final (lower, lowerMeta) = await exec(GetChatsConfig.firstPage(search: 'design'));
      final (upper, upperMeta) = await exec(GetChatsConfig.firstPage(search: '  DESIGN  '));

      expect(lowerMeta.hasMore, isFalse);
      expect(upperMeta.hasMore, lowerMeta.hasMore);
      expect(lower.single.name, 'Design crit');
      expect(upper.single.name, lower.single.name);
    });
  });

  group('mock-data shape', () {
    test('ids are chat_0.. in newest-first (lastMessageAt descending) order', () async {
      final (firstChats, _) = await exec(GetChatsConfig.firstPage());
      final (secondChats, _) = await exec(GetChatsConfig.nextPage(page: 2));
      final all = [...firstChats, ...secondChats];

      expect(all.first.id, 'chat_0');
      expect(all.map((c) => c.id), [for (var i = 0; i < seedSize; i++) 'chat_$i']);

      for (var i = 1; i < all.length; i++) {
        expect(all[i - 1].lastMessageAt.isAfter(all[i].lastMessageAt), isTrue);
      }
    });

    test('the wire carries no unread: every generated row maps to 0', () async {
      // Unread is device-local (contract §8.3) — the repository overlays
      // ChatSeedMockData at seed time (asserted in chat_repository_impl_test).
      final (firstChats, _) = await exec(GetChatsConfig.firstPage());
      expect(firstChats.every((c) => c.unreadCount == 0), isTrue);
    });
  });
}

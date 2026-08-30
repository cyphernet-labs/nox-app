import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

void main() {
  group('GetMessagesConfig (cursor request, contract §5)', () {
    test('exposes the fixed batch size', () {
      expect(GetMessagesConfig.pageSize, 20);
    });

    test('tail requests the newest batch: no beforeSeq, default limit', () {
      final config = GetMessagesConfig.tail(chatId: 'c1');

      expect(config.chatId, 'c1');
      expect(config.beforeSeq, isNull);
      expect(config.limit, GetMessagesConfig.pageSize);
    });

    test('tail accepts an explicit limit (the refresh window)', () {
      final config = GetMessagesConfig.tail(chatId: 'c1', limit: 55);

      expect(config.beforeSeq, isNull);
      expect(config.limit, 55);
    });

    test('olderThan carries the exclusive cursor verbatim', () {
      final config = GetMessagesConfig.olderThan(chatId: 'c2', beforeSeq: 1042);

      expect(config.chatId, 'c2');
      expect(config.beforeSeq, 1042);
      expect(config.limit, GetMessagesConfig.pageSize);
    });
  });

  group('the contract limit ceiling (026)', () {
    test('what goes on the wire is clamped, because the server clamps silently', () {
      // Unclamped, a request for 500 comes back as 100 rows while the caller
      // still believes it asked for 500 — and the loaded span quietly shrinks.
      expect(GetMessagesConfig.tail(chatId: 'c', limit: 500).wireLimit, GetMessagesConfig.maxLimit);
      expect(GetMessagesConfig.olderThan(chatId: 'c', beforeSeq: 42, limit: 500).wireLimit, GetMessagesConfig.maxLimit);
    });

    test('a cache-only read keeps the wider window it asked for', () {
      // The ceiling is the SERVER's. A local read is served from rows the cache
      // already holds, and clamping it would leave some of them unreachable.
      expect(GetMessagesConfig.tail(chatId: 'c', limit: 500, cachedOnly: true).limit, 500);
    });

    test('a request at or below the ceiling passes through untouched', () {
      expect(GetMessagesConfig.tail(chatId: 'c', limit: GetMessagesConfig.maxLimit).wireLimit, GetMessagesConfig.maxLimit);
      expect(GetMessagesConfig.tail(chatId: 'c').limit, GetMessagesConfig.pageSize);
      expect(GetMessagesConfig.olderThan(chatId: 'c', beforeSeq: 42, limit: 7).wireLimit, 7);
    });
  });
}

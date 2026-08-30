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
    test('a request above the server ceiling is clamped, not sent as asked', () {
      // The server clamps silently: an unclamped 500 would come back as 100
      // rows while the caller still believed it had asked for 500, and the
      // loaded span would quietly shrink.
      expect(GetMessagesConfig.tail(chatId: 'c', limit: 500).limit, GetMessagesConfig.maxLimit);
      expect(GetMessagesConfig.olderThan(chatId: 'c', beforeSeq: 42, limit: 500).limit, GetMessagesConfig.maxLimit);
    });

    test('a request at or below the ceiling passes through untouched', () {
      expect(GetMessagesConfig.tail(chatId: 'c', limit: GetMessagesConfig.maxLimit).limit, GetMessagesConfig.maxLimit);
      expect(GetMessagesConfig.tail(chatId: 'c').limit, GetMessagesConfig.pageSize);
      expect(GetMessagesConfig.olderThan(chatId: 'c', beforeSeq: 42, limit: 7).limit, 7);
    });
  });
}

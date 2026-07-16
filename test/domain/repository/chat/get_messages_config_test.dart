import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';

void main() {
  group('GetMessagesConfig constants', () {
    test('exposes the fixed pageSize and defaultPage', () {
      expect(GetMessagesConfig.pageSize, 20);
      expect(GetMessagesConfig.defaultPage, 1);
    });
  });

  group('GetMessagesConfig.firstPage', () {
    test('sets page to defaultPage and preserves chatId', () {
      final config = GetMessagesConfig.firstPage(chatId: 'c1');

      expect(config.page, GetMessagesConfig.defaultPage);
      expect(config.page, 1);
      expect(config.chatId, 'c1');
    });
  });

  group('GetMessagesConfig.nextPage', () {
    test('sets page to the requested page and preserves chatId', () {
      final config = GetMessagesConfig.nextPage(chatId: 'c2', page: 3);

      expect(config.page, 3);
      expect(config.chatId, 'c2');
    });

    test('carries the requested page verbatim for arbitrary values', () {
      final config = GetMessagesConfig.nextPage(chatId: 'c3', page: 42);

      expect(config.page, 42);
      expect(config.chatId, 'c3');
    });
  });
}

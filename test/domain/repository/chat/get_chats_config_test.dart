import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

void main() {
  group('GetChatsConfig constants', () {
    test('pageSize is 20 and defaultPage is 1', () {
      expect(GetChatsConfig.pageSize, 20);
      expect(GetChatsConfig.defaultPage, 1);
    });
  });

  group('GetChatsConfig.firstPage', () {
    test('sets page to defaultPage and passes null search through', () {
      final config = GetChatsConfig.firstPage();

      expect(config.page, GetChatsConfig.defaultPage);
      expect(config.page, 1);
      expect(config.search, isNull);
    });

    test('sets page to defaultPage and passes a search value through', () {
      final config = GetChatsConfig.firstPage(search: 'nox');

      expect(config.page, GetChatsConfig.defaultPage);
      expect(config.search, 'nox');
    });
  });

  group('GetChatsConfig.nextPage', () {
    test('sets page to the requested page and passes null search through', () {
      final config = GetChatsConfig.nextPage(page: 3);

      expect(config.page, 3);
      expect(config.search, isNull);
    });

    test('sets page to the requested page and forwards the search value', () {
      final config = GetChatsConfig.nextPage(page: 5, search: 'signal');

      expect(config.page, 5);
      expect(config.search, 'signal');
    });
  });
}

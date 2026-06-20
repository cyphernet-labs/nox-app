import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';

void main() {
  setUpAll(() async {
    await configureDependencies(Environment.test);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  group('ChatRepositoryImpl (mock)', () {
    late ChatRepository repository;

    setUp(() => repository = getIt<ChatRepository>());

    test('first page returns a slice + nextPage metadata', () async {
      final result = await repository.getChats(config: GetChatsConfig.firstPage());

      expect(result.hasData, isTrue);
      final (chats, metadata) = result.data!;
      expect(chats, isNotEmpty);
      expect(chats.length, lessThanOrEqualTo(GetChatsConfig.pageSize));
      expect(metadata.total, greaterThan(0));
      expect(metadata.nextPage, isNotNull); // more than one page of mock data
    });

    test('search filters by chat name', () async {
      final result = await repository.getChats(config: GetChatsConfig.firstPage(search: 'design'));

      final (chats, _) = result.data!;
      expect(chats, isNotEmpty);
      expect(chats.every((c) => c.name.toLowerCase().contains('design')), isTrue);
    });

    test('a non-matching search yields an empty page', () async {
      final result = await repository.getChats(config: GetChatsConfig.firstPage(search: 'zzzznomatch'));

      final (chats, metadata) = result.data!;
      expect(chats, isEmpty);
      expect(metadata.total, 0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ChatRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase(); // fresh local DB per test
    repository = getIt<ChatRepository>();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('ChatRepositoryImpl (cache-first Sembast)', () {
    test('first getChats seeds the mock set into the DB and returns a page + nextPage', () async {
      final (chats, metadata) = (await repository.getChats(config: GetChatsConfig.firstPage())).data!;

      expect(chats.length, lessThanOrEqualTo(GetChatsConfig.pageSize));
      expect(metadata.total, greaterThan(GetChatsConfig.pageSize)); // full mock set seeded
      expect(metadata.nextPage, isNotNull);
    });

    test('search filters the persisted chats by name', () async {
      final (matches, _) = (await repository.getChats(config: GetChatsConfig.firstPage(search: 'design'))).data!;
      expect(matches, isNotEmpty);
      expect(matches.every((c) => c.name.toLowerCase().contains('design')), isTrue);

      final (none, meta) = (await repository.getChats(config: GetChatsConfig.firstPage(search: 'zzzznomatch'))).data!;
      expect(none, isEmpty);
      expect(meta.total, 0);
    });

    test('createChat persists a chat that appears at the top on re-query', () async {
      await repository.getChats(config: GetChatsConfig.firstPage()); // seed
      final created = await repository.createChat(name: 'Fresh chat');
      expect(created.hasData, isTrue);

      final (chats, _) = (await repository.getChats(config: GetChatsConfig.firstPage())).data!;
      expect(chats.first.name, 'Fresh chat'); // created "now" → newest-first
    });

    test('re-querying reads from the DB without re-seeding', () async {
      final first = (await repository.getChats(config: GetChatsConfig.firstPage())).data!.$2.total;
      final second = (await repository.getChats(config: GetChatsConfig.firstPage())).data!.$2.total;
      expect(second, first);
    });
  });
}

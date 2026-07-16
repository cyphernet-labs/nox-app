import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MessageRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    repo = getIt<MessageRepository>();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('first getMessages seeds the chat history into the DB', () async {
    final (messages, meta) = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!;
    expect(messages, isNotEmpty);
    expect(meta.total, greaterThan(0));
  });

  test('sendMessage persists a message that shows up on re-query', () async {
    await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0')); // seed
    final before = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!.$2.total;

    final sent = await repo.sendMessage(chatId: 'chat_0', text: 'Hello from test');
    expect(sent.hasData, isTrue);

    final (messages, meta) = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!;
    expect(meta.total, before + 1);
    expect(messages.any((m) => m.text == 'Hello from test'), isTrue); // in the newest batch
  });

  test('re-querying reads from the DB without re-seeding', () async {
    final first = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!.$2.total;
    final second = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!.$2.total;
    expect(second, first);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeds a chat's history (first getMessages) then grows it past a single page by
/// sending messages until the thread reaches [target] total, returning the final
/// total. The deterministic mock seeds a chat with fewer than `pageSize` messages,
/// so the newest-batch-first window only spans two pages once the thread is grown.
/// The final message sent carries text `grow #${target - 1}` (the newest overall).
Future<int> _seedThenGrowTo(MessageRepository repo, {required String chatId, required int target}) async {
  final seeded = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: chatId))).data!.$2.total;
  for (var i = seeded; i < target; i++) {
    await repo.sendMessage(chatId: chatId, text: 'grow #$i');
  }
  return (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: chatId))).data!.$2.total;
}

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

  group('reverse-windowing pagination (newest batch first)', () {
    const chatId = 'chat_0';
    // Grow just past one page so page 1 is a full newest batch and page 2 is a small
    // older remainder. The deterministic seed is < pageSize, so growth is required.
    const growTo = GetMessagesConfig.pageSize + 2;
    const lastSentText = 'grow #${growTo - 1}'; // the newest message overall

    test('page 2 returns the older batch, disjoint from and strictly older than page 1', () async {
      final total = await _seedThenGrowTo(repo, chatId: chatId, target: growTo);
      expect(total, growTo);
      expect(total, greaterThan(GetMessagesConfig.pageSize)); // the window genuinely spans two pages

      final page1 = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: chatId))).data!;
      final page2 = (await repo.getMessages(config: GetMessagesConfig.nextPage(chatId: chatId, page: 2))).data!;

      // Page 1 is a full newest batch that points forward to page 2.
      expect(page1.$1.length, GetMessagesConfig.pageSize);
      expect(page1.$2.total, total);
      expect(page1.$2.nextPage, 2);
      // The newest message overall sits in page 1, never in the older page 2.
      expect(page1.$1.any((m) => m.text == lastSentText), isTrue);

      // Page 2 is the older remainder — non-empty and the last page (two windows only).
      expect(page2.$1, isNotEmpty);
      expect(page2.$2.total, total);
      expect(page2.$2.nextPage, isNull);

      // Disjoint by message id, and together they cover the whole history exactly once.
      final page1Ids = page1.$1.map((m) => m.id).toSet();
      final page2Ids = page2.$1.map((m) => m.id).toSet();
      expect(page1Ids.intersection(page2Ids), isEmpty);
      expect(page1Ids.union(page2Ids).length, total);

      // Reverse windowing: every page-2 message is at least as old as every page-1 message.
      final newestOfPage2 = page2.$1.map((m) => m.sentAt).reduce((a, b) => a.isAfter(b) ? a : b);
      final oldestOfPage1 = page1.$1.map((m) => m.sentAt).reduce((a, b) => a.isBefore(b) ? a : b);
      expect(newestOfPage2.isAfter(oldestOfPage1), isFalse);
    });

    test('a page past the end hits the end<=0 guard: empty slice, total reported, nextPage null', () async {
      // No growth needed — the raw seed fits one page, so any high page is past the end.
      final total = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: chatId))).data!.$2.total;
      expect(total, greaterThan(0));

      final beyond = (await repo.getMessages(config: GetMessagesConfig.nextPage(chatId: chatId, page: 50))).data!;
      expect(beyond.$1, isEmpty); // guarded empty slice
      expect(beyond.$2.total, total); // total is still reported on the empty page
      expect(beyond.$2.nextPage, isNull); // and there is nothing further back
    });
  });
}

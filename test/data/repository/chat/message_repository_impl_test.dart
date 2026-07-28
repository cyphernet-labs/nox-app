import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/message_mapper.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/message_remote_data_source.dart';
import 'package:nox_app/data/repository/chat/message_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_repository_impl_test.mocks.dart';

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

@GenerateMocks([MessageRemoteDataSource])
void main() {
  late MessageRepository repo;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
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

  test('sendMessage preserves the attachment localPath through the wire echo (P6/F4)', () async {
    await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0')); // seed
    const att = MessageAttachment(id: 'a', type: FileType.image, name: 'shot.png', sizeBytes: 3, localPath: '/tmp/shot.png');

    final sent = (await repo.sendMessage(chatId: 'chat_0', attachment: att)).data!;
    // The device-local path is re-attached after the (path-less) wire echo, so a sent
    // image still previews/saves. It also survives to the DB (re-read below).
    expect(sent.attachment?.localPath, '/tmp/shot.png');

    final persisted = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!.$1;
    expect(persisted.firstWhere((m) => m.attachment?.id == 'a').attachment?.localPath, '/tmp/shot.png');
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

  group('sendMessage updates the parent chat row (US2)', () {
    late ChatRepository chats;
    late ChatDao chatDao;

    setUp(() async {
      chats = getIt<ChatRepository>();
      chatDao = getIt<ChatDao>();
      await chats.getChats(config: GetChatsConfig.firstPage()); // seed the chat rows into ChatDao
    });

    test('a text send sets the chat preview + time and reorders it newest-first', () async {
      final before = await chatDao.getById('chat_5');
      expect(before, isNotNull);
      expect((await chatDao.getAllSorted()).first.id, isNot('chat_5')); // not the top row before

      await repo.sendMessage(chatId: 'chat_5', text: 'Hello world');

      final after = await chatDao.getById('chat_5');
      expect(after!.lastMessagePreview, 'Hello world');
      expect(DateTime.parse(after.lastMessageAt).isAfter(DateTime.parse(before!.lastMessageAt)), isTrue);
      expect((await chatDao.getAllSorted()).first.id, 'chat_5'); // reordered to newest-first
    });

    test('an attachment-only send previews as "You: <filename>"', () async {
      const att = MessageAttachment(id: 'a1', type: FileType.pdf, name: 'spec.pdf', sizeBytes: 10);
      await repo.sendMessage(chatId: 'chat_0', attachment: att);
      expect((await chatDao.getById('chat_0'))!.lastMessagePreview, 'You: spec.pdf');
    });

    test('an own send does not change the chat unread count', () async {
      final before = (await chatDao.getById('chat_0'))!.unreadCount;
      await repo.sendMessage(chatId: 'chat_0', text: 'x');
      expect((await chatDao.getById('chat_0'))!.unreadCount, before);
    });

    test('a failed send leaves the parent chat row untouched (FR-004)', () async {
      final before = await chatDao.getById('chat_0');
      final failingRemote = MockMessageRemoteDataSource();
      when(
        failingRemote.sendMessage(
          chatId: anyNamed('chatId'),
          authorId: anyNamed('authorId'),
          authorLabel: anyNamed('authorLabel'),
          text: anyNamed('text'),
          attachment: anyNamed('attachment'),
        ),
      ).thenThrow(Exception('network down'));
      final failingRepo = MessageRepositoryImpl(
        getIt<MessageDao>(),
        failingRemote,
        getIt<MessageMapper>(),
        getIt<MessageWireMapper>(),
        getIt<ChatDao>(),
        getIt<SessionRepository>(),
      );

      final result = await failingRepo.sendMessage(chatId: 'chat_0', text: 'should not persist');

      expect(result.hasData, isFalse);
      final after = await chatDao.getById('chat_0');
      expect(after!.lastMessagePreview, before!.lastMessagePreview); // unchanged
      expect(after.lastMessageAt, before.lastMessageAt);
    });
  });

  group('simulateIncoming (US4, debug)', () {
    late ChatDao chatDao;

    setUp(() async {
      chatDao = getIt<ChatDao>();
      await getIt<ChatRepository>().getChats(config: GetChatsConfig.firstPage()); // seed chat rows
      await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0')); // seed the thread
    });

    test('appends an inbound message (author != me) and increments the chat unread', () async {
      final beforeUnread = (await chatDao.getById('chat_0'))!.unreadCount;
      final beforeTotal = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!.$2.total;

      await repo.simulateIncoming(chatId: 'chat_0');

      expect((await chatDao.getById('chat_0'))!.unreadCount, beforeUnread + 1);
      final (messages, meta) = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!;
      expect(meta.total, beforeTotal + 1);
      final inbound = messages.firstWhere((m) => m.text == 'Simulated incoming message');
      expect(inbound.authorId, isNot('me')); // an inbound, not an own message
    });
  });

  test('a failed envelope (success:false / null data) surfaces as RepositoryResult.error (S4)', () async {
    // A session must be present for _seedChatIfEmpty to reach the remote.
    await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-err', onboardingComplete: true, label: 'Err');
    final errorRemote = MockMessageRemoteDataSource();
    when(
      errorRemote.getMessages(config: anyNamed('config')),
    ).thenAnswer((_) async => const ResponseEntity<MessagesWireEntity>(success: false));
    final errorRepo = MessageRepositoryImpl(
      getIt<MessageDao>(),
      errorRemote,
      getIt<MessageMapper>(),
      getIt<MessageWireMapper>(),
      getIt<ChatDao>(),
      getIt<SessionRepository>(),
    );

    final result = await errorRepo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'));
    expect(result.hasData, isFalse); // null-data envelope → _seedChatIfEmpty throws → error
  });

  group('signed-in identity (feature 015)', () {
    Future<void> signInAs(String identifier, String label) async {
      await getIt<SessionRepository>().saveIdentifier(identifier: identifier, onboardingComplete: true, label: label);
    }

    test('seeded own rows are reconciled to the session identifier (not the sentinel)', () async {
      await signInAs('sess-abc', 'Alice');

      final (messages, _) = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!;

      // The mock seeds own rows with the "me" sentinel; with a session they are rewritten
      // to the session identifier so own-detection follows the session.
      expect(messages.any((m) => m.authorId == 'sess-abc'), isTrue); // own rows carry the session id
      expect(messages.any((m) => m.authorId == 'me'), isFalse); // no un-reconciled sentinel left
      // The reconciled own rows keep their sent status (own history).
      expect(messages.where((m) => m.authorId == 'sess-abc').every((m) => m.status.name == 'sent'), isTrue);
    });

    test('sendMessage authors the persisted message with the session identity', () async {
      await signInAs('sess-abc', 'Alice');
      await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0')); // seed

      final sent = (await repo.sendMessage(chatId: 'chat_0', text: 'Mine')).data!;
      expect(sent.authorId, 'sess-abc');
      expect(sent.authorLabel, 'Alice');

      final (messages, _) = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!;
      final persisted = messages.firstWhere((m) => m.text == 'Mine');
      expect(persisted.authorId, 'sess-abc'); // persisted with the session identity
    });

    test('without a session, own rows fall back to the sentinel id', () async {
      // No saveIdentifier — readSession resolves to null → fallback own-id.
      final (messages, _) = (await repo.getMessages(config: GetMessagesConfig.firstPage(chatId: 'chat_0'))).data!;
      expect(messages.any((m) => m.authorId == 'me'), isTrue); // sentinel own rows remain recognisable
    });
  });

  group('chatFiles (E3)', () {
    test('derives the chat attachments newest-first; a newly sent file leads', () async {
      // The seeded thread carries one attachment (design-spec.pdf).
      final seeded = await repo.chatFiles(chatId: 'chat_0');
      expect(seeded, hasLength(1));
      expect(seeded.first.name, 'design-spec.pdf');

      // Sending a new attachment makes it the newest (first).
      const att = MessageAttachment(id: 'a-new', type: FileType.image, name: 'shot.png', sizeBytes: 100);
      await repo.sendMessage(chatId: 'chat_0', attachment: att);

      final after = await repo.chatFiles(chatId: 'chat_0');
      expect(after, hasLength(2));
      expect(after.first.name, 'shot.png'); // newest-first
      expect(after.last.name, 'design-spec.pdf');
    });

    test('a chat whose messages have no attachments yields an empty list, isolated per chat', () async {
      // A created chat (D5) seeds only a system line — no attachment.
      final created = (await getIt<ChatRepository>().createChat(name: 'No files chat')).data!;
      expect(await repo.chatFiles(chatId: created.id), isEmpty);
      expect(await repo.chatFiles(chatId: 'chat_0'), isNotEmpty); // the other chat is unaffected
    });
  });
}

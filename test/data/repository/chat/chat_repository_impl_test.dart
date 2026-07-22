import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/get_chats_config.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/general/constants.dart';
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

  group('ChatRepositoryImpl pagination', () {
    test('page 2 returns a slice disjoint from page 1 and nextPage becomes null on the final page', () async {
      final (page1, meta1) = (await repository.getChats(config: GetChatsConfig.firstPage())).data!;
      expect(page1, hasLength(GetChatsConfig.pageSize)); // a full first page
      expect(meta1.nextPage, 2);

      final (page2, meta2) = (await repository.getChats(config: GetChatsConfig.nextPage(page: 2))).data!;
      expect(page2, isNotEmpty);
      expect(meta2.total, meta1.total); // total is stable across pages
      expect(meta2.nextPage, isNull); // the mock set fits in two pages → page 2 is last

      final page1Ids = page1.map((c) => c.id).toSet();
      final page2Ids = page2.map((c) => c.id).toSet();
      expect(page1Ids.intersection(page2Ids), isEmpty); // the two slices do not overlap
      expect(page1.length + page2.length, meta1.total); // the two pages cover the whole set
    });

    test('walking pages to the end yields every chat exactly once and terminates at nextPage null', () async {
      final seenIds = <String>[];
      var config = GetChatsConfig.firstPage();
      int? total;

      while (true) {
        final (chats, meta) = (await repository.getChats(config: config)).data!;
        seenIds.addAll(chats.map((c) => c.id));
        total = meta.total;
        final next = meta.nextPage;
        if (next == null) break; // reached the final page
        config = GetChatsConfig.nextPage(page: next);
      }

      expect(total, greaterThan(GetChatsConfig.pageSize)); // more than one page was walked
      expect(seenIds, hasLength(total)); // no missing/duplicate rows across pages
      expect(seenIds.toSet(), hasLength(seenIds.length)); // every id is unique (disjoint slices)
    });
  });

  group('ChatRepositoryImpl watchChats', () {
    test('seeds then emits the persisted list and re-emits after a createChat', () async {
      final emissions = <List<ChatModel>>[];
      final firstEmission = Completer<void>();
      final secondEmission = Completer<void>();

      final subscription = repository.watchChats().listen((chats) {
        emissions.add(chats);
        if (emissions.length == 1 && !firstEmission.isCompleted) firstEmission.complete();
        if (emissions.length == 2 && !secondEmission.isCompleted) secondEmission.complete();
      });
      addTearDown(subscription.cancel);

      await firstEmission.future; // the one-time seed lands, then the persisted list is emitted
      final seededCount = emissions.first.length;
      expect(seededCount, greaterThan(GetChatsConfig.pageSize)); // full mock set seeded into the DB

      await repository.createChat(name: 'Watched chat');
      await secondEmission.future; // the store change re-emits on the same stream

      final latest = emissions.last;
      expect(latest, hasLength(seededCount + 1));
      expect(latest.any((c) => c.name == 'Watched chat'), isTrue);
    });
  });

  group('created chat genesis system line (D5)', () {
    test('a created chat opens with only the "Chat created by {label}" system line, not the generic mock history', () async {
      await repository.getChats(config: GetChatsConfig.firstPage()); // seed the mock chat set
      final created = (await repository.createChat(name: 'Fresh D5 chat')).data!;

      final (messages, _) = (await getIt<MessageRepository>().getMessages(config: GetMessagesConfig.firstPage(chatId: created.id))).data!;

      // Only the genesis line — the generic Aria/Mox/Kit mock history is NOT seeded (countByChat>0 skips it).
      expect(messages, hasLength(1));
      final systemLine = messages.single;
      expect(systemLine.isSystem, isTrue);
      expect(systemLine.id, '${created.id}_sys');
      expect(systemLine.authorLabel, Constants.defaultUserLabel); // no session in the test → the label fallback
      expect(messages.any((m) => m.authorLabel == 'Aria'), isFalse); // generic mock history absent
    });

    test('seedCreatedChat is idempotent — a second call adds no duplicate line', () async {
      final created = (await repository.createChat(name: 'Idempotent D5 chat')).data!;
      await getIt<MessageRepository>().seedCreatedChat(chatId: created.id); // second call

      final (messages, _) = (await getIt<MessageRepository>().getMessages(config: GetMessagesConfig.firstPage(chatId: created.id))).data!;
      expect(messages, hasLength(1)); // still just the one genesis line
    });

    test('the genesis line is authored by the signed-in session label when a session exists', () async {
      await getIt<SessionRepository>().saveIdentifier(identifier: 'sess-nova', onboardingComplete: true, label: 'Nova');
      addTearDown(() => getIt<SessionRepository>().clear()); // don't leak the session into sibling tests

      final created = (await repository.createChat(name: 'Nova chat')).data!;

      final (messages, _) = (await getIt<MessageRepository>().getMessages(config: GetMessagesConfig.firstPage(chatId: created.id))).data!;
      // Renders "Chat created by Nova" — the real session label, NOT the fallback constant.
      expect(messages.single.authorLabel, 'Nova');
      expect(messages.single.authorLabel, isNot(Constants.defaultUserLabel));
    });
  });

  group('isChatNameTaken (D4)', () {
    test('a seeded chat name is taken; a novel name is free', () async {
      await repository.getChats(config: GetChatsConfig.firstPage()); // seed the mock chat set into the DB
      expect((await repository.isChatNameTaken(name: 'Random thoughts')).data, isTrue); // a seeded mock chat
      expect((await repository.isChatNameTaken(name: 'Totally novel name 12345')).data, isFalse);
    });

    test('a name becomes taken once a chat with it is created (accumulating DB, not a frozen set)', () async {
      const name = 'D4 accumulating chat';
      expect((await repository.isChatNameTaken(name: name)).data, isFalse); // not yet
      await repository.createChat(name: name);
      expect((await repository.isChatNameTaken(name: name)).data, isTrue); // now taken, straight from the DB
    });

    test('the uniqueness check is case-sensitive', () async {
      await repository.createChat(name: 'CaseChat');
      expect((await repository.isChatNameTaken(name: 'CaseChat')).data, isTrue);
      expect((await repository.isChatNameTaken(name: 'casechat')).data, isFalse);
    });
  });

  group('markChatRead (US4)', () {
    test('resets a chat unread count to 0 and is a no-op when already 0', () async {
      await repository.getChats(config: GetChatsConfig.firstPage()); // seed the chat rows
      final chatDao = getIt<ChatDao>();
      final unread = (await chatDao.getAllSorted()).firstWhere((c) => c.unreadCount > 0);

      await repository.markChatRead(chatId: unread.id);
      expect((await chatDao.getById(unread.id))!.unreadCount, 0);

      // Idempotent: a second call on an already-read chat leaves it at 0 (no throw).
      await repository.markChatRead(chatId: unread.id);
      expect((await chatDao.getById(unread.id))!.unreadCount, 0);
    });
  });
}

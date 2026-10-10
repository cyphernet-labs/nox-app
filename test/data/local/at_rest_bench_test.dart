@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/chat_entity.dart';
import 'package:nox_app/data/entity/chat/message_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/local/vault_codec.dart';
import 'package:nox_tor/vault.dart';
import 'package:sembast/sembast_io.dart';

/// SC-003 (phase 048): the chats list and a thread open no slower than 20%
/// over what they took before the database was sealed - measured on 10 000
/// messages, the same database plain and sealed line by line.
///
/// It measures what opening a screen costs: the list reads every chat and
/// recounts every badge over the whole message store, the thread reads its
/// chat's messages - and the cold start that opens the database first, which
/// is where sealing costs, since sembast opens every line once and keeps the
/// records in memory after. Tagged `live`: it measures rather than checks
/// behaviour, and a loaded machine would make it flaky in the gate.
///
/// Run: `fvm flutter test --tags live test/data/local/at_rest_bench_test.dart`
void main() {
  const chats = 50;
  const messages = 10000;
  const runs = 7;

  late Directory dir;

  setUpAll(() async {
    NoxVault.setKey(Uint8List.fromList(List<int>.generate(32, (i) => 0x31 + i)));
    dir = await Directory.systemTemp.createTemp('nox_bench');
  });

  tearDownAll(() async {
    NoxVault.clear();
    await dir.delete(recursive: true);
  });

  Future<void> fill(_FixedDatabase database) async {
    final chatDao = ChatDao(database);
    final messageDao = MessageDao(database);
    final at = DateTime.utc(2026, 10, 1);
    await chatDao.saveData([
      for (var c = 0; c < chats; c++)
        ChatEntity(
          id: 'c_$c',
          name: 'Chat number $c',
          lastMessagePreview: 'The last thing said in chat $c, as long as a preview gets',
          lastMessageAt: at.add(Duration(minutes: c)).toIso8601String(),
          unreadCount: 0,
          lastOpenedSeq: 10,
        ),
    ]);
    await messageDao.saveData([
      for (var m = 0; m < messages; m++)
        MessageEntity(
          id: 'm_$m',
          chatId: 'c_${m % chats}',
          authorId: m.isEven ? 'u_me' : 'u_other',
          authorLabel: m.isEven ? 'Alice' : 'Bob',
          text: 'Message $m: a line of an ordinary conversation, about as long as most of them are in a chat.',
          sentAt: at.add(Duration(seconds: m)).toIso8601String(),
          status: 'sent',
          isSystem: false,
          attachmentId: null,
          attachmentType: null,
          attachmentName: null,
          attachmentSizeBytes: null,
          seq: m ~/ chats + 1,
        ),
    ]);
    await database.close();
  }

  int median(List<int> values) => (List<int>.of(values)..sort())[values.length ~/ 2];

  /// One measurement of each: the cold start - the database opened, every line
  /// of it read - then the list and a thread, each the median of [repeats]
  /// openings: a single one is a few milliseconds, and the machine's jitter is
  /// as large.
  Future<({int open, int list, int thread})> measure(_FixedDatabase database) async {
    const repeats = 25;
    final chatDao = ChatDao(database);
    final messageDao = MessageDao(database);
    Future<void> openList() async {
      final all = await chatDao.getAllSorted();
      await messageDao.countUnreadByChat(marks: {for (final chat in all) chat.id: chat.lastOpenedSeq ?? 0}, excludeAuthors: const {'u_me'});
    }

    final watch = Stopwatch()..start();
    await database.db;
    final open = watch.elapsedMicroseconds;

    final lists = <int>[];
    final threads = <int>[];
    for (var i = 0; i < repeats; i++) {
      watch.reset();
      await openList();
      lists.add(watch.elapsedMicroseconds);
      watch.reset();
      final thread = await messageDao.getByChatSorted('c_${i % chats}');
      threads.add(watch.elapsedMicroseconds);
      expect(thread, hasLength(messages ~/ chats));
    }

    await database.close();
    return (open: open, list: median(lists), thread: median(threads));
  }

  test('the chats list and a thread with 10 000 messages, plain and sealed (SC-003)', () async {
    final plain = _FixedDatabase('${dir.path}/plain.db');
    final sealed = _FixedDatabase('${dir.path}/sealed.db', codec: VaultCodec.sembast);
    await fill(plain);
    await fill(sealed);

    final results = {'plain': <({int open, int list, int thread})>[], 'sealed': <({int open, int list, int thread})>[]};
    // Alternated, so whatever the machine does meanwhile falls on both.
    for (var run = 0; run < runs; run++) {
      results['plain']!.add(await measure(plain));
      results['sealed']!.add(await measure(sealed));
    }

    final report = <String, ({int open, int list, int thread})>{
      for (final MapEntry(:key, :value) in results.entries)
        key: (
          open: median([for (final r in value) r.open]),
          list: median([for (final r in value) r.list]),
          thread: median([for (final r in value) r.thread]),
        ),
    };
    String ms(int micros) => (micros / 1000).toStringAsFixed(2);
    String ratio(int a, int b) => '${b >= a ? '+' : ''}${((b / a - 1) * 100).toStringAsFixed(0)}%';
    final p = report['plain']!;
    final s = report['sealed']!;
    stdout.writeln('MEASURE: $messages messages in $chats chats, median of $runs runs');
    stdout.writeln('MEASURE: database file: plain ${File(plain.path).lengthSync()} B, sealed ${File(sealed.path).lengthSync()} B');
    stdout.writeln('MEASURE: database open (start): plain ${ms(p.open)} ms, sealed ${ms(s.open)} ms (${ratio(p.open, s.open)})');
    stdout.writeln('MEASURE: chats list open:       plain ${ms(p.list)} ms, sealed ${ms(s.list)} ms (${ratio(p.list, s.list)})');
    stdout.writeln('MEASURE: thread open:           plain ${ms(p.thread)} ms, sealed ${ms(s.thread)} ms (${ratio(p.thread, s.thread)})');
  });
}

/// One database file, opened as the app opens it - with the codec, or without.
class _FixedDatabase implements AppDatabase {
  _FixedDatabase(this.path, {this.codec});

  final String path;
  final SembastCodec? codec;
  Database? _database;

  @override
  Future<Database> get db async => _database ??= await databaseFactoryIo.openDatabase(path, codec: codec);

  @override
  Future<void> close() async {
    final open = _database;
    _database = null;
    await open?.close();
  }

  @override
  Future<void> clearEntireDatabase() async {
    await close();
    await databaseFactoryIo.deleteDatabase(path);
  }
}

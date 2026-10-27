import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/identity_mock_data.dart';

/// Locks the deterministic MOCK thread synthesis of [GetMessagesApi] — no DI,
/// no mocks. `AppClock` is frozen so the `now - ago` seed timestamps are
/// stable. The wire seed is `12 messages + 1 attachment` = 13 items (the
/// genesis line is NOT on the wire — contract §4; the repository synthesizes
/// it locally), each carrying a deterministic seq `chatBase + position`
/// (positions 1..13; position 0 is reserved for the genesis). `execute`
/// serves contract §5 cursor batches: the tail when `beforeSeq` is absent,
/// strictly-older batches otherwise, `has_more` for the remainder.
void main() {
  final now = DateTime(2026, 6, 15, 21, 30);

  final mapper = MessageWireMapper();
  late GetMessagesApi api;

  Future<(List<MessageModel>, bool)> exec(GetMessagesConfig config) async {
    final response = await api.execute(config: config);
    final data = response.data!;
    return (mapper.toListModel(entities: data.messages), data.hasMore);
  }

  setUp(() {
    AppClock.freeze(now);
    api = GetMessagesApi(mapper);
  });

  tearDown(AppClock.reset);

  // Wire total = 12 seed messages + 1 attachment message (no genesis line).
  const total = 13;

  test('the tail returns the whole sub-page-size history in one batch', () async {
    final (messages, hasMore) = await exec(GetMessagesConfig.tail(chatId: 'chat_1'));

    expect(messages, hasLength(total));
    expect(hasMore, isFalse);
  });

  test('every message carries a deterministic seq: chatBase + ascending position from 1', () async {
    final (messages, _) = await exec(GetMessagesConfig.tail(chatId: 'chat_1'));
    final base = GetMessagesApi.chatSeqBase('chat_1');

    expect(messages.first.seq, base + 1);
    expect(messages.last.seq, base + total);
    for (var i = 1; i < messages.length; i++) {
      expect(messages[i].seq, greaterThan(messages[i - 1].seq)); // ascending in batch
    }
    // Chronological order and seq order agree (goldens freeze the visual order).
    final byTime = [...messages]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    expect(messages.map((m) => m.id).toList(), byTime.map((m) => m.id).toList());
  });

  test('seeded chat_N ids get the (N+1)*1000 base; arbitrary ids get a stable base', () {
    expect(GetMessagesApi.chatSeqBase('chat_0'), 1000);
    expect(GetMessagesApi.chatSeqBase('chat_27'), 28000);
    expect(GetMessagesApi.chatSeqBase('chat_1'), GetMessagesApi.chatSeqBase('chat_1')); // stable
    expect(GetMessagesApi.chatSeqBase('chat_1'), isNot(GetMessagesApi.chatSeqBase('chat_2')));
  });

  test('a beforeSeq cursor returns the strictly-older batch with has_more for the rest', () async {
    final base = GetMessagesApi.chatSeqBase('chat_1');
    final (older, hasMore) = await exec(GetMessagesConfig.olderThan(chatId: 'chat_1', beforeSeq: base + 6, limit: 3));

    expect(older.map((m) => m.seq).toList(), [base + 3, base + 4, base + 5]); // ascending, exclusive bound
    expect(hasMore, isTrue); // seqs base+1..base+2 remain older
  });

  test('a cursor at the oldest message returns an empty batch with no more history', () async {
    final base = GetMessagesApi.chatSeqBase('chat_1');
    final (older, hasMore) = await exec(GetMessagesConfig.olderThan(chatId: 'chat_1', beforeSeq: base + 1));

    expect(older, isEmpty);
    expect(hasMore, isFalse);
  });

  test('walking the cursor to the end covers the history exactly once', () async {
    final seen = <int>[];
    GetMessagesConfig config = GetMessagesConfig.tail(chatId: 'chat_1', limit: 4);
    while (true) {
      final (batch, hasMore) = await exec(config);
      seen.insertAll(0, batch.map((m) => m.seq));
      if (!hasMore || batch.isEmpty) break;
      config = GetMessagesConfig.olderThan(chatId: 'chat_1', beforeSeq: batch.first.seq, limit: 4);
    }
    expect(seen.toSet(), hasLength(total)); // no duplicates
    expect(seen, hasLength(total)); // no gaps
  });

  test('the seed mixes own and other authors and carries the attachment message', () async {
    final (messages, _) = await exec(GetMessagesConfig.tail(chatId: 'chat_1'));

    expect(messages.any((m) => m.authorId == IdentityMockData.fallbackOwnId), isTrue);
    expect(messages.any((m) => m.authorId != IdentityMockData.fallbackOwnId), isTrue);
    final withFile = messages.singleWhere((m) => m.attachment != null);
    expect(withFile.id, 'chat_1_file');
    expect(withFile.attachment!.type, FileType.pdf);
    expect(withFile.attachment!.name, 'design-spec.pdf');
    expect(withFile.attachment!.mime, 'application/pdf');
    expect(withFile.attachment!.expiresAt, isNotNull); // stage-1 far-future retention
  });

  test('no system line rides the wire - the genesis is client-synthesized (contract §4)', () async {
    final (messages, _) = await exec(GetMessagesConfig.tail(chatId: 'chat_1'));
    expect(messages.any((m) => m.isSystem), isFalse);
    expect(messages.any((m) => m.id == 'c1_sys'), isFalse);
  });
}

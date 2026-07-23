import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/data/remote/api/chat/get_messages_api.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/identity_mock_data.dart';

/// Locks the deterministic MOCK chat-thread synthesis of [GetMessagesApi] — no DI,
/// no mocks. `AppClock` is frozen so the `now - ago` seed timestamps are stable, and
/// the API is constructed directly. The seed is `1 system + 12 messages + 1 attachment`
/// = 14 items, which is BELOW [GetMessagesConfig.pageSize] (20): so only two branches
/// of `execute()` are reachable — page 1 returns the full batch (`nextPage == null`)
/// and page 2 hits the `end <= 0` guard returning an empty list. The intermediate
/// multi-page / `hasMore` branch cannot be reached via `execute()` and is not asserted.
///
/// The generator now returns the `ResponseEntity<MessagesWireEntity>` envelope (feature
/// 018/S4); the `exec` helper unwraps it + maps wire->model so the seed assertions read
/// off the domain model as before (the envelope's page/pageSize/total derive the same
/// PageMetadata the repository computes, page*pageSize < total).
void main() {
  // Fixed reference "now" — the seed timestamps resolve as `now - ago`, so freezing
  // keeps the synthesized thread identical run-to-run.
  final now = DateTime(2026, 6, 15, 21, 30);

  final mapper = MessageWireMapper();
  late GetMessagesApi api;

  Future<(List<MessageModel>, PageMetadata)> exec(GetMessagesConfig config) async {
    final response = await api.execute(config: config);
    final data = response.data!;
    final messages = mapper.toListModel(entities: data.items);
    final hasMore = (data.page * data.pageSize) < data.total;
    return (messages, PageMetadata(total: data.total, nextPage: hasMore ? data.page + 1 : null));
  }

  setUp(() {
    AppClock.freeze(now);
    api = GetMessagesApi(mapper);
  });

  tearDown(AppClock.reset);

  // Total = 1 system line + 12 seed messages + 1 attachment message.
  const total = 14;

  test('the generator returns a success envelope carrying the wire page', () async {
    final response = await api.execute(config: const GetMessagesConfig(chatId: 'c1', page: 1));
    expect(response.success, isTrue);
    expect(response.data, isNotNull);
    expect(response.data!.items, hasLength(total)); // wire items
    expect(response.data!.total, total);
  });

  test('page 1 synthesizes a chronological thread led by the system line', () async {
    final (messages, meta) = await exec(const GetMessagesConfig(chatId: 'c1', page: 1));

    expect(messages.length, total);
    expect(meta.total, total);

    // The opening system line sorts oldest → first, and carries the `<chatId>_sys` id.
    expect(messages.first.isSystem, isTrue);
    expect(messages.first.id, 'c1_sys');

    // The list is sorted ascending by sentAt.
    final sorted = [...messages]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    expect(messages.map((m) => m.id).toList(), sorted.map((m) => m.id).toList());
  });

  test('own messages are marked sent while every other author stays none', () async {
    final (messages, _) = await exec(const GetMessagesConfig(chatId: 'c1', page: 1));

    final own = messages.where((m) => m.authorId == IdentityMockData.fallbackOwnId).toList();
    expect(own, isNotEmpty);
    expect(own.every((m) => m.status == MessageStatus.sent), isTrue);
    expect(messages.where((m) => m.authorId != IdentityMockData.fallbackOwnId).every((m) => m.status == MessageStatus.none), isTrue);
  });

  test('exactly one message carries the pdf attachment', () async {
    final (messages, _) = await exec(const GetMessagesConfig(chatId: 'c1', page: 1));

    final withAttachment = messages.where((m) => m.attachment != null).toList();
    expect(withAttachment, hasLength(1));

    final file = withAttachment.single;
    expect(file.id, 'c1_file');
    expect(file.attachment!.type, FileType.pdf);
    expect(file.attachment!.name, 'design-spec.pdf');
  });

  test('every id is namespaced by its chatId', () async {
    final (messages, _) = await exec(const GetMessagesConfig(chatId: 'c1', page: 1));

    expect(messages.every((m) => m.id.startsWith('c1_')), isTrue);
  });

  test('two chats produce ids distinguished only by their chatId prefix', () async {
    final (first, _) = await exec(const GetMessagesConfig(chatId: 'alpha', page: 1));
    final (second, _) = await exec(const GetMessagesConfig(chatId: 'beta', page: 1));

    expect(first.every((m) => m.id.startsWith('alpha_')), isTrue);
    expect(second.every((m) => m.id.startsWith('beta_')), isTrue);

    // Same suffixes, different prefixes — the thread shape is chat-independent.
    String suffix(String id, String chatId) => id.substring('${chatId}_'.length);
    expect(first.map((m) => suffix(m.id, 'alpha')).toList(), second.map((m) => suffix(m.id, 'beta')).toList());
  });

  test('page 1 returns the whole batch as the last page', () async {
    // batch (14) < pageSize (20) → the full history is served in one page, nextPage null.
    final (messages, meta) = await exec(const GetMessagesConfig(chatId: 'c1', page: 1));

    expect(messages, hasLength(total));
    expect(meta.total, total);
    expect(meta.nextPage, isNull);
  });

  test('page 2 hits the end guard and returns an empty list with total preserved', () async {
    // end = total - (2 - 1) * pageSize = 14 - 20 <= 0 → empty slice, total kept, nextPage null.
    final (messages, meta) = await exec(const GetMessagesConfig(chatId: 'c1', page: 2));

    expect(messages, isEmpty);
    expect(meta.total, total);
    expect(meta.nextPage, isNull);
  });
}

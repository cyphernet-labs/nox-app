import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/domain/repository/base/page_metadata.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/general/identity_mock_data.dart';

/// Skeleton MOCK source for a chat thread (no real backend — UI phase). Synthesizes
/// a deterministic history per `chatId`: an opening system line, a mix of own
/// ([IdentityMockData.fallbackOwnId]) and other authors with consecutive same-author
/// groups, one attachment, spread across a few days. Own rows are reconciled to the
/// signed-in identity by the repository at seed time. Paginates OLDER messages
/// (page 1 = newest batch). The real impl wraps a Dio request (path `v1/chats/{id}/messages`,
/// query `page`/`page_size`) — example/TBD until the NOX backend is chosen. `// TODO(backend):`.
@lazySingleton
class GetMessagesApi {
  Future<(List<MessageModel>, PageMetadata)> execute({required GetMessagesConfig config}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final all = _mockMessages(config.chatId); // chronological: oldest (system line) → newest
    final total = all.length;
    const pageSize = GetMessagesConfig.pageSize;

    // page 1 = newest `pageSize`; each next page reaches further back in time.
    final end = total - (config.page - 1) * pageSize;
    if (end <= 0) return (const <MessageModel>[], PageMetadata(total: total));
    final start = (end - pageSize) < 0 ? 0 : end - pageSize;
    final slice = all.sublist(start, end);
    final hasMore = start > 0;
    return (slice, PageMetadata(total: total, nextPage: hasMore ? config.page + 1 : null));
  }

  /// Deterministic history for a chat. Authors: `me` (own) + a few others; one
  /// message carries an attachment. Timestamps are relative to "now" so the date
  /// separators (Today / Yesterday / date) read consistently.
  List<MessageModel> _mockMessages(String chatId) {
    final now = AppClock.now();
    final messages = <MessageModel>[
      MessageModel(
        id: '${chatId}_sys',
        chatId: chatId,
        authorId: 'system',
        authorLabel: 'Aria',
        sentAt: now.subtract(const Duration(days: 2, hours: 6)),
        isSystem: true,
      ),
    ];

    // (authorId, authorLabel, text, ago) — chronological oldest → newest.
    const seed = <(String, String, String, Duration)>[
      ('u_aria', 'Aria', 'Hey, welcome to the chat 👋', Duration(days: 2, hours: 5, minutes: 50)),
      ('u_aria', 'Aria', 'Drop anything you want to share here.', Duration(days: 2, hours: 5, minutes: 49)),
      ('me', 'You', 'Thanks! Happy to be here.', Duration(days: 2, hours: 5, minutes: 30)),
      ('u_mox', 'Mox', 'Did anyone look at the spacing tokens?', Duration(days: 1, hours: 8)),
      ('u_mox', 'Mox', 'I think 4dp base reads cleaner.', Duration(days: 1, hours: 7, minutes: 58)),
      ('me', 'You', 'Agree. Pushed a draft just now.', Duration(days: 1, hours: 7)),
      ('u_kit', 'Kit', 'Here is the export.', Duration(days: 1, hours: 2)),
      ('u_aria', 'Aria', 'Nice, the contrast looks better in dark.', Duration(hours: 20)),
      ('me', 'You', 'Yep, fixed the divider too.', Duration(hours: 5, minutes: 10)),
      ('u_mox', 'Mox', 'Ship it 🚀', Duration(hours: 2)),
      ('u_mox', 'Mox', 'Also: lunch at 1?', Duration(hours: 1, minutes: 58)),
      ('me', 'You', 'Sounds good.', Duration(minutes: 35)),
    ];

    for (final (index, (authorId, authorLabel, text, ago)) in seed.indexed) {
      messages.add(
        MessageModel(
          id: '${chatId}_$index',
          chatId: chatId,
          authorId: authorId,
          authorLabel: authorLabel,
          text: text,
          sentAt: now.subtract(ago),
          status: authorId == IdentityMockData.fallbackOwnId ? MessageStatus.sent : MessageStatus.none,
        ),
      );
    }

    // One attachment-bearing message from another author (older side).
    messages.insert(
      8,
      MessageModel(
        id: '${chatId}_file',
        chatId: chatId,
        authorId: 'u_kit',
        authorLabel: 'Kit',
        attachment: const MessageAttachment(id: 'att_spec', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2516582),
        sentAt: now.subtract(const Duration(days: 1, hours: 2, minutes: 1)),
      ),
    );

    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return messages;
  }
}

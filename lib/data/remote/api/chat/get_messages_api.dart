import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/messages_wire_entity.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/domain/repository/chat/get_messages_config.dart';
import 'package:nox_app/general/identity_mock_data.dart';

/// Skeleton MOCK source for a chat thread. Synthesizes a deterministic
/// contract-shaped history per `chatId`: a mix of own
/// ([IdentityMockData.fallbackOwnId]) and other authors with consecutive
/// same-author groups, one attachment, spread across a few days. Journal
/// numbers are minted deterministically — `seq = chatBase + position` with
/// position 1.. over the chronological order (position 0 is reserved for the
/// locally-synthesized genesis line: the wire carries NO system messages,
/// contract §4). Serves cursor batches per §5 (`before_seq`/`has_more`,
/// ascending inside a batch) in the `ResponseEntity<MessagesWireEntity>`
/// envelope. Own rows are reconciled to the signed-in identity (and their
/// local `sent` status) by the repository at seed time.
@lazySingleton
class GetMessagesApi {
  GetMessagesApi(this._wireMapper);

  final MessageWireMapper _wireMapper;

  Future<ResponseEntity<MessagesWireEntity>> execute({required GetMessagesConfig config}) async {
    // No artificial latency: reads happen on every open now (read-through), so a
    // fake delay here made every widget and golden test race the clock for no
    // gain — the loading states the delay once demonstrated are covered by the
    // explicit debug scenarios instead.

    final all = _mockMessages(config.chatId); // ascending by seq (== chronological)
    final beforeSeq = config.beforeSeq;
    // end = one past the newest message inside the window (seq < beforeSeq).
    var end = all.length;
    if (beforeSeq != null) {
      while (end > 0 && all[end - 1].seq >= beforeSeq) {
        end--;
      }
    }
    final start = (end - config.limit) < 0 ? 0 : end - config.limit;
    final slice = all.sublist(start, end);
    return ResponseEntity<MessagesWireEntity>(
      success: true,
      data: MessagesWireEntity(
        messages: _wireMapper.toListEntity(models: slice),
        hasMore: start > 0,
      ),
    );
  }

  /// Deterministic per-chat seq base: seeded `chat_N` ids get `(N+1)*1000`;
  /// arbitrary ids (tests) get a stable code-unit-sum base. Position 0 is
  /// reserved for the repository-synthesized genesis line.
  static int chatSeqBase(String chatId) {
    const prefix = 'chat_';
    if (chatId.startsWith(prefix)) {
      final n = int.tryParse(chatId.substring(prefix.length));
      if (n != null) return (n + 1) * 1000;
    }
    var sum = 0;
    for (final unit in chatId.codeUnits) {
      sum = (sum + unit) % 100000;
    }
    return (sum + 1) * 1000;
  }

  /// Deterministic history for a chat. Authors: `me` (own) + a few others; one
  /// message carries an attachment. Timestamps are relative to "now" so the date
  /// separators (Today / Yesterday / date) read consistently.
  /// The generator only knows the chats it seeds (`chat_0`..`chat_N`). Anything
  /// else — a chat the user just created — has no history, exactly as a real
  /// server would answer for a brand-new chat. Returning the generic history
  /// for every id would bury a fresh chat under someone else's conversation.
  static bool knowsChat(String chatId) => RegExp(r'^chat_\d+$').hasMatch(chatId);

  List<MessageModel> _mockMessages(String chatId) {
    if (!knowsChat(chatId)) return const <MessageModel>[];
    final now = AppClock.now();
    final messages = <MessageModel>[];

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
        attachment: MessageAttachment(
          id: 'att_spec',
          type: FileType.pdf,
          name: 'design-spec.pdf',
          sizeBytes: 2516582,
          mime: 'application/pdf',
          // Stage-1 indefinite retention: ten years out, deterministic under
          // the frozen golden clock.
          expiresAt: now.add(const Duration(days: 3650)),
        ),
        sentAt: now.subtract(const Duration(days: 1, hours: 2, minutes: 1)),
      ),
    );

    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final base = chatSeqBase(chatId);
    return [
      // Positions start at 1: position 0 (base + 0) is the genesis line the
      // repository synthesizes locally (no system messages on the wire).
      for (final (index, message) in messages.indexed) message.copyWith(seq: base + index + 1),
    ];
  }
}

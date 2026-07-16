import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/identity_mock_data.dart';
import 'package:uuid/uuid.dart';

/// Skeleton MOCK one-shot send (no real backend — UI phase). Echoes the message
/// back as accepted (`sent`) after a short delay. The caller (ChatThreadBloc) shows
/// the optimistic `pending` bubble; this stands in for the server ack. The real impl
/// POSTs to `v1/chats/{id}/messages` — example/TBD until the backend is chosen.
/// `// TODO(backend):` real send + server-assigned id/timestamp.
@lazySingleton
class SendMessageApi {
  Future<MessageModel> execute({required String chatId, String? text, MessageAttachment? attachment}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return MessageModel(
      // A stable unique id (not clock-derived: under a frozen AppClock two sends
      // would otherwise collide and the DAO upsert would drop one). Only sentAt is
      // clock-based for deterministic display.
      id: 'srv_${const Uuid().v4()}',
      chatId: chatId,
      authorId: IdentityMockData.currentUserId,
      authorLabel: IdentityMockData.currentLabel,
      text: text,
      attachment: attachment,
      sentAt: AppClock.now(),
      status: MessageStatus.sent,
    );
  }
}

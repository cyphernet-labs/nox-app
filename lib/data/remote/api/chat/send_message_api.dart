import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:nox_app/general/mock_seq.dart';
import 'package:uuid/uuid.dart';

/// Skeleton MOCK one-shot send (no real backend — UI phase). Echoes the message
/// back as accepted (`sent`) after a short delay, authored with the signed-in
/// identity resolved by the caller (MessageRepositoryImpl, from the session), wrapped
/// in the reference `ResponseEntity<MessageWireEntity>` envelope (feature P6 — uniform
/// with the paged reads / Item harness). The echo carries the contract-v0 wire shape
/// (feature 025); the real impl sends `message.send` over the WS envelope (feature 027).
@lazySingleton
class SendMessageApi {
  SendMessageApi(this._wireMapper);

  final MessageWireMapper _wireMapper;

  Future<ResponseEntity<MessageWireEntity>> execute({
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final echoed = MessageModel(
      // A stable unique id (not clock-derived: under a frozen AppClock two sends
      // would otherwise collide and the DAO upsert would drop one). Only sentAt is
      // clock-based for deterministic display.
      id: 'srv_${const Uuid().v4()}',
      // Runtime journal number: always above the seeded bases and unique
      // under the frozen golden clock (MockSeq counter component).
      seq: MockSeq.next(),
      chatId: chatId,
      authorId: authorId,
      authorLabel: authorLabel,
      text: text,
      attachment: attachment,
      sentAt: AppClock.now(),
      status: MessageStatus.sent,
    );
    return ResponseEntity<MessageWireEntity>(success: true, data: _wireMapper.toEntity(model: echoed));
  }
}

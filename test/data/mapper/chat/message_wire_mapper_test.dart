import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

void main() {
  final mapper = MessageWireMapper();

  MessageModel base({MessageAttachment? attachment, bool isSystem = false, MessageStatus status = MessageStatus.sent}) => MessageModel(
    id: 'm1',
    chatId: 'chat_0',
    authorId: 'user:abc',
    authorLabel: 'Aria',
    text: 'hello',
    attachment: attachment,
    sentAt: DateTime(2026, 6, 15, 21, 30),
    status: status,
    isSystem: isSystem,
  );

  void expectRoundTrips(MessageModel model) {
    final round = mapper.toModel(entity: mapper.toEntity(model: model));
    expect(round.id, model.id);
    expect(round.chatId, model.chatId);
    expect(round.authorId, model.authorId);
    expect(round.authorLabel, model.authorLabel);
    expect(round.text, model.text);
    expect(round.sentAt.toUtc(), model.sentAt.toUtc());
    expect(round.status, model.status);
    expect(round.isSystem, model.isSystem);
    expect(round.attachment?.id, model.attachment?.id);
    expect(round.attachment?.type, model.attachment?.type);
    expect(round.attachment?.name, model.attachment?.name);
    expect(round.attachment?.sizeBytes, model.attachment?.sizeBytes);
  }

  test('round-trips a plain message (no attachment)', () => expectRoundTrips(base()));

  test('round-trips a message with an attachment', () {
    expectRoundTrips(
      base(
        attachment: const MessageAttachment(id: 'a1', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2400000),
      ),
    );
  });

  test('round-trips a system line and preserves status none', () {
    expectRoundTrips(base(isSystem: true, status: MessageStatus.none));
  });

  test('an unknown wire status/type falls back to none/other (defensive)', () {
    // toModel with an out-of-range string uses the mapper's orElse fallbacks.
    final wire = mapper.toEntity(model: base()).copyWith(status: 'not-a-status');
    expect(mapper.toModel(entity: wire).status, MessageStatus.none);
  });
}

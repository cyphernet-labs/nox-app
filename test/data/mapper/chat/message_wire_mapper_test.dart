import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/entity/chat/wire/message_wire_entity.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

void main() {
  final mapper = MessageWireMapper();

  MessageModel base({MessageAttachment? attachment, String? text = 'hello'}) => MessageModel(
    id: 'm1',
    seq: 1042,
    chatId: 'chat_0',
    authorId: 'user:abc',
    authorLabel: 'Aria',
    text: text,
    attachment: attachment,
    sentAt: DateTime.utc(2026, 6, 15, 21, 30),
  );

  void expectRoundTrips(MessageModel model) {
    final round = mapper.toModel(entity: mapper.toEntity(model: model));
    expect(round.id, model.id);
    expect(round.seq, model.seq);
    expect(round.chatId, model.chatId);
    expect(round.authorId, model.authorId);
    expect(round.authorLabel, model.authorLabel);
    expect(round.text, model.text);
    expect(round.sentAt.toUtc(), model.sentAt.toUtc());
    expect(round.attachment?.id, model.attachment?.id);
    expect(round.attachment?.name, model.attachment?.name);
    expect(round.attachment?.sizeBytes, model.attachment?.sizeBytes);
    expect(round.attachment?.mime, model.attachment?.mime);
  }

  test('round-trips a plain text message', () => expectRoundTrips(base()));

  test('round-trips an attachment message; the category re-derives from the name extension', () {
    final model = base(
      attachment: MessageAttachment(
        id: 'f_77',
        type: FileType.pdf,
        name: 'design-spec.pdf',
        sizeBytes: 2400000,
        mime: 'application/pdf',
        expiresAt: DateTime.utc(2027, 1, 1),
      ),
    );
    expectRoundTrips(model);

    final round = mapper.toModel(entity: mapper.toEntity(model: model));
    expect(round.attachment!.type, FileType.pdf); // from '.pdf', not from the wire
    expect(round.attachment!.expiresAt!.toUtc(), DateTime.utc(2027, 1, 1));
  });

  test('an attachment-only message maps with a null text both ways', () {
    final model = base(
      text: null,
      attachment: MessageAttachment(
        id: 'f_1',
        type: FileType.other,
        name: 'blob.bin',
        sizeBytes: 10,
        mime: 'application/octet-stream',
        expiresAt: DateTime.utc(2027),
      ),
    );
    final wire = mapper.toEntity(model: model);
    expect(wire.body, isNull); // no text → no body object
    expect(mapper.toModel(entity: wire).text, isNull);
  });

  test('local-only fields never reach the wire and default locally', () {
    final wire = mapper.toEntity(model: base());
    final json = wire.toJson();
    expect(json.containsKey('status'), isFalse);
    expect(json.containsKey('is_system'), isFalse);

    final round = mapper.toModel(entity: wire);
    expect(round.status, MessageStatus.none); // local status is assigned by the repo, not the wire
    expect(round.isSystem, isFalse);
  });

  test('a non-text body maps to a null text (the Q1 blob seam)', () {
    const wire = MessageWireEntity(
      messageId: 'm2',
      seq: 5,
      chatId: 'c',
      authorId: 'a',
      authorLabel: 'A',
      sentAt: 1755600000,
      body: BodyWireEntity(type: 'blob'),
    );
    expect(mapper.toModel(entity: wire).text, isNull);
  });

  test('a name without an extension derives FileType.other', () {
    const wire = MessageWireEntity(
      messageId: 'm3',
      seq: 6,
      chatId: 'c',
      authorId: 'a',
      authorLabel: 'A',
      sentAt: 1755600000,
      attachment: AttachmentWireEntity(fileId: 'f_2', name: 'README', size: 5, mime: 'text/plain', expiresAt: 1758200000),
    );
    expect(mapper.toModel(entity: wire).attachment!.type, FileType.other);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/mapper/chat/message_wire_mapper.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  final mapper = MessageWireMapper();
  final api = SendMessageApi(mapper);

  // The send now returns the ResponseEntity<MessageWireEntity> echo envelope (feature P6).
  // Unwrap it + map wire->model here so the ack assertions read off the domain model as before.
  Future<MessageModel> exec({
    required String chatId,
    required String authorId,
    required String authorLabel,
    String? text,
    MessageAttachment? attachment,
  }) async {
    final response = await api.execute(chatId: chatId, authorId: authorId, authorLabel: authorLabel, text: text, attachment: attachment);
    return mapper.toModel(entity: response.data!);
  }

  // A fixed reference instant so `sentAt` (the only clock-derived field) is
  // deterministic and the anti-collision claim isolates the id generator.
  final frozen = DateTime(2026, 6, 15, 21, 30);

  setUp(() => AppClock.freeze(frozen));
  tearDown(AppClock.reset);

  test('the send returns a success envelope carrying the wire message', () async {
    final response = await api.execute(chatId: 'c1', authorId: 'abc-id', authorLabel: 'Alice', text: 'hello');
    expect(response.success, isTrue);
    expect(response.data, isNotNull);
    expect(response.data!.messageId, startsWith('srv_')); // wire echo
    expect(response.data!.chatId, 'c1');
  });

  test('text-only send echoes the caller-supplied identity + ack contract under the frozen clock', () async {
    final message = await exec(chatId: 'c1', authorId: 'abc-id', authorLabel: 'Alice', text: 'hello');

    expect(message.chatId, 'c1');
    expect(message.text, 'hello');
    expect(message.attachment, isNull);
    expect(message.authorId, 'abc-id'); // echoes the resolved signed-in identity (feature 015)
    expect(message.authorLabel, 'Alice');
    expect(message.status, MessageStatus.none); // the wire carries no statuses; the repo marks the echo sent
    expect(message.sentAt.toUtc(), frozen.toUtc());
    expect(message.id, startsWith('srv_'));
  });

  test('attachment-only send echoes the attachment with null text', () async {
    const attachment = MessageAttachment(id: 'a1', type: FileType.pdf, name: 'spec.pdf', sizeBytes: 2048);

    final message = await exec(chatId: 'c2', authorId: 'abc-id', authorLabel: 'Alice', attachment: attachment);

    expect(message.chatId, 'c2');
    expect(message.text, isNull);
    expect(message.attachment?.id, attachment.id);
    expect(message.attachment?.type, attachment.type);
    expect(message.attachment?.name, attachment.name);
    expect(message.attachment?.sizeBytes, attachment.sizeBytes);
    expect(message.authorId, 'abc-id');
    expect(message.status, MessageStatus.none); // the wire carries no statuses; the repo marks the echo sent
    expect(message.id, startsWith('srv_'));
  });

  test('two sequential sends under the frozen clock yield distinct ids', () async {
    final first = await exec(chatId: 'c3', authorId: 'abc-id', authorLabel: 'Alice', text: 'one');
    final second = await exec(chatId: 'c3', authorId: 'abc-id', authorLabel: 'Alice', text: 'two');

    // Both share the same clock-derived sentAt, proving the clock is frozen — so a
    // clock-derived id would collide. Distinct ids prove the id is NOT clock-derived.
    expect(first.sentAt, second.sentAt);
    expect(first.id, startsWith('srv_'));
    expect(second.id, startsWith('srv_'));
    expect(first.id, isNot(second.id));
  });
}

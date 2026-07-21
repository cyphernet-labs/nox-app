import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/remote/api/chat/send_message_api.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/app_clock.dart';

void main() {
  final api = SendMessageApi();

  // A fixed reference instant so `sentAt` (the only clock-derived field) is
  // deterministic and the anti-collision claim isolates the id generator.
  final frozen = DateTime(2026, 6, 15, 21, 30);

  setUp(() => AppClock.freeze(frozen));
  tearDown(AppClock.reset);

  test('text-only send echoes the caller-supplied identity + ack contract under the frozen clock', () async {
    final message = await api.execute(chatId: 'c1', authorId: 'abc-id', authorLabel: 'Alice', text: 'hello');

    expect(message.chatId, 'c1');
    expect(message.text, 'hello');
    expect(message.attachment, isNull);
    expect(message.authorId, 'abc-id'); // echoes the resolved signed-in identity (feature 015)
    expect(message.authorLabel, 'Alice');
    expect(message.status, MessageStatus.sent);
    expect(message.sentAt, frozen);
    expect(message.id, startsWith('srv_'));
  });

  test('attachment-only send echoes the attachment with null text', () async {
    const attachment = MessageAttachment(id: 'a1', type: FileType.pdf, name: 'spec.pdf', sizeBytes: 2048);

    final message = await api.execute(chatId: 'c2', authorId: 'abc-id', authorLabel: 'Alice', attachment: attachment);

    expect(message.chatId, 'c2');
    expect(message.text, isNull);
    expect(message.attachment, attachment);
    expect(message.authorId, 'abc-id');
    expect(message.authorLabel, 'Alice');
    expect(message.status, MessageStatus.sent);
    expect(message.sentAt, frozen);
    expect(message.id, startsWith('srv_'));
  });

  test('two sequential sends under the frozen clock yield distinct ids', () async {
    final first = await api.execute(chatId: 'c3', authorId: 'abc-id', authorLabel: 'Alice', text: 'one');
    final second = await api.execute(chatId: 'c3', authorId: 'abc-id', authorLabel: 'Alice', text: 'two');

    // Both share the same clock-derived sentAt, proving the clock is frozen — so a
    // clock-derived id would collide. Distinct ids prove the id is NOT clock-derived.
    expect(first.sentAt, second.sentAt);
    expect(first.id, startsWith('srv_'));
    expect(second.id, startsWith('srv_'));
    expect(first.id, isNot(second.id));
  });
}

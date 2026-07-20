import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/general/formatters/chat_preview_formatter.dart';

void main() {
  MessageModel message({String? text, MessageAttachment? attachment}) =>
      MessageModel(id: 'm1', chatId: 'c1', authorId: 'me', authorLabel: 'You', text: text, attachment: attachment, sentAt: DateTime(2026));

  const pdf = MessageAttachment(id: 'a1', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 1024);

  test('a text message previews as its text', () {
    expect(chatPreviewFor(message(text: 'Hello there')), 'Hello there');
  });

  test('an attachment-only message previews as "You: <filename>"', () {
    expect(chatPreviewFor(message(attachment: pdf)), 'You: design-spec.pdf');
  });

  test('a whitespace-only text falls back to the attachment filename', () {
    expect(chatPreviewFor(message(text: '   ', attachment: pdf)), 'You: design-spec.pdf');
  });
}

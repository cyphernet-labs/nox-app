import 'package:nox_app/domain/model/chat/message_model.dart';

/// The chats-list last-message preview for a message (Feature 014).
///
/// A text message → its text. An attachment-only message → `"You: <filename>"` (the
/// clarified format: author prefix + filename, no new l10n string, no emoji). This is a
/// data-layer literal stored in the DB — untranslated by design for this phase.
String chatPreviewFor(MessageModel message) {
  final text = message.text;
  if (text != null && text.trim().isNotEmpty) return text;
  final attachment = message.attachment;
  if (attachment != null) return 'You: ${attachment.name}';
  return '';
}

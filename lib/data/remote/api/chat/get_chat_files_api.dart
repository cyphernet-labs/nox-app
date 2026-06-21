import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';

/// Skeleton MOCK source for a chat's shared files (5.4) — no real backend (UI phase).
/// Synthesizes a deterministic set of attachments per `chatId` (varied types/sizes,
/// incl. a long name); a designated chat id returns an empty set for the empty state.
/// The real impl wraps a Dio request (path `v1/chats/{id}/files`) — example/TBD until
/// the NOX backend is chosen. `// TODO(backend):`.
@lazySingleton
class GetChatFilesApi {
  Future<List<MessageAttachment>> execute({required String chatId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (chatId == 'chat_empty') return const [];
    return const [
      MessageAttachment(id: 'f0', type: FileType.pdf, name: 'design-spec.pdf', sizeBytes: 2516582),
      MessageAttachment(id: 'f1', type: FileType.image, name: 'mockup-final-v3.png', sizeBytes: 1153434),
      MessageAttachment(id: 'f2', type: FileType.sheet, name: 'budget.xlsx', sizeBytes: 48211),
      MessageAttachment(id: 'f3', type: FileType.archive, name: 'assets-export-bundle.zip', sizeBytes: 18874368),
      MessageAttachment(id: 'f4', type: FileType.audio, name: 'voice-note.m4a', sizeBytes: 743210),
      MessageAttachment(id: 'f5', type: FileType.doc, name: 'a-rather-long-attachment-name-that-should-truncate.docx', sizeBytes: 91234),
      MessageAttachment(id: 'f6', type: FileType.video, name: 'walkthrough.mp4', sizeBytes: 64487424),
      MessageAttachment(id: 'f7', type: FileType.text, name: 'notes.txt', sizeBytes: 2048),
    ];
  }
}

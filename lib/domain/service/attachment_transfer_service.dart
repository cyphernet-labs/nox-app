import 'package:nox_app/domain/model/file/attachment_transfer.dart';

/// Attachment transfers running right now, by message id: what lets a picture
/// or a file in the thread show that its bytes are on their way.
///
/// Two writers and one reader. The queue reports an upload under the
/// message's `client_message_id` (the id its bubble has until the server
/// accepts it), the picture prefetch reports a download under the stored
/// message id, and the thread draws both the same way.
abstract class AttachmentTransferService {
  /// What is moving now.
  Map<String, AttachmentTransfer> get current;

  /// [current] on listen, then every change.
  Stream<Map<String, AttachmentTransfer>> watch();

  /// A transfer for [messageId], in [chatId], is under way; no bytes have
  /// moved yet.
  void begin(String messageId, TransferDirection direction, {required String chatId});

  /// How far it has got, 0 to 1. Dropped once the transfer has ended, and
  /// when it would not change the whole percent shown: a large file reports
  /// thousands of times, and each report would redraw the thread.
  void report(String messageId, double fraction);

  /// It is over, whichever way it ended.
  void end(String messageId);
}

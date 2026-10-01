import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/service/attachment_transfer_service_impl.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

import 'attachment_prefetch_service_test.mocks.dart';

/// The SECOND downloader, and the one easiest to forget: it reaches Dio on its
/// own schedule without passing through the socket, so the phase that stops
/// everything else does not reach it by itself. A machine that failed to prove
/// who it is must not be asked for this person's pictures — and a refusal here
/// is only logged, so nothing on screen would ever say why they stopped.
@GenerateMocks([FileRepository, MessageRepository])
void main() {
  late MockFileRepository files;
  late MockMessageRepository messages;

  MessageModel image(String id) => MessageModel(
    id: id,
    seq: 1,
    chatId: 'c1',
    authorId: 'u_other',
    authorLabel: 'Aria',
    sentAt: DateTime.utc(2026, 6, 1),
    status: MessageStatus.sent,
    attachment: const MessageAttachment(id: 'f1', type: FileType.image, name: 'photo.png', sizeBytes: 2048),
  );

  setUp(() {
    provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.error(exception: RepositoryException.unknown));
    files = MockFileRepository();
    messages = MockMessageRepository();
    when(
      files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')),
    ).thenAnswer((_) async => const RepositoryResult<String>.success(data: '/tmp/photo.png'));
  });

  test('asks for nothing while the machine that answered is the wrong one', () async {
    final service = AttachmentPrefetchService(files, messages, _Phase(SessionPhase.serverMismatch), AttachmentTransferServiceImpl());

    await service.prefetch([image('m1')]);

    verifyNever(files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')));
  });

  test('fetches a received image when the channel is trusted', () async {
    // The other half of the gate: without it the test above would pass over a
    // service that never fetches anything at all.
    final service = AttachmentPrefetchService(files, messages, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());

    await service.prefetch([image('m2')]);

    verify(files.download(fileId: 'f1', suggestedName: 'photo.png', onProgress: anyNamed('onProgress'))).called(1);
  });

  test('a fetch is a download for its message while it runs - the placeholder fills with it', () async {
    final transfers = AttachmentTransferServiceImpl();
    final seen = <AttachmentTransfer?>[];
    when(
      files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')),
    ).thenAnswer((invocation) async {
      seen.add(transfers.current['m3']);
      (invocation.namedArguments[#onProgress] as TransferFraction?)?.call(0.5);
      seen.add(transfers.current['m3']);
      return const RepositoryResult<String>.success(data: '/tmp/photo.png');
    });
    final service = AttachmentPrefetchService(files, messages, _Phase(SessionPhase.live), transfers);

    await service.prefetch([image('m3')]);

    expect(seen, [
      const AttachmentTransfer(direction: TransferDirection.download),
      const AttachmentTransfer(direction: TransferDirection.download, fraction: 0.5),
    ]);
    expect(transfers.current, isEmpty, reason: 'over once the bytes are here');
  });

  test('a fetch the network cut short ends its transfer and is tried again on the next call', () async {
    // The thread calls again on its next refresh and when the channel comes
    // back. A failure remembered for good would leave the picture a
    // placeholder until the app restarted.
    final transfers = AttachmentTransferServiceImpl();
    when(
      files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')),
    ).thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.connection));
    final service = AttachmentPrefetchService(files, messages, _Phase(SessionPhase.live), transfers);

    await service.prefetch([image('m4')]);
    expect(transfers.current, isEmpty);

    await service.prefetch([image('m4')]);
    verify(files.download(fileId: 'f1', suggestedName: 'photo.png', onProgress: anyNamed('onProgress'))).called(2);
  });
}

class _Phase implements SessionPhaseService {
  _Phase(this.phase);

  @override
  final SessionPhase phase;

  @override
  Stream<SessionPhase> watchPhase() => Stream<SessionPhase>.value(phase);

  @override
  Future<void> reconnect() async {}
}

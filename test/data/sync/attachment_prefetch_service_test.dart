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
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';

import 'attachment_prefetch_service_test.mocks.dart';

/// The SECOND downloader, and the one easiest to forget: it reaches Dio on its
/// own schedule without passing through the socket, so the phase that stops
/// everything else does not reach it by itself. A machine that failed to prove
/// who it is must not be asked for this person's pictures — and a refusal here
/// is only logged, so nothing on screen would ever say why they stopped.
@GenerateMocks([AttachmentDownloadService])
void main() {
  late MockAttachmentDownloadService downloads;

  MessageModel image(String id, {String fileId = 'f1'}) => MessageModel(
    id: id,
    seq: 1,
    chatId: 'c1',
    authorId: 'u_other',
    authorLabel: 'Aria',
    sentAt: DateTime.utc(2026, 6, 1),
    status: MessageStatus.sent,
    attachment: MessageAttachment(id: fileId, type: FileType.image, name: 'photo.png', sizeBytes: 2048),
  );

  PostExpectation<Future<RepositoryResult<String>>> whenFetched() =>
      when(downloads.fetch(messageId: anyNamed('messageId'), attachment: anyNamed('attachment'), onProgress: anyNamed('onProgress')));

  VerificationResult verifyFetched({String? fileId}) => verify(
    downloads.fetch(
      messageId: anyNamed('messageId'),
      attachment: fileId == null
          ? anyNamed('attachment')
          : argThat(isA<MessageAttachment>().having((a) => a.id, 'id', fileId), named: 'attachment'),
      onProgress: anyNamed('onProgress'),
    ),
  );

  setUp(() {
    provideDummy<RepositoryResult<String>>(const RepositoryResult<String>.error(exception: RepositoryException.unknown));
    downloads = MockAttachmentDownloadService();
    whenFetched().thenAnswer((_) async => const RepositoryResult<String>.success(data: '/tmp/photo.png'));
  });

  test('asks for nothing while the machine that answered is the wrong one', () async {
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.serverMismatch), AttachmentTransferServiceImpl());

    await service.prefetch([image('m1')]);

    verifyNever(downloads.fetch(messageId: anyNamed('messageId'), attachment: anyNamed('attachment'), onProgress: anyNamed('onProgress')));
  });

  test('fetches a received image when the channel is trusted, for its message', () async {
    // The other half of the gate: without it the test above would pass over a
    // service that never fetches anything at all. The message id goes along -
    // the download service records the path against it itself.
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());

    await service.prefetch([image('m2')]);

    final call = verify(
      downloads.fetch(
        messageId: captureAnyNamed('messageId'),
        attachment: captureAnyNamed('attachment'),
        onProgress: anyNamed('onProgress'),
      ),
    )..called(1);
    expect(call.captured[0], 'm2');
    expect((call.captured[1] as MessageAttachment).id, 'f1');
  });

  test('a fetch is a download for its message while it runs - the placeholder fills with it', () async {
    final transfers = AttachmentTransferServiceImpl();
    final seen = <AttachmentTransfer?>[];
    whenFetched().thenAnswer((invocation) async {
      seen.add(transfers.current['m3']);
      (invocation.namedArguments[#onProgress] as TransferFraction?)?.call(0.5);
      seen.add(transfers.current['m3']);
      return const RepositoryResult<String>.success(data: '/tmp/photo.png');
    });
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), transfers);

    await service.prefetch([image('m3')]);

    expect(seen, [
      const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.download),
      const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.download, fraction: 0.5),
    ]);
    expect(transfers.current, isEmpty, reason: 'over once the bytes are here');
  });

  test('while the download service keeps at it through a broken link, the transfer does not end', () async {
    // The service pauses and goes on by itself (phase 043); the placeholder
    // keeps its ring at the share already here instead of turning back into a
    // spinner between attempts.
    final transfers = AttachmentTransferServiceImpl();
    final held = Completer<RepositoryResult<String>>();
    whenFetched().thenAnswer((invocation) {
      (invocation.namedArguments[#onProgress] as TransferFraction?)?.call(0.4);
      return held.future;
    });
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), transfers);

    final running = service.prefetch([image('m5')]);
    await pumpEventQueue();
    expect(transfers.current['m5']?.percent, 40);

    held.complete(const RepositoryResult<String>.success(data: '/tmp/photo.png'));
    await running;
    expect(transfers.current, isEmpty);
  });

  group('after the automation gave up on a picture', () {
    late AttachmentTransferServiceImpl transfers;
    late AttachmentPrefetchService service;

    setUp(() {
      transfers = AttachmentTransferServiceImpl();
      // What the download service answers once the server refused too often.
      whenFetched().thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.internal));
      service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), transfers);
    });

    test('the transfer ends, and later refreshes do not start the ladder over', () async {
      // Every new message refreshes the thread; each would otherwise start
      // another whole ladder of refusals for this picture.
      await service.prefetch([image('m4')]);
      expect(transfers.current, isEmpty);

      await service.prefetch([image('m4')]);
      await service.prefetch([image('m4')]);

      verifyFetched(fileId: 'f1').called(1);
    });

    test('it is asked for again at once when the channel comes back', () async {
      await service.prefetch([image('m4')]);

      await service.prefetch([image('m4')], retryNow: true);

      verifyFetched(fileId: 'f1').called(2);
    });
  });

  test('a file the server no longer has is never asked for again, not even when the channel comes back', () async {
    whenFetched().thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.attachmentGone));
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());

    await service.prefetch([image('m6')]);
    await service.prefetch([image('m6')], retryNow: true);

    verifyFetched(fileId: 'f1').called(1);
  });

  test('pictures are fetched one at a time, in the order they were asked for', () async {
    // A walker per call grew to nine downloads at once through Tor, and the
    // first picture arrived last.
    var running = 0;
    var mostAtOnce = 0;
    final order = <String>[];
    whenFetched().thenAnswer((invocation) async {
      running++;
      mostAtOnce = running > mostAtOnce ? running : mostAtOnce;
      order.add((invocation.namedArguments[#attachment] as MessageAttachment).id);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      running--;
      return const RepositoryResult<String>.success(data: '/tmp/photo.png');
    });
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());

    final first = service.prefetch([image('a', fileId: 'fa'), image('b', fileId: 'fb')]);
    final second = service.prefetch([image('b', fileId: 'fb'), image('c', fileId: 'fc')]); // a refresh mid-way
    await Future.wait([first, second]);

    expect(mostAtOnce, 1);
    expect(order, ['fa', 'fb', 'fc'], reason: 'each picture once, in the order asked');
  });

  test('a reset empties the queue: the worker does not start the next picture of the identity that left', () async {
    // Reset before the downloads stop (logout, a change of server): otherwise
    // the worker takes the next picture the moment the current one ends, and
    // starts it into the wipe.
    final held = Completer<RepositoryResult<String>>();
    final asked = <String>[];
    whenFetched().thenAnswer((invocation) {
      asked.add((invocation.namedArguments[#attachment] as MessageAttachment).id);
      return held.future;
    });
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());
    final running = service.prefetch([image('a', fileId: 'fa'), image('b', fileId: 'fb')]);
    await pumpEventQueue();

    service.reset();
    held.complete(const RepositoryResult<String>.error(exception: RepositoryException.connection));
    await running;

    expect(asked, ['fa']);
  });

  test('what a fetch of the identity that left learned is not remembered for the next one', () async {
    // The same server signed in to again hands out the same message ids: a
    // picture the stopped fetch marked as given up on would never be fetched
    // for the next identity until the channel came back.
    final held = Completer<RepositoryResult<String>>();
    var calls = 0;
    whenFetched().thenAnswer((_) {
      calls++;
      return calls == 1 ? held.future : Future<RepositoryResult<String>>.value(const RepositoryResult<String>.success(data: '/tmp/p.png'));
    });
    final service = AttachmentPrefetchService(downloads, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());
    final stopped = service.prefetch([image('m1')]);
    await pumpEventQueue();

    service.reset();
    held.complete(const RepositoryResult<String>.error(exception: RepositoryException.connection));
    await stopped;
    await service.prefetch([image('m1')]);

    expect(calls, 2, reason: 'asked for again by the next identity');
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

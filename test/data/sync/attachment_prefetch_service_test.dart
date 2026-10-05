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
import 'package:nox_app/general/app_clock.dart';

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
      const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.download),
      const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.download, fraction: 0.5),
    ]);
    expect(transfers.current, isEmpty, reason: 'over once the bytes are here');
  });

  group('after a failed fetch', () {
    late AttachmentTransferServiceImpl transfers;
    late AttachmentPrefetchService service;

    setUp(() {
      AppClock.freeze(DateTime(2026, 10, 4, 12));
      addTearDown(AppClock.reset);
      transfers = AttachmentTransferServiceImpl();
      when(
        files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')),
      ).thenAnswer((_) async => const RepositoryResult<String>.error(exception: RepositoryException.connection));
      service = AttachmentPrefetchService(files, messages, _Phase(SessionPhase.live), transfers);
    });

    test('the transfer ends, and a refresh moments later does not ask again', () async {
      // Every stored path refreshes the thread; without a pause a file the
      // server keeps refusing was asked for after each of them.
      await service.prefetch([image('m4')]);
      expect(transfers.current, isEmpty);

      await service.prefetch([image('m4')]);

      verify(files.download(fileId: 'f1', suggestedName: 'photo.png', onProgress: anyNamed('onProgress'))).called(1);
    });

    test('it is asked for again once the pause is over', () async {
      // A failure remembered for good would leave the picture a placeholder
      // until the app restarted.
      await service.prefetch([image('m4')]);
      AppClock.freeze(DateTime(2026, 10, 4, 12, 0, 16));

      await service.prefetch([image('m4')]);

      verify(files.download(fileId: 'f1', suggestedName: 'photo.png', onProgress: anyNamed('onProgress'))).called(2);
    });

    test('it is asked for again at once when the channel comes back', () async {
      await service.prefetch([image('m4')]);

      await service.prefetch([image('m4')], retryNow: true);

      verify(files.download(fileId: 'f1', suggestedName: 'photo.png', onProgress: anyNamed('onProgress'))).called(2);
    });
  });

  test('pictures are fetched one at a time, in the order they were asked for', () async {
    // A walker per call grew to nine downloads at once through Tor, and the
    // first picture arrived last.
    var running = 0;
    var mostAtOnce = 0;
    final order = <String>[];
    when(
      files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')),
    ).thenAnswer((invocation) async {
      running++;
      mostAtOnce = running > mostAtOnce ? running : mostAtOnce;
      order.add(invocation.namedArguments[#fileId] as String);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      running--;
      return const RepositoryResult<String>.success(data: '/tmp/photo.png');
    });
    final service = AttachmentPrefetchService(files, messages, _Phase(SessionPhase.live), AttachmentTransferServiceImpl());

    final first = service.prefetch([image('a', fileId: 'fa'), image('b', fileId: 'fb')]);
    final second = service.prefetch([image('b', fileId: 'fb'), image('c', fileId: 'fc')]); // a refresh mid-way
    await Future.wait([first, second]);

    expect(mostAtOnce, 1);
    expect(order, ['fa', 'fb', 'fc'], reason: 'each picture once, in the order asked');
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

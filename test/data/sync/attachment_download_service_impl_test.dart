import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/sync/attachment_download_service_impl.dart';
import 'package:nox_app/data/sync/retry_ladder.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/transfer_cancellation.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/log_repository.dart';

import '../../utils/fixed_session_phase.dart';

/// One attempt per call, scripted: each [download] takes the next answer.
class _ScriptedFiles implements FileRepository {
  /// What the coming attempts answer, in order; with none left, the file.
  final List<RepositoryException> failures = <RepositoryException>[];

  /// Holds the next attempt until completed, reporting [heldShare] first.
  Completer<void>? hold;
  double heldShare = 0.3;

  int attempts = 0;
  int cancels = 0;

  @override
  Future<RepositoryResult<String>> download({
    required String fileId,
    required String suggestedName,
    int? expectedSize,
    TransferFraction? onProgress,
  }) async {
    attempts++;
    final held = hold;
    if (held != null) {
      onProgress?.call(heldShare);
      await held.future;
    }
    if (failures.isNotEmpty) return RepositoryResult<String>.error(exception: failures.removeAt(0));
    onProgress?.call(1);
    return RepositoryResult<String>.success(data: '/cache/$fileId.bin');
  }

  @override
  Future<void> cancelTransfers() async => cancels++;

  @override
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
    TransferCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<String?> localPathFor({required String fileId, required String suggestedName}) async => null;

  @override
  Future<String> cachePathFor({required String fileId, required String suggestedName}) async => '/cache/$fileId';

  @override
  Future<void> clean() async {}
}

/// Records where the bytes were said to be, and nothing else.
class _RecordingMessages implements MessageRepository {
  final Map<String, String> attached = <String, String>{};

  /// The store refuses the write: the database was closed under it.
  bool refuse = false;

  @override
  Future<void> attachLocalFile({required String messageId, required String localPath}) async {
    if (refuse) throw StateError('database closed');
    attached[messageId] = localPath;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _ScriptedFiles files;
  late _RecordingMessages messages;
  late FixedSessionPhaseService phase;
  late List<int> pausesAsked;
  late Duration pause;

  const attachment = MessageAttachment(id: 'f_big', type: FileType.video, name: 'trip.mp4', sizeBytes: 83886080);

  AttachmentDownloadServiceImpl service({Duration resetWait = AttachmentDownloadServiceImpl.defaultResetWait}) =>
      AttachmentDownloadServiceImpl.forTest(
        files,
        messages,
        phase,
        pause: (attempts) {
          pausesAsked.add(attempts);
          return pause;
        },
        resetWait: resetWait,
      );

  setUp(() {
    getIt.registerSingleton<LogRepository>(_SilentLog());
    addTearDown(getIt.reset);
    files = _ScriptedFiles();
    messages = _RecordingMessages();
    phase = FixedSessionPhaseService();
    pausesAsked = <int>[];
    pause = Duration.zero;
  });

  test('the bytes are recorded against the message when they are all here', () async {
    final result = await service().fetch(messageId: 'm1', attachment: attachment);

    expect(result.data, '/cache/f_big.bin');
    expect(messages.attached, {'m1': '/cache/f_big.bin'});
  });

  test('a broken link never ends a download, however many times it breaks (FR-010)', () async {
    // Fifteen breaks in a row, more than the refusal cap: a dead channel is not
    // the server refusing, and does not spend the ladder.
    files.failures.addAll(List<RepositoryException>.filled(15, RepositoryException.connection));

    final result = await service().fetch(messageId: 'm1', attachment: attachment);

    expect(result.data, isNotNull);
    expect(files.attempts, 16);
    expect(pausesAsked, [for (var n = 1; n <= 15; n++) n], reason: 'each pause a step further up the ladder');
  });

  test('a server that keeps refusing ends it after the cap, and only refusals count', () async {
    files.failures.addAll([
      for (var n = 0; n < RetryLadder.refusalLimit; n++) ...[RepositoryException.connection, RepositoryException.internal],
    ]);

    final result = await service().fetch(messageId: 'm1', attachment: attachment);

    expect(result.exception, RepositoryException.internal);
    expect(files.attempts, RetryLadder.refusalLimit * 2, reason: 'the breaks in between did not count');
    expect(messages.attached, isEmpty);
  });

  test('after giving up, a new fetch - Try again - climbs the whole ladder again (FR-011)', () async {
    files.failures.addAll(List<RepositoryException>.filled(RetryLadder.refusalLimit, RepositoryException.internal));
    final downloads = service();
    final first = await downloads.fetch(messageId: 'm1', attachment: attachment);
    expect(first.exception, RepositoryException.internal);
    expect(files.attempts, RetryLadder.refusalLimit);

    files.failures.addAll(List<RepositoryException>.filled(RetryLadder.refusalLimit - 1, RepositoryException.internal));
    final again = await downloads.fetch(messageId: 'm1', attachment: attachment);

    expect(again.data, isNotNull, reason: 'nine refusals do not spend a fresh ladder');
    expect(files.attempts, RetryLadder.refusalLimit * 2);
  });

  test('bytes the server no longer has end it at once', () async {
    files.failures.add(RepositoryException.attachmentGone);

    final result = await service().fetch(messageId: 'm1', attachment: attachment);

    expect(result.exception, RepositoryException.attachmentGone);
    expect(files.attempts, 1);
  });

  test('the channel coming back ends the pause at once', () async {
    pause = const Duration(minutes: 10);
    phase.emit(SessionPhase.disconnected);
    files.failures.add(RepositoryException.connection);

    final running = service().fetch(messageId: 'm1', attachment: attachment);
    await pumpEventQueue();
    expect(files.attempts, 1, reason: 'waiting out the pause');

    phase.emit(SessionPhase.live);
    final result = await running.timeout(const Duration(seconds: 5));

    expect(result.data, isNotNull);
    expect(files.attempts, 2);
  });

  test('a channel that was current all along is no reason to skip the pause', () async {
    // The phase stream hands over what it is on listen; reading that as "it
    // came back" would retry a refusing server with no pause at all.
    pause = const Duration(milliseconds: 300);
    files.failures.add(RepositoryException.internal);
    final watch = Stopwatch()..start();

    await service().fetch(messageId: 'm1', attachment: attachment);

    expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 300)));
  });

  test('one download per file: a second caller joins it and hears at once how far it is', () async {
    final downloads = service();
    files.hold = Completer<void>();
    final first = downloads.fetch(messageId: 'm1', attachment: attachment);
    await pumpEventQueue();

    final heard = <double>[];
    final second = downloads.fetch(messageId: 'm1', attachment: attachment, onProgress: heard.add);
    expect(heard, [0.3], reason: 'the file view reopened mid-download shows where it stands (FR-007a)');

    files.hold!.complete();
    await Future.wait([first, second]);
    expect(files.attempts, 1);
    expect(heard.last, 1.0);
  });

  test('the path is recorded even when nobody listens any more', () async {
    // The file view closed in the middle: the bytes keep coming and still
    // land against the message (FR-007a).
    final downloads = service();
    files.hold = Completer<void>();
    unawaited(downloads.fetch(messageId: 'm1', attachment: attachment, onProgress: (_) {}));
    await pumpEventQueue();

    files.hold!.complete();
    await pumpEventQueue();

    expect(messages.attached, {'m1': '/cache/f_big.bin'});
  });

  test('reset stops a pause and a download, cancels the transfers and waits for them', () async {
    pause = const Duration(minutes: 10);
    files.failures.add(RepositoryException.connection);
    final downloads = service();
    final running = downloads.fetch(messageId: 'm1', attachment: attachment);
    await pumpEventQueue();

    await downloads.reset().timeout(const Duration(seconds: 5));

    expect(files.cancels, 1);
    final result = await running;
    expect(result.hasData, isFalse);
    expect(files.attempts, 1, reason: 'nothing more is asked after the reset');
    expect(messages.attached, isEmpty);
  });

  test('a fetch asked for while a reset runs is refused, not started into the wipe', () async {
    final downloads = service(resetWait: const Duration(milliseconds: 300));
    files.hold = Completer<void>(); // a download that does not end when stopped
    unawaited(downloads.fetch(messageId: 'm1', attachment: attachment));
    await pumpEventQueue();

    final resetting = downloads.reset();
    final asked = await downloads.fetch(
      messageId: 'm2',
      attachment: attachment.copyWith(id: 'f_other'),
    );

    expect(asked.exception, RepositoryException.connection);
    expect(files.attempts, 1, reason: 'the second file was never asked for');
    await resetting;
    files.hold!.complete();
  });

  test('a reset waits a bounded time for a download that will not end - a logout waits on it', () async {
    final downloads = service(resetWait: const Duration(milliseconds: 200));
    files.hold = Completer<void>();
    unawaited(downloads.fetch(messageId: 'm1', attachment: attachment));
    await pumpEventQueue();
    final watch = Stopwatch()..start();

    await downloads.reset().timeout(const Duration(seconds: 5));

    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    files.hold!.complete();
  });

  test('a path the store will not record still ends the download with the file, and a reset after it', () async {
    // A throw here ended the download as a failure, and the reset waiting on
    // it with it - skipping the wipe of the cache it was meant to protect.
    messages.refuse = true;
    final downloads = service();

    final result = await downloads.fetch(messageId: 'm1', attachment: attachment);

    expect(result.data, '/cache/f_big.bin', reason: 'the bytes are here; the next look finds them by file id');
    await downloads.reset().timeout(const Duration(seconds: 5));
  });

  test('a listener that stopped listening hears nothing more, and the download goes on', () async {
    final downloads = service();
    files.hold = Completer<void>();
    final heard = <double>[];
    void screen(double share) => heard.add(share);
    final running = downloads.fetch(messageId: 'm1', attachment: attachment, onProgress: screen);
    await pumpEventQueue();
    expect(heard, [0.3]);

    downloads.stopListening(screen);
    files.hold!.complete();
    final result = await running;

    expect(result.hasData, isTrue);
    expect(heard, [0.3], reason: 'the closed screen is not kept alive by the download');
  });
}

class _SilentLog implements LogRepository {
  @override
  void debug({Object? target, required String message}) {}

  @override
  void error({Object? target, required Object error, StackTrace? stackTrace}) {}
}

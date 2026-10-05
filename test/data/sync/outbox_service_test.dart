import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/data/entity/base/error_wire_entity.dart';
import 'package:nox_app/data/entity/base/response_entity.dart';
import 'package:nox_app/data/entity/chat/wire/chat_wire_entity.dart';
import 'package:nox_app/data/local/app_database.dart';
import 'package:nox_app/data/local/chat/chat_dao.dart';
import 'package:nox_app/data/local/chat/message_dao.dart';
import 'package:nox_app/data/mapper/chat/chat_mapper.dart';
import 'package:nox_app/data/mapper/chat/chat_wire_mapper.dart';
import 'package:nox_app/data/remote/datasource/chat_remote_data_source.dart';
import 'package:nox_app/data/repository/chat/chat_repository_impl.dart';
import 'package:nox_app/data/service/attachment_transfer_service_impl.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/chat_model.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/chat/message_model.dart';
import 'package:nox_app/domain/model/file/attachment_transfer.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/model/chat/message_status.dart';
import 'package:nox_app/domain/model/chat/outbox_status.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/general/app_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outbox_service_test.mocks.dart';

/// A phase source the test drives by hand — the drain keys on the SESSION
/// phase, not on raw device connectivity, so this is the switch under test.
class _FakePhase implements SessionPhaseService {
  _FakePhase(this._phase);

  SessionPhase _phase;
  final StreamController<SessionPhase> _controller = StreamController<SessionPhase>.broadcast();

  @override
  SessionPhase get phase => _phase;

  @override
  Stream<SessionPhase> watchPhase() => _controller.stream;

  int reconnects = 0;

  @override
  Future<void> reconnect() async => reconnects++;

  void emit(SessionPhase next) {
    _phase = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();
}

/// A file repository the test drives by hand: it counts uploads, can run a hook
/// in the middle of one, and can be told to refuse. Nothing touches a disk or a
/// server.
class _FakeFiles implements FileRepository {
  int uploads = 0;
  RepositoryException? failure;
  Future<void> Function()? duringUpload;

  /// Every `from` the queue handed over, in order.
  final List<UnfinishedUpload?> continuedFrom = <UnfinishedUpload?>[];

  /// The upload "the server" names before the first byte, when set.
  UnfinishedUpload? names;

  /// The share already on "the server", reported as soon as it answers.
  double? alreadyThere;

  @override
  Future<RepositoryResult<String>> upload({
    required String path,
    required String mime,
    UnfinishedUpload? from,
    Future<void> Function(UnfinishedUpload? upload)? onUnfinished,
    TransferFraction? onProgress,
  }) async {
    uploads++;
    continuedFrom.add(from);
    final named = names;
    if (named != null) await onUnfinished?.call(named);
    final share = alreadyThere;
    if (share != null) onProgress?.call(share);
    await duringUpload?.call();
    if (failure != null) return RepositoryResult<String>.error(exception: failure!);
    if (!File(path).existsSync()) return RepositoryResult<String>.error(exception: RepositoryException.notFound);
    onProgress?.call(1);
    return RepositoryResult<String>.success(data: 'f_fake_$uploads');
  }

  @override
  Future<RepositoryResult<String>> download({
    required String fileId,
    required String suggestedName,
    int? expectedSize,
    TransferFraction? onProgress,
  }) async => RepositoryResult<String>.success(data: '/tmp/$fileId');

  @override
  Future<void> cancelTransfers() async {}

  @override
  Future<String?> localPathFor({required String fileId, required String suggestedName}) async => null;

  @override
  Future<void> clean() async {}
}

/// A chat source the test scripts, standing in for the server's side of
/// `chat.create` (phase 041). Each create takes the next of [answers]: `ok`, a
/// wire code (`name_taken`, `internal`, ...), `connection` (the channel died
/// before the server saw it) or `lost` (the server made the chat and the
/// answer never came back). With no answers left it is `ok`. Like the server
/// it is idempotent on the id: a repeat gets the chat as the server holds it.
class _ScriptedChats implements ChatRemoteDataSource {
  final List<String> answers = <String>[];

  /// The `chat_id` of every create, in order.
  final List<String?> sentIds = <String?>[];

  /// What the SERVER holds: id -> name.
  final Map<String, String> made = <String, String>{};

  /// Set to answer like a server older than phase 041, which skips the id it
  /// does not know and makes one of its own.
  String? answerWithId;

  void Function()? onCreate;

  @override
  Future<ResponseEntity<ChatWireEntity>> createChat({required String name, String? chatId}) async {
    sentIds.add(chatId);
    onCreate?.call();
    final answer = answers.isEmpty ? 'ok' : answers.removeAt(0);
    final id = answerWithId ?? chatId!;
    switch (answer) {
      case 'ok':
        final stored = made.putIfAbsent(id, () => name);
        return ResponseEntity<ChatWireEntity>(
          success: true,
          data: ChatWireEntity(
            chatId: id,
            name: stored,
            createdAt: 1759600000,
            createdByLabel: 'Anna',
            lastMessagePreview: '',
            lastActivityAt: 1759600000,
          ),
        );
      case 'connection':
        throw RepositoryException.connection;
      case 'lost':
        made.putIfAbsent(id, () => name);
        throw RepositoryException.connection;
      default:
        return ResponseEntity<ChatWireEntity>(
          error: ErrorWireEntity(code: answer, message: answer),
        );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The drain is the only sender in the app, so the properties asserted here —
/// strict order, one pass at a time, remove-after-persist, and a classification
/// that does not retry the unretryable — are the ones a duplicate or a lost
/// message would come from.
@GenerateMocks([MessageRepository])
void main() {
  late MockMessageRepository messages;
  late OutboxRepository outbox;
  late _FakePhase phase;
  late OutboxService service;
  late _FakeFiles files;
  late AttachmentTransferServiceImpl transfers;
  late List<String> sentKeys;
  late List<String> sentChatIds;
  late List<String> sentAttachmentIds;

  /// Fails the SEND without touching the upload — the two are separate steps
  /// now, and a test that cannot tell them apart proves nothing about either.
  late RepositoryException? sendFailure;
  late Map<String, RepositoryException> failures;

  MessageModel echo(String chatId, String text) => MessageModel(
    id: 'srv_$text',
    chatId: chatId,
    authorId: 'me',
    authorLabel: 'Me',
    text: text,
    sentAt: AppClock.now(),
    status: MessageStatus.sent,
  );

  setUp(() async {
    AppClock.freeze(DateTime(2026, 6, 15, 21, 30));
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    await getIt<AppDatabase>().clearEntireDatabase();
    outbox = getIt<OutboxRepository>();
    provideDummy<RepositoryResult<MessageModel>>(RepositoryResult.error(exception: RepositoryException.unknown));

    sentKeys = <String>[];
    sentChatIds = <String>[];
    sentAttachmentIds = <String>[];
    failures = <String, RepositoryException>{};
    sendFailure = null;
    messages = MockMessageRepository();
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#clientMessageId] as String;
      final text = invocation.namedArguments[#text] as String?;
      final attached = invocation.namedArguments[#attachment] as MessageAttachment?;
      sentKeys.add(key);
      sentChatIds.add(invocation.namedArguments[#chatId] as String);
      if (attached != null) sentAttachmentIds.add(attached.id);
      final failure = failures[text] ?? sendFailure;
      if (failure != null) return RepositoryResult<MessageModel>.error(exception: failure);
      return RepositoryResult<MessageModel>.success(data: echo(invocation.namedArguments[#chatId] as String, text ?? ''));
    });

    files = _FakeFiles();
    transfers = AttachmentTransferServiceImpl();
    phase = _FakePhase(SessionPhase.live);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
  });

  tearDown(() async {
    await service.stop();
    await phase.dispose();
    AppClock.reset();
    await getIt.reset();
  });

  Future<List<String>> enqueue(List<String> texts) async {
    final keys = <String>[];
    for (final text in texts) {
      keys.add((await outbox.enqueue(chatId: 'c1', text: text)).data!.clientMessageId);
    }
    return keys;
  }

  test('the queue is drained strictly in order, and each accepted send leaves it', () async {
    // Ten, not two: order is only interesting once it could plausibly scramble.
    final texts = [for (var i = 0; i < 10; i++) 'm$i'];
    final keys = await enqueue(texts);

    await service.flush();

    expect(sentKeys, keys); // same order they were written in
    expect(await outbox.pending(), isEmpty);
  });

  test('two flushes at once do not send anything twice', () async {
    // A connectivity flap plus a fresh send is exactly this shape, and it is
    // what double-posted before the drain was serialised.
    await enqueue(['a', 'b']);

    await Future.wait([service.flush(), service.flush(), service.flush()]);

    expect(sentKeys.toSet(), hasLength(2));
    expect(sentKeys, hasLength(2));
  });

  test('a retryable refusal stops the pass so the queue cannot arrive out of order', () async {
    failures['b'] = RepositoryException.connection;
    final keys = await enqueue(['a', 'b', 'c']);

    await service.flush();

    // 'c' must NOT overtake the message stuck in front of it.
    expect(sentKeys, [keys[0], keys[1]]);
    final still = await outbox.pending();
    expect(still.map((e) => e.text), ['b', 'c']);
    expect(still.first.attempts, 1);
  });

  test('a refusal a retry cannot fix is marked and the pass continues past it', () async {
    // Otherwise one oversized message holds every later message hostage.
    failures['b'] = RepositoryException.payloadTooLarge;
    await enqueue(['a', 'b', 'c']);

    await service.flush();

    expect(sentKeys, hasLength(3));
    final left = await outbox.watchQueue().first;
    expect(left.single.text, 'b');
    expect(left.single.status, OutboxStatus.error);
    expect(await outbox.pending(), isEmpty); // nothing retries it on its own
  });

  test('an unrecognised failure is retried rather than declared dead', () async {
    // Same rule the contract applies to unknown error codes: guessing "give up"
    // would silently drop a message the user believes they sent.
    failures['a'] = RepositoryException.unknown;
    await enqueue(['a']);

    await service.flush();

    expect((await outbox.pending()).single.status, OutboxStatus.pending);
  });

  test('nothing is sent while the channel is down, and the attempt is not burned', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    await enqueue(['a']);

    await service.flush();

    expect(sentKeys, isEmpty);
    // No failed attempt was recorded, so the backoff does not grow for a reason
    // that has nothing to do with the message.
    expect((await outbox.pending()).single.attempts, 0);
  });

  test('catching up is not live: the drain waits for the replay to finish', () async {
    phase = _FakePhase(SessionPhase.catchingUp);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    await enqueue(['a']);

    await service.flush();

    expect(sentKeys, isEmpty);
  });

  test('a refused server holds the queue and marks nothing as failed', () async {
    // The gate itself already exists - the drain keys on `isCurrent` - and that
    // is exactly why it has to be locked down: it holds only because the new
    // phase is not the live one, which a later edit could undo without ever
    // touching this file.
    //
    // What must NOT happen is the other half: a message marked `error` here
    // would be a message the person is told failed, over a server that never
    // saw it. Their text waits; it is not lost and it is not blamed on them.
    phase = _FakePhase(SessionPhase.serverMismatch);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    await enqueue(['a', 'b']);

    await service.flush();

    expect(sentKeys, isEmpty, reason: 'nothing may go to a machine that failed to prove who it is');
    final pending = await outbox.pending();
    expect(pending, hasLength(2), reason: 'both messages are still queued');
    for (final entry in pending) {
      expect(entry.attempts, 0, reason: 'no attempt was made, so none may be counted against the message');
      expect(entry.refusals, 0, reason: 'the server refused nothing - it never answered');
    }
  });

  test('a refused server drains nothing even when the phase arrives while running', () async {
    // Mutation of the case above: the drain is started live, then the refusal
    // arrives. A pass triggered by that transition would send into the very
    // machine the refusal is about.
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    service.start();
    await enqueue(['a']);

    phase.emit(SessionPhase.serverMismatch);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, isEmpty);
    expect((await outbox.pending()).single.attempts, 0);
  });

  test('the channel going live drains the queue with no one asking', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    service.start();
    await enqueue(['written while offline']);

    phase.emit(SessionPhase.live);
    for (var i = 0; i < 100 && sentKeys.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(1));
    expect(await outbox.pending(), isEmpty);
  });

  test('a message written while the path comes up waits for it and goes out once (FR-023)', () async {
    // Through Tor the path can take the better part of two minutes to come up.
    // The queue neither tries early - which would only grow the backoff - nor
    // counts the wait against the message; it goes out on the live edge, once.
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    service.start();
    await enqueue(['written during the bring-up']);

    for (final step in [SessionPhase.connecting, SessionPhase.disconnected, SessionPhase.connecting, SessionPhase.catchingUp]) {
      phase.emit(step);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(sentKeys, isEmpty, reason: 'not before the path is up and caught up');
    expect((await outbox.pending()).single.attempts, 0, reason: 'waiting is not an attempt');

    phase.emit(SessionPhase.live);
    for (var i = 0; i < 100 && sentKeys.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(1));
    expect(await outbox.pending(), isEmpty);
  });

  test('start() twice does not open a second subscription (one live edge, one drain)', () async {
    phase = _FakePhase(SessionPhase.disconnected);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    service.start();
    service.start();
    await enqueue(['once']);

    phase.emit(SessionPhase.live);
    for (var i = 0; i < 100 && sentKeys.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(1));
  });

  test('a pass that blows up does not end sending for the life of the process', () async {
    // `_queue.then(...)` on a rejected future stays rejected forever, so an
    // unabsorbed throw would silently stop every later drain — the same shape
    // as the halt that once silenced event sync.
    await enqueue(['a']);
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenThrow(StateError('the store blew up mid-pass'));

    await service.flush();
    expect(await outbox.pending(), hasLength(1)); // nothing was sent, nothing was lost

    // The next trigger has to get a real attempt.
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      sentKeys.add(invocation.namedArguments[#clientMessageId] as String);
      return RepositoryResult<MessageModel>.success(data: echo('c1', 'a'));
    });

    await service.flush();
    expect(sentKeys, hasLength(1));
    expect(await outbox.pending(), isEmpty);
  });

  group('attachments', () {
    late File source;

    setUp(() async {
      source = File('${Directory.systemTemp.path}/nox_outbox_${DateTime.now().microsecondsSinceEpoch}.png')
        ..writeAsBytesSync(List<int>.filled(64, 7));
      addTearDown(() => source.existsSync() ? source.deleteSync() : null);
    });

    MessageAttachment picked() => MessageAttachment(
      id: 'att_local',
      type: FileType.image,
      name: 'shot.png',
      sizeBytes: 64,
      mime: 'image/png',
      localPath: source.path,
    );

    test('the bytes go up before the message names them, and the id is remembered', () async {
      final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;

      await service.flush();

      // The message went out naming the SERVER's id, not the composer's local
      // draft id — the latter means nothing to anyone else.
      expect(sentAttachmentIds.single, isNot('att_local'));
      expect(sentAttachmentIds.single, startsWith('f_'));
      expect(files.uploads, 1);
      expect(await outbox.pending(), isEmpty);
      expect(entry.fileId, isNull, reason: 'the snapshot taken at enqueue knew nothing yet');
    });

    test('a confirmed upload is not repeated when the send is retried', () async {
      // The whole point of remembering the id: a crash between the transfer and
      // the send must not push the bytes again.
      service.start(); // a live edge is what lifts the backoff pause between passes
      await outbox.enqueue(chatId: 'c1', text: null, attachment: picked());

      // First pass: the bytes go up, then the send fails retryably.
      sendFailure = RepositoryException.connection;
      await service.flush();
      expect(files.uploads, 1);
      expect((await outbox.pending()).single.fileId, isNotNull, reason: 'the confirmed id is remembered');

      // Second pass: the send works this time.
      sendFailure = null;
      phase.emit(SessionPhase.live);
      await service.flush();

      expect(files.uploads, 1, reason: 'the bytes were already there — do not push them again');
      expect(await outbox.pending(), isEmpty);
    });

    test('a file that vanished from disk fails this message and lets the queue move on', () async {
      await outbox.enqueue(chatId: 'c1', text: null, attachment: picked());
      final behind = (await outbox.enqueue(chatId: 'c1', text: 'behind it')).data!;
      source.deleteSync(); // the user cleared their photos between attach and drain

      await service.flush();

      final left = await outbox.watchQueue().first;
      expect(left.single.status, OutboxStatus.error);
      expect(sentKeys, contains(behind.clientMessageId), reason: 'one bad attachment must not hold the queue');
    });

    test('a file being sent is a transfer from before its first byte until the server has the message', () async {
      // Without it the bubble of a picture taking a minute through Tor looked
      // exactly like a text that goes in a blink: a small clock, nothing else.
      final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
      AttachmentTransfer? beforeBytes;
      AttachmentTransfer? whileSending;
      files.duringUpload = () async => beforeBytes = transfers.current[entry.clientMessageId];
      when(
        messages.sendMessage(
          chatId: anyNamed('chatId'),
          clientMessageId: anyNamed('clientMessageId'),
          text: anyNamed('text'),
          attachment: anyNamed('attachment'),
        ),
      ).thenAnswer((_) async {
        whileSending = transfers.current[entry.clientMessageId];
        return RepositoryResult<MessageModel>.success(data: echo('c1', ''));
      });

      await service.flush();

      expect(beforeBytes, const AttachmentTransfer(chatId: 'c1', direction: TransferDirection.upload));
      // The bytes are all up (the fake reports the whole file) while the
      // message itself is still on its way: the ring stays, full.
      expect(whileSending?.percent, 100);
      expect(transfers.current, isEmpty, reason: 'nothing is moving once the server has the message');
    });

    test('a failed upload ends its transfer, so the bubble stops claiming bytes are moving', () async {
      await outbox.enqueue(chatId: 'c1', text: null, attachment: picked());
      files.failure = RepositoryException.connection;

      await service.flush();

      expect(await outbox.pending(), hasLength(1), reason: 'still queued, to be tried again');
      expect(transfers.current, isEmpty);
    });

    test('a text is never a transfer', () async {
      final published = <Map<String, AttachmentTransfer>>[];
      final subscription = transfers.watch().listen(published.add);
      addTearDown(subscription.cancel);
      await outbox.enqueue(chatId: 'c1', text: 'just words');

      await service.flush();
      await pumpEventQueue();

      expect(sentKeys, hasLength(1));
      expect(published.every((m) => m.isEmpty), isTrue);
    });

    test('a message discarded during the upload is not sent', () async {
      // Phase 027 re-reads right before sending so a discard is honoured; an
      // upload stretches that window from milliseconds to minutes.
      final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
      files.duringUpload = () async => outbox.remove(clientMessageId: entry.clientMessageId);

      await service.flush();

      expect(sentKeys, isEmpty, reason: 'the bytes may be up, but no message may name them');
      expect(await outbox.pending(), isEmpty);
    });

    group('an upload the server holds part of (phase 043)', () {
      final handle = UnfinishedUpload(fileId: 'f_77', sourceSize: 64, sourceModifiedAt: DateTime.utc(2026, 10, 5, 9, 30));

      Matcher sameAs(UnfinishedUpload expected) => isA<UnfinishedUpload>()
          .having((u) => u.fileId, 'fileId', expected.fileId)
          .having((u) => u.sourceSize, 'sourceSize', expected.sourceSize)
          .having((u) => u.sourceModifiedAt.isAtSameMomentAs(expected.sourceModifiedAt), 'same moment', isTrue);

      test('the stored upload is handed to the repository to go on from', () async {
        final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
        await outbox.noteUpload(clientMessageId: entry.clientMessageId, upload: handle);

        await service.flush();

        expect(files.continuedFrom.single, sameAs(handle));
      });

      test('the upload the server names is written down before the bytes go', () async {
        final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
        files.names = handle;
        UnfinishedUpload? onRecordWhileSending;
        files.duringUpload = () async => onRecordWhileSending = (await outbox.find(clientMessageId: entry.clientMessageId))?.upload;
        files.failure = RepositoryException.connection; // and then the link breaks

        await service.flush();

        expect(onRecordWhileSending, sameAs(handle), reason: 'a restart in the middle has to find it');
        expect((await outbox.find(clientMessageId: entry.clientMessageId))!.upload, sameAs(handle));
      });

      test('a restart goes on from the stored upload instead of declaring the file again', () async {
        await outbox.enqueue(chatId: 'c1', text: null, attachment: picked());
        files.names = handle;
        files.failure = RepositoryException.connection;
        await service.flush();
        await service.stop();

        // A new process: a fresh queue over the same store.
        files
          ..names = null
          ..failure = null;
        service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
        await service.flush();

        expect(files.continuedFrom.last, sameAs(handle), reason: 'what the server has is not sent again (FR-003)');
        expect(await outbox.pending(), isEmpty);
      });

      test('a source that vanished or changed fails the message and forgets the upload', () async {
        final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
        await outbox.noteUpload(clientMessageId: entry.clientMessageId, upload: handle);
        files.failure = RepositoryException.notFound;

        await service.flush();

        final left = (await outbox.watchQueue().first).single;
        expect(left.status, OutboxStatus.error);
        expect(left.upload, isNull, reason: 'a manual retry then sends the file as it is now, as a new upload');
      });

      test('a broken link keeps the upload for the next attempt', () async {
        final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
        await outbox.noteUpload(clientMessageId: entry.clientMessageId, upload: handle);
        files.failure = RepositoryException.connection;

        await service.flush();

        expect((await outbox.pending()).single.upload, sameAs(handle));
      });

      test('confirmed bytes forget the upload: only the message is left to send', () async {
        final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
        await outbox.noteUpload(clientMessageId: entry.clientMessageId, upload: handle);
        sendFailure = RepositoryException.connection; // the message itself waits

        await service.flush();

        final left = (await outbox.pending()).single;
        expect(left.fileId, isNotNull);
        expect(left.upload, isNull);
      });

      test('the bubble shows what the server already has as soon as it says so, not zero', () async {
        final entry = (await outbox.enqueue(chatId: 'c1', text: null, attachment: picked())).data!;
        files.alreadyThere = 0.45;
        AttachmentTransfer? whileGoing;
        files.duringUpload = () async => whileGoing = transfers.current[entry.clientMessageId];

        await service.flush();

        expect(whileGoing?.percent, 45, reason: 'FR-012: the share of the whole file');
      });
    });
  });

  test('messages for chats nobody has open are sent all the same', () async {
    // The drain lives in the data layer precisely so that leaving the screen —
    // or never opening it — does not strand a message. No bloc exists in this
    // file at all, which is the point.
    final a = (await outbox.enqueue(chatId: 'chat_a', text: 'to a')).data!;
    final b = (await outbox.enqueue(chatId: 'chat_b', text: 'to b')).data!;

    await service.flush();

    expect(sentKeys, [a.clientMessageId, b.clientMessageId]);
    expect(await outbox.pending(), isEmpty);
  });

  test('stop() does not return while a send is in flight — logout must not wipe underneath a write', () async {
    // Hold the send open so "in flight" is a fact of the test, not a hope about
    // timing: the earlier version of this test passed even with the await in
    // stop() deleted, because the pass finished on its own first.
    final held = Completer<void>();
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      sentKeys.add(invocation.namedArguments[#clientMessageId] as String);
      await held.future;
      return RepositoryResult<MessageModel>.success(data: echo('c1', 'held'));
    });
    await enqueue(['held']);

    unawaited(service.flush());
    await Future<void>.delayed(const Duration(milliseconds: 20)); // let the send start
    expect(sentKeys, hasLength(1)); // precondition: we are inside sendMessage

    var stopped = false;
    final stopping = service.stop().then((_) => stopped = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(stopped, isFalse, reason: 'stop() must not return while a write is still running');

    held.complete();
    await stopping;

    expect(stopped, isTrue);
    // The write finished before stop() returned, so the caller may now wipe.
    expect(await outbox.pending(), isEmpty);
  });

  test('a pass that has not started yet is abandoned by stop(), not sent into a wipe', () async {
    await enqueue(['a']);

    await service.stop();
    await service.flush(); // whatever was chained must not send now

    expect(sentKeys, isEmpty);
    // Nothing lost: the entry is still queued for whoever starts the drain next.
    expect(await outbox.pending(), hasLength(1));
  });

  test('a retryable refusal actually pauses: an immediate flush does not re-hit the head', () async {
    // Without the pause, every other trigger — a fresh send, a reconnect —
    // retries the stuck head at once, which makes the backoff decorative and
    // inflates the attempt count for a reason that has nothing to do with the
    // server.
    failures['a'] = RepositoryException.connection;
    await enqueue(['a']);

    await service.flush();
    expect(sentKeys, hasLength(1));

    await service.flush();
    await service.flush();
    expect(sentKeys, hasLength(1), reason: 'the pause has to hold against other triggers');
    expect((await outbox.pending()).single.attempts, 1, reason: 'and it must not inflate the count');
  });

  test('the pause is lifted by the channel coming back, and the retry then goes out', () async {
    failures['a'] = RepositoryException.connection;
    files = _FakeFiles();
    transfers = AttachmentTransferServiceImpl();
    phase = _FakePhase(SessionPhase.live);
    service = OutboxService(outbox, messages, phase, files, transfers, getIt<ChatRepository>());
    service.start();
    await enqueue(['a']);

    await service.flush();
    expect(sentKeys, hasLength(1));

    failures.clear(); // the server is back
    phase.emit(SessionPhase.live); // a fresh live edge is a new reason to try
    for (var i = 0; i < 100 && sentKeys.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(sentKeys, hasLength(2));
    expect(sentKeys.first, sentKeys.last, reason: 'the retry must carry the SAME idempotency key');
    expect(await outbox.pending(), isEmpty);
  });

  test('a message the server keeps refusing retryably stops holding the queue', () async {
    // The spec's edge case: something that will never go must not occupy the
    // line forever. Set aside is not discarded — it stays, visible, retryable.
    failures['stuck'] = RepositoryException.internal; // the SERVER keeps refusing it
    service.start(); // a live edge lifts the backoff pause, which is what drives the retries
    final keys = await enqueue(['stuck', 'behind it']);

    for (var i = 0; i < 20 && (await outbox.pending()).isNotEmpty; i++) {
      phase.emit(SessionPhase.live);
      await service.flush();
    }

    final left = await outbox.watchQueue().first;
    expect(left.single.text, 'stuck');
    expect(left.single.status, OutboxStatus.error);
    expect(left.single.refusals, 10); // the ladder is spent by refusals, and only by them
    expect(sentKeys.where((k) => k == keys[0]), hasLength(10));
    // And the message behind it got out rather than waiting forever.
    expect(sentKeys, contains(keys[1]));
    expect(await outbox.pending(), isEmpty);
  });

  test('a flapping link never sets a message aside — a dead channel is not a refusal', () async {
    // The cap exists for a server that keeps saying no, not for a bad tunnel.
    // Counting connection failures would strand a perfectly good message within
    // seconds of a train going through one.
    failures['on my way'] = RepositoryException.connection;
    service.start();
    await enqueue(['on my way']);

    for (var i = 0; i < 25; i++) {
      phase.emit(SessionPhase.live); // each reconnect lifts the pause and buys an attempt
      await service.flush();
    }

    final entry = (await outbox.pending()).single;
    expect(entry.status, OutboxStatus.pending, reason: 'the network is not the message\'s fault');
    expect(entry.refusals, 0);
    expect(entry.attempts, greaterThan(10)); // it kept trying, as it must

    failures.clear();
    phase.emit(SessionPhase.live);
    await service.flush();
    expect(await outbox.pending(), isEmpty); // and it goes as soon as the link holds
  });

  test('a manual retry replenishes the ladder rather than being a single shot', () async {
    failures['stuck'] = RepositoryException.internal;
    service.start();
    final keys = await enqueue(['stuck']);
    for (var i = 0; i < 20 && (await outbox.pending()).isNotEmpty; i++) {
      phase.emit(SessionPhase.live);
      await service.flush();
    }
    expect((await outbox.watchQueue().first).single.status, OutboxStatus.error);
    final spent = sentKeys.length;

    // The user taps Retry. That has to mean "start over", not "one more try":
    // keeping the spent counters makes every later tap fail straight back.
    await outbox.markPending(clientMessageId: keys[0]);
    final requeued = (await outbox.pending()).single;
    expect(requeued.refusals, 0);
    expect(requeued.attempts, 0);

    for (var i = 0; i < 20 && (await outbox.pending()).isNotEmpty; i++) {
      phase.emit(SessionPhase.live);
      await service.flush();
    }
    expect(sentKeys.length - spent, 10, reason: 'a full ladder, not one attempt');
  });

  test('a pause dies with the entry that caused it — a discarded head does not hold the queue', () async {
    // The pause is keyed to one entry. A bare flag would keep every later
    // message waiting on a record that no longer exists.
    failures['head'] = RepositoryException.internal;
    final keys = await enqueue(['head']);
    await service.flush();
    expect((await outbox.pending()).single.attempts, 1); // paused now

    await outbox.remove(clientMessageId: keys[0]); // the user discards it
    final fresh = (await outbox.enqueue(chatId: 'c1', text: 'sent right after')).data!;
    await service.flush();

    expect(sentKeys, contains(fresh.clientMessageId), reason: 'a pause must not outlive its reason');
    expect(await outbox.pending(), isEmpty);
  });

  test('a discard landing mid-pass is honoured — the message is not sent', () async {
    // A pass spans as long as the sends ahead of an entry take. Anything the
    // user cancels in that window is gone from the store, and sending it anyway
    // publishes, permanently, a message they were shown had been cancelled.
    final keys = await enqueue(['first', 'second']);
    when(
      messages.sendMessage(
        chatId: anyNamed('chatId'),
        clientMessageId: anyNamed('clientMessageId'),
        text: anyNamed('text'),
        attachment: anyNamed('attachment'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#clientMessageId] as String;
      sentKeys.add(key);
      // While the first send is in flight, the user discards the second.
      if (key == keys[0]) await outbox.remove(clientMessageId: keys[1]);
      return RepositoryResult<MessageModel>.success(data: echo('c1', 'x'));
    });

    await service.flush();

    expect(sentKeys, [keys[0]]);
    expect(await outbox.pending(), isEmpty);
  });

  group('a chat created on this device (phase 041)', () {
    late _ScriptedChats server;
    late ChatRepository chats;

    setUp(() {
      server = _ScriptedChats();
      chats = ChatRepositoryImpl(
        getIt<ChatDao>(),
        server,
        getIt<ChatMapper>(),
        getIt<ChatWireMapper>(),
        getIt<MessageRepository>(),
        getIt<MessageDao>(),
        getIt<SessionRepository>(),
      );
      service = OutboxService(outbox, messages, phase, files, transfers, chats);
    });

    Future<ChatModel> createHere(String name) async => (await chats.createChat(name: name)).data!;

    Future<String> write(String chatId, String text) async => (await outbox.enqueue(chatId: chatId, text: text)).data!.clientMessageId;

    /// The stored creation state: `pending`, `name_taken`, `failed`, or null
    /// once the server has the chat.
    Future<String?> creationOf(String chatId) async => (await getIt<ChatDao>().getById(chatId))?.creation;

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('the chat reaches the server before any of its messages, which then go in order in the same pass', () async {
      final chat = await createHere('Kitchen');
      final keys = [await write(chat.id, 'one'), await write(chat.id, 'two')];
      final sentBeforeCreate = <int>[];
      server.onCreate = () => sentBeforeCreate.add(sentKeys.length);

      await service.flush();

      expect(server.sentIds, [chat.id], reason: 'the id the device minted, so nothing has to be renamed');
      expect(sentBeforeCreate, [0], reason: 'no message may name a chat the server does not have');
      expect(sentKeys, keys);
      expect(sentChatIds.toSet(), {chat.id});
      expect(await creationOf(chat.id), isNull);
      expect(await outbox.pending(), isEmpty);
    });

    test('the messages of a chat still waiting are held without an attempt, and other chats go on', () async {
      server.answers.add('internal');
      final chat = await createHere('Kitchen');
      final held = await write(chat.id, 'held');
      final other = await write('c1', 'to a chat the server has');

      await service.flush();

      expect(sentKeys, [other], reason: 'one chat the server will not make yet must not hold every other chat');
      final entry = (await outbox.find(clientMessageId: held))!;
      expect(entry.status, OutboxStatus.pending, reason: 'waiting, not failed');
      expect(entry.attempts, 0, reason: 'nobody tried to send it');
      expect(entry.refusals, 0);
    });

    test('a retryable failure keeps the chat waiting, counts the attempt and pauses it', () async {
      service.start();
      server.answers.add('internal');
      final chat = await createHere('Kitchen');
      await write(chat.id, 'held');

      await service.flush();
      expect(await creationOf(chat.id), 'pending');
      expect((await chats.pendingCreations()).single.attempts, 1);

      await service.flush();
      await service.flush();
      expect(server.sentIds, hasLength(1), reason: 'the pause holds against other triggers');

      phase.emit(SessionPhase.live); // a fresh channel is a new reason to try
      await until(() => sentKeys.isNotEmpty);

      expect(server.sentIds, hasLength(2));
      expect(await creationOf(chat.id), isNull);
      expect(sentKeys, hasLength(1));
    });

    test('the pause ends on its own, with nothing else to wake the queue', () async {
      server.answers.add('internal');
      final chat = await createHere('Kitchen');

      await service.flush();
      expect(server.sentIds, hasLength(1));

      // The first rung of the ladder is a second, give or take a fifth.
      for (var i = 0; i < 60 && server.sentIds.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(server.sentIds, hasLength(2));
      expect(await creationOf(chat.id), isNull);
    });

    test('a restart picks a waiting chat up and carries its attempts on', () async {
      server.answers.add('internal');
      final chat = await createHere('Kitchen');
      final key = await write(chat.id, 'after the restart');
      await service.flush();
      expect((await chats.pendingCreations()).single.attempts, 1, reason: 'counted on the row, not in memory');

      // The process restarts: the pause was in memory and is gone with it.
      await service.stop();
      service = OutboxService(outbox, messages, phase, files, transfers, chats);
      await service.flush();

      expect(server.sentIds, [chat.id, chat.id]);
      expect(sentKeys, [key]);
      expect(await creationOf(chat.id), isNull);
    });

    test('`name_taken` marks the chat and holds its messages, and nothing is tried again', () async {
      server.answers.add('name_taken');
      final chat = await createHere('Kitchen');
      final key = await write(chat.id, 'held');

      await service.flush();
      await service.flush();

      expect(server.sentIds, hasLength(1), reason: 'only a rename puts it back in line');
      expect(await creationOf(chat.id), 'name_taken');
      final entry = (await outbox.find(clientMessageId: key))!;
      expect(entry.status, OutboxStatus.pending, reason: 'the message waits, it did not fail');
      expect(entry.attempts, 0);
      expect(sentKeys, isEmpty);
    });

    test('a rename after `name_taken` creates the chat under the new name, then its messages go', () async {
      server.answers.add('name_taken');
      final chat = await createHere('Kitchen');
      final key = await write(chat.id, 'held');
      await service.flush();

      await chats.updateChatName(chatId: chat.id, name: 'Kitchen 2');
      await service.flush();

      expect(server.made, {chat.id: 'Kitchen 2'});
      expect(sentKeys, [key]);
      expect(await creationOf(chat.id), isNull);
    });

    test('a refusal no retry can change marks the chat failed, and Try again creates it', () async {
      server.answers.add('invalid_request');
      final chat = await createHere('Kitchen');
      final key = await write(chat.id, 'held');

      await service.flush();
      await service.flush();
      expect(await creationOf(chat.id), 'failed');
      expect(server.sentIds, hasLength(1), reason: 'a refusal like this one is not retried on its own');
      expect(sentKeys, isEmpty);

      await chats.retryCreation(chatId: chat.id);
      await service.flush();

      expect(await creationOf(chat.id), isNull);
      expect(sentKeys, [key]);
    });

    test('a server that keeps refusing sets the chat aside after the same ladder as a message', () async {
      service.start();
      server.answers.addAll(List<String>.filled(20, 'internal'));
      final chat = await createHere('Kitchen');

      for (var i = 0; i < 20 && (await chats.pendingCreations()).isNotEmpty; i++) {
        phase.emit(SessionPhase.live);
        await service.flush();
      }

      expect(await creationOf(chat.id), 'failed');
      expect(server.sentIds, hasLength(10));
    });

    test('a flapping link never sets a chat aside - a dead channel is not a refusal', () async {
      service.start();
      server.answers.addAll(List<String>.filled(25, 'connection'));
      final chat = await createHere('Kitchen');

      for (var i = 0; i < 25; i++) {
        phase.emit(SessionPhase.live);
        await service.flush();
      }

      expect(await creationOf(chat.id), 'pending');
      expect((await chats.pendingCreations()).single.attempts, greaterThan(10));
    });

    test('an answer lost on the way: the repeat gets the same chat, and the device ends with one', () async {
      service.start();
      server.answers.add('lost');
      final chat = await createHere('Kitchen');
      final key = await write(chat.id, 'after the loss');

      await service.flush();
      expect(server.made, {chat.id: 'Kitchen'}, reason: 'the server made it');
      expect(await creationOf(chat.id), 'pending', reason: 'the device never heard');

      phase.emit(SessionPhase.live);
      await until(() => sentKeys.isNotEmpty);

      expect(server.sentIds, [chat.id, chat.id]);
      expect(server.made, hasLength(1));
      final kitchens = (await getIt<ChatDao>().getAllSorted()).where((c) => c.name == 'Kitchen');
      expect(kitchens.single.id, chat.id);
      expect(sentKeys, [key]);
    });

    test('the server\'s own event arriving before the repeat settles the chat, and it is not created again', () async {
      server.answers.add('lost');
      final chat = await createHere('Kitchen');
      final key = await write(chat.id, 'held');
      await service.flush();

      // `chat.created` reaches the device first - written as SyncService
      // writes a chat from the wire, which knows nothing of a creation state.
      await getIt<ChatDao>().upsert(getIt<ChatMapper>().toEntity(model: chat.copyWith(creation: null), lastOpenedSeq: null));
      await service.flush();

      expect(server.sentIds, hasLength(1), reason: 'the server already said it has the chat');
      expect(sentKeys, [key]);
    });

    test('a server older than phase 041 answers with its own id: one chat under it, the messages moved there', () async {
      server.answerWithId = 'c_0123456789abcdef';
      final chat = await createHere('Kitchen');
      final keys = [await write(chat.id, 'one'), await write(chat.id, 'two')];

      await service.flush();

      expect(sentKeys, keys);
      expect(sentChatIds, ['c_0123456789abcdef', 'c_0123456789abcdef']);
      expect(await getIt<ChatDao>().getById(chat.id), isNull, reason: 'the local copy is gone');
      expect(await getIt<MessageDao>().getById('${chat.id}_sys'), isNull, reason: 'and its "Chat created by" line with it');
      expect(await creationOf('c_0123456789abcdef'), isNull);
      expect((await getIt<ChatDao>().getAllSorted()).where((c) => c.name == 'Kitchen'), hasLength(1));
    });

    test('a stopped queue creates nothing', () async {
      final chat = await createHere('Kitchen');

      await service.stop();
      await service.flush();

      expect(server.sentIds, isEmpty);
      expect(await creationOf(chat.id), 'pending', reason: 'still waiting for whoever starts the queue next');
    });
  });
}

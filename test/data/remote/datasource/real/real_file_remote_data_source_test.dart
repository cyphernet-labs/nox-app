import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/local/app_data_root.dart';
import 'package:nox_app/data/local/chat/outbox_copies.dart';
import 'package:nox_app/data/local/device_vault.dart';
import 'package:nox_app/data/local/sealed_file.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_file_remote_data_source.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/repository/file/file_repository_impl.dart';
import 'package:nox_app/data/repository/log_repository_impl.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/file/unfinished_upload.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/log_repository.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_tor/channel.dart' show channelWindowBytes;
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/file/transfer_cancellation.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_tor/vault.dart';

import '../../../../utils/fake_session_repository.dart';
import '../../channel/fake_channel.dart';

/// The byte half of the file chain against a real HTTP server, over the
/// channel client (phase 043, phase 044): what goes on the wire when a
/// transfer is continued, what each answer means, and that only silence -
/// never time alone - ends a transfer. The channels are loopback TCP to the
/// address each request names; the module's TLS and check are its own tests'.
ChannelHttpClient _channels([LoopbackChannelApi? api]) =>
    ChannelHttpClient(api ?? LoopbackChannelApi())
      ..bind(serverKey: Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i)), deviceSeed: Uint8List(32));

class _Config implements AppConfigRepository {
  @override
  AppConfig get config => const AppConfig(flavor: AppFlavorType.stage);
  @override
  Future<void> initialize({required AppFlavorType flavorType}) async {}
  @override
  Future<String?> getUserAuthIdToken() async => null;
  @override
  bool get isTestEnvironment => true;
  @override
  ServerLimits get limits => ServerLimits.contractDefaults;
  @override
  void updateLimits(ServerLimits limits) {}
}

/// The socket half, scripted: what each command was sent with, and a reply.
class _FakeSocket implements NoxSocketClient {
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
  Map<String, dynamic> reply = <String, dynamic>{};

  @override
  Future<CommandReply> send(String cmd, Map<String, dynamic> data, {bool waitForConnection = true}) async {
    sent.add(data);
    return CommandReply(id: sent.length, ok: true, data: reply);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The server's side of a PUT.
class _PutServer {
  late HttpServer _server;
  int get port => _server.port;

  /// What to answer once the body is in.
  int status = HttpStatus.noContent;

  /// Never read the body: a path that went dead under the transfer.
  bool stopReading = false;

  /// Read the body slowly, at this many bytes a second - paced by the bytes
  /// rather than by the chunks, whose size the transport decides.
  int? bytesPerSecond;

  /// Go quiet for [quietFor] once this many bytes are in - the tail still in
  /// the buffers, the way a slow path holds it.
  int? quietAfter;
  Duration quietFor = Duration.zero;

  final List<int> received = <int>[];
  int? contentLength;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      contentLength = request.contentLength;
      if (stopReading) return; // holds the request open, reads nothing
      try {
        var quieted = false;
        await for (final chunk in request) {
          received.addAll(chunk);
          final rate = bytesPerSecond;
          if (rate != null) await Future<void>.delayed(Duration(microseconds: chunk.length * 1000000 ~/ rate));
          final after = quietAfter;
          if (!quieted && after != null && received.length >= after) {
            quieted = true;
            await Future<void>.delayed(quietFor);
          }
        }
        request.response.statusCode = status;
        await request.response.close();
      } on Object {
        // The client went away; nothing to answer.
      }
    });
  }

  Future<void> close() => _server.close(force: true);
}

/// The server's side of a GET, played on the paired machine's certificate:
/// [HttpRequest.response] with Range and If-Range answered the way
/// `http.ServeContent` answers them.
class _GetServer {
  late HttpServer _server;
  int get port => _server.port;

  List<int> file = const <int>[];
  String version = 'Mon, 05 Oct 2026 09:30:00 GMT';

  /// Send this many bytes of the body, then stop - keeping the connection.
  int? stallAfter;

  /// Answer this status instead, with no body.
  int? status;

  /// Send the whole file with no length: chunked, a size nobody can tell.
  bool chunked = false;

  final List<Map<String, String?>> asked = <Map<String, String?>>[];

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final range = request.headers.value('range');
      final ifRange = request.headers.value('if-range');
      asked.add(<String, String?>{'range': range, 'if-range': ifRange});
      final response = request.response;
      final forced = status;
      if (forced != null) {
        response.statusCode = forced;
        await response.close();
        return;
      }
      response.headers.set('last-modified', version);
      var from = 0;
      if (range != null && ifRange == version) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        if (from >= file.length) {
          response
            ..statusCode = HttpStatus.requestedRangeNotSatisfiable
            ..headers.set('content-range', 'bytes */${file.length}');
          await response.close();
          return;
        }
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-range', 'bytes $from-${file.length - 1}/${file.length}');
      }
      final body = file.sublist(from);
      if (!chunked) response.contentLength = body.length;
      final cut = stallAfter;
      if (cut != null) {
        // Unbuffered, or dart:io keeps these bytes back until it has more.
        response.bufferOutput = false;
        if (cut > 0) response.add(body.sublist(0, cut));
        await response.flush();
        return; // never finishes: the path went quiet
      }
      response.add(body);
      await response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

/// The secure store as the vault reads it: one key, always there.
class _KeyStore extends FakeSessionRepository {
  _KeyStore(this.key);

  final String key;

  @override
  Future<RepositoryResult<String?>> storageKey() async => RepositoryResult<String?>.success(data: key);
}

/// [bytes] from [from] on, the way the decrypting reader of a sealed copy hands
/// them over: `Uint8List` chunks out of an `async*` generator. Its runtime type
/// is a `Stream<Uint8List>` - a stream of a SUBTYPE of `List<int>` - which a
/// file's own `openRead()` never is, so no test that read a file saw it.
Stream<Uint8List> _uint8Chunks(List<int> bytes, {int from = 0}) async* {
  for (var at = from; at < bytes.length; at += SealedFile.chunkSize) {
    yield Uint8List.fromList(bytes.sublist(at, min(at + SealedFile.chunkSize, bytes.length)));
  }
}

void main() {
  late HttpOverrides? saved;
  setUpAll(() {
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = saved);
  setUp(() {
    getIt.allowReassignment = true;
    getIt.registerSingleton<LogRepository>(LoggerLogRepository());
  });
  tearDown(getIt.reset);

  late _PutServer server;
  late _FakeSocket socket;
  late ApiClient api;
  late File file;
  late List<int> payload;

  RealFileRemoteDataSource source({Duration stallLimit = const Duration(seconds: 2), Duration answerWait = const Duration(seconds: 10)}) =>
      RealFileRemoteDataSource.forTest(socket, api, stallLimit: stallLimit, answerWait: answerWait);

  Future<void> writePayload(int length) async {
    final random = Random(43);
    payload = List<int>.generate(length, (_) => random.nextInt(256));
    await file.writeAsBytes(payload);
  }

  setUp(() async {
    server = _PutServer();
    await server.start();
    socket = _FakeSocket();
    api = ApiClient(_Config(), _channels())..initBase(address: 'https://127.0.0.1:${server.port}');
    file = File('${Directory.systemTemp.path}/nox_put_${DateTime.now().microsecondsSinceEpoch}.bin');
    await writePayload(64 * 1024);
  });

  tearDown(() async {
    await server.close();
    if (file.existsSync()) file.deleteSync();
  });

  group('uploadBegin', () {
    test('names the upload to continue only when continuing', () async {
      socket.reply = <String, dynamic>{
        'file_id': 'f_77',
        'upload_url': '/files/t',
        'upload_token': 't',
        'max_attachment_bytes': 104857600,
        'received': 4096,
      };

      final fresh = await source().uploadBegin(name: 'a.bin', sizeBytes: 10, mime: 'x/y');
      final continued = await source().uploadBegin(name: 'a.bin', sizeBytes: 10, mime: 'x/y', fileId: 'f_77');

      expect(socket.sent.first.containsKey('file_id'), isFalse, reason: 'an absent field is a new upload');
      expect(socket.sent.last['file_id'], 'f_77');
      expect(socket.sent.last['name'], 'a.bin', reason: 'the declaration stays whole for a server that cannot continue');
      expect(fresh.data?.received, 4096);
      expect(continued.data?.received, 4096);
    });

    test('a server that cannot continue sends no received, and that is read as null', () async {
      socket.reply = <String, dynamic>{'file_id': 'f_1', 'upload_url': '/files/t', 'upload_token': 't', 'max_attachment_bytes': 104857600};

      final ticket = await source().uploadBegin(name: 'a.bin', sizeBytes: 10, mime: 'x/y');

      expect(ticket.data?.received, isNull);
    });
  });

  group('putBytes', () {
    test('sends exactly the bytes from the offset to the end, and says how many', () async {
      final shares = <(int, int)>[];

      await source().putBytes(
        uploadPath: '/files/t',
        size: payload.length,
        offset: 40000,
        body: file.openRead(40000),
        onProgress: (done, total) => shares.add((done, total)),
      );

      expect(server.contentLength, payload.length - 40000);
      expect(server.received, payload.sublist(40000), reason: 'what the server already holds is not sent again (FR-001)');
      expect(shares.first.$1, greaterThanOrEqualTo(40000), reason: 'progress counts the whole file (FR-012)');
      expect(shares.last, (payload.length, payload.length));
    });

    test('nothing left to send is an empty PUT that completes the upload', () async {
      await source().putBytes(uploadPath: '/files/t', size: payload.length, offset: payload.length, body: file.openRead(payload.length));

      expect(server.contentLength, 0);
      expect(server.received, isEmpty);
    });

    for (final (status, failure) in <(int, FileTransferFailure)>[
      (HttpStatus.notFound, FileTransferFailure.passRejected),
      (HttpStatus.requestEntityTooLarge, FileTransferFailure.sizeMismatch),
      (HttpStatus.badRequest, FileTransferFailure.sizeMismatch),
      (HttpStatus.requestTimeout, FileTransferFailure.connection),
      (HttpStatus.conflict, FileTransferFailure.connection),
      // The server answering, not the link breaking: counted towards giving
      // up, or one that answers it every time held the whole queue for good.
      (HttpStatus.internalServerError, FileTransferFailure.serverError),
      (HttpStatus.serviceUnavailable, FileTransferFailure.serverError),
      (HttpStatus.forbidden, FileTransferFailure.serverError),
    ]) {
      test('$status means ${failure.name}', () async {
        server.status = status;

        await expectLater(
          source().putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0)),
          throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', failure)),
        );
        expect(api.transfersUnderWay, 0, reason: 'the transfer is handed back whatever the answer');
      });
    }

    test('a file that is there but cannot be read is the source failing, not the link - and none of it arrives', () async {
      // A sandbox forgets a picked file when the app restarts, and still lets
      // its size be read. Taken for a broken link, the queue retried it - and
      // held everything behind it - for good.
      Process.runSync('chmod', ['000', file.path]);
      addTearDown(() => Process.runSync('chmod', ['644', file.path]));
      try {
        await file.open().then((f) => f.close());
        markTestSkipped('this user can read a file nobody may read');
        return;
      } on FileSystemException {
        // As it should be.
      }

      await expectLater(
        source().putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0)),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.sourceUnreadable)),
      );
      expect(server.received, isEmpty);
      expect(api.transfersUnderWay, 0);
    });

    test('a file gone by the time its bytes are sent is the source failing too, and its path stays here', () async {
      file.deleteSync();

      await expectLater(
        source().putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0)),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.sourceUnreadable)),
      );
    });

    test('a body of Uint8List chunks - what an opened sealed copy is - goes as any other (phase 048)', () async {
      // The type the parameter names is Stream<List<int>>; the stream that
      // arrives can be of a subtype, and wrapping it the wrong way threw a
      // TypeError before a byte went - every file message failed to send.
      final shares = <(int, int)>[];

      await source().putBytes(
        uploadPath: '/files/t',
        size: payload.length,
        offset: 40000,
        body: _uint8Chunks(payload, from: 40000),
        onProgress: (done, total) => shares.add((done, total)),
      );

      expect(server.contentLength, payload.length - 40000);
      expect(server.received, payload.sublist(40000));
      expect(shares.last, (payload.length, payload.length));
      expect(api.transfersUnderWay, 0, reason: 'the transfer is handed back');
    });

    test('a Uint8List body that breaks half-way is the source failing, and the transfer is handed back', () async {
      Stream<Uint8List> breaking() async* {
        yield Uint8List.fromList(payload.sublist(0, 1000));
        throw const SealedFileException(SealedFileError.truncated);
      }

      await expectLater(
        source().putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: breaking()),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.sourceUnreadable)),
      );
      expect(api.transfersUnderWay, 0);
    });

    test('a cancellation ends this one transfer at once, and it is handed back', () async {
      // The message was thrown away: its upload must stop holding the queue
      // now, not when its last byte has gone.
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final cancellation = TransferCancellation();
      final put = source(
        stallLimit: const Duration(minutes: 1),
      ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0), cancellation: cancellation);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();

      cancellation.cancel();

      await expectLater(put, throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(api.transfersUnderWay, 0);
    });

    test('a cancellation that came first sends nothing', () async {
      final cancellation = TransferCancellation()..cancel();

      await expectLater(
        source().putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0), cancellation: cancellation),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)),
      );
      expect(server.contentLength, isNull);
    });

    test('bytes that stop moving end the transfer as a broken connection', () async {
      // A path that went dead under the transfer: nothing reads, and without
      // a watch on silence the PUT would hang until the OS gave up on it.
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final watch = Stopwatch()..start();

      await expectLater(
        source(
          stallLimit: const Duration(milliseconds: 500),
        ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0)),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)),
      );
      // Ended by the stall limit while the body was going out - once the
      // buffers and the window are full - not by the 10 s wait for an answer.
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('a slow transfer that keeps moving is never cut, however long it takes (FR-009)', () async {
      // Two seconds in all at 4 MiB/s, and never a quiet second at a time.
      await writePayload(8 * 1024 * 1024);
      server.bytesPerSecond = 4 * 1024 * 1024;
      final watch = Stopwatch()..start();

      await source(
        stallLimit: const Duration(seconds: 1),
      ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));

      expect(watch.elapsed, greaterThan(const Duration(seconds: 1)), reason: 'it outlasted the stall limit');
      expect(server.received.length, payload.length);
    });

    test('a slow path keeps an upload moving a chunk at a time, though half a window outlasts the stall limit', () async {
      // The path drains 1 MiB/s: a chunk every 62 ms, half a window every
      // 500 ms - longer than the 300 ms stall limit. Progress comes with each
      // chunk the path takes; were the writer let go only at half a window, a
      // healthy slow upload - Tor on a bad day - would be cut as dead.
      await writePayload(3 * 1024 * 1024);
      final channels = LoopbackChannelApi(null, 1024 * 1024);
      final paced = ApiClient(_Config(), _channels(channels))..initBase(address: 'https://127.0.0.1:${server.port}');
      final watch = Stopwatch()..start();

      await RealFileRemoteDataSource.forTest(
        socket,
        paced,
        stallLimit: const Duration(milliseconds: 300),
      ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));

      expect(watch.elapsed, greaterThan(const Duration(seconds: 1)), reason: 'it outlasted the stall limit many times over');
      expect(channels.opened.map((c) => c.peakQueued), contains(greaterThan(channelWindowBytes)), reason: 'the window held it back');
      expect(server.received, payload);
    });

    test('the bytes still draining after the last one is handed over are waited for, not taken for a stall', () async {
      // Handed to the socket is not arrived: the buffers between here and the
      // server drain at the path's pace, and this side sees none of it. Here
      // the server goes quiet for longer than the stall limit while the last
      // 256 KiB - already handed over - still sit in the buffers. Measured
      // against the stall limit, a healthy upload was cut in its last minute.
      await writePayload(4 * 1024 * 1024);
      server
        ..quietAfter = payload.length - 256 * 1024
        ..quietFor = const Duration(seconds: 2);

      await source(
        stallLimit: const Duration(seconds: 1),
        answerWait: const Duration(seconds: 20),
      ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));

      expect(server.received.length, payload.length);
    });

    test('cancelTransfers ends a transfer under way as a broken connection', () async {
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final put = source(
        stallLimit: const Duration(minutes: 1),
      ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      source().cancelTransfers();

      await expectLater(put, throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)));
    });
  });

  /// The queue sends from its own copy of a file, sealed on the disk (phase
  /// 043, phase 048), and reads it through the vault: the upload the person
  /// actually makes, with nothing between the copy and this server but the
  /// real code.
  group("the queue's sealed copy (phase 048)", () {
    final key = base64.encode(List<int>.generate(32, (i) => 0x30 + i));
    // Four chunks: three whole ones and a short last one.
    final plain = List<int>.generate(3 * SealedFile.chunkSize + 3392, (i) => (i * 31 + i ~/ 977) & 0xFF);
    late DeviceVault vault;
    late File picked;
    late File copy;

    setUp(() async {
      vault = DeviceVault(_KeyStore(key));
      picked = File('${Directory.systemTemp.path}/nox_put_picked_${DateTime.now().microsecondsSinceEpoch}.bin')..writeAsBytesSync(plain);
      copy = File((await OutboxCopies(vault).keep(key: 'cmid-1', source: picked.path))!);
    });

    tearDown(() async {
      NoxVault.clear();
      if (picked.existsSync()) picked.deleteSync();
      final copies = Directory(await AppDataRoot.pathOf(AppDataRoot.outboxFolder));
      if (copies.existsSync()) copies.deleteSync(recursive: true);
    });

    FileRepositoryImpl repository() => FileRepositoryImpl(source(), _Config(), vault);

    Map<String, dynamic> ticket({required int received}) => <String, dynamic>{
      'file_id': 'f_9',
      'upload_url': '/files/t',
      'upload_token': 't',
      'max_attachment_bytes': 104857600,
      'received': received,
    };

    test('the copy is sealed, so nothing but the plain bytes opened from it may reach the server', () async {
      expect(await SealedFile.isSealed(copy), isTrue);
      expect(copy.lengthSync(), SealedFile.sealedLength(plain.length));
    });

    test('its plain bytes go from where the server stopped, opened chunk by chunk', () async {
      final reader = (await SealedReader.open(copy))!;

      await source().putBytes(uploadPath: '/files/t', size: reader.length, offset: 70000, body: reader.read(from: 70000));

      expect(server.contentLength, plain.length - 70000);
      expect(server.received, plain.sublist(70000), reason: 'from the middle of a chunk, exactly the rest');
      expect(api.transfersUnderWay, 0);
    });

    test('a chunk that no longer opens ends the upload as the source failing, before anything past it is sent', () async {
      final bytes = copy.readAsBytesSync()..[SealedFile.headerLength + SealedFile.sealedChunkLength + 9] ^= 0x01;
      copy.writeAsBytesSync(bytes);
      final reader = (await SealedReader.open(copy))!;

      await expectLater(
        source().putBytes(uploadPath: '/files/t', size: reader.length, offset: 0, body: reader.read()),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.sourceUnreadable)),
      );
      expect(server.received.length, lessThanOrEqualTo(SealedFile.chunkSize));
      expect(server.received, plain.sublist(0, server.received.length));
      expect(api.transfersUnderWay, 0);
    });

    test('through the repository, the copy reaches the server as the plain file, under its plain length', () async {
      socket.reply = ticket(received: 0);

      final result = await repository().upload(path: copy.path, mime: 'application/octet-stream');

      expect(result.data, 'f_9');
      expect(socket.sent.single['size'], plain.length, reason: 'the server is told the plain length, not the sealed one');
      expect(server.received, plain);
      expect(api.transfersUnderWay, 0);
    });

    test('through the repository, a continued upload sends the plain rest from the middle of a chunk', () async {
      socket.reply = ticket(received: 70000);
      final stat = copy.statSync();
      final from = UnfinishedUpload(
        fileId: 'f_9',
        sourceSize: plain.length,
        sourceModifiedAt: DateTime.fromMillisecondsSinceEpoch(stat.modified.millisecondsSinceEpoch),
      );

      final result = await repository().upload(path: copy.path, mime: 'application/octet-stream', from: from);

      expect(result.data, 'f_9');
      expect(socket.sent.single['file_id'], 'f_9');
      expect(server.received, plain.sublist(70000));
      expect(api.transfersUnderWay, 0);
    });
  });

  group('openBytes', () {
    late _GetServer getServer;
    late ApiClient getApi;

    RealFileRemoteDataSource downloads({Duration stallLimit = const Duration(seconds: 2)}) =>
        RealFileRemoteDataSource.forTest(socket, getApi, stallLimit: stallLimit);

    Future<List<int>> drain(FetchedBytes fetched) async => [await for (final chunk in fetched.bytes) ...chunk];

    setUp(() async {
      getServer = _GetServer()..file = List<int>.generate(1000, (i) => i % 251);
      await getServer.start();
      getApi = ApiClient(_Config(), _channels())..initBase(address: 'https://127.0.0.1:${getServer.port}');
    });

    tearDown(() => getServer.close());

    test('from the start asks for no range and gets the whole file, with its version', () async {
      final fetched = await downloads().openBytes(downloadPath: '/files/t', offset: 0);

      expect(getServer.asked.single, {'range': null, 'if-range': null});
      expect(fetched.whole, isTrue);
      expect(fetched.total, 1000);
      expect(fetched.validator, getServer.version);
      expect(await drain(fetched), getServer.file);
    });

    test('with bytes of the same version here, only the rest comes (FR-006)', () async {
      final fetched = await downloads().openBytes(downloadPath: '/files/t', offset: 600, validator: getServer.version);

      expect(getServer.asked.single, {'range': 'bytes=600-', 'if-range': getServer.version});
      expect(fetched.whole, isFalse);
      expect(fetched.total, 1000, reason: 'the size of the whole file, from Content-Range');
      expect(await drain(fetched), getServer.file.sublist(600));
    });

    test('bytes of another version get the whole file again (FR-007)', () async {
      final fetched = await downloads().openBytes(downloadPath: '/files/t', offset: 600, validator: 'Sun, 04 Oct 2026 09:30:00 GMT');

      expect(fetched.whole, isTrue);
      expect(await drain(fetched), getServer.file);
    });

    test('bytes nobody wrote the version of are not continued: no range is asked for', () async {
      final fetched = await downloads().openBytes(downloadPath: '/files/t', offset: 600);

      expect(getServer.asked.single['range'], isNull);
      expect(fetched.whole, isTrue);
    });

    test('a part no shorter than the file is a stale range', () async {
      await expectLater(
        downloads().openBytes(downloadPath: '/files/t', offset: 1000, validator: getServer.version),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.staleRange)),
      );
    });

    test('a refused pass is passRejected', () async {
      getServer.status = HttpStatus.notFound;

      await expectLater(
        downloads().openBytes(downloadPath: '/files/t', offset: 0),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.passRejected)),
      );
      expect(getApi.transfersUnderWay, 0);
    });

    for (final status in <int>[HttpStatus.internalServerError, HttpStatus.forbidden]) {
      test('$status is the server answering: serverError, counted towards giving up', () async {
        getServer.status = status;

        await expectLater(
          downloads().openBytes(downloadPath: '/files/t', offset: 0),
          throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.serverError)),
        );
        expect(getApi.transfersUnderWay, 0);
      });
    }

    test('a whole file whose size nobody can tell is no use: serverError', () async {
      // Complete only at the size the message names - and here there is no
      // size to hold it to.
      getServer.chunked = true;

      await expectLater(
        downloads().openBytes(downloadPath: '/files/t', offset: 0),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.serverError)),
      );
      expect(getApi.transfersUnderWay, 0);
    });

    test('a body read to its end, or let go unread, hands its transfer back', () async {
      final read = await downloads().openBytes(downloadPath: '/files/t', offset: 0);
      await drain(read);
      expect(getApi.transfersUnderWay, 0);

      final unread = await downloads().openBytes(downloadPath: '/files/t', offset: 0);
      expect(getApi.transfersUnderWay, 1);
      unread.abandon();
      expect(getApi.transfersUnderWay, 0);
    });

    test('a body that goes quiet ends as a broken connection, keeping what came', () async {
      getServer.stallAfter = 300;
      final fetched = await downloads(stallLimit: const Duration(milliseconds: 500)).openBytes(downloadPath: '/files/t', offset: 0);

      final got = <int>[];
      await expectLater(
        fetched.bytes.forEach(got.addAll),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)),
      );
      expect(got, getServer.file.sublist(0, 300));
    });

    test('a body that never sends a byte after its headers ends too - Dio\'s clock would never start', () async {
      // dart:io sends headers only with the first byte of a body, so this one
      // is written by hand: the headers of a 1000-byte file, then nothing.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      final held = <Socket>[];
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
      });
      raw.listen((socket) {
        held.add(socket);
        socket.listen((_) {
          socket.write('HTTP/1.1 200 OK\r\ncontent-length: 1000\r\nlast-modified: ${getServer.version}\r\n\r\n');
        });
      });
      final api = ApiClient(_Config(), _channels())..initBase(address: 'https://127.0.0.1:${raw.port}');

      final fetched = await RealFileRemoteDataSource.forTest(
        socket,
        api,
        stallLimit: const Duration(milliseconds: 500),
      ).openBytes(downloadPath: '/files/t', offset: 0);

      await expectLater(
        fetched.bytes.forEach((_) {}).timeout(const Duration(seconds: 10)),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)),
      );
    });

    test('cancelTransfers ends a body under way as a broken connection', () async {
      getServer.stallAfter = 300;
      final source = downloads(stallLimit: const Duration(minutes: 1));
      final fetched = await source.openBytes(downloadPath: '/files/t', offset: 0);
      final reading = fetched.bytes.forEach((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      source.cancelTransfers();

      await expectLater(reading, throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)));
    });
  });

  group('a change of path (phase 043, FR-008)', () {
    test('a PUT on the old path ends at once when the path changes, and the next one takes the new path', () async {
      // Home -> away: the old connection dies without a word, and only the
      // stall limit would notice it. The new greeting moves REST, and the move
      // ends the transfer there and then.
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final other = _PutServer();
      await other.start();
      addTearDown(other.close);
      final transfers = source(stallLimit: const Duration(minutes: 1));

      final stuck = transfers.putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();
      api.initBase(address: 'https://127.0.0.1:${other.port}');

      // Said as what it is: the caller goes on at once by the new path, where
      // a broken link would first wait out a pause.
      await expectLater(stuck, throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.pathChanged)));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

      await writePayload(1024);
      await transfers.putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));
      expect(other.received, payload, reason: 'the retry went by the new path');
    });

    test('a download on the old path ends at once too', () async {
      final quiet = _GetServer()
        ..file = List<int>.generate(1000, (i) => i % 251)
        ..stallAfter = 100;
      await quiet.start();
      addTearDown(quiet.close);
      final getApi = ApiClient(_Config(), _channels())..initBase(address: 'https://127.0.0.1:${quiet.port}');
      final fetched = await RealFileRemoteDataSource.forTest(
        socket,
        getApi,
        stallLimit: const Duration(minutes: 1),
      ).openBytes(downloadPath: '/files/t', offset: 0);
      final reading = fetched.bytes.forEach((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final watch = Stopwatch()..start();

      getApi.initBase(address: 'https://127.0.0.1:${server.port}');

      await expectLater(
        reading,
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.pathChanged)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a break with the path unchanged is still a broken link, not a change of path', () async {
      // Only a change of path skips the pause; calling every break one would
      // retry a dead link with no pause at all.
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final stuck = source(
        stallLimit: const Duration(minutes: 1),
      ).putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      api.initBase(address: 'https://127.0.0.1:${server.port}'); // the same path, asked for again
      api.cancelTransfers();

      await expectLater(stuck, throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)));
    });
  });

  group('opening a connection through Tor (phase 043)', () {
    /// Records how long each request may take to connect, and goes no further.
    List<Duration?> watchConnects(ApiClient api) {
      final seen = <Duration?>[];
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seen.add(options.connectTimeout);
            handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
          },
        ),
      );
      return seen;
    }

    test('a transfer through the onion service may take as long to connect as the socket does', () async {
      // A new stream to the onion service sometimes fetches its descriptor
      // anew; the socket waits 45 s for that, and a transfer cut at 30 s failed
      // exactly where the socket got through.
      final onion = ApiClient(_Config(), ChannelHttpClient(ScriptedChannelApi()))
        ..initBase(address: 'https://abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion:443');
      final seen = watchConnects(onion);
      final transfers = RealFileRemoteDataSource.forTest(socket, onion);

      await expectLater(
        transfers.putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0)),
        throwsA(isA<FileTransferException>()),
      );
      await expectLater(transfers.openBytes(downloadPath: '/files/t', offset: 0), throwsA(isA<FileTransferException>()));

      expect(seen, [WebSocketChannelFactory.onionConnectTimeout, WebSocketChannelFactory.onionConnectTimeout]);
    });

    test('a transfer at a direct address keeps the default', () async {
      final seen = watchConnects(api);
      final transfers = RealFileRemoteDataSource.forTest(socket, api);

      await expectLater(
        transfers.putBytes(uploadPath: '/files/t', size: payload.length, offset: 0, body: file.openRead(0)),
        throwsA(isA<FileTransferException>()),
      );

      expect(seen.single, api.dio.options.connectTimeout);
    });
  });
}

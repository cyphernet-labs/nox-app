import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/data/remote/datasource/file_remote_data_source.dart';
import 'package:nox_app/data/remote/datasource/real/real_file_remote_data_source.dart';
import 'package:nox_app/data/remote/pinned_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/domain/model/app_config/app_config.dart';
import 'package:nox_app/domain/model/app_config/app_flavor_type.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';

/// The byte half of the file chain against a real TLS server on the paired
/// machine's certificate (phase 043): what goes on the wire when a transfer
/// is continued, what each answer means, and that only silence - never time
/// alone - ends a transfer.
const String _fixtures = 'test/general/pairing/fixtures';

String get _fingerprint => File('$_fixtures/fingerprint.txt').readAsStringSync().trim();

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

/// The server's side of a PUT, played on the paired machine's certificate.
class _PutServer {
  late HttpServer _server;
  int get port => _server.port;

  /// What to answer once the body is in.
  int status = HttpStatus.noContent;

  /// Never read the body: a path that went dead under the transfer.
  bool stopReading = false;

  /// Read the body slowly: a pause after every chunk.
  Duration? pausePerChunk;

  /// Go quiet for [quietFor] once this many bytes are in - the tail still in
  /// the buffers, the way a slow path holds it.
  int? quietAfter;
  Duration quietFor = Duration.zero;

  final List<int> received = <int>[];
  int? contentLength;

  Future<void> start() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(File('$_fixtures/valid.pem').readAsBytesSync())
      ..usePrivateKeyBytes(File('$_fixtures/server_key.pem').readAsBytesSync());
    _server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    _server.listen((request) async {
      contentLength = request.contentLength;
      if (stopReading) return; // holds the request open, reads nothing
      try {
        var quieted = false;
        await for (final chunk in request) {
          received.addAll(chunk);
          final pause = pausePerChunk;
          if (pause != null) await Future<void>.delayed(pause);
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

  final List<Map<String, String?>> asked = <Map<String, String?>>[];

  Future<void> start() async {
    final context = SecurityContext()
      ..useCertificateChainBytes(File('$_fixtures/valid.pem').readAsBytesSync())
      ..usePrivateKeyBytes(File('$_fixtures/server_key.pem').readAsBytesSync());
    _server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
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
      response.contentLength = body.length;
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

void main() {
  late HttpOverrides? saved;
  setUpAll(() {
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDownAll(() => HttpOverrides.global = saved);

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
    api = ApiClient(_Config(), PinnedHttpClient()..pinTo(_fingerprint))..initBase(address: 'https://127.0.0.1:${server.port}');
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

      await source().putBytes(uploadPath: '/files/t', file: file, offset: 40000, onProgress: (done, total) => shares.add((done, total)));

      expect(server.contentLength, payload.length - 40000);
      expect(server.received, payload.sublist(40000), reason: 'what the server already holds is not sent again (FR-001)');
      expect(shares.first.$1, greaterThanOrEqualTo(40000), reason: 'progress counts the whole file (FR-012)');
      expect(shares.last, (payload.length, payload.length));
    });

    test('nothing left to send is an empty PUT that completes the upload', () async {
      await source().putBytes(uploadPath: '/files/t', file: file, offset: payload.length);

      expect(server.contentLength, 0);
      expect(server.received, isEmpty);
    });

    for (final (status, failure) in <(int, FileTransferFailure)>[
      (HttpStatus.notFound, FileTransferFailure.passRejected),
      (HttpStatus.requestEntityTooLarge, FileTransferFailure.sizeMismatch),
      (HttpStatus.badRequest, FileTransferFailure.sizeMismatch),
      (HttpStatus.requestTimeout, FileTransferFailure.connection),
      (HttpStatus.conflict, FileTransferFailure.connection),
      (HttpStatus.internalServerError, FileTransferFailure.connection),
    ]) {
      test('$status means ${failure.name}', () async {
        server.status = status;

        await expectLater(
          source().putBytes(uploadPath: '/files/t', file: file, offset: 0),
          throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', failure)),
        );
      });
    }

    test('bytes that stop moving end the transfer as a broken connection', () async {
      // A path that went dead under the transfer: nothing reads, and without
      // a watch on silence the PUT would hang until the OS gave up on it.
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final watch = Stopwatch()..start();

      await expectLater(
        source(stallLimit: const Duration(milliseconds: 500)).putBytes(uploadPath: '/files/t', file: file, offset: 0),
        throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('a slow transfer that keeps moving is never cut, however long it takes (FR-009)', () async {
      await writePayload(8 * 1024 * 1024);
      server.pausePerChunk = const Duration(milliseconds: 5);
      final watch = Stopwatch()..start();

      await source(stallLimit: const Duration(seconds: 1)).putBytes(uploadPath: '/files/t', file: file, offset: 0);

      expect(watch.elapsed, greaterThan(const Duration(seconds: 1)), reason: 'it outlasted the stall limit');
      expect(server.received.length, payload.length);
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
      ).putBytes(uploadPath: '/files/t', file: file, offset: 0);

      expect(server.received.length, payload.length);
    });

    test('cancelTransfers ends a transfer under way as a broken connection', () async {
      await writePayload(16 * 1024 * 1024);
      server.stopReading = true;
      final put = source(stallLimit: const Duration(minutes: 1)).putBytes(uploadPath: '/files/t', file: file, offset: 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      source().cancelTransfers();

      await expectLater(put, throwsA(isA<FileTransferException>().having((e) => e.failure, 'failure', FileTransferFailure.connection)));
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
      getApi = ApiClient(_Config(), PinnedHttpClient()..pinTo(_fingerprint))..initBase(address: 'https://127.0.0.1:${getServer.port}');
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
      final context = SecurityContext()
        ..useCertificateChainBytes(File('$_fixtures/valid.pem').readAsBytesSync())
        ..usePrivateKeyBytes(File('$_fixtures/server_key.pem').readAsBytesSync());
      final raw = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context);
      addTearDown(raw.close);
      final held = <SecureSocket>[];
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
      final api = ApiClient(_Config(), PinnedHttpClient()..pinTo(_fingerprint))..initBase(address: 'https://127.0.0.1:${raw.port}');

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
}

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/data/exception/file_transfer_exception.dart';
import 'package:nox_app/data/remote/api_client.dart';
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
}
